import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../models/equipo_model.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/background_location_task.dart';
import '../services/location_tracking_service.dart';

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

  Future<void> ensureEquiposLoaded() async {
    if (_user == null || _equipos.isNotEmpty) return;
    try {
      _equipos = await _service.getEquipos(_user!.idUsuario);
      notifyListeners();
    } catch (_) {
      // Evita romper la sesion; el consumidor decide como proceder si sigue vacio.
    }
    // Si el tracker se detuvo mientras la app estaba en background, reiniciarlo.
    if (_user != null && !LocationTrackingService.instance.isTracking) {
      _autoStartTracking(_user!);
    }
  }

  /// Devuelve true si el usuario es mensajero (no admin ni lider).
  bool _isMensajero(UserModel user) {
    final t = user.type.toLowerCase();
    return !t.contains('admin') && !t.contains('lider');
  }

  /// Arranca el tracking de ubicación en background si el usuario es mensajero.
  /// Restaura el estado de viaje guardado en SharedPreferences para sobrevivir
  /// reinicios del proceso (kill de Android, cambio de app, etc.).
  /// No lanza excepción — falla silenciosa para no bloquear el flujo de auth.
  Future<void> _autoStartTracking(UserModel user) async {
    if (!_isMensajero(user)) return;
    try {
      final token = await ApiService.getToken();
      if (token == null) return;
      // Recuperar estado de viaje previo desde SharedPreferences.
      // Si el proceso fue reiniciado mientras el viaje estaba activo,
      // esto garantiza que start() recibe enViaje=true en lugar de false.
      final prefs = await SharedPreferences.getInstance();
      final savedEnViaje = prefs.getBool(kPrefsEnViaje) ?? false;
      final savedIdOrden = prefs.getInt(kPrefsIdOrden);
      final savedFolioOrden = prefs.getString(kPrefsFolioOrden);
      await LocationTrackingService.instance.start(
        idMensajero: user.idUsuario,
        token: token,
        idOrden: savedIdOrden,
        folioOrden: savedFolioOrden,
        enViaje: savedEnViaje,
      );
      debugPrint('[Auth] auto-tracking started for mensajero ${user.idUsuario} enViaje=$savedEnViaje');
    } catch (e) {
      debugPrint('[Auth] auto-tracking start error: $e');
    }
  }

  /// Verifica localmente si el JWT está expirado sin hacer llamadas al servidor.
  bool _isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      String normalized = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      switch (normalized.length % 4) {
        case 2: normalized += '==';
        case 3: normalized += '=';
      }
      final payload =
          jsonDecode(utf8.decode(base64Decode(normalized))) as Map<String, dynamic>;
      final exp = payload['exp'] as int?;
      if (exp == null) return false;
      return DateTime.now().millisecondsSinceEpoch ~/ 1000 > exp;
    } catch (_) {
      return false;
    }
  }

  Future<void> checkSession() async {
    try {
      final token = await ApiService.getToken();
      if (token != null) {
        // Verificar expiración localmente antes de cualquier llamada al servidor.
        if (_isTokenExpired(token)) {
          await _service.logout();
          _state = AuthState.unauthenticated;
          notifyListeners();
          return;
        }
        _user = await _service.getSavedUser();
        if (_user == null) {
          await _service.logout();
          _state = AuthState.unauthenticated;
        } else {
          // Autenticar inmediatamente para no bloquear el splash.
          _state = AuthState.authenticated;
          // Arrancar tracking automático si es mensajero.
          _autoStartTracking(_user!);
          // Cargar equipos en background; si falla NO cerrar sesión —
          // ensureEquiposLoaded() los reintentará cuando el usuario haga una acción.
          _service.getEquipos(_user!.idUsuario).then((eq) {
            _equipos = eq;
            notifyListeners();
          }).catchError((dynamic e) async {
            if (e is ApiException && e.statusCode == 401) {
              await _service.logout();
              _user = null;
              _equipos = [];
              _state = AuthState.unauthenticated;
              notifyListeners();
              return;
            }
            // Error silencioso: el usuario sigue autenticado aunque equipos esté vacío.
          });
        }
      } else {
        _state = AuthState.unauthenticated;
      }
    } catch (_) {
      _state = AuthState.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> login(String correo, String password, {bool forceLogin = false}) async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await _service.login(correo, password, forceLogin: forceLogin);
      _equipos = await _service.getEquipos(_user!.idUsuario);
      _state = AuthState.authenticated;
      _loading = false;
      notifyListeners();
      // Arrancar tracking automático si es mensajero.
      _autoStartTracking(_user!);
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
    await LocationTrackingService.instance.stop();
    await _service.logout();
    _user = null;
    _equipos = [];
    _state = AuthState.unauthenticated;
    notifyListeners();
  }
}
