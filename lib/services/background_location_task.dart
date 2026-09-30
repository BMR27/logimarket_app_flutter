import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Clave usada para compartir config entre el isolate principal y el background.
const String kPrefsMensajero  = 'bg_tracking_idMensajero';
const String kPrefsToken      = 'bg_tracking_token';
const String kPrefsIdOrden    = 'bg_tracking_idOrden';
const String kPrefsFolioOrden = 'bg_tracking_folioOrden';
const String kPrefsEnViaje    = 'bg_tracking_enViaje';
const String kPrefsApiUrl     = 'bg_tracking_apiUrl';
const String kPrefsAppVersion = 'bg_tracking_appVersion';
const String kPrefsColaPuntos = 'bg_tracking_colaPuntos';
const String kPrefsLocationDisclosureAccepted = 'location_disclosure_accepted';

/// Puntos con peor precisión no sirven para dibujar el recorrido (antes se
/// mandaba la "última posición conocida", con errores de hasta 2 km).
const double kPrecisionMaximaM = 100;
/// Distancia mínima entre puntos: da detalle en calle sin llenar la base
/// cuando el mensajero está detenido.
const int kDistanciaEntrePuntosM = 15;
/// Máximo de puntos guardados en el celular mientras no hay señal.
const int kColaMaxima = 1500;

/// Punto de entrada del foreground task — DEBE estar anotado con vm:entry-point.
@pragma('vm:entry-point')
void backgroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_LocationTaskHandler());
}

/// Rastreo continuo: el GPS queda encendido con un stream filtrado por
/// distancia (antes se encendía en frío cada 10 s y, si tardaba más de 8 s, se
/// mandaba una posición vieja). Los puntos se juntan en una cola que se envía
/// por lote en cada tick; si no hay datos, se conservan y se mandan después.
class _LocationTaskHandler extends TaskHandler {
  StreamSubscription<Position>? _suscripcion;
  final List<Map<String, dynamic>> _cola = [];
  Position? _ultima;
  DateTime? _ultimoEnvioOk;
  bool _enviando = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[BgTask] onStart starter=$starter');
    final prefs = await SharedPreferences.getInstance();
    final guardada = prefs.getString(kPrefsColaPuntos);
    if (guardada != null) {
      try {
        _cola.addAll((jsonDecode(guardada) as List).cast<Map<String, dynamic>>());
      } catch (_) {
        await prefs.remove(kPrefsColaPuntos);
      }
    }
    _iniciarStream();
  }

  void _iniciarStream() {
    final LocationSettings ajustes;
    if (defaultTargetPlatform == TargetPlatform.android) {
      ajustes = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: kDistanciaEntrePuntosM,
        intervalDuration: const Duration(seconds: 5),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      ajustes = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: kDistanciaEntrePuntosM,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: false,
      );
    } else {
      ajustes = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: kDistanciaEntrePuntosM,
      );
    }
    _suscripcion?.cancel();
    _suscripcion = Geolocator.getPositionStream(locationSettings: ajustes).listen(
      _alRecibir,
      onError: (e) {
        debugPrint('[BgTask] stream error: $e');
        // Se reintenta en el siguiente tick (GPS apagado, permiso revocado…)
        _suscripcion?.cancel();
        _suscripcion = null;
      },
      cancelOnError: true,
    );
  }

  void _alRecibir(Position p) {
    _ultima = p;
    if (p.accuracy > kPrecisionMaximaM) return;
    _encolar(p);
  }

  void _encolar(Position p) {
    _cola.add({
      'latitud': p.latitude,
      'longitud': p.longitude,
      'accuracy': p.accuracy,
      if (p.speed >= 0) 'velocidad': p.speed,
      'capturadoEn': p.timestamp.millisecondsSinceEpoch,
    });
    if (_cola.length > kColaMaxima) _cola.removeRange(0, _cola.length - kColaMaxima);
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    if (_suscripcion == null) _iniciarStream();

    // Parado sin moverse el stream no emite: se manda un punto cada ~minuto
    // para seguir apareciendo "en línea" en Gestión de Ruta.
    final sinEnviar = _ultimoEnvioOk == null ||
        DateTime.now().difference(_ultimoEnvioOk!) > const Duration(seconds: 60);
    if (_cola.isEmpty && sinEnviar) {
      final reciente = _ultima != null &&
          DateTime.now().difference(_ultima!.timestamp) < const Duration(minutes: 2);
      Position? pos = reciente ? _ultima : null;
      if (pos == null) {
        try {
          pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
              .timeout(const Duration(seconds: 20));
        } catch (_) {
          pos = null;
        }
      }
      if (pos != null) _encolar(pos);
    }
    await _enviar();
  }

  Future<void> _enviar() async {
    if (_enviando || _cola.isEmpty) return;
    _enviando = true;
    final prefs = await SharedPreferences.getInstance();
    try {
      final idMensajero = prefs.getInt(kPrefsMensajero);
      final token = prefs.getString(kPrefsToken);
      final apiUrl = prefs.getString(kPrefsApiUrl);
      if (idMensajero == null || token == null || apiUrl == null) {
        // Sesión cerrada: los puntos pendientes no deben mandarse a nombre de
        // quien inicie sesión después en este celular.
        _cola.clear();
        return;
      }

      final lote = _cola.take(300).toList();
      final permiso = await Geolocator.checkPermission();
      final idOrden = prefs.getInt(kPrefsIdOrden);
      final appVersion = prefs.getString(kPrefsAppVersion);
      final resp = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'idMensajero': idMensajero,
          'enViaje': prefs.getBool(kPrefsEnViaje) ?? false,
          if (idOrden != null) 'idOrden': idOrden,
          'permiso': permiso.name,
          'plataforma': defaultTargetPlatform.name.toLowerCase(),
          if (appVersion != null) 'appVersion': appVersion,
          'puntos': lote,
        }),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        _cola.removeRange(0, lote.length);
        _ultimoEnvioOk = DateTime.now();
        debugPrint('[BgTask] lote enviado: ${lote.length} puntos, pendientes ${_cola.length}');
      } else if (resp.statusCode == 400) {
        // Lote rechazado (p. ej. reloj del celular muy desfasado): no reintentar para siempre
        _cola.removeRange(0, lote.length);
      }
    } catch (e) {
      debugPrint('[BgTask] envío falló, se reintenta: $e');
    } finally {
      // La cola sobrevive a que Android reinicie el servicio
      if (_cola.isEmpty) {
        await prefs.remove(kPrefsColaPuntos);
      } else {
        await prefs.setString(kPrefsColaPuntos, jsonEncode(_cola));
      }
      _enviando = false;
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[BgTask] onDestroy — limpiando ubicación del backend');
    await _suscripcion?.cancel();
    _suscripcion = null;
    // Último intento de mandar lo pendiente antes de salir
    await _enviar();
    final prefs = await SharedPreferences.getInstance();
    final idMensajero = prefs.getInt(kPrefsMensajero);
    final token       = prefs.getString(kPrefsToken);
    final apiUrl      = prefs.getString(kPrefsApiUrl);
    if (idMensajero != null && token != null && apiUrl != null) {
      try {
        await http.delete(
          Uri.parse('$apiUrl/$idMensajero'),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 5));
        debugPrint('[BgTask] ubicación eliminada del backend');
      } catch (e) {
        debugPrint('[BgTask] error limpiando ubicación: $e');
      }
    }
  }
}
