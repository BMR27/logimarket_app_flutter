import 'package:flutter/foundation.dart';
import '../models/order_model.dart';
import '../models/product_model.dart';
import '../services/orders_service.dart';
import '../services/api_service.dart';
import '../db/local_database.dart';

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
  String? _errorMessage;

  List<OrderModel> get orders => _orders;
  OrderModel? get selectedOrder => _selectedOrder;
  List<ProductModel> get products => _products;
  bool get loading => _loading;
  bool get offline => _offline;
  String? get errorMessage => _errorMessage;

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
      _orders = [];
      _offline = false;
      _loading = false;
      notifyListeners();
      return;
    }

    bool hadNetworkError = false;
    bool hadAuthError = false;
    final loaded = <OrderModel>[];

    for (final id in uniqueIds) {
      try {
        final order = await _service.getOrderDetail(id, equipos: equipos);
        loaded.add(order);
      } on ApiException catch (e) {
        if (e.statusCode == 0) hadNetworkError = true;
        if (e.statusCode == 401 || e.statusCode == 403) hadAuthError = true;
      } catch (_) {
        // Continúa para no perder las órdenes que sí se puedan cargar.
      }
    }

    if (loaded.isNotEmpty) {
      final normalizedFolio = folio.trim().toLowerCase();
      _orders = normalizedFolio.isEmpty
          ? loaded
          : loaded.where((o) {
              final text = '${o.folioOrdenCliente} ${o.cliente}'.toLowerCase();
              return text.contains(normalizedFolio);
            }).toList();

      for (final o in _orders) {
        await _localDb.upsertOrder(o);
      }

      _offline = false;
      if (kDebugMode) {
        debugPrint('[ORDERS] load-by-ids ok count=${_orders.length}');
      }
    } else {
      _orders = [];
      _offline = hadNetworkError;
      if (hadAuthError) {
        _errorMessage = 'Sesion expirada. Inicia sesion nuevamente.';
      } else if (hadNetworkError) {
        _errorMessage = 'Sin conexion - no se pudieron cargar entregas activas.';
      } else {
        _errorMessage = 'No se pudieron cargar las entregas activas.';
      }
      if (kDebugMode) {
        debugPrint(
          '[ORDERS] load-by-ids empty ids=${uniqueIds.length} network=$hadNetworkError auth=$hadAuthError',
        );
      }
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> loadOrders(String equipos, {String folio = ''}) async {
    _loading = true;
    _errorMessage = null;
    if (kDebugMode) {
      debugPrint('[ORDERS] load start equipos="$equipos" folio="$folio"');
    }
    notifyListeners();
    try {
      _orders = await _service.getOrders(equipos: equipos, folio: folio);
      try {
        final mapOrders = await _service.getOrdersForMap(equipos: equipos, folio: folio);
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
    final cachedOrder = _orderDetailCache[id];
    final cachedProducts = _orderProductsCache[id];

    _loading = true;
    _selectedOrder = cachedOrder;
    _products = cachedProducts != null ? List<ProductModel>.from(cachedProducts) : [];
    _errorMessage = null;
    notifyListeners();
    try {
      final results = await Future.wait<dynamic>([
        _service.getOrderDetail(id, equipos: equipos),
        _service.getProducts(id),
      ]);

      _selectedOrder = results[0] as OrderModel;
      _products = results[1] as List<ProductModel>;
      _orderDetailCache[id] = _selectedOrder!;
      _orderProductsCache[id] = List<ProductModel>.from(_products);
    } on ApiException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Error al cargar la orden: $e';
    }
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
      try {
        await _service.updateOrder(
          idOrden: row['id'] as int,
          status: int.tryParse(row['bd_status'] ?? '0') ?? 0,
          idUsuario: int.tryParse(row['bd_idUsuario'] ?? '0') ?? 0,
          motivoStatus: int.tryParse(row['bd_idStatusMotivo'] ?? '0') ?? 0,
          explicacionMotivo: int.tryParse(row['bd_explicacionMotivo'] ?? '0') ?? 0,
          fechaReagenda: row['bd_fechaReagenda'] as String?,
          latitud: double.tryParse(row['bd_latitud'] ?? ''),
          longitud: double.tryParse(row['bd_longitud'] ?? ''),
        );
        synced++;
      } catch (_) {
        // Continuar con el siguiente
      }
    }
    if (synced > 0) await _localDb.clearEditedOrders();
    return synced;
  }
}
