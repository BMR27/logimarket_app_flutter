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

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  factory BackpackItemModel.fromJson(Map<String, dynamic> json) => BackpackItemModel(
        idBackpack: _toInt(json['IdBackpack'] ?? json['idBackpack']),
        idBackpackItem: _toInt(json['IdBackPackItem'] ?? json['IdBackpackItem'] ?? json['idBackpackItem']),
        idOrdenVenta: _toInt(json['IdOrdenVenta'] ?? json['idOrdenVenta']),
        folioOrden: json['FolioOrden'] ?? json['folioOrden'] ?? '',
        idStatusOrden: _toInt(json['IdStatusOrden'] ?? json['idStatusOrden']),
        statusName: json['StatusName'] ?? json['statusName'] ?? '',
        nombreCliente: json['NombreCliente'] ?? json['nombreCliente'] ?? '',
        validation: _toInt(json['Validation'] ?? json['validation']),
        latitud: json['Latitud']?.toString() ?? json['latitud']?.toString(),
        longitud: json['Longitud']?.toString() ?? json['longitud']?.toString(),
      );
}
