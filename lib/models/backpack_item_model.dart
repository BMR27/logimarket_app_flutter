class BackpackItemModel {
  final int idBackpack;
  final int idBackpackItem;
  final int idOrdenVenta;
  final String folioOrden;
  final int idStatusOrden;
  final String statusName;
  final String nombreCliente;
  final int validation;
  final String? latitud;
  final String? longitud;
  final String? calle;
  final String? numExterior;
  final String? colonia;
  final String? municipio;
  final String? estado;
  final String? codigoPostal;

  BackpackItemModel({
    required this.idBackpack,
    required this.idBackpackItem,
    required this.idOrdenVenta,
    required this.folioOrden,
    required this.idStatusOrden,
    required this.statusName,
    required this.nombreCliente,
    required this.validation,
    this.latitud,
    this.longitud,
    this.calle,
    this.numExterior,
    this.colonia,
    this.municipio,
    this.estado,
    this.codigoPostal,
  });

  bool get isValidated => validation == 1;

  String get fullAddress {
    final parts = [
      if (calle != null && calle!.isNotEmpty) '${calle!} ${numExterior ?? ''}'.trim(),
      if (colonia != null && colonia!.isNotEmpty) colonia!,
      if (municipio != null && municipio!.isNotEmpty) municipio!,
      if (estado != null && estado!.isNotEmpty) estado!,
      if (codigoPostal != null && codigoPostal!.isNotEmpty) 'CP ${codigoPostal!}',
    ];
    return parts.join(', ');
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  factory BackpackItemModel.fromJson(Map<String, dynamic> json) => BackpackItemModel(
      idBackpack: _toInt(json['IdBackPack'] ?? json['IdBackpack'] ?? json['idBackpack']),
        idBackpackItem: _toInt(json['IdBackPackItem'] ?? json['IdBackpackItem'] ?? json['idBackpackItem']),
        idOrdenVenta: _toInt(json['IdOrdenVenta'] ?? json['idOrdenVenta']),
        folioOrden: json['FolioOrden'] ?? json['folioOrden'] ?? '',
        idStatusOrden: _toInt(json['IdStatusOrden'] ?? json['idStatusOrden']),
        statusName: json['StatusName'] ?? json['statusName'] ?? '',
        nombreCliente: json['NombreCliente'] ?? json['nombreCliente'] ?? '',
      validation: _toInt(
        json['Validation'] ??
        json['validation'] ??
        json['Validacion'] ??
        json['validacion'],
      ),
        latitud: json['Latitud']?.toString() ?? json['latitud']?.toString(),
        longitud: json['Longitud']?.toString() ?? json['longitud']?.toString(),
        calle: json['Calle']?.toString() ?? json['calle']?.toString(),
        numExterior: json['NumExterior']?.toString() ?? json['numExterior']?.toString(),
        colonia: json['Colonia']?.toString() ?? json['colonia']?.toString(),
        municipio: json['MunicipioDelegacion']?.toString() ?? json['municipio']?.toString(),
        estado: json['Estado']?.toString() ?? json['estado']?.toString(),
        codigoPostal: json['CodigoPostal']?.toString() ?? json['codigoPostal']?.toString(),
      );
}
