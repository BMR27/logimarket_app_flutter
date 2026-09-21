import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../db/local_database.dart';
import '../models/backpack_model.dart';
import '../models/backpack_item_model.dart';
import '../services/backpacks_service.dart';
import '../services/api_service.dart';

class BackpacksProvider extends ChangeNotifier {
  final _service = BackpacksService();
  final _localDb = LocalDatabase();

  List<BackpackModel> _backpacks = [];
  List<BackpackItemModel> _selectedItems = [];
  final Map<int, List<BackpackItemModel>> _itemsByBackpack = {};
  int? _selectedBackpackId;
  bool _loadingBackpacks = false;
  bool _loadingItems = false;
  bool _syncingBackpackOps = false;
  String? _errorMessage;
  bool _lastActionQueuedOffline = false;

  List<BackpackModel> get backpacks => _backpacks;
  List<BackpackItemModel> get selectedItems => _selectedItems;
  bool get loading => _loadingBackpacks || _loadingItems;
  bool get loadingBackpacks => _loadingBackpacks;
  bool get loadingItems => _loadingItems;
  String? get errorMessage => _errorMessage;
  /// true si la última operación exitosa (validar/eliminar/cambiar estado) se
  /// guardó localmente porque no había conexión, en vez de aplicarse en el servidor.
  bool get lastActionQueuedOffline => _lastActionQueuedOffline;

