import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/api_config.dart';
import 'api_service.dart';

/// Ruta en auto calculada en el servidor.
class RutaCalculada {
  final List<LatLng> puntos;
  final double distanciaMetros;
  final int duracionSegundos;

  const RutaCalculada({
    required this.puntos,
    required this.distanciaMetros,
    required this.duracionSegundos,
  });
}

/// Rutas y centros de CP con HERE, a través de logimarket-api.
class GeoService extends ApiService {
  Future<RutaCalculada?> ruta(LatLng origen, LatLng destino) async {
    final data = await get(ApiConfig.geoRuta(
      origen.latitude, origen.longitude, destino.latitude, destino.longitude,
    ));
    if (data is! Map<String, dynamic> || data['puntos'] is! List) return null;
    final puntos = <LatLng>[];
    for (final p in data['puntos'] as List) {
      if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
        puntos.add(LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()));
      }
    }
    if (puntos.isEmpty) return null;
    return RutaCalculada(
      puntos: puntos,
      distanciaMetros: (data['distanciaMetros'] as num?)?.toDouble() ?? 0,
      duracionSegundos: (data['duracionSegundos'] as num?)?.toInt() ?? 0,
    );
  }

  Future<LatLng?> centroCp(String cp) async {
    final data = await get(ApiConfig.geoCp(cp));
    if (data is! Map<String, dynamic>) return null;
    final lat = (data['latitud'] as num?)?.toDouble();
    final lng = (data['longitud'] as num?)?.toDouble();
    return lat != null && lng != null ? LatLng(lat, lng) : null;
  }
}
