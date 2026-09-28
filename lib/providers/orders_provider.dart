import 'package:flutter/foundation.dart';
import '../models/order_model.dart';
import '../models/product_model.dart';
import '../services/orders_service.dart';
import '../services/api_service.dart';
import '../config/api_config.dart';
import '../db/local_database.dart';

/// Corre [work] sobre [items] en paralelo, pero nunca más de [maxConcurrent]
/// a la vez. Con mensajeros que llegan a tener 50-60+ órdenes asignadas,
/// lanzar TODAS las peticiones de golpe (Future.wait sin límite) puede saturar
/// el pool de conexiones del dispositivo y golpear al backend con un pico de
/// peticiones simultáneas — esto reparte la carga en oleadas controladas sin
/// volver a la lentitud de hacerlas una por una.
Future<List<R>> _mapWithConcurrency<T, R>(
  List<T> items,
  int maxConcurrent,
  Future<R> Function(T item) work,
) async {
  final results = List<R?>.filled(items.length, null);
  var nextIndex = 0;

  Future<void> runWorker() async {
    while (true) {
      final i = nextIndex;
      if (i >= items.length) return;
      nextIndex++;
      results[i] = await work(items[i]);
    }
  }

  final workerCount = maxConcurrent < items.length ? maxConcurrent : items.length;
  await Future.wait(List.generate(workerCount, (_) => runWorker()));
  return results.cast<R>();
}

class OrdersProvider extends ChangeNotifier {
  final _service = OrdersService();
  final _localDb = LocalDatabase();

  List<OrderModel> _orders = [];
  OrderModel? _selectedOrder;
  List<ProductModel> _products = [];
  final Map<int, OrderModel> _orderDetailCache = {};
  final Map<int, List<ProductModel>> _orderProductsCache = {};
  bool _loading = false;
  bool _offline = false;
  bool _syncingOffline = false;
  String? _errorMessage;
  // Error propio del detalle: separado de [_errorMessage] (lista) para que una
  // recarga de la lista no muestre su aviso en la pantalla de detalle.
  String? _detailErrorMessage;

  /// Limpia la lista sin caer en el fallback de caché local de [loadOrdersByIds],
  /// que asume "sin conexión" ante una lista de ids vacía. Se usa cuando la
  /// lista está vacía por una razón legítima (ej. el mensajero no tiene
  /// mochila aceptada todavía), no por un fallo de red.
  void clearOrders() {
    _orders = [];
    _errorMessage = null;
    _offline = false;
    notifyListeners();
  }

  List<OrderModel> get orders => _orders;
  OrderModel? get selectedOrder => _selectedOrder;
  List<ProductModel> get products => _products;
  bool get loading => _loading;
  bool get offline => _offline;
  String? get errorMessage => _errorMessage;
  String? get detailErrorMessage => _detailErrorMessage;

