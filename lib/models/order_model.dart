class OrderModel {
  final int id;
  final int idOrdenVenta;
  final String folioOrdenCliente;
  final String cliente;
  final String telefonoPrincipal;
  final String telefonoOpcional;
  final String codigoPostal;
  final String estado;
  final String municipioDelegacion;
  final String colonia;
  final String calle;
  final String numExterior;
  final String numInterior;
  final String entreCalles;
  final String referencias;
  final String descripcionFachada;
  final String notas;
  final double total;
  final String? observacionesMensajero;
  final int idStatus;
  final int idMotivoStatus;
  final int idExplicacionMotivo;
  final String statusOrden;
  final String motivoStatus;
  final String explicacionMotivo;
  final String fechaPedido;
  final String fechaEntrega;
  final String? latitud;
  final String? longitud;
  final String? metros;
  final String? tiempo;

  OrderModel({
    required this.id,
    required this.idOrdenVenta,
    required this.folioOrdenCliente,
    required this.cliente,
    required this.telefonoPrincipal,
    required this.telefonoOpcional,
    required this.codigoPostal,
    required this.estado,
    required this.municipioDelegacion,
    required this.colonia,
    required this.calle,
    required this.numExterior,
    required this.numInterior,
    required this.entreCalles,
    required this.referencias,
    required this.descripcionFachada,
    required this.notas,
    required this.total,
    this.observacionesMensajero,
    required this.idStatus,
    required this.idMotivoStatus,
    required this.idExplicacionMotivo,
    required this.statusOrden,
    required this.motivoStatus,
    required this.explicacionMotivo,
    required this.fechaPedido,
    required this.fechaEntrega,
    this.latitud,
    this.longitud,
    this.metros,
    this.tiempo,
  });

  String get fullAddress =>
      '$calle $numExterior, $colonia, $municipioDelegacion, $estado CP $codigoPostal';

  OrderModel copyWith({
    String? latitud,
    String? longitud,
    String? metros,
    String? tiempo,
  }) {
    return OrderModel(
      id: id,
      idOrdenVenta: idOrdenVenta,
      folioOrdenCliente: folioOrdenCliente,
      cliente: cliente,
      telefonoPrincipal: telefonoPrincipal,
      telefonoOpcional: telefonoOpcional,
      codigoPostal: codigoPostal,
      estado: estado,
      municipioDelegacion: municipioDelegacion,
      colonia: colonia,
      calle: calle,
      numExterior: numExterior,
      numInterior: numInterior,
      entreCalles: entreCalles,
      referencias: referencias,
      descripcionFachada: descripcionFachada,
      notas: notas,
      total: total,
      observacionesMensajero: observacionesMensajero,
      idStatus: idStatus,
      idMotivoStatus: idMotivoStatus,
      idExplicacionMotivo: idExplicacionMotivo,
      statusOrden: statusOrden,
      motivoStatus: motivoStatus,
      explicacionMotivo: explicacionMotivo,
      fechaPedido: fechaPedido,
      fechaEntrega: fechaEntrega,
      latitud: latitud ?? this.latitud,
      longitud: longitud ?? this.longitud,
      metros: metros ?? this.metros,
      tiempo: tiempo ?? this.tiempo,
    );
  }

  factory OrderModel.fromJson(Map<String, dynamic> json) => OrderModel(
        id: _asInt(json['id'] ?? json['Id']),
        idOrdenVenta: _asInt(json['idOrdenVenta'] ?? json['IdOrdenVenta']),
        folioOrdenCliente: _asString(json['folioOrdenCliente'] ?? json['FolioOrdenCliente']),
        cliente: _asString(json['cliente'] ?? json['Cliente']),
        telefonoPrincipal: _asString(json['telefonoPrincipal'] ?? json['TelefonoPrincipal']),
        telefonoOpcional: _asString(json['telefonoOpcional'] ?? json['TelefonoOpcional']),
        codigoPostal: _asString(json['codigoPostal'] ?? json['CodigoPostal']),
        estado: _asString(json['estado'] ?? json['Estado']),
        municipioDelegacion: _asString(json['municipioDelegacion'] ?? json['MunicipioDelegacion']),
        colonia: _asString(json['colonia'] ?? json['Colonia']),
        calle: _asString(json['calle'] ?? json['Calle']),
        numExterior: _asString(json['numExterior'] ?? json['NumExterior']),
        numInterior: _asString(json['numInterior'] ?? json['NumInterior']),
        entreCalles: _asString(json['entreCalles'] ?? json['EntreCalles']),
        referencias: _asString(json['referencias'] ?? json['Referencias']),
        descripcionFachada: _asString(json['descripcionFachada'] ?? json['DescripcionFachada']),
        notas: _asString(json['notas'] ?? json['Notas']),
        total: _asDouble(json['total'] ?? json['Total']),
        observacionesMensajero: json['observacionesMensajero']?.toString(),
        idStatus: _asInt(json['idStatus'] ?? json['IdStatus']),
        idMotivoStatus: _asInt(json['idMotivoStatus'] ?? json['IdMotivoStatus']),
        idExplicacionMotivo:
            _asInt(json['idExplicacionMotivo'] ?? json['IdExplicacionMotivo']),
        statusOrden: _asString(json['StatusOrden'] ?? json['statusOrden']),
        motivoStatus: _asString(json['MotivoStatus'] ?? json['motivoStatus']),
        explicacionMotivo: _asString(json['ExplicacionMotivo'] ?? json['explicacionMotivo']),
        fechaPedido: _asString(json['fechaPedido'] ?? json['FechaPedido']),
        fechaEntrega: _asString(json['fechaEntrega'] ?? json['FechaEntrega']),
        latitud: json['Latitud']?.toString() ?? json['latitud']?.toString(),
        longitud: json['Longitud']?.toString() ?? json['longitud']?.toString(),
        metros: json['Metros']?.toString() ?? json['metros']?.toString(),
        tiempo: json['Tiempo']?.toString() ?? json['tiempo']?.toString(),
      );

  static int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim()) ?? 0;
  }

  static double _asDouble(dynamic value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim()) ?? 0;
  }

  static String _asString(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }
}
