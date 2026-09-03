import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_config.dart';
import '../models/user_model.dart';
import '../models/equipo_model.dart';
import 'api_service.dart';

/// Decodifica el payload de un JWT sin verificar la firma.
UserModel? decodeUserFromJwt(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    // Base64url → Base64
    String normalized = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    switch (normalized.length % 4) {
      case 2: normalized += '==';
      case 3: normalized += '=';
    }
    final payload = jsonDecode(utf8.decode(base64Decode(normalized))) as Map<String, dynamic>;
    return UserModel.fromJson(payload);
  } catch (_) {
    return null;
  }
}

class AuthService extends ApiService {
  static const _storage = FlutterSecureStorage();
  static const String _userKey = 'user_data';
  static const String _deviceIdKey = 'device_id';

  String _generateDeviceId() {
    final random = Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final suffix = List.generate(24, (_) => chars[random.nextInt(chars.length)]).join();
    return 'lm-$suffix';
  }

  Future<String> _getOrCreateDeviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }

    final generated = _generateDeviceId();
    await _storage.write(key: _deviceIdKey, value: generated);
    return generated;
  }

  /// SHA-256 hash — igual que la app Android original
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  /// Login — devuelve el usuario y guarda el token JWT automáticamente
  Future<UserModel> login(String correo, String password, {bool forceLogin = false}) async {
    final deviceId = await _getOrCreateDeviceId();
    final data = await post(ApiConfig.login, {
      'correo': correo,
      'password': _hashPassword(password),
      'deviceId': deviceId,
      'forceLogin': forceLogin,
    });
    await ApiService.saveToken(data['token'] as String);
    final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
    await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
    return user;
  }

  /// Restaura el usuario: primero desde storage, luego desde el JWT como fallback.
  Future<UserModel?> getSavedUser() async {
    final raw = await _storage.read(key: _userKey);
    if (raw != null) {
      return UserModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
    // Fallback: decodificar el JWT almacenado
    final token = await ApiService.getToken();
    if (token == null) return null;
    return decodeUserFromJwt(token);
  }

  /// Obtiene los equipos del usuario tras login
  Future<List<EquipoModel>> getEquipos(int idUsuario) async {
    final raw = await get(ApiConfig.equipos(idUsuario));

    final List<dynamic> listData;
    if (raw is List) {
      listData = raw;
    } else if (raw is Map<String, dynamic> && raw['data'] is List) {
      listData = raw['data'] as List<dynamic>;
    } else {
      throw ApiException(statusCode: 500, message: 'Respuesta invalida al obtener equipos');
    }

    return listData
        .whereType<Map<String, dynamic>>()
        .map(EquipoModel.fromJson)
        .toList();
  }

  Future<void> logout() async {
    try {
      await post(ApiConfig.logout, {});
    } catch (_) {
      // Si el backend no responde, de todos modos limpiamos sesión local.
    }
    await ApiService.deleteToken();
    await _storage.delete(key: _userKey);
  }
}
