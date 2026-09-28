import '../config/api_config.dart';
import '../models/order_model.dart';
import '../models/product_model.dart';
import 'api_service.dart';

class OrdersService extends ApiService {
  List<dynamic> _ensureList(dynamic data, String endpointName) {
    if (data is List) return data;
    throw ApiException(
      statusCode: -1,
      message: 'Respuesta invalida del servidor en $endpointName',
    );
  }

  Future<List<OrderModel>> getOrders({
    required String equipos,
    String folio = '',
  }) async {
    final data = _ensureList(
      await get(ApiConfig.orders(equipos: equipos, folio: folio)),
      '/orders',
    );
    return data.map((e) => OrderModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<OrderModel>> getOrdersPaginated({
    required String equipos,
    String folio = '',
    int lastId = 0,
  }) async {
    final data = _ensureList(
      await get(
        ApiConfig.ordersPaginated(equipos: equipos, folio: folio, lastId: lastId),
      ),
      '/orders/paginated',
    );
    return data.map((e) => OrderModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<OrderModel>> getOrdersForMap({
    required String equipos,
    String folio = '',
  }) async {
    final data = _ensureList(
      await get(ApiConfig.ordersWays(equipos: equipos, folio: folio)),
      '/orders/ways',
    );
    return data.map((e) => OrderModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<OrderModel> getOrderDetail(int id, {required String equipos}) async {
    final data = await get(ApiConfig.orderDetail(id, equipos: equipos));
    return OrderModel.fromJson(data as Map<String, dynamic>);
  }

  /// Detalle de varias órdenes en una sola petición (POST /orders/batch).
  /// [missing] son los IDs que ya no existen en el servidor (borradas/depuradas).
  Future<({List<OrderModel> orders, List<int> missing})> getOrdersBatch(
    List<int> ids, {
    required String equipos,
  }) async {
    final data = await post(
      ApiConfig.ordersBatch,
      {'ids': ids, 'equipos': equipos},
      timeout: const Duration(seconds: 30),
    );
    if (data is! Map<String, dynamic> || data['orders'] is! List) {
      throw ApiException(statusCode: -1, message: 'Respuesta invalida del servidor en /orders/batch');
    }
    final orders = (data['orders'] as List)
        .map((e) => OrderModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final missing = (data['missing'] is List ? data['missing'] as List : const [])
        .map((e) => int.tryParse(e.toString()) ?? 0)
        .where((id) => id > 0)
        .toList();
    return (orders: orders, missing: missing);
  }

  /// Obtiene solo la dirección de una orden directamente de la tabla,
  /// sin filtro de equipo — para geocodificar en el mapa.
  Future<OrderModel> getOrderAddress(int id) async {
    final data = await get(ApiConfig.orderAddress(id));
    return OrderModel.fromJson(data as Map<String, dynamic>);
  }

  /// Guarda en el backend el punto ya validado contra el CP para que ningún
  /// otro celular ni sesión tenga que volver a geocodificar esta orden.
  /// [precision]: 'direccion' o 'cp' (centro del CP como último recurso).
  Future<void> saveOrderGeocode(
    int idOrden, {
    required double latitud,
    required double longitud,
    required String precision,
  }) async {
    await put(ApiConfig.orderGeocode(idOrden), {
      'latitud': latitud,
      'longitud': longitud,
      'precision': precision,
    });
  }

  Future<void> updateOrder({
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
    await put(ApiConfig.updateOrder(idOrden), {
      'status': status,
      'motivoStatus': motivoStatus,
      'explicacionMotivo': explicacionMotivo,
      'idUsuario': idUsuario,
      if (fechaReagenda != null) 'fechaReagenda': fechaReagenda,
      if (latitud != null) 'latitud': latitud,
      if (longitud != null) 'longitud': longitud,
      if (metros != null) 'metros': metros,
      if (tiempo != null) 'tiempo': tiempo,
    });
  }

  Future<List<ProductModel>> getProducts(int idOrden) async {
    final data = _ensureList(await get(ApiConfig.products(idOrden)), '/products/:idOrden');
    return data.map((e) => ProductModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Map<String, dynamic>>> getOrderStatusHistory(int idOrden) async {
    final data = _ensureList(
      await get(ApiConfig.orderStatusHistory(idOrden)),
      '/orders/:id/status-history',
    );
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
