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

/// Punto de entrada del foreground task — DEBE estar anotado con vm:entry-point.
@pragma('vm:entry-point')
void backgroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_LocationTaskHandler());
}

class _LocationTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[BgTask] onStart starter=$starter');
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    final idMensajero = prefs.getInt(kPrefsMensajero);
    final token       = prefs.getString(kPrefsToken);
    final apiUrl      = prefs.getString(kPrefsApiUrl);
    final idOrden     = prefs.getInt(kPrefsIdOrden);
    final enViaje     = prefs.getBool(kPrefsEnViaje) ?? false;

    if (idMensajero == null || token == null || apiUrl == null) return;

    try {
      // Intentar posición con precisión media (GPS + red) — más rápida que 'high'.
      // Si falla o tarda demasiado, usar última posición conocida como fallback
      // para garantizar que el ping siempre se envíe aunque el GPS esté frío.
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(const Duration(seconds: 8));
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
        debugPrint('[BgTask] GPS timeout — usando última posición conocida');
      }
      if (pos == null) {
        debugPrint('[BgTask] sin posición disponible, ping cancelado');
        return;
      }

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
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 8));

      debugPrint('[BgTask] ping ok lat=${pos.latitude} lng=${pos.longitude}');
    } catch (e) {
      debugPrint('[BgTask] ping error: $e');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[BgTask] onDestroy — limpiando ubicación del backend');
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
