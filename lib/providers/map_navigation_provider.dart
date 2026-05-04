import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class MapNavigationProvider extends ChangeNotifier {
  LatLng? _destination;
  LatLng? _origin;
  List<LatLng> _routePoints = [];
  bool _loading = false;
  bool _started = false; // false = vista previa, true = navegando
  double? _distanceMeters;
  int? _durationSeconds;
  String? _destinationAddress;
  String? _routeError;

  LatLng? get destination => _destination;
  LatLng? get origin => _origin;
  List<LatLng> get routePoints => _routePoints;
  bool get loading => _loading;
  bool get started => _started;
  double? get distanceMeters => _distanceMeters;
  int? get durationSeconds => _durationSeconds;
  String? get destinationAddress => _destinationAddress;
  String? get routeError => _routeError;

  String get distanceText {
    if (_distanceMeters == null) return '';
    if (_distanceMeters! >= 1000) {
      return '${(_distanceMeters! / 1000).toStringAsFixed(1)} km';
    }
    return '${_distanceMeters!.toInt()} m';
  }

  String get durationText {
    if (_durationSeconds == null) return '';
    final mins = (_durationSeconds! / 60).ceil();
    if (mins >= 60) {
      final h = mins ~/ 60;
      final m = mins % 60;
      return '${h}h ${m}min';
    }
    return '~$mins min';
  }

  double get bearingToDestination {
    if (_origin == null || _destination == null) return 0;
    return _calculateBearing(_origin!, _destination!);
  }

  Future<void> setDestination(
    LatLng destination,
    LatLng origin, {
    String? address,
    String? destinationQuery,
  }) async {
    _destination = destination;
    _origin = origin;
    _destinationAddress = address;
    _routePoints = [];
    _distanceMeters = null;
    _durationSeconds = null;
    _routeError = null;
    _loading = true;
    notifyListeners();

    var hasRealRoute = false;
    try {
      final googleByAddressOk = await _loadRouteFromGoogleDirectionsByAddress(
        origin,
        destinationQuery,
      );

      if (googleByAddressOk) {
        hasRealRoute = true;
      } else {
        final googleByCoordsOk = await _loadRouteFromGoogleDirections(origin, destination);
        if (googleByCoordsOk) {
          hasRealRoute = true;
        } else {
          final osrmOk = await _loadRouteFromOsrm(origin, destination);
          hasRealRoute = osrmOk;
        }
      }
    } catch (_) {
      hasRealRoute = false;
    }

    if (!hasRealRoute) {
      _routePoints = [];
      _distanceMeters = null;
      _durationSeconds = null;
      _routeError ??= 'No se pudo calcular una ruta real por calles';
    }

    _loading = false;
    _started = false;
    notifyListeners();
  }

  Future<bool> _loadRouteFromOsrm(LatLng origin, LatLng destination) async {
    final baseHosts = <String>[
      'https://router.project-osrm.org',
      'https://routing.openstreetmap.de/routed-car',
    ];

    for (final host in baseHosts) {
      try {
        // 1) Intento clásico (polyline): era el flujo que ya te funcionaba.
        final polylineUrl = Uri.parse(
          '$host/route/v1/driving'
          '/${origin.longitude},${origin.latitude}'
          ';${destination.longitude},${destination.latitude}'
          '?overview=full&geometries=polyline&alternatives=false&steps=false',
        );
        final polylineResp = await http.get(polylineUrl).timeout(const Duration(seconds: 10));
        if (polylineResp.statusCode == 200) {
          final data = jsonDecode(polylineResp.body) as Map<String, dynamic>;
          final routes = data['routes'] as List?;
          if (routes != null && routes.isNotEmpty) {
            final route = routes.first as Map<String, dynamic>;
            final geometry = (route['geometry'] ?? '').toString();
            if (geometry.isNotEmpty) {
              final parsed = _decodePolyline(geometry);
              if (parsed.isNotEmpty) {
                _distanceMeters = (route['distance'] as num?)?.toDouble();
                _durationSeconds = (route['duration'] as num?)?.toInt();
                _routePoints = parsed;
                return true;
              }
            }
          }
        }

        // 2) Segundo intento por host (geojson), más tolerante a cambios.
        final geojsonUrl = Uri.parse(
          '$host/route/v1/driving'
          '/${origin.longitude},${origin.latitude}'
          ';${destination.longitude},${destination.latitude}'
          '?overview=full&geometries=geojson&alternatives=false&steps=false',
        );
        final response = await http.get(geojsonUrl).timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) continue;

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final routes = data['routes'] as List?;
        if (routes == null || routes.isEmpty) continue;

        final route = routes.first as Map<String, dynamic>;
        final geometry = route['geometry'] as Map<String, dynamic>?;
        final coordinates = geometry?['coordinates'] as List?;
        if (coordinates == null || coordinates.isEmpty) continue;

        final parsed = <LatLng>[];
        for (final c in coordinates) {
          if (c is List && c.length >= 2) {
            final lng = (c[0] as num?)?.toDouble();
            final lat = (c[1] as num?)?.toDouble();
            if (lat != null && lng != null) {
              parsed.add(LatLng(lat, lng));
            }
          }
        }

        if (parsed.isEmpty) continue;

        _distanceMeters = (route['distance'] as num?)?.toDouble();
        _durationSeconds = (route['duration'] as num?)?.toInt();
        _routePoints = parsed;
        return true;
      } catch (_) {
        // Probar el siguiente host.
      }
    }

    return false;
  }

  double _haversineMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final la1 = a.latitude * pi / 180;
    final la2 = b.latitude * pi / 180;
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(la1) * cos(la2) * sin(dLng / 2) * sin(dLng / 2);
    return 2 * r * atan2(sqrt(h), sqrt(1 - h));
  }

  Future<bool> _loadRouteFromGoogleDirections(LatLng origin, LatLng destination) async {
    final key = ApiConfig.mapsApiKey.trim();
    if (key.isEmpty) return false;

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '&mode=driving&language=es&region=mx&key=${Uri.encodeComponent(key)}',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return false;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = (data['status'] ?? '').toString();
      if (status != 'OK') {
        _routeError = _googleStatusToMessage(status);
        return false;
      }

      final routes = (data['routes'] as List?) ?? const [];
      if (routes.isEmpty) return false;
      final route = routes.first as Map<String, dynamic>;

      final overview = route['overview_polyline'] as Map<String, dynamic>?;
      final points = (overview?['points'] ?? '').toString();
      if (points.isEmpty) return false;

      final legs = (route['legs'] as List?) ?? const [];
      if (legs.isNotEmpty) {
        final firstLeg = legs.first as Map<String, dynamic>;
        _distanceMeters = (firstLeg['distance']?['value'] as num?)?.toDouble();
        _durationSeconds = (firstLeg['duration']?['value'] as num?)?.toInt();
      }

      _routePoints = _decodePolyline(points);
      return _routePoints.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _loadRouteFromGoogleDirectionsByAddress(
    LatLng origin,
    String? destinationQuery,
  ) async {
    final key = ApiConfig.mapsApiKey.trim();
    final query = destinationQuery?.trim() ?? '';
    if (key.isEmpty || query.isEmpty) return false;

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${Uri.encodeComponent(query)}'
        '&mode=driving&language=es&region=mx&key=${Uri.encodeComponent(key)}',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return false;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = (data['status'] ?? '').toString();
      if (status != 'OK') {
        _routeError = _googleStatusToMessage(status);
        return false;
      }

      final routes = (data['routes'] as List?) ?? const [];
      if (routes.isEmpty) return false;
      final route = routes.first as Map<String, dynamic>;

      final overview = route['overview_polyline'] as Map<String, dynamic>?;
      final points = (overview?['points'] ?? '').toString();
      if (points.isEmpty) return false;

      final legs = (route['legs'] as List?) ?? const [];
      if (legs.isNotEmpty) {
        final firstLeg = legs.first as Map<String, dynamic>;
        _distanceMeters = (firstLeg['distance']?['value'] as num?)?.toDouble();
        _durationSeconds = (firstLeg['duration']?['value'] as num?)?.toInt();
      }

      _routePoints = _decodePolyline(points);
      return _routePoints.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  String _googleStatusToMessage(String status) {
    switch (status) {
      case 'ZERO_RESULTS':
        return 'No hay ruta vial disponible para ese destino';
      case 'REQUEST_DENIED':
      case 'OVER_DAILY_LIMIT':
      case 'OVER_QUERY_LIMIT':
        return 'Google Directions rechazó la solicitud (revisa API key y facturacion)';
      case 'INVALID_REQUEST':
        return 'Solicitud inválida al calcular la ruta';
      default:
        return 'No se pudo calcular una ruta real por calles';
    }
  }

  void startNavigation() {
    _started = true;
    notifyListeners();
  }

  void clearRoute() {
    _destination = null;
    _origin = null;
    _routePoints = [];
    _loading = false;
    _started = false;
    _distanceMeters = null;
    _durationSeconds = null;
    _destinationAddress = null;
    _routeError = null;
    notifyListeners();
  }

  double _calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * pi / 180;
    final lat2 = to.latitude * pi / 180;
    final dLng = (to.longitude - from.longitude) * pi / 180;
    final y = sin(dLng) * cos(lat2);
    final x =
        cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  List<LatLng> _decodePolyline(String encoded) {
    final result = <LatLng>[];
    int index = 0;
    final len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int shift = 0, res = 0, b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        res |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += ((res & 1) != 0 ? ~(res >> 1) : (res >> 1));

      shift = 0; res = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        res |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += ((res & 1) != 0 ? ~(res >> 1) : (res >> 1));

      result.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return result;
  }
}
