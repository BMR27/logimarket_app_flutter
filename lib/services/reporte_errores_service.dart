import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// Reporta al monitoreo de NEXT OS LITE (Configuración → Alertas, origen "App mensajeros")
/// los errores no controlados de la app y las peticiones en las que el servidor no respondió.
/// Reglas para no afectar al mensajero: se envía en segundo plano, sin esperar respuesta,
/// máximo [_maxPorSesion] reportes por sesión, sin repetir el mismo error, y nunca lanza
/// excepciones.
class ReporteErroresService {
  static const int _maxPorSesion = 20;
  static int _enviados = 0;
  static final Set<String> _vistos = <String>{};

  static String get _plataforma {
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      return 'desconocida';
    }
  }

  static void reportar({
    required String mensaje,
    String? stack,
    String tipo = 'error',
    String? pantalla,
    String? ruta,
    String? metodo,
    int? duracionMs,
  }) {
    try {
      if (mensaje.isEmpty) return;
      final clave = '$tipo|${ruta ?? pantalla ?? ''}|${mensaje.length > 200 ? mensaje.substring(0, 200) : mensaje}';
      if (_vistos.contains(clave) || _enviados >= _maxPorSesion) return;
      _vistos.add(clave);
      _enviados++;
      final cuerpo = jsonEncode({
        'tipo': tipo,
        'mensaje': mensaje.length > 1000 ? mensaje.substring(0, 1000) : mensaje,
        if (stack != null) 'stack': stack.length > 6000 ? stack.substring(0, 6000) : stack,
        if (pantalla != null) 'pantalla': pantalla,
        if (ruta != null) 'ruta': ruta,
        if (metodo != null) 'metodo': metodo,
        if (duracionMs != null) 'duracionMs': duracionMs,
        'plataforma': _plataforma,
      });
      // Sin await: el reporte nunca retrasa ni interrumpe la app
      unawaited(http
          .post(Uri.parse('${ApiConfig.baseUrl}/monitoreo/app'),
              headers: {'Content-Type': 'application/json'}, body: cuerpo)
          .timeout(const Duration(seconds: 8))
          .then((_) {}, onError: (_) {}));
    } catch (_) {
      // El reporte nunca debe afectar la app
    }
  }

  /// Ruta sin parámetros ni ids, para agrupar el mismo problema (ej. /api/orders/:id).
  static String rutaDe(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.path
          .split('/')
          .map((s) => RegExp(r'^\d+$').hasMatch(s) ? ':id' : s)
          .join('/');
    } catch (_) {
      return url;
    }
  }
}