  Future<void> loadBackpacks(int idUsuario) async {
    _loadingBackpacks = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final fetched = await _service.getBackpacks(idUsuario);
      // Salvaguarda cliente: una mochila cerrada/cancelada (state=4) no debe mostrarse al mensajero.
      _backpacks = fetched.where((b) => b.state != 4).toList();
      // Persist for offline access
      await LocalDatabase().saveBackpacks(idUsuario, _backpacks);
    } on ApiException catch (e) {
      if (e.statusCode == 0) {
        // Red no disponible — cargar desde caché local
        final cached = await LocalDatabase().getCachedBackpacks(idUsuario);
        _backpacks = cached.where((b) => b.state != 4).toList();
        _errorMessage = cached.isEmpty ? 'Sin conexión y sin mochilas guardadas.' : 'Sin conexión — mochilas en caché.';
      } else {
        // Si hay error de servidor/timeout, usar caché local cuando exista.
        final cached = await LocalDatabase().getCachedBackpacks(idUsuario);
        if (cached.isNotEmpty) {
          _backpacks = cached.where((b) => b.state != 4).toList();
          _errorMessage = e.message;
        } else {
          _errorMessage = e.message;
        }
      }
    }
    _loadingBackpacks = false;
    notifyListeners();
  }

  Future<void> loadBackpackItems(int idBackpack) async {
    final cached = _itemsByBackpack[idBackpack];
    if (cached != null && cached.isNotEmpty) {
      _selectedBackpackId = idBackpack;
      _selectedItems = List<BackpackItemModel>.from(cached);
      notifyListeners();
      return;
    }

    _loadingItems = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final fetched = await _service.getBackpackItemsAdmin(idBackpack);
      _selectedBackpackId = idBackpack;
      _selectedItems = fetched;
      _itemsByBackpack[idBackpack] = List<BackpackItemModel>.from(fetched);
      // Persist to SQLite for offline access
      await LocalDatabase().saveBackpackItems(idBackpack, fetched);
    } on ApiException catch (e) {
      if (e.statusCode == 0) {
        // Red no disponible — cargar desde caché local
        final sqlCached = await LocalDatabase().getBackpackItems(idBackpack);
        if (sqlCached.isNotEmpty) {
          _selectedBackpackId = idBackpack;
          _selectedItems = sqlCached;
          _itemsByBackpack[idBackpack] = List<BackpackItemModel>.from(sqlCached);
          _errorMessage = 'Sin conexión — mostrando datos guardados.';
        } else {
          _errorMessage = 'Sin conexión y sin datos guardados para esta mochila.';
        }
      } else {
        _errorMessage = e.message;
      }
    }
    _loadingItems = false;
    notifyListeners();
  }

  Future<void> prefetchBackpackItems(int idBackpack) async {
    final cached = _itemsByBackpack[idBackpack];
    if (cached != null && cached.isNotEmpty) return;

    try {
      final fetched = await _service.getBackpackItemsAdmin(idBackpack);
      _itemsByBackpack[idBackpack] = List<BackpackItemModel>.from(fetched);
    } catch (_) {
      // Prefetch silencioso: no interrumpe flujo de UI.
    }
  }

  Future<void> loadDeliverItems(int idRepartidor) async {
    _loadingItems = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _selectedItems = await _service.getBackpackItemsDeliver(idRepartidor);
    } on ApiException catch (e) {
      _errorMessage = e.message;
    }
    _loadingItems = false;
    notifyListeners();
  }

  Future<void> loadMapItems({
    required bool isAdmin,
    required int userId,
    int? idBackpack,
    int? idRepartidor,
    List<int>? idBackpackIds,
  }) async {
    _loadingItems = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (isAdmin) {
        if (idBackpack == null) {
          _selectedItems = [];
          return;
        }
        _selectedItems = await _service.getBackpackItemsAdmin(idBackpack);
        // Cache for offline
        await LocalDatabase().saveBackpackItems(idBackpack, _selectedItems);
        return;
      }

      final deliverItems = await _service.getBackpackItemsDeliver(idRepartidor ?? userId);

      if (deliverItems.isNotEmpty) {
        _selectedItems = deliverItems;
        // Cache each backpack's items
        final byBackpack = <int, List<BackpackItemModel>>{};
        for (final item in deliverItems) {
          (byBackpack[item.idBackpack] ??= []).add(item);
        }
        for (final entry in byBackpack.entries) {
          await LocalDatabase().saveBackpackItems(entry.key, entry.value);
        }
        return;
      }

      // Fallback de contingencia cuando el endpoint deliver no devuelve datos.
      if (idBackpackIds != null && idBackpackIds.isNotEmpty) {
        final allItems = <BackpackItemModel>[];
        for (final backpackId in idBackpackIds.toSet()) {
          final items = await _service.getBackpackItemsAdmin(backpackId);
          allItems.addAll(items);
          await LocalDatabase().saveBackpackItems(backpackId, items);
        }
        final byItemId = <int, BackpackItemModel>{};
        for (final item in allItems) {
          byItemId[item.idBackpackItem] = item;
        }
        _selectedItems = byItemId.values.toList();
      } else if (idBackpack != null) {
        _selectedItems = await _service.getBackpackItemsAdmin(idBackpack);
        await LocalDatabase().saveBackpackItems(idBackpack, _selectedItems);
      } else {
        _selectedItems = deliverItems;
      }
    } on ApiException catch (e) {
      if (e.statusCode == 0) {
        // Red no disponible — cargar ítems desde caché SQLite
        final backpackIds = idBackpackIds ?? (idBackpack != null ? [idBackpack] : <int>[]);
        if (backpackIds.isNotEmpty) {
          final allItems = <BackpackItemModel>[];
          for (final bid in backpackIds.toSet()) {
            allItems.addAll(await LocalDatabase().getBackpackItems(bid));
          }
          final byItemId = <int, BackpackItemModel>{};
          for (final item in allItems) {
            byItemId[item.idBackpackItem] = item;
          }
          _selectedItems = byItemId.values.toList();
        } else {
          _errorMessage = 'Sin conexión y sin datos guardados para esta mochila.';
        }
      } else {
        _errorMessage = e.message;
      }
    } finally {
      _loadingItems = false;
      notifyListeners();
    }
  }

  Future<bool> createBackpack({
    required int idRepartidor,
    required int idLider,
    required List<int> orderIds,
  }) async {
    try {
      await _service.createBackpack(
        idRepartidor: idRepartidor,
        idLider: idLider,
        orderIds: orderIds.join(','),
      );
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateState(int idBackpack, int state) async {
    _lastActionQueuedOffline = false;
    try {
      await _service.updateBackpackState(idBackpack, state);
      _applyStateLocally(idBackpack, state);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 0) {
        await _localDb.savePendingBackpackOp(
          idBackpack: idBackpack,
          opType: 'update_state',
          payload: {'state': state},
        );
        _applyStateLocally(idBackpack, state);
        _lastActionQueuedOffline = true;
        notifyListeners();
        return true;
      }
      _errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }

  void _applyStateLocally(int idBackpack, int state) {
    final idx = _backpacks.indexWhere((b) => b.id == idBackpack);
    if (idx >= 0) {
      _backpacks[idx] = BackpackModel.fromJson({
        ..._backpackToMap(_backpacks[idx]),
        'State': state,
      });
    }
  }

  Future<bool> deleteItem(int idItem) async {
    _lastActionQueuedOffline = false;
    try {
      await _service.deleteBackpackItem(idItem);
      _selectedItems.removeWhere((i) => i.idBackpackItem == idItem);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 0) {
        final item = _selectedItems.cast<BackpackItemModel?>().firstWhere(
              (i) => i?.idBackpackItem == idItem,
              orElse: () => null,
            );
        await _localDb.savePendingBackpackOp(
          idBackpack: item?.idBackpack ?? 0,
          opType: 'delete_item',
          payload: {'idItem': idItem},
        );
        _selectedItems.removeWhere((i) => i.idBackpackItem == idItem);
        _lastActionQueuedOffline = true;
        notifyListeners();
        return true;
      }
      _errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }

  void _markItemValidatedLocally({int? idItem, int? idBackpack, String? folio}) {
    final normalizedFolio = folio?.trim();
    bool matches(BackpackItemModel i) {
      if (idItem != null) return i.idBackpackItem == idItem;
      return i.idBackpack == idBackpack && i.folioOrden.trim() == normalizedFolio;
    }

    BackpackItemModel validated(BackpackItemModel item) => BackpackItemModel.fromJson({
      'IdBackpack': item.idBackpack,
      'IdBackPackItem': item.idBackpackItem,
      'IdOrdenVenta': item.idOrdenVenta,
      'FolioOrden': item.folioOrden,
      'IdStatusOrden': item.idStatusOrden,
      'StatusName': item.statusName,
      'NombreCliente': item.nombreCliente,
      'Validation': 1,
    });

    final idx = _selectedItems.indexWhere(matches);
    if (idx >= 0) {
      _selectedItems[idx] = validated(_selectedItems[idx]);
    }

    // También hay que actualizar el caché en memoria (_itemsByBackpack): si no se
    // toca aquí, la próxima vez que se entre a esta mochila loadBackpackItems()
    // sirve la copia vieja sin validar desde el caché y "revierte" el estatus.
    final cacheBackpackId = idBackpack ?? (idx >= 0 ? _selectedItems[idx].idBackpack : null);
    final cachedList = cacheBackpackId != null ? _itemsByBackpack[cacheBackpackId] : null;
    if (cachedList != null) {
      final cacheIdx = cachedList.indexWhere(matches);
      if (cacheIdx >= 0) {
        cachedList[cacheIdx] = validated(cachedList[cacheIdx]);
      }
    }
  }

  Future<bool> validateItem(int idItem) async {
    _lastActionQueuedOffline = false;
    if (idItem <= 0) {
      _errorMessage = 'No se pudo identificar el ítem a validar';
      notifyListeners();
      return false;
    }
    try {
      await _service.validateBackpackItem(idItem);
      // Actualiza localmente SIN hacer reload del servidor
      // Esto evita conflictos de estado y "Guardado Offline"
      _markItemValidatedLocally(idItem: idItem);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 0) {
        final item = _selectedItems.cast<BackpackItemModel?>().firstWhere(
              (i) => i?.idBackpackItem == idItem,
              orElse: () => null,
            );
        if (item == null) {
          _errorMessage = 'Sin conexión y el ítem no está guardado localmente';
          notifyListeners();
          return false;
        }
        await _localDb.savePendingBackpackOp(
          idBackpack: item.idBackpack,
          opType: 'validate_item',
          payload: {'idItem': idItem},
        );
        _markItemValidatedLocally(idItem: idItem);
        _lastActionQueuedOffline = true;
        notifyListeners();
        return true;
      }
      _errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> validateItemByFolio({
    required int idBackpack,
    required String folio,
  }) async {
    _lastActionQueuedOffline = false;
    final normalizedFolio = folio.trim();
    if (idBackpack <= 0 || normalizedFolio.isEmpty) {
      _errorMessage = 'Datos invalidos para validar la orden';
      notifyListeners();
      return false;
    }
    try {
      await _service.validateBackpackItemByFolio(
        idBackpack: idBackpack,
        folio: normalizedFolio,
      );
      _markItemValidatedLocally(idBackpack: idBackpack, folio: normalizedFolio);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 0) {
        // Se encola por folio aunque el ítem no esté cacheado localmente: el
        // endpoint valida por folio, no requiere conocer el idBackpackItem.
        await _localDb.savePendingBackpackOp(
          idBackpack: idBackpack,
          opType: 'validate_folio',
          payload: {'folio': normalizedFolio},
        );
        _markItemValidatedLocally(idBackpack: idBackpack, folio: normalizedFolio);
        _lastActionQueuedOffline = true;
        notifyListeners();
        return true;
      }
      _errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }

  /// Reintenta en orden todas las operaciones de mochila guardadas offline.
  /// Se detiene ante la primera falla por falta de red (sigue offline); ante
  /// un error real del servidor marca esa fila como fallida y sigue con las
  /// demás, para no bloquear el resto de la cola por un solo conflicto.
  /// Devuelve cuántas se sincronizaron y cuántas quedaron marcadas como fallidas.
  Future<({int synced, int failed})> syncPendingBackpackOps() async {
    if (_syncingBackpackOps) return (synced: 0, failed: 0);
    _syncingBackpackOps = true;
    var synced = 0;
    var failed = 0;
    try {
      final ops = await _localDb.getPendingBackpackOps();
      for (final op in ops) {
        final id = op['id'] as int;
        final opType = op['opType'] as String;
        final payload = Map<String, dynamic>.from(
          jsonDecode(op['payload'] as String) as Map,
        );
        try {
          switch (opType) {
            case 'update_state':
              await _service.updateBackpackState(
                op['idBackpack'] as int,
                payload['state'] as int,
              );
              break;
            case 'delete_item':
              await _service.deleteBackpackItem(payload['idItem'] as int);
              break;
            case 'validate_item':
              await _service.validateBackpackItem(payload['idItem'] as int);
              break;
            case 'validate_folio':
              await _service.validateBackpackItemByFolio(
                idBackpack: op['idBackpack'] as int,
                folio: payload['folio'] as String,
              );
              break;
          }
          await _localDb.deletePendingBackpackOp(id);
          synced++;
        } on ApiException catch (e) {
          if (e.statusCode == 0) {
            // Sigue sin red: deja el resto de la cola intacta para el próximo intento.
            break;
          }
          await _localDb.markPendingBackpackOpFailed(id, e.message);
          failed++;
        }
      }
    } finally {
      _syncingBackpackOps = false;
    }
    return (synced: synced, failed: failed);
  }

  Map<String, dynamic> _backpackToMap(BackpackModel b) => {
        'Id': b.id,
        'IdRepartidor': b.idRepartidor,
        'NombreRepartidor': b.nombreRepartidor,
        'CreationDate': b.creationDate,
        'State': b.state,
        'StateName': b.stateName,
        'TotalOrders': b.totalOrders,
        'ProgressOrders': b.progressOrders,
      };
}
