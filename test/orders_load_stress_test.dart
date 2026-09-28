// Valida OrdersProvider.loadOrdersByIds con mochilas grandes (60 órdenes) SIN
// tocar el backend real: levanta un servidor HTTP local que imita la API y le
// apunta la app vía --dart-define=API_BASE_URL.
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
  late int batchRequests;
  late int detailRequests;
  // Comportamiento configurable del servidor falso por test.
  late bool batchEnabled; // false = API anterior sin /orders/batch (404)
  late int batchFailuresBeforeOk; // fallas 503 antes de responder bien
  late Set<int> inexistentes; // órdenes borradas en el servidor
  const requestLatency = Duration(milliseconds: 150);

  setUp(() async {
    maxConcurrentSeen = 0;
    inFlight = 0;
    batchRequests = 0;
    detailRequests = 0;
    batchEnabled = true;
    batchFailuresBeforeOk = 0;
    inexistentes = {};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8765);
    server.listen((HttpRequest request) async {
      inFlight++;
      if (inFlight > maxConcurrentSeen) maxConcurrentSeen = inFlight;
      await Future.delayed(requestLatency);

      final segments = request.uri.pathSegments; // ['api', 'orders', ...]
      final isBatch = request.method == 'POST' && segments.length == 3 && segments[1] == 'orders' && segments[2] == 'batch';
      if (isBatch) {
        batchRequests++;
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
        if (!batchEnabled) {
          request.response.statusCode = 404;
        } else if (batchFailuresBeforeOk > 0) {
          batchFailuresBeforeOk--;
          request.response.statusCode = 503;
        } else {
          final ids = (body['ids'] as List).cast<int>();
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({
              'orders': ids.where((id) => !inexistentes.contains(id)).map(_fakeOrderJson).toList(),
              'missing': ids.where(inexistentes.contains).toList(),
            }));
        }
      } else if (request.method == 'GET' && segments.length >= 3 && segments[1] == 'orders') {
        detailRequests++;
        final id = int.tryParse(segments[2]) ?? 0;
        if (inexistentes.contains(id)) {
          request.response.statusCode = 404;
        } else {
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(_fakeOrderJson(id)));
        }
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

  test('60 órdenes: una sola petición batch, todas cargadas y sin duplicados', () async {
    expect(ApiConfig.baseUrl, 'http://127.0.0.1:8765/api',
        reason: 'Corre este test con --dart-define=API_BASE_URL=http://127.0.0.1:8765/api');

    final provider = OrdersProvider();
    final ids = List.generate(60, (i) => 100000 + i);
    final stopwatch = Stopwatch()..start();
    await provider.loadOrdersByIds('1123', ids);
    stopwatch.stop();

    expect(provider.orders.length, 60);
    expect(provider.orders.map((o) => o.id).toSet().length, 60);
    expect(provider.loading, false);
    expect(provider.errorMessage, null);
    expect(provider.offline, false);
    expect(batchRequests, 1, reason: 'Toda la mochila debe pedirse en una sola petición.');
    expect(detailRequests, 0);
    expect(stopwatch.elapsed < const Duration(seconds: 2), true,
        reason: 'Tardó ${stopwatch.elapsedMilliseconds}ms');
    // ignore: avoid_print
    print('[STRESS] 60 órdenes en ${stopwatch.elapsedMilliseconds}ms con $batchRequests petición(es)');
  });

  test('falla temporal de red en el batch: se reintenta y carga todo', () async {
    batchFailuresBeforeOk = 2;
    final provider = OrdersProvider();
    final ids = List.generate(60, (i) => 100000 + i);
    await provider.loadOrdersByIds('1123', ids);

    expect(provider.orders.length, 60);
    expect(provider.errorMessage, null);
    expect(batchRequests, 3);
  });

  test('órdenes borradas en el servidor no cuentan como "no se pudieron cargar"', () async {
    inexistentes = {100000, 100001};
    final provider = OrdersProvider();
    final ids = List.generate(60, (i) => 100000 + i);
    await provider.loadOrdersByIds('1123', ids);

    expect(provider.orders.length, 58);
    expect(provider.errorMessage, null);
  });

  test('API anterior sin /orders/batch: carga por orden, máx. 6 a la vez', () async {
    batchEnabled = false;
    final provider = OrdersProvider();
    final ids = List.generate(60, (i) => 100000 + i);
    await provider.loadOrdersByIds('1123', ids);

    expect(provider.orders.length, 60);
    expect(provider.errorMessage, null);
    expect(detailRequests, 60);
    expect(maxConcurrentSeen <= 6, true, reason: 'Se vieron $maxConcurrentSeen simultáneas');
  });

  test('al reducirse la lista de asignados no quedan órdenes viejas ("stale")', () async {
    final provider = OrdersProvider();
    final allIds = List.generate(60, (i) => 100000 + i);
    await provider.loadOrdersByIds('1123', allIds);
    expect(provider.orders.length, 60);

    final remainingIds = allIds.take(20).toList();
    await provider.loadOrdersByIds('1123', remainingIds);

    expect(provider.orders.length, 20);
    expect(provider.orders.map((o) => o.id).toSet(), remainingIds.toSet());
    expect(provider.loading, false);
  });
}
