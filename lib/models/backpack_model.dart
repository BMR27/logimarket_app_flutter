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

  factory BackpackModel.fromJson(Map<String, dynamic> json) => BackpackModel(
        id: (json['Id'] ?? json['id'] ?? 0) as int,
        idRepartidor: (json['IdRepartidor'] ?? json['idRepartidor'] ?? 0) as int,
        nombreRepartidor: json['NombreRepartidor'] ?? json['nombreRepartidor'] ?? '',
        creationDate: json['CreationDate'] ?? json['creationDate'] ?? '',
        state: (json['State'] ?? json['state'] ?? 0) as int,
        stateName: json['StateName'] ?? json['stateName'] ?? '',
        totalOrders: (json['TotalOrders'] ?? json['totalOrders'] ?? 0) as int,
        progressOrders: (json['ProgressOrders'] ?? json['progressOrders'] ?? 0) as int,
      );
}
