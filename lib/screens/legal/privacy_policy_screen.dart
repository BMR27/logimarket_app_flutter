import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Politica de Privacidad'),
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Politica de Privacidad de Logimarket App',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('Ultima actualizacion: 6 de mayo de 2026'),
            SizedBox(height: 16),
            Text(
              'En Logimarket respetamos tu privacidad y protegemos la informacion personal que utilizamos para operar el servicio de entregas. Esta politica explica que datos se recopilan, como se usan y que opciones tienes sobre ellos.',
            ),
            SizedBox(height: 16),
            _SectionTitle('1. Datos que recopilamos'),
            _Bullet('Datos de cuenta: nombre, correo y rol dentro de la plataforma.'),
            _Bullet('Datos operativos de pedidos: folios, estatus, notas, motivos y evidencias de entrega.'),
            _Bullet('Ubicacion: coordenadas GPS cuando se usa la funcion de viaje/seguimiento para la operacion logistica.'),
            _Bullet('Imagenes y evidencia: fotografias capturadas por el usuario para comprobar entregas.'),
            _Bullet('Datos tecnicos basicos del dispositivo para seguridad y funcionamiento de la app.'),
            SizedBox(height: 16),
            _SectionTitle('2. Para que usamos la informacion'),
            _Bullet('Asignar, monitorear y cerrar entregas.'),
            _Bullet('Registrar evidencia y trazabilidad de cada orden.'),
            _Bullet('Calcular indicadores operativos y comisiones de mensajeros.'),
            _Bullet('Atender incidencias, soporte y auditoria interna.'),
            _Bullet('Cumplir obligaciones legales y de seguridad de la operacion.'),
            SizedBox(height: 16),
            _SectionTitle('3. Permisos del dispositivo'),
            _Bullet('Ubicacion: necesaria para funciones de mapa, ruta y seguimiento de viaje.'),
            _Bullet('Camara/galeria: necesaria para capturar o adjuntar evidencia de entrega.'),
            _Bullet('Internet: necesaria para sincronizar informacion con los servidores.'),
            Text(
              'Si no otorgas ciertos permisos, algunas funciones pueden no estar disponibles.',
            ),
            SizedBox(height: 16),
            _SectionTitle('4. Comparticion de datos'),
            Text(
              'No vendemos informacion personal. Los datos pueden compartirse unicamente con personal autorizado, proveedores tecnologicos y autoridades cuando exista una obligacion legal.',
            ),
            SizedBox(height: 16),
            _SectionTitle('5. Conservacion y seguridad'),
            Text(
              'Aplicamos medidas administrativas, tecnicas y operativas para proteger la informacion. Conservamos los datos durante el tiempo necesario para la operacion, auditoria y cumplimiento legal.',
            ),
            SizedBox(height: 16),
            _SectionTitle('6. Derechos del usuario'),
            Text(
              'Puedes solicitar acceso, correccion o eliminacion de tus datos, segun aplique por ley y por la relacion operativa con la plataforma.',
            ),
            SizedBox(height: 16),
            _SectionTitle('7. Menores de edad'),
            Text(
              'La app esta dirigida a personal operativo autorizado y no esta orientada a menores de edad.',
            ),
            SizedBox(height: 16),
            _SectionTitle('8. Cambios a esta politica'),
            Text(
              'Podemos actualizar esta politica en cualquier momento. La version vigente se mostrara en esta seccion con su fecha de actualizacion.',
            ),
            SizedBox(height: 16),
            _SectionTitle('9. Contacto'),
            Text(
              'Para dudas sobre privacidad o tratamiento de datos, contacta al equipo administrador de Logimarket.',
            ),
            SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}