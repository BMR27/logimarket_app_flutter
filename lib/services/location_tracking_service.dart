import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import 'background_location_task.dart';

/// Servicio singleton que mantiene el rastreo de ubicación activo incluso
/// cuando la app está en segundo plano (Waze, Google Maps, etc.).
/// Usa FlutterForegroundTask para un foreground service en Android.
class LocationTrackingService {
  LocationTrackingService._();
  static final instance = LocationTrackingService._();

  bool _isRunning = false;
  bool _enViaje   = false;
  int? _idOrden;

  bool get isTracking => _isRunning;
  bool get enViaje    => _enViaje;
  int? get activeOrderId => _idOrden;

  static const int intervalSeconds = 10;

  // ── Inicialización (llamar una sola vez en main) ─────────────────────────
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId:   'lm_location',
        channelName: 'Rastreo Logimarket',
        channelDescription: 'Mantiene el rastreo activo en segundo plano',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(intervalSeconds * 1000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> _ensureLocationPermission() async {
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

  /// Guarda la config en SharedPreferences para que el isolate background
  /// pueda leerla sin depender del estado en memoria.
  Future<void> _savePrefs({
    required int idMensajero,
    required String token,
    int?    idOrden,
    required bool enViaje,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kPrefsMensajero, idMensajero);
    await prefs.setString(kPrefsToken,  token);
    await prefs.setString(kPrefsApiUrl, ApiConfig.ubicacion);
    await prefs.setBool(kPrefsEnViaje,  enViaje);
    if (idOrden != null) {
      await prefs.setInt(kPrefsIdOrden, idOrden);
    } else {
      await prefs.remove(kPrefsIdOrden);
    }
  }

  /// Inicia el tracking con foreground service.
  Future<void> start({
    required int    idMensajero,
    required String token,
    int?            idOrden,
    bool            enViaje = false,
  }) async {
    _enViaje = enViaje;
    _idOrden = idOrden;

    await _ensureLocationPermission();
    await _savePrefs(
      idMensajero: idMensajero,
      token:       token,
      idOrden:     idOrden,
      enViaje:     enViaje,
    );

    if (_isRunning) {
      // Ya está corriendo — solo actualizamos los prefs (suficiente para el handler).
      debugPrint('[LocationTracking] updated prefs idOrden=$idOrden enViaje=$enViaje');
      return;
    }

    await FlutterForegroundTask.startService(
      notificationTitle: 'Logimarket activo',
      notificationText:  'Rastreando tu ubicación...',
      callback:           backgroundTaskCallback,
    );

    _isRunning = await FlutterForegroundTask.isRunningService;
    debugPrint('[LocationTracking] started running=$_isRunning enViaje=$enViaje');
  }

  /// Actualiza orden activa y estado de viaje sin reiniciar el servicio.
  Future<void> updateTrip({int? idOrden, required bool enViaje}) async {
    _idOrden = idOrden;
    _enViaje = enViaje;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kPrefsEnViaje, enViaje);
    if (idOrden != null) {
      await prefs.setInt(kPrefsIdOrden, idOrden);
    } else {
      await prefs.remove(kPrefsIdOrden);
    }
    debugPrint('[LocationTracking] trip updated idOrden=$idOrden enViaje=$enViaje');
  }

  /// Detiene el foreground service.
  Future<void> stop() async {
    await FlutterForegroundTask.stopService();
    _isRunning = false;
    _enViaje   = false;
    _idOrden   = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kPrefsMensajero);
    await prefs.remove(kPrefsToken);
    await prefs.remove(kPrefsIdOrden);
    await prefs.remove(kPrefsEnViaje);
    await prefs.remove(kPrefsApiUrl);
    debugPrint('[LocationTracking] stopped');
  }
}
