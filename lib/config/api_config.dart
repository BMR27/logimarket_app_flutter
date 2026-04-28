// Configuración de la API — cambia BASE_URL por la URL de Railway cuando despliegues

class ApiConfig {
  // En desarrollo local:
  // static const String baseUrl = 'http://10.0.2.2:3000/api'; // Android emulador
  // static const String baseUrl = 'http://localhost:3000/api'; // iOS simulador

  // En producción (Railway):
  static const String baseUrl = 'https://logimarket-api-production.up.railway.app/api';

  // Endpoints
  static const String login = '$baseUrl/auth/login';
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
  static String updateOrder(int id) => '$baseUrl/orders/$id';
  static String orderNotes(int id) => '$baseUrl/orders/$id/notes';
  static String orderPriceRequest(int id) => '$baseUrl/orders/$id/price-request';
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
  static const String motivosStatus = '$baseUrl/catalogs/motivos-status';
  static const String explicacionesMotivo = '$baseUrl/catalogs/explicaciones-motivo';
  static const String adminReset = '$baseUrl/admin/reset';
  static const String mapsApiKey = 'AIzaSyBzIkJJsRkfTOYOvlaoaAx-0nveVOvwMgs';
}
