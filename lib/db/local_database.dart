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
      version: 4,
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
}
