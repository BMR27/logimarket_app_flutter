import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class MapNavigationProvider extends ChangeNotifier {
  LatLng? _destination;
  LatLng? _origin;
  List<LatLng> _routePoints = [];
  bool _loading = false;
  bool _started = false; // false = vista previa, true = navegando
  double? _distanceMeters;
  int? _durationSeconds;
  String? _destinationAddress;

  LatLng? get destination => _destination;
  LatLng? get origin => _origin;
  List<LatLng> get routePoints => _routePoints;
  bool get loading => _loading;
  bool get started => _started;
  double? get distanceMeters => _distanceMeters;
  int? get durationSeconds => _durationSeconds;
  String? get destinationAddress => _destinationAddress;

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
  }) async {
    _destination = destination;
    _origin = origin;
    _destinationAddress = address;
    _routePoints = [];
    _distanceMeters = null;
    _durationSeconds = null;
    _loading = true;
    notifyListeners();

    try {
      // OSRM — routing gratuito, sin API key
      // IMPORTANTE: OSRM usa orden lng,lat
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving'
        '/${origin.longitude},${origin.latitude}'
        ';${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=polyline',
      );
      final response =
          await http.get(url).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final route = routes[0] as Map<String, dynamic>;
          _distanceMeters = (route['distance'] as num).toDouble();
          _durationSeconds = (route['duration'] as num).toInt();
          _routePoints = _decodePolyline(route['geometry'] as String);
        } else {
          _routePoints = [origin, destination];
        }
      } else {
        _routePoints = [origin, destination];
      }
    } catch (_) {
      _routePoints = [origin, destination];
    }

    _loading = false;
    _started = false;
    notifyListeners();
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
