import '../config/api_config.dart';
import '../models/order_model.dart';
import '../models/product_model.dart';
import 'api_service.dart';

class OrdersService extends ApiService {
  Future<List<OrderModel>> getOrders({
    required String equipos,
    String folio = '',
  }) async {
    final data = await get(ApiConfig.orders(equipos: equipos, folio: folio)) as List;
    return data.map((e) => OrderModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<OrderModel>> getOrdersPaginated({
    required String equipos,
    String folio = '',
    int lastId = 0,
  }) async {
    final data = await get(
      ApiConfig.ordersPaginated(equipos: equipos, folio: folio, lastId: lastId),
    ) as List;
    return data.map((e) => OrderModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<OrderModel>> getOrdersForMap({
    required String equipos,
    String folio = '',
  }) async {
    final data = await get(ApiConfig.ordersWays(equipos: equipos, folio: folio)) as List;
    return data.map((e) => OrderModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<OrderModel> getOrderDetail(int id, {required String equipos}) async {
    final data = await get(ApiConfig.orderDetail(id, equipos: equipos));
    return OrderModel.fromJson(data as Map<String, dynamic>);
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
    final data = await get(ApiConfig.products(idOrden)) as List;
    return data.map((e) => ProductModel.fromJson(e as Map<String, dynamic>)).toList();
  }
}
