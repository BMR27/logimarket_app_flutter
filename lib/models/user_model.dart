class UserModel {
  final int idUsuario;
  final String correo;
  final String nombres;
  final String apellidoPaterno;
  final String apellidoMaterno;
  final String type;

  UserModel({
    required this.idUsuario,
    required this.correo,
    required this.nombres,
    required this.apellidoPaterno,
    required this.apellidoMaterno,
    required this.type,
  });

  String get fullName => '$nombres $apellidoPaterno $apellidoMaterno'.trim();

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        idUsuario: json['idUsuario'] as int,
        correo: json['correo'] as String? ?? '',
        nombres: json['nombres'] as String? ?? '',
        apellidoPaterno: json['apellidoPaterno'] as String? ?? '',
        apellidoMaterno: json['apellidoMaterno'] as String? ?? '',
        type: json['type'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'idUsuario': idUsuario,
        'correo': correo,
        'nombres': nombres,
        'apellidoPaterno': apellidoPaterno,
        'apellidoMaterno': apellidoMaterno,
        'type': type,
      };
}
