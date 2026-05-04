import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Servicio HTTP base con inyección automática del JWT en cada request.
class ApiService {
  static const _storage = FlutterSecureStorage();
  static const String _tokenKey = 'jwt_token';

  static Future<String?> getToken() => _storage.read(key: _tokenKey);
  static Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);
  static Future<void> deleteToken() => _storage.delete(key: _tokenKey);

  Future<Map<String, String>> _headers() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<dynamic> get(String url) async {
    try {
      final response = await http.get(Uri.parse(url), headers: await _headers());
      return _handleResponse(response);
    } on SocketException {
      throw ApiException(
        statusCode: 0,
        message: 'Sin conexion a internet',
      );
    } on http.ClientException {
      throw ApiException(
        statusCode: 0,
        message: 'No se pudo conectar con el servidor',
      );
    }
  }

  Future<dynamic> post(String url, Map<String, dynamic> body) async {
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: await _headers(),
        body: jsonEncode(body),
      );
      return _handleResponse(response);
    } on SocketException {
      throw ApiException(
        statusCode: 0,
        message: 'Sin conexion a internet',
      );
    } on http.ClientException {
      throw ApiException(
        statusCode: 0,
        message: 'No se pudo conectar con el servidor',
      );
    }
  }

  Future<dynamic> put(String url, Map<String, dynamic> body) async {
    try {
      final response = await http.put(
        Uri.parse(url),
        headers: await _headers(),
        body: jsonEncode(body),
      );
      return _handleResponse(response);
    } on SocketException {
      throw ApiException(
        statusCode: 0,
        message: 'Sin conexion a internet',
      );
    } on http.ClientException {
      throw ApiException(
        statusCode: 0,
        message: 'No se pudo conectar con el servidor',
      );
    }
  }

  Future<dynamic> delete(String url) async {
    try {
      final response = await http.delete(Uri.parse(url), headers: await _headers());
      return _handleResponse(response);
    } on SocketException {
      throw ApiException(
        statusCode: 0,
        message: 'Sin conexion a internet',
      );
    } on http.ClientException {
      throw ApiException(
        statusCode: 0,
        message: 'No se pudo conectar con el servidor',
      );
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
      if (parsed is String) {
        throw ApiException(
          statusCode: -1,
          message: 'Respuesta invalida del servidor',
        );
      }
      return parsed;
    }

    String message = 'Error del servidor (${response.statusCode})';
    if (parsed is Map<String, dynamic> && parsed['error'] != null) {
      message = parsed['error'].toString();
    } else if (parsed is String && parsed.trim().isNotEmpty) {
      message = parsed.trim();
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
