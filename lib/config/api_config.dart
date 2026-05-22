// Configuración de la API — cambia BASE_URL por la URL de Railway cuando despliegues

class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://logimarket-api-production.up.railway.app/api',
  );

  // En desarrollo local:
  // Usa --dart-define=API_BASE_URL=... para sobreescribir esta base.

  // Endpoints
  static const String login = '$baseUrl/auth/login';
  static const String logout = '$baseUrl/auth/logout';
  static const String version = '$baseUrl/auth/version';
  static String equipos(int idUsuario) => '$baseUrl/equipos/$idUsuario';
  static String orders({String equipos = '', String folio = ''}) =>
      '$baseUrl/orders?equipos=${Uri.encodeComponent(equipos)}&folio=${Uri.encodeComponent(folio)}';
  static String ordersPaginated({String equipos = '', String folio = '', int lastId = 0}) =>
      '$baseUrl/orders/paginated?equipos=${Uri.encodeComponent(equipos)}&folio=${Uri.encodeComponent(folio)}&lastId=$lastId';
  static String ordersWays({String equipos = '', String folio = ''}) =>
      '$baseUrl/orders/ways?equipos=${Uri.encodeComponent(equipos)}&folio=${Uri.encodeComponent(folio)}';
  static String orderDetail(int id, {String equipos = ''}) =>
      '$baseUrl/orders/$id?equipos=${Uri.encodeComponent(equipos)}';
  static String orderAddress(int id) => '$baseUrl/orders/$id/address';
  static String updateOrder(int id) => '$baseUrl/orders/$id';
  static String orderNotes(int id) => '$baseUrl/orders/$id/notes';
  static String orderPriceRequest(int id) => '$baseUrl/orders/$id/price-request';
  static String orderGeneratePayment(int id) => '$baseUrl/orders/$id/payments/generate';
  static String orderPaymentStatus(int id) => '$baseUrl/orders/$id/payments/status';
    static String orderStatusHistory(int id) => '$baseUrl/orders/$id/status-history';
  static String products(int idOrden) => '$baseUrl/products/$idOrden';
  static String productsSimple(int idOrden) => '$baseUrl/products/$idOrden/simple';
  static String search({String equipos = '', String folio = ''}) =>
      '$baseUrl/search?equipos=${Uri.encodeComponent(equipos)}&folio=${Uri.encodeComponent(folio)}';
  static String searchBackpack({String idEquipo = '', String folio = ''}) =>
      '$baseUrl/search/backpack?idEquipo=${Uri.encodeComponent(idEquipo)}&folio=${Uri.encodeComponent(folio)}';
  static String searchRepartidores({String equipos = '', String nombre = ''}) =>
      '$baseUrl/search/repartidores?equipos=${Uri.encodeComponent(equipos)}&nombre=${Uri.encodeComponent(nombre)}';
  static String backpacks(int idUsuario) => '$baseUrl/backpacks/$idUsuario';
  static const String createBackpack = '$baseUrl/backpacks';
  static String updateBackpack(int id) => '$baseUrl/backpacks/$id';
  static String backpackItems(int id) => '$baseUrl/backpacks/$id/items';
  static String deliverItems(int idRepartidor) =>
      '$baseUrl/backpacks/deliver/$idRepartidor/items';
  static String deleteBackpackItem(int id) => '$baseUrl/backpacks/items/$id';
  static String validateBackpackItem(int id) => '$baseUrl/backpacks/items/$id/validate';
    static String validateBackpackItemByFolio(int idBackpack) => '$baseUrl/backpacks/$idBackpack/items/validate-folio';
  static const String motivosStatus = '$baseUrl/catalogs/motivos-status';
  static const String explicacionesMotivo = '$baseUrl/catalogs/explicaciones-motivo';
  static const String adminReset = '$baseUrl/admin/reset';
    static const String mapsApiKey = 'AIzaSyBzIkJJsRkfTOYOvlaoaAx-0nveVOvwMgs';
    static String orderEvidencia(int id) => '$baseUrl/orders/$id/evidencia';

  // Ubicación en tiempo real
  static const String ubicacion = '$baseUrl/ubicacion';
  static String ubicacionMensajero(int id) => '$baseUrl/ubicacion/$id';
}
