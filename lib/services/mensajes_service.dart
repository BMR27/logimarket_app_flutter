import '../config/api_config.dart';
import '../models/mensaje_model.dart';
import 'api_service.dart';

class MensajesService extends ApiService {
  Future<List<MensajeModel>> getMensajesPorOrden(int idOrden) async {
    final data = await get(ApiConfig.orderMensajes(idOrden));
    if (data is! List) return [];
    return data.map((e) => MensajeModel.fromJson(e as Map<String, dynamic>)).toList();
  }
}
