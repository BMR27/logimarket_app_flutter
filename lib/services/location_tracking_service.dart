import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

/// Servicio singleton que envía la ubicación del mensajero al backend
/// cada [intervalSeconds] segundos mientras [isTracking] == true.
class LocationTrackingService {
  LocationTrackingService._();
  static final instance = LocationTrackingService._();

  Timer? _timer;
  int? _idMensajero;
  int? _idOrden;
  bool _enViaje = false;
  String? _token;

  bool get isTracking => _timer != null && _timer!.isActive;
  bool get enViaje => _enViaje;
  int? get activeOrderId => _idOrden;

  static const int intervalSeconds = 10;

  Future<void> _ensureLocationReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Activa el GPS del dispositivo para iniciar viaje');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Permiso de ubicación denegado');
    }
  }

  /// Inicia el tracking.
  /// [idMensajero] — ID del usuario mensajero
  /// [token]       — JWT para autenticar la petición
  /// [idOrden]     — Orden activa (opcional)
  /// [enViaje]     — true cuando el mensajero dio "Iniciar Viaje"
  void start({
    required int idMensajero,
    required String token,
    int? idOrden,
    bool enViaje = false,
  }) {
    _idMensajero = idMensajero;
    _token = token;
    _idOrden = idOrden;
    _enViaje = enViaje;

    _timer?.cancel();
    _sendNow(); // envío inmediato
    _timer = Timer.periodic(
      const Duration(seconds: intervalSeconds),
      (_) => _sendNow(),
    );
    debugPrint('[LocationTracking] started idOrden=$idOrden enViaje=$enViaje');
  }

  /// Actualiza la orden activa y el estado de viaje sin reiniciar el timer.
  void updateTrip({int? idOrden, required bool enViaje}) {
    _idOrden = idOrden;
    _enViaje = enViaje;
    _sendNow();
  }

  /// Detiene el tracking y notifica al backend que ya no está en viaje.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _enViaje = false;
    _sendNow(forceEnViaje: false); // último ping sin enViaje
    _idOrden = null;
    debugPrint('[LocationTracking] stopped');
  }

  Future<void> _sendNow({bool? forceEnViaje}) async {
    if (_idMensajero == null || _token == null) return;
    try {
      await _ensureLocationReady();

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 8));

      final body = {
        'idMensajero': _idMensajero,
        'latitud': pos.latitude,
        'longitud': pos.longitude,
        'accuracy': pos.accuracy,
        if (_idOrden != null) 'idOrden': _idOrden,
        'enViaje': forceEnViaje ?? _enViaje,
      };

      final response = await http
          .post(
            Uri.parse(ApiConfig.ubicacion),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode >= 400) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      debugPrint('[LocationTracking] sent ok lat=${pos.latitude} lng=${pos.longitude} enViaje=${body['enViaje']} idOrden=${body['idOrden']}');
    } catch (e) {
      debugPrint('[LocationTracking] send error: $e');
      rethrow;
    }
  }
}
