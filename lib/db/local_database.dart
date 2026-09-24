import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/backpack_item_model.dart';
import '../models/backpack_model.dart';
import '../models/order_model.dart';

/// Base de datos local SQLite para el modo offline.
/// Replica la estructura de logimarket_mirror_orders.db de Android.
class LocalDatabase {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'logimarket_offline.db');
    return openDatabase(
      path,
      version: 7,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE ordenes (
            id INTEGER PRIMARY KEY,
            idStatus INTEGER,
            idMotivoStatus INTEGER,
            idExplicacionMotivo INTEGER,
            folioOrdenCliente TEXT,
            cliente TEXT,
            telefonoPrincipal TEXT,
            telefonoOpcional TEXT,
            codigoPostal TEXT,
            estado TEXT,
            municipioDelegacion TEXT,
            colonia TEXT,
            calle TEXT,
            numExterior TEXT,
            numInterior TEXT,
            entreCalles TEXT,
            referencias TEXT,
            descripcionFachada TEXT,
            notas TEXT,
            total REAL,
            comisionEquipo REAL,
            fechaPedido TEXT,
            fechaEntrega TEXT,
            statusOrden TEXT,
            motivoStatus TEXT,
            explicacionMotivo TEXT,
            latitud TEXT,
            longitud TEXT,
            metros TEXT,
            tiempo TEXT,
            editado TEXT DEFAULT 'false',
            bd_status TEXT,
            bd_idStatusMotivo TEXT,
            bd_explicacionMotivo TEXT,
            bd_idUsuario TEXT,
            bd_fechaModificacion TEXT,
            bd_fechaReagenda TEXT,
            bd_latitud TEXT,
            bd_longitud TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE motivos_status (
            id INTEGER PRIMARY KEY,
            idStatus INTEGER,
            motivo TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE explicaciones_motivo (
            id INTEGER PRIMARY KEY,
            idMotivo INTEGER,
            explicacion TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE pending_evidence (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            idOrden INTEGER NOT NULL,
            idUsuario INTEGER NOT NULL,
            nombreReceptor TEXT,
            fotoBase64 TEXT,
            firmaBase64 TEXT,
            createdAt TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE backpack_items_cache (
            idBackpack INTEGER NOT NULL,
            idBackpackItem INTEGER NOT NULL,
            json TEXT NOT NULL,
            PRIMARY KEY (idBackpack, idBackpackItem)
          )
        ''');

        await db.execute('''
          CREATE TABLE backpacks_cache (
            idUsuario INTEGER NOT NULL,
            idBackpack INTEGER NOT NULL,
            json TEXT NOT NULL,
            PRIMARY KEY (idUsuario, idBackpack)
          )
        ''');

        await db.execute('''
          CREATE TABLE pending_backpack_ops (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            idBackpack INTEGER NOT NULL,
            opType TEXT NOT NULL,
            payload TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            lastError TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE pending_notes (
            idOrden INTEGER PRIMARY KEY,
            notas TEXT NOT NULL,
            createdAt TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS pending_evidence (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              idOrden INTEGER NOT NULL,
              idUsuario INTEGER NOT NULL,
              nombreReceptor TEXT,
              fotoBase64 TEXT,
              firmaBase64 TEXT,
              createdAt TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS backpack_items_cache (
              idBackpack INTEGER NOT NULL,
              idBackpackItem INTEGER NOT NULL,
              json TEXT NOT NULL,
              PRIMARY KEY (idBackpack, idBackpackItem)
            )
          ''');
        }
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS backpacks_cache (
              idUsuario INTEGER NOT NULL,
              idBackpack INTEGER NOT NULL,
              json TEXT NOT NULL,
              PRIMARY KEY (idUsuario, idBackpack)
            )
          ''');
        }
        if (oldVersion < 5) {
          await db.execute('ALTER TABLE ordenes ADD COLUMN comisionEquipo REAL');
        }
        if (oldVersion < 6) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS pending_backpack_ops (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              idBackpack INTEGER NOT NULL,
              opType TEXT NOT NULL,
              payload TEXT NOT NULL,
              createdAt TEXT NOT NULL,
              attempts INTEGER NOT NULL DEFAULT 0,
              lastError TEXT
            )
          ''');
        }
        if (oldVersion < 7) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS pending_notes (
              idOrden INTEGER PRIMARY KEY,
              notas TEXT NOT NULL,
              createdAt TEXT NOT NULL
            )
          ''');
        }
      },
    );
  }

  // ─── Órdenes ────────────────────────────────────────────────────────────────

  Future<void> upsertOrder(OrderModel order) async {
    final database = await db;
    await database.insert(
      'ordenes',
      {
        'id': order.id,
        'idStatus': order.idStatus,
        'idMotivoStatus': order.idMotivoStatus,
        'idExplicacionMotivo': order.idExplicacionMotivo,
        'folioOrdenCliente': order.folioOrdenCliente,
        'cliente': order.cliente,
        'telefonoPrincipal': order.telefonoPrincipal,
        'telefonoOpcional': order.telefonoOpcional,
        'codigoPostal': order.codigoPostal,
        'estado': order.estado,
        'municipioDelegacion': order.municipioDelegacion,
        'colonia': order.colonia,
        'calle': order.calle,
        'numExterior': order.numExterior,
        'numInterior': order.numInterior,
        'entreCalles': order.entreCalles,
        'referencias': order.referencias,
        'descripcionFachada': order.descripcionFachada,
        'notas': order.notas,
        'total': order.total,
        'comisionEquipo': order.comisionEquipo,
        'fechaPedido': order.fechaPedido,
        'fechaEntrega': order.fechaEntrega,
        'statusOrden': order.statusOrden,
        'motivoStatus': order.motivoStatus,
        'explicacionMotivo': order.explicacionMotivo,
        'latitud': order.latitud,
        'longitud': order.longitud,
        'metros': order.metros,
        'tiempo': order.tiempo,
        'editado': 'false',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> markOrderAsEdited({
    required int id,
    required int status,
    required int motivoStatus,
    required int explicacionMotivo,
    required int idUsuario,
    String? fechaReagenda,
    String? latitud,
    String? longitud,
  }) async {
    final database = await db;
    await database.update(
      'ordenes',
      {
        'editado': 'true',
        'bd_status': status.toString(),
        'bd_idStatusMotivo': motivoStatus.toString(),
        'bd_explicacionMotivo': explicacionMotivo.toString(),
        'bd_idUsuario': idUsuario.toString(),
        'bd_fechaModificacion': DateTime.now().toIso8601String(),
        'bd_fechaReagenda': fechaReagenda,
        'bd_latitud': latitud,
        'bd_longitud': longitud,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getEditedOrders() async {
    final database = await db;
    return database.query('ordenes', where: "editado = 'true'");
  }

  Future<void> clearEditedOrders() async {
    final database = await db;
    await database.update('ordenes', {'editado': 'false'}, where: "editado = 'true'");
  }

  Future<List<Map<String, dynamic>>> getAllOrders() async {
    final database = await db;
    // Incluye todos los status activos: En Ruta(2), Intento1(5), Intento2(6), On Delivery(7)
    return database.query('ordenes', where: 'idStatus IN (2, 5, 6, 7)');
  }

  // ─── Caché de ítems de mochila ────────────────────────────────────────────

  Future<void> saveBackpackItems(
      int idBackpack, List<BackpackItemModel> items) async {
    final database = await db;
    final batch = database.batch();
    batch.delete('backpack_items_cache',
        where: 'idBackpack = ?', whereArgs: [idBackpack]);
    for (final item in items) {
      batch.insert(
        'backpack_items_cache',
        {
          'idBackpack': idBackpack,
          'idBackpackItem': item.idBackpackItem,
          'json': jsonEncode(item.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<BackpackItemModel>> getBackpackItems(int idBackpack) async {
    final database = await db;
    final rows = await database.query('backpack_items_cache',
        where: 'idBackpack = ?', whereArgs: [idBackpack]);
    return rows
        .map((r) =>
            BackpackItemModel.fromJson(
                Map<String, dynamic>.from(jsonDecode(r['json'] as String) as Map)))
        .toList();
  }

  /// Borra el caché de ítems de una mochila que ya no está activa (cerrada/cancelada),
  /// para que un fallback offline nunca pueda resucitar órdenes ya resueltas — se llama
  /// desde loadBackpacks() en cuanto el servidor confirma que una mochila pasó a State=4.
  Future<void> deleteBackpackItems(int idBackpack) async {
    final database = await db;
    await database.delete('backpack_items_cache',
        where: 'idBackpack = ?', whereArgs: [idBackpack]);
  }

  // ─── Caché de lista de mochilas ─────────────────────────────────────────────

  Future<void> saveBackpacks(int idUsuario, List<BackpackModel> backpacks) async {
    final database = await db;
    final batch = database.batch();
    batch.delete('backpacks_cache',
        where: 'idUsuario = ?', whereArgs: [idUsuario]);
    for (final b in backpacks) {
      batch.insert(
        'backpacks_cache',
        {
          'idUsuario': idUsuario,
          'idBackpack': b.id,
          'json': jsonEncode(b.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<BackpackModel>> getCachedBackpacks(int idUsuario) async {
    final database = await db;
    final rows = await database.query('backpacks_cache',
        where: 'idUsuario = ?', whereArgs: [idUsuario]);
    return rows
        .map((r) => BackpackModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(r['json'] as String) as Map)))
        .toList();
  }



  Future<void> savePendingEvidence({
    required int idOrden,
    required int idUsuario,
    String? nombreReceptor,
    String? fotoBase64,
    String? firmaBase64,
  }) async {
    final database = await db;
    await database.insert('pending_evidence', {
      'idOrden': idOrden,
      'idUsuario': idUsuario,
      'nombreReceptor': nombreReceptor,
      'fotoBase64': fotoBase64,
      'firmaBase64': firmaBase64,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getPendingEvidence() async {
    final database = await db;
    return database.query('pending_evidence', orderBy: 'createdAt ASC');
  }

  Future<void> deletePendingEvidence(int id) async {
    final database = await db;
    await database.delete('pending_evidence', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Cola de operaciones de mochila offline ────────────────────────────────

  Future<int> savePendingBackpackOp({
    required int idBackpack,
    required String opType,
    required Map<String, dynamic> payload,
  }) async {
    final database = await db;
    return database.insert('pending_backpack_ops', {
      'idBackpack': idBackpack,
      'opType': opType,
      'payload': jsonEncode(payload),
      'createdAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getPendingBackpackOps() async {
    final database = await db;
    return database.query('pending_backpack_ops', orderBy: 'id ASC');
  }

  Future<void> deletePendingBackpackOp(int id) async {
    final database = await db;
    await database.delete('pending_backpack_ops', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markPendingBackpackOpFailed(int id, String error) async {
    final database = await db;
    await database.rawUpdate(
      'UPDATE pending_backpack_ops SET attempts = attempts + 1, lastError = ? WHERE id = ?',
      [error, id],
    );
  }

  // ─── Notas de orden pendientes de sincronizar ──────────────────────────────
  // PK por idOrden: si el mensajero edita la nota varias veces offline, solo
  // se conserva/reenvía la última versión (REPLACE), no una por cada edición.

  Future<void> savePendingNote({required int idOrden, required String notas}) async {
    final database = await db;
    await database.insert(
      'pending_notes',
      {
        'idOrden': idOrden,
        'notas': notas,
        'createdAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingNotes() async {
    final database = await db;
    return database.query('pending_notes', orderBy: 'createdAt ASC');
  }

  Future<void> deletePendingNote(int idOrden) async {
    final database = await db;
    await database.delete('pending_notes', where: 'idOrden = ?', whereArgs: [idOrden]);
  }
}