  Future<void> loadOrdersByIds(
    String equipos,
    List<int> orderIds, {
    String folio = '',
  }) async {
    _loading = true;
    _errorMessage = null;
    if (kDebugMode) {
      debugPrint(
        '[ORDERS] load-by-ids start equipos="$equipos" ids=${orderIds.length} folio="$folio"',
      );
    }
    notifyListeners();

    final uniqueIds = orderIds.toSet().where((id) => id > 0).toList()..sort();
    if (uniqueIds.isEmpty) {
      try {
        // Puede ser que los backpacks también fallaron offline — intentar caché local
        final cached = await _localDb.getAllOrders();
        if (cached.isNotEmpty) {
          _orders = cached.map((r) => OrderModel.fromJson(r)).toList();
          _offline = true;
          _errorMessage = 'Sin conexión — mostrando datos guardados localmente.';
        } else {
          _orders = [];
          _offline = false;
        }
      } finally {
        _loading = false;
        notifyListeners();
      }
      return;
    }

    bool hadNetworkError = false;
    bool hadAuthError = false;
    var failedCount = 0;

    // Se envuelve todo en try/catch/finally: un error inesperado (incluida
    // cualquier falla al leer/escribir la caché local) nunca debe dejar el
    // spinner de "Entregas" pegado para siempre — antes eso podía pasar
    // porque nada garantizaba que _loading volviera a false.
    try {
      // Una sola petición (POST /orders/batch) por bloque de hasta 100 órdenes, en
      // vez de una por orden: con datos móviles, decenas de conexiones simultáneas
      // se caían antes de llegar al servidor, y con 80+ mensajeros eran miles de
      // peticiones contra el backend. Si la API aún no tiene el endpoint, se usa
      // la carga por orden de siempre.
      final fetch = await _fetchOrdersByIds(uniqueIds, equipos);
      final loaded = fetch.loaded;
      failedCount = fetch.failed;
      hadNetworkError = fetch.networkError;
      hadAuthError = fetch.authError;
      for (final o in loaded) {
        _orderDetailCache[o.id] = o;
      }

      if (loaded.isNotEmpty) {
        final normalizedFolio = folio.trim().toLowerCase();
        _orders = normalizedFolio.isEmpty
            ? loaded
            : loaded.where((o) {
                final text = '${o.folioOrdenCliente} ${o.cliente}'.toLowerCase();
                return text.contains(normalizedFolio);
              }).toList();

        for (final o in loaded) {
          await _localDb.upsertOrder(o);
        }
        // Evita que órdenes viejas (ya reasignadas o completadas) sigan
        // apareciendo desde la caché local si más adelante falla la red.
        await _localDb.pruneOrdersNotIn(loaded.map((o) => o.id).toList());

        _offline = false;
        _errorMessage = failedCount > 0
            ? 'No se pudieron cargar $failedCount de ${uniqueIds.length - fetch.missing} entregas. Desliza para reintentar.'
            : null;
        if (kDebugMode) {
          debugPrint('[ORDERS] load-by-ids ok count=${_orders.length} failed=$failedCount');
        }
      } else {
        // Sin resultados: intentar DB local si fue error de red
        if (hadNetworkError) {
          final cached = await _localDb.getAllOrders();
          _orders = cached.map((r) => OrderModel.fromJson(r)).toList();
          _offline = true;
          _errorMessage = cached.isEmpty
              ? 'Sin conexión y sin datos guardados localmente.'
              : 'Sin conexión — mostrando datos guardados localmente.';
        } else {
          _orders = [];
          _offline = false;
          if (hadAuthError) {
            _errorMessage = 'Sesion expirada. Inicia sesion nuevamente.';
          } else {
            _errorMessage = 'No se pudieron cargar las entregas activas.';
          }
        }
        if (kDebugMode) {
          debugPrint(
            '[ORDERS] load-by-ids fallback network=$hadNetworkError auth=$hadAuthError cached=${_orders.length}',
          );
        }
      }
    } catch (e) {
      _offline = false;
      _errorMessage = 'Error inesperado al cargar entregas.';
      if (kDebugMode) {
        debugPrint('[ORDERS] load-by-ids unexpected error: $e');
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  static const int _batchSize = 100;
  static const List<Duration> _retryDelays = [
    Duration.zero,
    Duration(seconds: 1),
    Duration(seconds: 3),
  ];

  /// Carga el detalle de [ids] con el endpoint batch (reintentos con espera
  /// creciente ante fallas de red). Si el servidor no conoce el endpoint
  /// (404/405, API anterior), cae a la carga por orden con un reintento.
  Future<({List<OrderModel> loaded, int failed, int missing, bool networkError, bool authError})>
      _fetchOrdersByIds(List<int> ids, String equipos) async {
    final loaded = <OrderModel>[];
    var failed = 0;
    var missing = 0;
    var networkError = false;
    var authError = false;
    var batchUnsupported = false;

    for (var start = 0; start < ids.length && !batchUnsupported; start += _batchSize) {
      final chunk = ids.sublist(start, (start + _batchSize).clamp(0, ids.length));
      var done = false;
      for (final delay in _retryDelays) {
        if (delay > Duration.zero) await Future.delayed(delay);
        try {
          final r = await _service.getOrdersBatch(chunk, equipos: equipos);
          loaded.addAll(r.orders);
          missing += r.missing.length;
          final returned = r.orders.map((o) => o.id).toSet()..addAll(r.missing);
          failed += chunk.where((id) => !returned.contains(id)).length;
          done = true;
          break;
        } on ApiException catch (e) {
          // 404/405: la API aún no tiene el endpoint. -1: respondió algo que no es
          // un batch (p. ej. un proxy o una versión vieja) — se usa la carga por orden.
          if (e.statusCode == 404 || e.statusCode == 405 || e.statusCode == -1) {
            batchUnsupported = true;
            break;
          }
          if (e.statusCode == 401 || e.statusCode == 403) {
            authError = true;
            break;
          }
          if (e.statusCode == 0) networkError = true;
        } catch (_) {
          // Respuesta inesperada: se reintenta igual que una falla de red.
        }
      }
      if (!done && !batchUnsupported) failed += chunk.length;
    }

    if (!batchUnsupported) {
      loaded.sort((x, y) => x.id.compareTo(y.id));
      return (loaded: loaded, failed: failed, missing: missing, networkError: networkError, authError: authError);
    }

    // API anterior sin /orders/batch: carga por orden (6 a la vez) y un segundo
    // intento solo para las que fallaron por red. Las 404 ya no existen: no se
    // reintentan ni cuentan como fallidas.
    final yaCargadas = loaded.map((o) => o.id).toSet();
    final inexistentes = <int>{};
    Future<OrderModel?> uno(int id) async {
      try {
        return await _service.getOrderDetail(id, equipos: equipos);
      } on ApiException catch (e) {
        if (e.statusCode == 0) networkError = true;
        if (e.statusCode == 401 || e.statusCode == 403) authError = true;
        if (e.statusCode == 404) inexistentes.add(id);
        return null;
      } catch (_) {
        return null;
      }
    }

    var restantes = ids.where((id) => !yaCargadas.contains(id)).toList();
    for (var intento = 0; intento < 2 && restantes.isNotEmpty && !authError; intento++) {
      if (intento > 0) await Future.delayed(const Duration(seconds: 1));
      final results = await _mapWithConcurrency<int, OrderModel?>(restantes, 6, uno);
      final siguientes = <int>[];
      for (var i = 0; i < restantes.length; i++) {
        final r = results[i];
        if (r != null) {
          loaded.add(r);
        } else if (!inexistentes.contains(restantes[i])) {
          siguientes.add(restantes[i]);
        }
      }
      restantes = siguientes;
    }
    loaded.sort((x, y) => x.id.compareTo(y.id));
    return (loaded: loaded, failed: restantes.length, missing: inexistentes.length, networkError: networkError, authError: authError);
  }

  Future<void> loadOrders(String equipos, {String folio = ''}) async {
    _loading = true;
    _errorMessage = null;
    if (kDebugMode) {
      debugPrint('[ORDERS] load start equipos="$equipos" folio="$folio"');
    }
    notifyListeners();
    try {
      // Ambas peticiones son independientes — lanzarlas en paralelo evita sumar
      // sus tiempos de espera (antes se esperaba una y luego la otra).
      final ordersFuture = _service.getOrders(equipos: equipos, folio: folio);
      final mapOrdersFuture = _service
          .getOrdersForMap(equipos: equipos, folio: folio)
          .catchError((_) => <OrderModel>[]);

      _orders = await ordersFuture;
      try {
        final mapOrders = await mapOrdersFuture;
        final byId = <int, OrderModel>{for (final o in mapOrders) o.id: o};
        _orders = _orders.map((o) {
          final mo = byId[o.id];
          if (mo == null) return o;
          final lat = (o.latitud == null || o.latitud!.trim().isEmpty) ? mo.latitud : o.latitud;
          final lng = (o.longitud == null || o.longitud!.trim().isEmpty) ? mo.longitud : o.longitud;
          final met = (o.metros == null || o.metros!.trim().isEmpty) ? mo.metros : o.metros;
          final tpo = (o.tiempo == null || o.tiempo!.trim().isEmpty) ? mo.tiempo : o.tiempo;
          if (lat == o.latitud && lng == o.longitud && met == o.metros && tpo == o.tiempo) {
            return o;
          }
          return o.copyWith(latitud: lat, longitud: lng, metros: met, tiempo: tpo);
        }).toList();
      } catch (_) {
        // Si falla /orders/ways mantenemos la carga base sin romper el flujo.
      }
      // Guardar en local para modo offline
      for (final o in _orders) {
        await _localDb.upsertOrder(o);
      }
      _offline = false;
      if (kDebugMode) {
        debugPrint('[ORDERS] load ok count=${_orders.length} offline=$_offline');
      }
    } on ApiException catch (e) {
      _offline = e.statusCode == 0;
      if (_offline) {
        _errorMessage = 'Sin conexion - mostrando datos guardados localmente.';
      } else if (e.statusCode == 401 || e.statusCode == 403) {
        _errorMessage = 'Sesion expirada. Inicia sesion nuevamente.';
      } else {
        _errorMessage = '${e.message} - mostrando datos guardados localmente.';
      }
      final cached = await _localDb.getAllOrders();
      _orders = cached.map((r) => OrderModel.fromJson(r)).toList();
      if (kDebugMode) {
        debugPrint(
          '[ORDERS] api error status=${e.statusCode} msg="${e.message}" offline=$_offline cached=${_orders.length}',
        );
      }
    } catch (e, st) {
      _offline = false;
      _errorMessage = 'Error inesperado al cargar entregas - mostrando datos guardados localmente.';
      final cached = await _localDb.getAllOrders();
      _orders = cached.map((r) => OrderModel.fromJson(r)).toList();
      if (kDebugMode) {
        debugPrint('[ORDERS] unexpected error type=${e.runtimeType} msg="$e" offline=$_offline cached=${_orders.length}');
        debugPrint('[ORDERS] unexpected stack $st');
      }
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> selectOrder(int id, String equipos) async {
    // La orden ya viene completa en la lista (batch) o en la caché: se muestra
    // de inmediato y se refresca en segundo plano.
    OrderModel? cachedOrder = _orderDetailCache[id];
    if (cachedOrder == null) {
      for (final o in _orders) {
        if (o.id == id) {
          cachedOrder = o;
          break;
        }
      }
    }
    final cachedProducts = _orderProductsCache[id];

    _loading = true;
    _selectedOrder = cachedOrder;
    _products = cachedProducts != null ? List<ProductModel>.from(cachedProducts) : [];
    _detailErrorMessage = null;
    notifyListeners();

    for (var intento = 0; intento < 2; intento++) {
      if (intento > 0) await Future.delayed(const Duration(seconds: 1));
      try {
        final results = await Future.wait<dynamic>([
          _service.getOrderDetail(id, equipos: equipos),
          _service.getProducts(id),
        ]);

        _selectedOrder = results[0] as OrderModel;
        _products = results[1] as List<ProductModel>;
        _orderDetailCache[id] = _selectedOrder!;
        _orderProductsCache[id] = List<ProductModel>.from(_products);
        _detailErrorMessage = null;
        break;
      } on ApiException catch (e) {
        _detailErrorMessage = e.message;
        if (e.statusCode == 404) {
          // La orden ya no existe en el servidor (borrada/depurada) — no dejarla
          // en caché ni en el listado local para que no se siga mostrando.
          _selectedOrder = null;
          _orderDetailCache.remove(id);
          _orderProductsCache.remove(id);
          _orders = _orders.where((o) => o.id != id).toList();
          break;
        }
        if (e.statusCode == 401 || e.statusCode == 403) break;
      } catch (e) {
        _detailErrorMessage = 'Error al cargar la orden: $e';
      }
    }
    // Si hay orden en pantalla (de la lista/caché) no se bloquea por un fallo
    // de red al refrescarla.
    if (_selectedOrder != null && _detailErrorMessage != null) _detailErrorMessage = null;
    _loading = false;
    notifyListeners();
  }

  Future<void> preloadOrder(int id, String equipos) async {
    if (_orderDetailCache.containsKey(id) && _orderProductsCache.containsKey(id)) {
      return;
    }

    try {
      final results = await Future.wait<dynamic>([
        _service.getOrderDetail(id, equipos: equipos),
        _service.getProducts(id),
      ]);

      _orderDetailCache[id] = results[0] as OrderModel;
      _orderProductsCache[id] = List<ProductModel>.from(results[1] as List<ProductModel>);
    } catch (_) {
      // Prefetch silencioso.
    }
  }

  Future<bool> updateOrder({
    required int idOrden,
    required int status,
    required int idUsuario,
    int motivoStatus = 0,
    int explicacionMotivo = 0,
    String? fechaReagenda,
    double? latitud,
    double? longitud,
    String? metros,
    String? tiempo,
  }) async {
    try {
      await _service.updateOrder(
        idOrden: idOrden,
        status: status,
        idUsuario: idUsuario,
        motivoStatus: motivoStatus,
        explicacionMotivo: explicacionMotivo,
        fechaReagenda: fechaReagenda,
        latitud: latitud,
        longitud: longitud,
        metros: metros,
        tiempo: tiempo,
      );
      return true;
    } on ApiException catch (e) {
      if (e.statusCode != 0) {
        rethrow;
      }
      // Guardar en local solo si no hay red
      await _localDb.markOrderAsEdited(
        id: idOrden,
        status: status,
        motivoStatus: motivoStatus,
        explicacionMotivo: explicacionMotivo,
        idUsuario: idUsuario,
        fechaReagenda: fechaReagenda,
        latitud: latitud?.toString(),
        longitud: longitud?.toString(),
      );
      return false;
    }
  }

  /// Sincroniza los pedidos editados offline con el servidor
  Future<int> syncOfflineOrders() async {
    final edited = await _localDb.getEditedOrders();
    int synced = 0;
    for (final row in edited) {
      final id = row['id'] as int;
      try {
        await _service.updateOrder(
          idOrden: id,
          status: int.tryParse(row['bd_status'] ?? '0') ?? 0,
          idUsuario: int.tryParse(row['bd_idUsuario'] ?? '0') ?? 0,
          motivoStatus: int.tryParse(row['bd_idStatusMotivo'] ?? '0') ?? 0,
          explicacionMotivo: int.tryParse(row['bd_explicacionMotivo'] ?? '0') ?? 0,
          fechaReagenda: row['bd_fechaReagenda'] as String?,
          latitud: double.tryParse(row['bd_latitud'] ?? ''),
          longitud: double.tryParse(row['bd_longitud'] ?? ''),
        );
        // Antes se limpiaba el flag de TODAS las órdenes editadas en cuanto
        // UNA sincronizaba con éxito (un UPDATE sin filtro por id).
        // Si de 3 órdenes offline solo la primera lograba subir y las otras 2
        // fallaban (conexión intermitente, rechazo del servidor, etc.), las 2
        // se marcaban como "ya no pendientes" sin haberse guardado nunca en
        // el servidor — el mensajero las veía como Exitosa en el teléfono
        // pero el cambio jamás llegaba al sistema, ni reabriendo la app.
        await _localDb.clearEditedOrder(id);
        synced++;
      } catch (_) {
        // Se deja marcada como pendiente para reintentar en el próximo sync.
      }
    }
    return synced;
  }

  /// Sube las evidencias que fueron guardadas offline (foto/firma).
  Future<int> syncPendingEvidence() async {
    final pending = await _localDb.getPendingEvidence();
    int synced = 0;
    final svc = ApiService();
    for (final row in pending) {
      try {
        await svc.post(ApiConfig.orderEvidencia(row['idOrden'] as int), {
          'idUsuario': row['idUsuario'],
          if (row['nombreReceptor'] != null) 'nombreReceptor': row['nombreReceptor'],
          if (row['fotoBase64'] != null) 'fotoBase64': row['fotoBase64'],
          if (row['firmaBase64'] != null) 'firmaBase64': row['firmaBase64'],
        });
        await _localDb.deletePendingEvidence(row['id'] as int);
        synced++;
      } on ApiException catch (e) {
        if (e.statusCode == 0) break; // sigue sin conexión, detener
      } catch (_) {
        // Continuar con el siguiente
      }
    }
    return synced;
  }

  /// Sube las notas/comentarios de orden guardados offline.
  Future<int> syncPendingNotes() async {
    final pending = await _localDb.getPendingNotes();
    int synced = 0;
    final svc = ApiService();
    for (final row in pending) {
      final idOrden = row['idOrden'] as int;
      try {
        await svc.put(ApiConfig.orderNotes(idOrden), {
          'observacionesMensajero': row['notas'],
        });
        await _localDb.deletePendingNote(idOrden);
        synced++;
      } on ApiException catch (e) {
        if (e.statusCode == 0) break; // sigue sin conexión, detener
      } catch (_) {
        // Continuar con el siguiente
      }
    }
    return synced;
  }

  /// Sincroniza todo lo pendiente (órdenes + evidencias + notas).
  /// Retorna el total de ítems sincronizados. Evita ejecuciones concurrentes:
  /// se dispara tanto al reconectar como desde el botón manual del menú, y
  /// ambas pueden coincidir.
  Future<int> syncAllOffline() async {
    if (_syncingOffline) return 0;
    _syncingOffline = true;
    try {
      final orders = await syncOfflineOrders();
      final evidence = await syncPendingEvidence();
      final notes = await syncPendingNotes();
      return orders + evidence + notes;
    } finally {
      _syncingOffline = false;
    }
  }
}
