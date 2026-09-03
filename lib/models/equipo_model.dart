class EquipoModel {
  final int idEquipo;
  final String equipo;
  final String nomenclatura;
  final bool lider;

  EquipoModel({
    required this.idEquipo,
    required this.equipo,
    required this.nomenclatura,
    required this.lider,
  });

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == '1' || normalized == 'true' || normalized == 'si' || normalized == 'sí';
    }
    return false;
  }

  factory EquipoModel.fromJson(Map<String, dynamic> json) => EquipoModel(
        idEquipo: _toInt(json['idEquipo'] ?? json['IdEquipo']),
        equipo: (json['equipo'] ?? json['Equipo'] ?? '').toString(),
        nomenclatura: (json['nomenclatura'] ?? json['Nomenclatura'] ?? '').toString(),
        lider: _toBool(json['lider']),
      );
}
