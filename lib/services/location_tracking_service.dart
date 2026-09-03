import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
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
  String? _folioOrden;

  bool get isTracking => _isRunning;
  bool get enViaje    => _enViaje;
  int? get activeOrderId => _idOrden;
  String? get activeOrderFolio => _folioOrden;

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
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      // No solicitar permiso aqui para cumplir Play policy: el permiso solo
      // se pide desde pantallas con aviso destacado visible para el usuario.
      throw Exception('Permiso de ubicacion pendiente. Abre Mapa o Iniciar viaje para autorizarlo.');
    }
    // NOTA: El permiso ACCESS_BACKGROUND_LOCATION se solicita desde la UI
    // (order_detail_screen.dart) DESPUÉS de mostrar el aviso destacado
    // obligatorio según la política de Google Play. No se solicita aquí para
    // garantizar que el usuario vea el aviso antes que el diálogo del sistema.
  }

  /// Guarda la config en SharedPreferences para que el isolate background
  /// pueda leerla sin depender del estado en memoria.
  Future<void> _savePrefs({
    required int idMensajero,
    required String token,
    int?    idOrden,
    String? folioOrden,
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
    if (folioOrden != null && folioOrden.trim().isNotEmpty) {
      await prefs.setString(kPrefsFolioOrden, folioOrden.trim());
    } else {
      await prefs.remove(kPrefsFolioOrden);
    }
  }

  /// Inicia el tracking con foreground service.
  Future<void> start({
    required int    idMensajero,
    required String token,
    int?            idOrden,
    String?         folioOrden,
    bool            enViaje = false,
  }) async {
    await _ensureLocationPermission();

    if (_isRunning) {
      // Ya está corriendo — solo refrescamos credenciales, NO tocamos _enViaje/_idOrden
      // (éstos son gestionados exclusivamente por updateTrip).
      await _savePrefs(
        idMensajero: idMensajero,
        token:       token,
        idOrden:     _idOrden,
        folioOrden:  _folioOrden,
        enViaje:     _enViaje,
      );
      debugPrint('[LocationTracking] already running — creds refreshed, enViaje=$_enViaje idOrden=$_idOrden');
      return;
    }

    _enViaje = enViaje;
    _idOrden = idOrden;
    _folioOrden = (folioOrden != null && folioOrden.trim().isNotEmpty)
        ? folioOrden.trim()
        : null;

    await _savePrefs(
      idMensajero: idMensajero,
      token:       token,
      idOrden:     idOrden,
      folioOrden:  _folioOrden,
      enViaje:     enViaje,
    );

    // Solicitar exención de optimización de batería para que Android
    // no mate el foreground service (crítico en Samsung, Xiaomi, Huawei, etc.)
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    await FlutterForegroundTask.startService(
      notificationTitle: 'Logimarket activo',
      notificationText:  'Rastreando tu ubicación...',
      callback:           backgroundTaskCallback,
    );

    _isRunning = await FlutterForegroundTask.isRunningService;
    debugPrint('[LocationTracking] started running=$_isRunning enViaje=$enViaje');

    // Ping inmediato para aparecer en Gestión de Ruta sin esperar el primer tick (10s).
    unawaited(_sendImmediatePing(idMensajero: idMensajero, token: token));
  }

  /// Envía un ping de ubicación de inmediato en el hilo principal.
  Future<void> _sendImmediatePing({
    required int    idMensajero,
    required String token,
  }) async {
    try {
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(const Duration(seconds: 8));
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) return;
      final prefs   = await SharedPreferences.getInstance();
      final apiUrl  = prefs.getString(kPrefsApiUrl);
      final idOrden = prefs.getInt(kPrefsIdOrden);
      final enViaje = prefs.getBool(kPrefsEnViaje) ?? false;
      if (apiUrl == null) return;
      final body = <String, dynamic>{
        'idMensajero': idMensajero,
        'latitud':     pos.latitude,
        'longitud':    pos.longitude,
        'accuracy':    pos.accuracy,
        'enViaje':     enViaje,
        if (idOrden != null) 'idOrden': idOrden,
      };
      await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 8));
      debugPrint('[LocationTracking] immediate ping ok lat=${pos.latitude} lng=${pos.longitude}');
    } catch (e) {
      debugPrint('[LocationTracking] immediate ping error: $e');
    }
  }

  /// Actualiza orden activa y estado de viaje sin reiniciar el servicio.
  Future<void> updateTrip({int? idOrden, String? folioOrden, required bool enViaje}) async {
    _enViaje = enViaje;
    if (enViaje) {
      _idOrden = idOrden;
      if (folioOrden != null && folioOrden.trim().isNotEmpty) {
        _folioOrden = folioOrden.trim();
      }
    } else {
      _idOrden = null;
      _folioOrden = null;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kPrefsEnViaje, enViaje);
    if (_idOrden != null) {
      await prefs.setInt(kPrefsIdOrden, _idOrden!);
    } else {
      await prefs.remove(kPrefsIdOrden);
    }
    if (_folioOrden != null && _folioOrden!.isNotEmpty) {
      await prefs.setString(kPrefsFolioOrden, _folioOrden!);
    } else {
      await prefs.remove(kPrefsFolioOrden);
    }
    debugPrint('[LocationTracking] trip updated idOrden=$_idOrden folio=$_folioOrden enViaje=$enViaje');
  }

  /// Detiene el foreground service y borra la ubicación del backend.
  Future<void> stop() async {
    // Leer prefs ANTES de borrarlos para poder llamar al DELETE
    final prefs = await SharedPreferences.getInstance();
    final idMensajero = prefs.getInt(kPrefsMensajero);
    final token       = prefs.getString(kPrefsToken);
    final apiUrl      = prefs.getString(kPrefsApiUrl);

    await FlutterForegroundTask.stopService();
    _isRunning = false;
    _enViaje   = false;
    _idOrden   = null;

    await prefs.remove(kPrefsMensajero);
    await prefs.remove(kPrefsToken);
    await prefs.remove(kPrefsIdOrden);
    await prefs.remove(kPrefsFolioOrden);
    await prefs.remove(kPrefsEnViaje);
    await prefs.remove(kPrefsApiUrl);

    // Borrar del backend para que desaparezca del mapa de inmediato
    if (idMensajero != null && token != null && apiUrl != null) {
      try {
        await http.delete(
          Uri.parse('$apiUrl/$idMensajero'),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 5));
        debugPrint('[LocationTracking] ubicación eliminada del backend');
      } catch (e) {
        debugPrint('[LocationTracking] error al eliminar ubicación: $e');
      }
    }

    debugPrint('[LocationTracking] stopped');
  }
}
