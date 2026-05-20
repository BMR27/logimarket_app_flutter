import '../config/api_config.dart';
import 'api_service.dart';

class PaymentsService extends ApiService {
  Future<Map<String, dynamic>> generatePayment(int orderId) async {
    final data = await post(ApiConfig.orderGeneratePayment(orderId), {});
    if (data is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: -1,
        message: 'Respuesta invalida al generar pago',
      );
    }

    final payment = data['payment'];
    if (payment is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: -1,
        message: 'No se recibio objeto de pago',
      );
    }

    return Map<String, dynamic>.from(payment);
  }

  Future<Map<String, dynamic>> getPaymentStatus(int orderId) async {
    final data = await get(ApiConfig.orderPaymentStatus(orderId));
    if (data is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: -1,
        message: 'Respuesta invalida al consultar estado de pago',
      );
    }

    final payment = data['payment'];
    if (payment is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: -1,
        message: 'No se recibio estado de pago',
      );
    }

    final merged = Map<String, dynamic>.from(payment);
    merged['canDeliver'] = data['canDeliver'] == true;
    return merged;
  }
}
