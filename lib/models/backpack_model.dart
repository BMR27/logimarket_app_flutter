class BackpackModel {
  final int id;
  final int idRepartidor;
  final String nombreRepartidor;
  final String creationDate;
  final int state;
  final String stateName;
  final int totalOrders;
  final int progressOrders;

  BackpackModel({
    required this.id,
    required this.idRepartidor,
    required this.nombreRepartidor,
    required this.creationDate,
    required this.state,
    required this.stateName,
    required this.totalOrders,
    required this.progressOrders,
  });

  double get progressPercent =>
      totalOrders == 0 ? 0.0 : progressOrders / totalOrders;

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _parseState(Map<String, dynamic> json) {
    final numeric = _toInt(
      json['State'] ??
          json['state'] ??
          json['Estado'] ??
          json['estado'] ??
          json['Status'] ??
          json['status'] ??
          json['IdEstado'] ??
          json['idEstado'],
    );
    if (numeric > 0) return numeric;

    final text = (
      json['StateName'] ??
          json['stateName'] ??
          json['EstadoNombre'] ??
          json['estadoNombre'] ??
          json['Estatus'] ??
          json['estatus'] ??
          ''
    )
        .toString()
        .trim()
        .toLowerCase();

    if (text.contains('asign')) return 1;
    if (text.contains('ruta')) return 2;
    if (text.contains('termin') || text.contains('finaliz')) return 3;
    if (text.contains('cerr') || text.contains('cancel')) return 4;
    return 0;
  }

  factory BackpackModel.fromJson(Map<String, dynamic> json) => BackpackModel(
        id: _toInt(json['Id'] ?? json['id'] ?? json['IdBackpack'] ?? json['idBackpack']),
        idRepartidor: _toInt(
          json['IdRepartidor'] ?? json['idRepartidor'] ?? json['idMensajero'],
        ),
        nombreRepartidor: json['NombreRepartidor'] ?? json['nombreRepartidor'] ?? '',
        creationDate: json['CreationDate'] ?? json['creationDate'] ?? '',
        state: _parseState(json),
        stateName: (json['StateName'] ??
                json['stateName'] ??
                json['EstadoNombre'] ??
                json['estadoNombre'] ??
                '')
            .toString(),
        totalOrders: _toInt(json['TotalOrders'] ?? json['totalOrders']),
        progressOrders: _toInt(json['ProgressOrders'] ?? json['progressOrders']),
      );
}
