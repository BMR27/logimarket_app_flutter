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
        id: _asInt(json['id'] ?? json['Id']),
        idStatus: _asInt(json['IdStatus'] ?? json['idStatus']),
        motivo: json['Motivo'] ?? json['motivo'] ?? '',
      );

  static int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim()) ?? 0;
  }
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
        id: _asInt(json['id'] ?? json['Id']),
        idMotivo: _asInt(json['IdMotivo'] ?? json['idMotivo']),
        explicacion: json['Explicacion'] ?? json['explicacion'] ?? '',
      );

  static int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim()) ?? 0;
  }
}
