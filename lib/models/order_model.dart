class OrderModel {
  final int id;
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

  factory OrderModel.fromJson(Map<String, dynamic> json) => OrderModel(
        id: (json['id'] ?? json['Id'] ?? 0) as int,
        folioOrdenCliente: json['folioOrdenCliente'] ?? json['FolioOrdenCliente'] ?? '',
        cliente: json['cliente'] ?? json['Cliente'] ?? '',
        telefonoPrincipal: json['telefonoPrincipal'] ?? json['TelefonoPrincipal'] ?? '',
        telefonoOpcional: json['telefonoOpcional'] ?? json['TelefonoOpcional'] ?? '',
        codigoPostal: json['codigoPostal'] ?? json['CodigoPostal'] ?? '',
        estado: json['estado'] ?? json['Estado'] ?? '',
        municipioDelegacion: json['municipioDelegacion'] ?? json['MunicipioDelegacion'] ?? '',
        colonia: json['colonia'] ?? json['Colonia'] ?? '',
        calle: json['calle'] ?? json['Calle'] ?? '',
        numExterior: json['numExterior'] ?? json['NumExterior'] ?? '',
        numInterior: json['numInterior'] ?? json['NumInterior'] ?? '',
        entreCalles: json['entreCalles'] ?? json['EntreCalles'] ?? '',
        referencias: json['referencias'] ?? json['Referencias'] ?? '',
        descripcionFachada: json['descripcionFachada'] ?? json['DescripcionFachada'] ?? '',
        notas: json['notas'] ?? json['Notas'] ?? '',
        total: ((json['total'] ?? json['Total'] ?? 0) as num).toDouble(),
        observacionesMensajero: json['observacionesMensajero']?.toString(),
        idStatus: (json['idStatus'] ?? json['IdStatus'] ?? 0) as int,
        idMotivoStatus: (json['idMotivoStatus'] ?? json['IdMotivoStatus'] ?? 0) as int,
        idExplicacionMotivo:
            (json['idExplicacionMotivo'] ?? json['IdExplicacionMotivo'] ?? 0) as int,
        statusOrden: json['StatusOrden'] ?? json['statusOrden'] ?? '',
        motivoStatus: json['MotivoStatus'] ?? json['motivoStatus'] ?? '',
        explicacionMotivo: json['ExplicacionMotivo'] ?? json['explicacionMotivo'] ?? '',
        fechaPedido: json['fechaPedido'] ?? json['FechaPedido'] ?? '',
        fechaEntrega: json['fechaEntrega'] ?? json['FechaEntrega'] ?? '',
        latitud: json['Latitud']?.toString() ?? json['latitud']?.toString(),
        longitud: json['Longitud']?.toString() ?? json['longitud']?.toString(),
        metros: json['Metros']?.toString() ?? json['metros']?.toString(),
        tiempo: json['Tiempo']?.toString() ?? json['tiempo']?.toString(),
      );
}
