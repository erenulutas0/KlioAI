import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'auth_service.dart';

class SupportTicketService {
  final AuthService _authService = AuthService();

  Future<Map<String, String>> _headers() async {
    final token = await _authService.getToken();
    final userId = await _authService.getUserId();
    final deviceId = await _authService.getOrCreateDeviceId();
    if (token == null || token.isEmpty || userId == null || userId <= 0) {
      throw StateError('missing-auth-context');
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'X-User-Id': userId.toString(),
      'X-Device-Id': deviceId,
    };
  }

  Future<Map<String, dynamic>> listTickets() async {
    final apiUrl = await AppConfig.apiBaseUrl;
    final response = await http.get(
      Uri.parse('$apiUrl/support/tickets'),
      headers: await _headers(),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> createTicket({
    required String type,
    required String title,
    required String message,
    required String locale,
  }) async {
    final apiUrl = await AppConfig.apiBaseUrl;
    final response = await http.post(
      Uri.parse('$apiUrl/support/tickets'),
      headers: await _headers(),
      body: jsonEncode({
        'type': type,
        'title': title,
        'message': message,
        'locale': locale,
      }),
    );
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = response.body.trim();
    final decoded = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
    final map = decoded is Map<String, dynamic>
        ? decoded
        : Map<String, dynamic>.from(decoded as Map);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return map;
    }

    throw SupportTicketException(
      statusCode: response.statusCode,
      message: map['error']?.toString() ?? 'request-failed',
      payload: map,
    );
  }
}

class SupportTicketException implements Exception {
  final int statusCode;
  final String message;
  final Map<String, dynamic> payload;

  SupportTicketException({
    required this.statusCode,
    required this.message,
    required this.payload,
  });

  @override
  String toString() => 'SupportTicketException($statusCode, $message)';
}
