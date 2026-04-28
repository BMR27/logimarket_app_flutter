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

  factory EquipoModel.fromJson(Map<String, dynamic> json) => EquipoModel(
        idEquipo: (json['idEquipo'] ?? json['IdEquipo'] ?? 0) as int,
        equipo: json['equipo'] ?? json['Equipo'] ?? '',
        nomenclatura: json['nomenclatura'] ?? json['Nomenclatura'] ?? '',
        lider: json['lider'] == true || json['lider'] == 1,
      );
}
