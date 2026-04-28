import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
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
      version: 1,
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
    return database.query('ordenes', where: 'idStatus IN (2, 5, 6)');
  }
}
