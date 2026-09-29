import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/api_config.dart';
import 'api_service.dart';

/// Punto de una orden resuelto por el servidor.
class PuntoOrden {
  final LatLng posicion;
  /// cp < colonia < direccion < exacta < entrega < manual
  final String precision;
  const PuntoOrden(this.posicion, this.precision);

  /// Solo el centro del CP: el pin es aproximado y conviene confirmarlo.
  bool get esAproximado => precision == 'cp' || precision == 'colonia';
}

class SugerenciaDireccion {
  final String placeId;
  final String principal;
  final String secundario;
  final int? metros;
  const SugerenciaDireccion({required this.placeId, required this.principal, required this.secundario, this.metros});
}

class LugarElegido {
  final LatLng posicion;
  final String direccion;
  final String placeId;
  const LugarElegido(this.posicion, this.direccion, this.placeId);
}

class RutaCalculada {
  final List<LatLng> puntos;
  final double? distanciaMetros;
  final int? duracionSegundos;
  const RutaCalculada(this.puntos, this.distanciaMetros, this.duracionSegundos);
}

/// Mapas contra el backend: la geocodificación, la búsqueda de direcciones (Places)
/// y las rutas (Routes API con tráfico) se hacen en el servidor con Google.
class GeoService extends ApiService {
  /// Pines corregidos a mano en esta sesión: el mapa los aplica al instante, antes
  /// de que la lista de órdenes se vuelva a descargar.
  static final ValueNotifier<Map<int, LatLng>> pinesCorregidos = ValueNotifier(const {});

  static void registrarPinCorregido(int idOrden, LatLng p) {
    pinesCorregidos.value = {...pinesCorregidos.value, idOrden: p};
  }

  /// Puntos de varias órdenes. Devuelve los resueltos y los que el servidor dejó
  /// pendientes para otra llamada. Lanza si el servidor no tiene el endpoint.
  Future<({Map<int, PuntoOrden> puntos, List<int> pendientes})> puntosDeOrdenes(List<int> ids) async {
    final data = await post(ApiConfig.ordersGeocodeBatch, {'ids': ids}, timeout: const Duration(seconds: 45))
        as Map<String, dynamic>;
    final puntos = <int, PuntoOrden>{};
    final coords = (data['coords'] as Map<String, dynamic>?) ?? const {};
    coords.forEach((k, v) {
      final id = int.tryParse(k);
      final m = v as Map<String, dynamic>;
      final lat = (m['latitud'] as num?)?.toDouble();
      final lng = (m['longitud'] as num?)?.toDouble();
      if (id != null && lat != null && lng != null) {
        puntos[id] = PuntoOrden(LatLng(lat, lng), (m['precision'] ?? 'direccion').toString());
      }
    });
    final pendientes = ((data['pendientes'] as List?) ?? const []).map((e) => (e as num).toInt()).toList();
    return (puntos: puntos, pendientes: pendientes);
  }

  Future<List<SugerenciaDireccion>> autocompletar(String q, String sessionToken, {LatLng? cerca}) async {
    final data = await get(ApiConfig.geoAutocomplete(
      q: q, sessionToken: sessionToken, lat: cerca?.latitude, lng: cerca?.longitude,
    )) as Map<String, dynamic>;
    return ((data['sugerencias'] as List?) ?? const []).map((e) {
      final m = e as Map<String, dynamic>;
      return SugerenciaDireccion(
        placeId: (m['placeId'] ?? '').toString(),
        principal: (m['principal'] ?? '').toString(),
        secundario: (m['secundario'] ?? '').toString(),
        metros: (m['metros'] as num?)?.toInt(),
      );
    }).where((s) => s.placeId.isNotEmpty).toList();
  }

  Future<LugarElegido> lugar(String placeId, String sessionToken) async {
    final m = await get(ApiConfig.geoPlace(placeId, sessionToken: sessionToken)) as Map<String, dynamic>;
    return LugarElegido(
      LatLng((m['latitud'] as num).toDouble(), (m['longitud'] as num).toDouble()),
      (m['direccion'] ?? '').toString(),
      (m['placeId'] ?? placeId).toString(),
    );
  }

  Future<String?> direccionDe(LatLng p) async {
    final m = await get(ApiConfig.geoReverse(p.latitude, p.longitude)) as Map<String, dynamic>;
    return m['direccion']?.toString();
  }

  Future<RutaCalculada> ruta(LatLng origen, LatLng destino) async {
    final m = await post(ApiConfig.geoRoute, {
      'origen': {'lat': origen.latitude, 'lng': origen.longitude},
      'destino': {'lat': destino.latitude, 'lng': destino.longitude},
    }) as Map<String, dynamic>;
    return RutaCalculada(
      decodificarPolilinea((m['polilinea'] ?? '').toString()),
      (m['distanciaMetros'] as num?)?.toDouble(),
      (m['duracionSegundos'] as num?)?.toInt(),
    );
  }

  /// Token de sesión de Places: agrupa autocompletar + detalle en un solo cobro.
  static String nuevoTokenSesion() {
    final r = Random.secure();
    String hex(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-${hex(4)}-${hex(12)}';
  }
}

List<LatLng> decodificarPolilinea(String encoded) {
  final result = <LatLng>[];
  var index = 0, lat = 0, lng = 0;
  while (index < encoded.length) {
    var shift = 0, res = 0, b = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      res |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lat += (res & 1) != 0 ? ~(res >> 1) : (res >> 1);
    shift = 0;
    res = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      res |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lng += (res & 1) != 0 ? ~(res >> 1) : (res >> 1);
    result.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return result;
}
