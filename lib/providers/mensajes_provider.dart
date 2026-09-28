import 'package:flutter/foundation.dart';
import '../models/mensaje_model.dart';
import '../services/mensajes_service.dart';

class MensajesProvider extends ChangeNotifier {
  final _service = MensajesService();

  List<MensajeModel> _mensajes = [];
  bool _loading = false;
  int? _idOrdenCargado;

  List<MensajeModel> get mensajes => _mensajes;
  bool get loading => _loading;

  Future<void> cargarMensajes(int idOrden) async {
    _loading = true;
    _idOrdenCargado = idOrden;
    notifyListeners();
    try {
      _mensajes = await _service.getMensajesPorOrden(idOrden);
    } catch (_) {
      _mensajes = [];
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Vuelve a cargar los mensajes de la orden actualmente mostrada, si coincide
  /// con el idOrden del push recibido en foreground.
  Future<void> refrescarSiAplica(int idOrden) async {
    if (_idOrdenCargado == idOrden) {
      await cargarMensajes(idOrden);
    }
  }
}
