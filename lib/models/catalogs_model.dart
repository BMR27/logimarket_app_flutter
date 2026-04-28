class MotivoStatusModel {
  final int id;
  final int idStatus;
  final String motivo;

  MotivoStatusModel({
    required this.id,
    required this.idStatus,
    required this.motivo,
  });

  factory MotivoStatusModel.fromJson(Map<String, dynamic> json) => MotivoStatusModel(
        id: (json['id'] ?? json['Id'] ?? 0) as int,
        idStatus: (json['IdStatus'] ?? json['idStatus'] ?? 0) as int,
        motivo: json['Motivo'] ?? json['motivo'] ?? '',
      );
}

class MotivoExplicacionModel {
  final int id;
  final int idMotivo;
  final String explicacion;

  MotivoExplicacionModel({
    required this.id,
    required this.idMotivo,
    required this.explicacion,
  });

  factory MotivoExplicacionModel.fromJson(Map<String, dynamic> json) => MotivoExplicacionModel(
        id: (json['id'] ?? json['Id'] ?? 0) as int,
        idMotivo: (json['IdMotivo'] ?? json['idMotivo'] ?? 0) as int,
        explicacion: json['Explicacion'] ?? json['explicacion'] ?? '',
      );
}
