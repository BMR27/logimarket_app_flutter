import '../config/api_config.dart';
import '../models/backpack_model.dart';
import '../models/backpack_item_model.dart';
import 'api_service.dart';

class BackpacksService extends ApiService {
  Future<List<BackpackModel>> getBackpacks(int idUsuario) async {
    final data = await get(ApiConfig.backpacks(idUsuario)) as List;
    return data.map((e) => BackpackModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> createBackpack({
    required int idRepartidor,
    required int idLider,
    required String orderIds,
  }) async {
    await post(ApiConfig.createBackpack, {
      'idRepartidor': idRepartidor,
      'idLider': idLider,
      'orderIds': orderIds,
    });
  }

  Future<void> updateBackpackState(int idBackpack, int state) async {
    await put(ApiConfig.updateBackpack(idBackpack), {'state': state});
  }

  Future<List<BackpackItemModel>> getBackpackItemsAdmin(int idBackpack) async {
    final data = await get(ApiConfig.backpackItems(idBackpack)) as List;
    return data.map((e) => BackpackItemModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<BackpackItemModel>> getBackpackItemsDeliver(int idRepartidor) async {
    final data = await get(ApiConfig.deliverItems(idRepartidor)) as List;
    return data.map((e) => BackpackItemModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> deleteBackpackItem(int idItem) async {
    await delete(ApiConfig.deleteBackpackItem(idItem));
  }

  Future<void> validateBackpackItem(int idItem) async {
    await put(ApiConfig.validateBackpackItem(idItem), {});
  }

  Future<void> validateBackpackItemByFolio({
    required int idBackpack,
    required String folio,
  }) async {
    await put(ApiConfig.validateBackpackItemByFolio(idBackpack), {
      'folio': folio,
    });
  }

  Future<List<Map<String, dynamic>>> searchOrders({
    required String equipos,
    required String folio,
  }) async {
    final data = await get(ApiConfig.search(equipos: equipos, folio: folio)) as List;
    return data.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> searchRepartidores({
    required String equipos,
    required String nombre,
  }) async {
    final data = await get(
      ApiConfig.searchRepartidores(equipos: equipos, nombre: nombre),
    ) as List;
    return data.cast<Map<String, dynamic>>();
  }
}
