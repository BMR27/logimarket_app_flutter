import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Servicio HTTP base con inyección automática del JWT en cada request.
class ApiService {
  static const _storage = FlutterSecureStorage();
  static const String _tokenKey = 'jwt_token';

  static Future<String?> getToken() => safeSecureRead(_storage, _tokenKey);
  static Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);
  static Future<void> deleteToken() => _storage.delete(key: _tokenKey);

  /// Lee una clave del secure storage tolerando que la clave de cifrado del
  /// Android Keystore haya quedado invalidada (ej. tras reinstalar la app o
  /// restaurar un backup en otro dispositivo). En ese caso el valor cifrado
  /// es irrecuperable (BadPaddingException) — se descarta en vez de tronar
  /// el login, y se elimina para que no vuelva a fallar en el próximo intento.
  static Future<String?> safeSecureRead(FlutterSecureStorage storage, String key) async {
    try {
      return await storage.read(key: key);
    } catch (_) {
      try {
        await storage.delete(key: key);
      } catch (_) {
        // Si tampoco se puede borrar, se ignora: el próximo write la sobrescribe.
      }
      return null;
    }
  }

  Future<Map<String, String>> _headers() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<bool> _hasNetworkInterface() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  Future<Never> _throwNetworkException(Object e) async {
    final hasInterface = await _hasNetworkInterface();
    if (e is TimeoutException) {
      throw ApiException(statusCode: 408, message: 'El servidor no responde');
    }
    if (!hasInterface) {
      throw ApiException(statusCode: 0, message: 'Sin conexion a internet');
    }
    throw ApiException(statusCode: 503, message: 'No se pudo conectar con el servidor');
  }

  Future<dynamic> get(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url), headers: await _headers())
          .timeout(const Duration(seconds: 20));
      return _handleResponse(response);
    } on SocketException catch (e) {
      await _throwNetworkException(e);
    } on TimeoutException catch (e) {
      await _throwNetworkException(e);
    } on http.ClientException catch (e) {
      await _throwNetworkException(e);
    }
  }

  Future<dynamic> post(
    String url,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    try {
      final response = await http
          .post(Uri.parse(url), headers: await _headers(), body: jsonEncode(body))
          .timeout(timeout);
      return _handleResponse(response);
    } on SocketException catch (e) {
      await _throwNetworkException(e);
    } on TimeoutException catch (e) {
      await _throwNetworkException(e);
    } on http.ClientException catch (e) {
      await _throwNetworkException(e);
    }
  }

  Future<dynamic> put(String url, Map<String, dynamic> body) async {
    try {
      final response = await http
          .put(Uri.parse(url), headers: await _headers(), body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
      return _handleResponse(response);
    } on SocketException catch (e) {
      await _throwNetworkException(e);
    } on TimeoutException catch (e) {
      await _throwNetworkException(e);
    } on http.ClientException catch (e) {
      await _throwNetworkException(e);
    }
  }

  Future<dynamic> delete(String url) async {
    try {
      final response = await http
          .delete(Uri.parse(url), headers: await _headers())
          .timeout(const Duration(seconds: 20));
      return _handleResponse(response);
    } on SocketException catch (e) {
      await _throwNetworkException(e);
    } on TimeoutException catch (e) {
      await _throwNetworkException(e);
    } on http.ClientException catch (e) {
      await _throwNetworkException(e);
    }
  }

  dynamic _handleResponse(http.Response response) {
    final body = utf8.decode(response.bodyBytes);
    dynamic parsed;
    if (body.trim().isNotEmpty) {
      try {
        parsed = jsonDecode(body);
      } catch (_) {
        parsed = body;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // El servidor puede responder con texto plano (ej. "Updated", "OK") en
      // operaciones de escritura exitosas — no es un error, retornamos null.
      if (parsed is String) return null;
      return parsed;
    }

    String message = 'Error del servidor (${response.statusCode})';
    if (parsed is Map<String, dynamic> && parsed['error'] != null) {
      message = parsed['error'].toString();
    } else if (parsed is String && parsed.trim().isNotEmpty) {
      final trimmed = parsed.trim();
      // Avoid showing raw HTML error pages (e.g. Express 404 pages)
      message = trimmed.startsWith('<') ? 'Error del servidor (${response.statusCode})' : trimmed;
    }

    throw ApiException(
      statusCode: response.statusCode,
      message: message,
    );
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'ApiException($statusCode): $message';
}
