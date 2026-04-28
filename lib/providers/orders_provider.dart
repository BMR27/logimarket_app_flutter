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
  bool _loading = false;
  bool _offline = false;
  String? _errorMessage;

  List<OrderModel> get orders => _orders;
  OrderModel? get selectedOrder => _selectedOrder;
  List<ProductModel> get products => _products;
  bool get loading => _loading;
  bool get offline => _offline;
  String? get errorMessage => _errorMessage;

  Future<void> loadOrders(String equipos, {String folio = ''}) async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _orders = await _service.getOrders(equipos: equipos, folio: folio);
      // Guardar en local para modo offline
      for (final o in _orders) {
        await _localDb.upsertOrder(o);
      }
      _offline = false;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _offline = true;
      await _loadFromLocal();
    } catch (_) {
      _offline = true;
      await _loadFromLocal();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> _loadFromLocal() async {
    final rows = await _localDb.getAllOrders();
    // Minimal parse from raw map
    _orders = rows.map((r) => OrderModel.fromJson(r)).toList();
  }

  Future<void> selectOrder(int id, String equipos) async {
    _loading = true;
    _selectedOrder = null;
    _products = [];
    _errorMessage = null;
    notifyListeners();
    try {
      _selectedOrder = await _service.getOrderDetail(id, equipos: equipos);
      _products = await _service.getProducts(id);
    } on ApiException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Error al cargar la orden: $e';
    }
    _loading = false;
    notifyListeners();
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
    } on ApiException {
      // Guardar en local si no hay red
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
