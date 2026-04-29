import 'package:flutter/foundation.dart';
import '../models/backpack_model.dart';
import '../models/backpack_item_model.dart';
import '../services/backpacks_service.dart';
import '../services/api_service.dart';

class BackpacksProvider extends ChangeNotifier {
  final _service = BackpacksService();

  List<BackpackModel> _backpacks = [];
  List<BackpackItemModel> _selectedItems = [];
  bool _loading = false;
  String? _errorMessage;

  List<BackpackModel> get backpacks => _backpacks;
  List<BackpackItemModel> get selectedItems => _selectedItems;
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;

  Future<void> loadBackpacks(int idUsuario) async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _backpacks = await _service.getBackpacks(idUsuario);
    } on ApiException catch (e) {
      _errorMessage = e.message;
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> loadBackpackItems(int idBackpack) async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _selectedItems = await _service.getBackpackItemsAdmin(idBackpack);
    } on ApiException catch (e) {
      _errorMessage = e.message;
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> loadDeliverItems(int idRepartidor) async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _selectedItems = await _service.getBackpackItemsDeliver(idRepartidor);
    } on ApiException catch (e) {
      _errorMessage = e.message;
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> loadMapItems({
    required bool isAdmin,
    required int userId,
    int? idBackpack,
    int? idRepartidor,
    List<int>? idBackpackIds,
  }) async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (isAdmin) {
        if (idBackpack == null) {
          _selectedItems = [];
          return;
        }
        _selectedItems = await _service.getBackpackItemsAdmin(idBackpack);
        return;
      }

      final deliverItems = await _service.getBackpackItemsDeliver(idRepartidor ?? userId);

      if (deliverItems.isNotEmpty) {
        _selectedItems = deliverItems;
        return;
      }

      // Fallback de contingencia cuando el endpoint deliver no devuelve datos.
      if (idBackpackIds != null && idBackpackIds.isNotEmpty) {
        final allItems = <BackpackItemModel>[];
        for (final backpackId in idBackpackIds.toSet()) {
          final items = await _service.getBackpackItemsAdmin(backpackId);
          allItems.addAll(items);
        }
        final byItemId = <int, BackpackItemModel>{};
        for (final item in allItems) {
          byItemId[item.idBackpackItem] = item;
        }
        _selectedItems = byItemId.values.toList();
      } else if (idBackpack != null) {
        _selectedItems = await _service.getBackpackItemsAdmin(idBackpack);
      } else {
        _selectedItems = deliverItems;
      }
    } on ApiException catch (e) {
      _errorMessage = e.message;
    } finally {
      _loading = false;
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
    try {
      await _service.updateBackpackState(idBackpack, state);
      final idx = _backpacks.indexWhere((b) => b.id == idBackpack);
      if (idx >= 0) {
        _backpacks[idx] = BackpackModel.fromJson({
          ..._backpackToMap(_backpacks[idx]),
          'State': state,
        });
        notifyListeners();
      }
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteItem(int idItem) async {
    try {
      await _service.deleteBackpackItem(idItem);
      _selectedItems.removeWhere((i) => i.idBackpackItem == idItem);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> validateItem(int idItem) async {
    try {
      if (idItem <= 0) {
        _errorMessage = 'No se pudo identificar el ítem a validar';
        notifyListeners();
        return false;
      }

      await _service.validateBackpackItem(idItem);
      
      // Actualiza localmente SIN hacer reload del servidor
      // Esto evita conflictos de estado y "Guardado Offline"
      final idx = _selectedItems.indexWhere((i) => i.idBackpackItem == idItem);
      if (idx >= 0) {
        final item = _selectedItems[idx];
        _selectedItems[idx] = BackpackItemModel.fromJson({
          'IdBackpack': item.idBackpack,
          'IdBackPackItem': item.idBackpackItem,
          'IdOrdenVenta': item.idOrdenVenta,
          'FolioOrden': item.folioOrden,
          'IdStatusOrden': item.idStatusOrden,
          'StatusName': item.statusName,
          'NombreCliente': item.nombreCliente,
          'Validation': 1,
        });
        notifyListeners();
      }
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> validateItemByFolio({
    required int idBackpack,
    required String folio,
  }) async {
    try {
      final normalizedFolio = folio.trim();
      if (idBackpack <= 0 || normalizedFolio.isEmpty) {
        _errorMessage = 'Datos invalidos para validar la orden';
        notifyListeners();
        return false;
      }

      await _service.validateBackpackItemByFolio(
        idBackpack: idBackpack,
        folio: normalizedFolio,
      );

      final idx = _selectedItems.indexWhere(
        (i) => i.idBackpack == idBackpack && i.folioOrden.trim() == normalizedFolio,
      );

      if (idx >= 0) {
        final item = _selectedItems[idx];
        _selectedItems[idx] = BackpackItemModel.fromJson({
          'IdBackpack': item.idBackpack,
          'IdBackPackItem': item.idBackpackItem,
          'IdOrdenVenta': item.idOrdenVenta,
          'FolioOrden': item.folioOrden,
          'IdStatusOrden': item.idStatusOrden,
          'StatusName': item.statusName,
          'NombreCliente': item.nombreCliente,
          'Validation': 1,
        });
        notifyListeners();
      }

      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return false;
    }
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
