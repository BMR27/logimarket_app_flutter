class MensajeModel {
  final int id;
  final String direccion; // 'in' | 'out'
  final String? cuerpo;
  final String? templateSid;
  final String? tipoEvento; // 'aviso_entrega' | 'encuesta_satisfaccion' | null
  final String? estatus;
  final String? twilioSid;
  final String? errorMensaje;
  final DateTime createdAt;

  MensajeModel({
    required this.id,
    required this.direccion,
    this.cuerpo,
    this.templateSid,
    this.tipoEvento,
    this.estatus,
    this.twilioSid,
    this.errorMensaje,
    required this.createdAt,
  });

  bool get esSaliente => direccion == 'out';

  factory MensajeModel.fromJson(Map<String, dynamic> json) {
    return MensajeModel(
      id: json['id'] as int,
      direccion: json['direccion'] as String? ?? 'in',
      cuerpo: json['cuerpo'] as String?,
      templateSid: json['templateSid'] as String?,
      tipoEvento: json['tipoEvento'] as String?,
      estatus: json['estatus'] as String?,
      twilioSid: json['twilioSid'] as String?,
      errorMensaje: json['errorMensaje'] as String?,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
