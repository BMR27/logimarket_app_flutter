// Valida el comportamiento de OrdersProvider.loadOrdersByIds cuando a un
// mensajero se le asignan muchas órdenes (ej. 60), SIN tocar el backend
// real: levanta un servidor HTTP local que imita la API y le apunta la app
// vía --dart-define=API_BASE_URL (el mismo mecanismo que ya usa la app para
// apuntar a un backend de desarrollo).
//
// Corre con:
//   flutter test --dart-define=API_BASE_URL=http://127.0.0.1:8765/api \
//     test/orders_load_stress_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logimarket_app/config/api_config.dart';
import 'package:logimarket_app/providers/orders_provider.dart';

Map<String, dynamic> _fakeOrderJson(int id, {int idStatus = 5}) {
  return {
    'id': id,
    'idOrdenVenta': id,
    'folioOrdenCliente': 'F$id',
    'cliente': 'Cliente de prueba $id',
    'telefonoPrincipal': '5555550000',
    'telefonoOpcional': '',
    'codigoPostal': '54050',
    'estado': 'Mexico',
    'municipioDelegacion': 'Tlalnepantla de Baz',
    'colonia': 'Jacarandas',
    'calle': 'Calle $id',
    'numExterior': '$id',
    'numInterior': '',
    'entreCalles': 'Entre calle A y calle B',
    'referencias': 'Casa de prueba',
    'descripcionFachada': 'Fachada azul',
    'notas': '',
    'total': 100.0,
    'idStatus': idStatus,
    'idMotivoStatus': 0,
    'idExplicacionMotivo': 0,
    'statusOrden': 'On Delivery',
    'motivoStatus': '',
    'explicacionMotivo': '',
    'fechaPedido': '2026-09-24',
    'fechaEntrega': '',
  };
}

void main() {
  late HttpServer server;
  late int maxConcurrentSeen;
  late int inFlight;
  const requestLatency = Duration(milliseconds: 150);

  setUp(() async {
    maxConcurrentSeen = 0;
    inFlight = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8765);
    server.listen((HttpRequest request) async {
      inFlight++;
      if (inFlight > maxConcurrentSeen) maxConcurrentSeen = inFlight;

      // Simula latencia de red real por cada request de detalle de orden.
      await Future.delayed(requestLatency);

      final segments = request.uri.pathSegments; // ['api', 'orders', '<id>']
      if (segments.length >= 3 && segments[1] == 'orders') {
        final id = int.tryParse(segments[2]) ?? 0;
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(_fakeOrderJson(id)));
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
      inFlight--;
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test(
    '60 órdenes: cargan todas, rápido, sin duplicados y sin saturar el backend',
    () async {
      expect(
        ApiConfig.baseUrl,
        'http://127.0.0.1:8765/api',
        reason:
            'Corre este test con --dart-define=API_BASE_URL=http://127.0.0.1:8765/api',
      );

      final provider = OrdersProvider();
      final ids = List.generate(60, (i) => 100000 + i);

      final stopwatch = Stopwatch()..start();
      await provider.loadOrdersByIds('1123', ids);
      stopwatch.stop();

      // 1) Todas las 60 se cargaron, ninguna se quedó fuera.
      expect(provider.orders.length, 60,
          reason: 'Deben cargarse las 60 órdenes asignadas, sin faltantes.');

      // 2) Sin duplicados.
      final uniqueIds = provider.orders.map((o) => o.id).toSet();
      expect(uniqueIds.length, 60, reason: 'No debe haber órdenes repetidas.');

      // 3) El spinner de carga no se queda pegado (el bug real que se encontró).
      expect(provider.loading, false);
      expect(provider.errorMessage, null);
      expect(provider.offline, false);

      // 4) Rápido: en paralelo (máx. 12 a la vez) 60 órdenes a 150ms cada una
      // deberían tardar ~5 oleadas (~750ms) + overhead, muy lejos de los
      // ~9s que tomaría una por una en secuencia.
      expect(
        stopwatch.elapsed < const Duration(seconds: 4),
        true,
        reason:
            'Tardó ${stopwatch.elapsedMilliseconds}ms; con concurrencia acotada '
            'debería ser mucho menor que cargar 60 secuencialmente (~9s).',
      );

      // 5) Nunca se dispararon más de 12 peticiones simultáneas (protección
      // al backend con mochilas grandes).
      expect(
        maxConcurrentSeen <= 12,
        true,
        reason: 'Se vieron $maxConcurrentSeen peticiones simultáneas; el '
            'límite esperado es 12.',
      );

      print(
        '[STRESS] 60 órdenes cargadas en ${stopwatch.elapsedMilliseconds}ms, '
        'máx. concurrencia observada: $maxConcurrentSeen',
      );
    },
  );

  test(
    'al reducirse la lista de asignados no quedan órdenes viejas ("stale")',
    () async {
      final provider = OrdersProvider();
      final allIds = List.generate(60, (i) => 100000 + i);
      await provider.loadOrdersByIds('1123', allIds);
      expect(provider.orders.length, 60);

      // Simula que 40 de las 60 ya no están asignadas (reasignadas/completadas):
      // el mensajero solo debe ver las 20 vigentes, nunca las 40 viejas.
      final remainingIds = allIds.take(20).toList();
      await provider.loadOrdersByIds('1123', remainingIds);

      expect(provider.orders.length, 20,
          reason: 'Solo deben quedar las órdenes vigentes, sin residuos viejos.');
      final resultIds = provider.orders.map((o) => o.id).toSet();
      expect(resultIds, remainingIds.toSet());
      expect(provider.loading, false);
    },
  );
}
