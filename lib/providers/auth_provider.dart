import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../models/equipo_model.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';

enum AuthState { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final _service = AuthService();

  AuthState _state = AuthState.unknown;
  UserModel? _user;
  List<EquipoModel> _equipos = [];
  String? _errorMessage;
  bool _loading = false;

  AuthState get state => _state;
  UserModel? get user => _user;
  List<EquipoModel> get equipos => _equipos;
  String? get errorMessage => _errorMessage;
  bool get loading => _loading;

  /// IDs de equipos formateados para las queries (ej: "1,2,3")
  String get equiposForQuery =>
      _equipos.map((e) => e.idEquipo.toString()).join(',');

  Future<void> checkSession() async {
    try {
      final token = await ApiService.getToken();
      if (token != null) {
        _user = await _service.getSavedUser();
        if (_user != null) {
          try {
            _equipos = await _service.getEquipos(_user!.idUsuario);
          } catch (_) {
            _equipos = [];
          }
        }
        _state = AuthState.authenticated;
      } else {
        _state = AuthState.unauthenticated;
      }
    } catch (_) {
      _state = AuthState.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> login(String correo, String password) async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await _service.login(correo, password);
      _equipos = await _service.getEquipos(_user!.idUsuario);
      _state = AuthState.authenticated;
      _loading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _loading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Error de conexión, revisa tu internet';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _service.logout();
    _user = null;
    _equipos = [];
    _state = AuthState.unauthenticated;
    notifyListeners();
  }
}
