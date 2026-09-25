// Valida el reporte de un mensajero: marcó 3 entregas como Exitosa, cerró y
// reabrió la app, y el cambio nunca llegó "al sistema".
//
// La causa raíz encontrada: OrdersProvider.syncOfflineOrders() limpiaba el
// flag "editado" de TODAS las órdenes pendientes en cuanto UNA se
// sincronizaba con éxito (un UPDATE sin filtro por id) — si de 3 órdenes
// offline solo 1 lograba subir y las otras 2 fallaban (conexión
// intermitente, rechazo del servidor), las 2 se marcaban como "ya no
// pendientes" sin haberse guardado nunca en el servidor. Se perdían en
// silencio: ni se reintentaban ni se avisaba al mensajero.
//
// Este test usa sqflite_common_ffi para correr contra una base SQLite real
// (no mockeada) y un servidor HTTP local que hace fallar a propósito la
// segunda orden, igual que pasaría con un rechazo real del backend.
//
// Corre con:
//   flutter test --dart-define=API_BASE_URL=http://127.0.0.1:8766/api \
//     test/offline_sync_partial_failure_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:logimarket_app/config/api_config.dart';
import 'package:logimarket_app/db/local_database.dart';
import 'package:logimarket_app/models/order_model.dart';
import 'package:logimarket_app/providers/orders_provider.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late HttpServer server;
  late Set<int> rejectedIds;
  late List<int> updateCallsReceived;

  setUp(() async {
    rejectedIds = {};
    updateCallsReceived = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8766);
    server.listen((HttpRequest request) async {
      final segments = request.uri.pathSegments; // ['api', 'orders', '<id>']
      if (request.method == 'PUT' &&
          segments.length >= 3 &&
          segments[1] == 'orders') {
        final id = int.tryParse(segments[2]) ?? 0;
        updateCallsReceived.add(id);
        if (rejectedIds.contains(id)) {
          request.response.statusCode = 500;
          request.response.write('{"error":"regla de negocio simulada"}');
        } else {
          request.response.statusCode = 200;
          request.response.write('"OK"');
        }
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test(
    'si 1 de 3 órdenes offline falla al sincronizar, las otras 2 NO se pierden y la fallida se reintenta',
    () async {
      expect(
        ApiConfig.baseUrl,
        'http://127.0.0.1:8766/api',
        reason:
            'Corre con --dart-define=API_BASE_URL=http://127.0.0.1:8766/api',
      );

      final localDb = LocalDatabase();

      // markOrderAsEdited() solo hace UPDATE, no INSERT — necesita que la
      // fila ya exista (como pasaría en la app real: la orden se guarda en
      // caché al cargarla, antes de que el mensajero la edite offline).
      for (final id in [501, 502, 503]) {
        await localDb.upsertOrder(OrderModel.fromJson({'id': id}));
        await localDb.clearEditedOrder(id);
      }

      // Simula que el mensajero marcó 3 entregas como Exitosa estando
      // offline (o con un backend que rechaza la orden 502).
      await localDb.markOrderAsEdited(
          id: 501, status: 1, motivoStatus: 0, explicacionMotivo: 0, idUsuario: 9);
      await localDb.markOrderAsEdited(
          id: 502, status: 1, motivoStatus: 0, explicacionMotivo: 0, idUsuario: 9);
      await localDb.markOrderAsEdited(
          id: 503, status: 1, motivoStatus: 0, explicacionMotivo: 0, idUsuario: 9);

      // El backend rechaza específicamente la orden 502 (ej. una regla de
      // negocio, un conflicto de estatus, un timeout puntual).
      rejectedIds = {502};

      final provider = OrdersProvider();
      final synced = await provider.syncOfflineOrders();

      // Deben sincronizar exactamente las 2 que el backend aceptó.
      expect(synced, 2);
      expect(updateCallsReceived.toSet(), {501, 502, 503},
          reason: 'Las 3 debieron intentarse, aunque 1 haya sido rechazada.');

      // La 501 y 503 ya no deben quedar pendientes...
      final stillPending = await localDb.getEditedOrders();
      final stillPendingIds = stillPending.map((r) => r['id'] as int).toSet();
      expect(stillPendingIds.contains(501), false);
      expect(stillPendingIds.contains(503), false);

      // ...pero la 502 SÍ debe seguir marcada como pendiente, para
      // reintentarse en el próximo sync — nunca debe perderse en silencio.
      expect(
        stillPendingIds.contains(502),
        true,
        reason:
            'La orden rechazada por el servidor debe seguir pendiente de '
            'reintento, no descartarse como si ya se hubiera sincronizado.',
      );

      // Si el backend luego acepta la 502 (se resuelve el conflicto), un
      // segundo sync debe lograr subirla sin que el mensajero tenga que
      // volver a marcarla manualmente.
      rejectedIds = {};
      final secondSync = await provider.syncOfflineOrders();
      expect(secondSync, 1);
      final finalPending = await localDb.getEditedOrders();
      expect(finalPending.where((r) => r['id'] == 502), isEmpty);

      print('[SYNC] 1er intento: $synced sincronizadas, 502 quedó pendiente. '
          '2do intento: $secondSync sincronizada(s).');
    },
  );
}
