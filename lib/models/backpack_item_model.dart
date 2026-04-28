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
  });

  bool get isValidated => validation == 1;

  factory BackpackItemModel.fromJson(Map<String, dynamic> json) => BackpackItemModel(
        idBackpack: (json['IdBackpack'] ?? json['idBackpack'] ?? 0) as int,
        idBackpackItem: (json['IdBackPackItem'] ?? json['idBackpackItem'] ?? 0) as int,
        idOrdenVenta: (json['IdOrdenVenta'] ?? json['idOrdenVenta'] ?? 0) as int,
        folioOrden: json['FolioOrden'] ?? json['folioOrden'] ?? '',
        idStatusOrden: (json['IdStatusOrden'] ?? json['idStatusOrden'] ?? 0) as int,
        statusName: json['StatusName'] ?? json['statusName'] ?? '',
        nombreCliente: json['NombreCliente'] ?? json['nombreCliente'] ?? '',
        validation: (json['Validation'] ?? json['validation'] ?? 0) as int,
        latitud: json['Latitud']?.toString() ?? json['latitud']?.toString(),
        longitud: json['Longitud']?.toString() ?? json['longitud']?.toString(),
      );
}
