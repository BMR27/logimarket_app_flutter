import '../config/api_config.dart';
import '../models/catalogs_model.dart';
import 'api_service.dart';

class CatalogsService extends ApiService {
  Future<List<MotivoStatusModel>> getMotivosStatus() async {
    final data = await get(ApiConfig.motivosStatus) as List;
    return data
        .map((e) => MotivoStatusModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<MotivoExplicacionModel>> getExplicacionesMotivo() async {
    final data = await get(ApiConfig.explicacionesMotivo) as List;
    return data
        .map((e) => MotivoExplicacionModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
