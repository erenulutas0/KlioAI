import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'auth_service.dart';

/// Records that the learner opened the app.
///
/// This was one method inside SocialService, kept when the rest of that file went with the
/// community feature. It survives on its own merit: `lastSeenAt` answers whether someone
/// came back, and the review event log cannot — a learner who opens the app and practises
/// nothing leaves no trace there, and that is exactly the case worth seeing.
class ActivityPingService {
  final AuthService _authService = AuthService();

  /// Failures are ignored on purpose. This is bookkeeping and must never interrupt the
  /// learner or surface as an error on top of what they were doing.
  Future<void> sendHeartbeat() async {
    try {
      final userId = await _authService.getUserId();
      final baseUrl = await AppConfig.apiBaseUrl;
      await http.post(
        Uri.parse('$baseUrl/users/heartbeat'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-Id': userId.toString(),
        },
      );
    } catch (_) {
      // Deliberately silent.
    }
  }
}
