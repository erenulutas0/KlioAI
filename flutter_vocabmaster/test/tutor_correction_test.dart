import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/models/tutor_correction.dart';
import 'package:vocabmaster/services/api_service.dart';
import 'package:vocabmaster/services/auth_service.dart';

/// The correction the tutor has always produced and never shown.
///
/// It reaches the screen through a marker in the model's output, a server that
/// splits it off, a JSON key and a parser — four places to be wrong, on the one
/// screen where being wrong is most expensive. So the rule everything here
/// checks is the same: anything malformed becomes NO correction. Never a broken
/// reply, and never a chip that tells a learner they made a mistake without
/// showing them one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    await AuthService().saveSession('t', 'r', <String, dynamic>{
      'id': 4,
      'userId': 4,
      'email': 'learner@test.local',
      'displayName': 'Learner',
      'userTag': '#00004',
      'role': 'USER',
    });
  });

  ApiService serving(Map<String, Object?> body) => ApiService(
        baseUrl: 'http://localhost:8080/api',
        client: MockClient((http.Request request) async => http.Response(
              json.encode(body),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            )),
      );

  group('parsing what the server sent', () {
    test('a correction arrives with the reply', () async {
      final TutorReply reply = await serving(<String, Object?>{
        'response': 'Where did you go?',
        'correction': <String, Object?>{
          'said': 'I go to Paris yesterday',
          'better': 'I went to Paris yesterday',
        },
      }).chatbotChatTurn(message: 'I go to Paris yesterday');

      expect(reply.text, 'Where did you go?');
      expect(reply.correction!.said, 'I go to Paris yesterday');
      expect(reply.correction!.better, 'I went to Paris yesterday');
    });

    test('no correction key is the ordinary case, not a failure', () async {
      // Most turns have nothing worth correcting, and at A1 the server is told
      // not to correct at all. A missing key must read as "nothing to show".
      final TutorReply reply = await serving(<String, Object?>{
        'response': 'Sounds good.',
      }).chatbotChatTurn(message: 'I went yesterday');

      expect(reply.text, 'Sounds good.');
      expect(reply.correction, isNull);
    });

    test('a half-built correction is dropped, and the reply survives', () async {
      final TutorReply reply = await serving(<String, Object?>{
        'response': 'Nice.',
        'correction': <String, Object?>{'said': 'I go', 'better': '   '},
      }).chatbotChatTurn(message: 'I go');

      expect(reply.text, 'Nice.', reason: 'the reply must never be the casualty');
      expect(reply.correction, isNull);
    });

    test('a correction of the wrong shape is dropped', () async {
      final TutorReply reply = await serving(<String, Object?>{
        'response': 'Nice.',
        'correction': 'I went yesterday',
      }).chatbotChatTurn(message: 'I go');

      expect(reply.text, 'Nice.');
      expect(reply.correction, isNull);
    });

    test('the old plain-text call still returns just the text', () async {
      // Nothing that only wanted the reply had to change.
      final String text = await serving(<String, Object?>{
        'response': 'Sounds good.',
        'correction': <String, Object?>{'said': 'a', 'better': 'b'},
      }).chatbotChat(message: 'hi');

      expect(text, 'Sounds good.');
    });
  });

  group('what counts as a correction at all', () {
    test('a correction identical to what was said is not one', () {
      // Being told you were wrong and shown your own sentence back teaches
      // nothing and is worse than silence.
      expect(
        TutorCorrection.fromJson(<String, Object?>{
          'said': 'I went yesterday',
          'better': 'I went yesterday',
        }),
        isNull,
      );
    });

    test('and neither is one that differs only in case', () {
      expect(
        TutorCorrection.fromJson(<String, Object?>{
          'said': 'I Went Yesterday',
          'better': 'i went yesterday',
        }),
        isNull,
      );
    });

    test('surrounding space is not a difference worth showing', () {
      final TutorCorrection? correction = TutorCorrection.fromJson(
        <String, Object?>{'said': '  I go  ', 'better': 'I went'},
      );
      expect(correction!.said, 'I go');
      expect(correction.better, 'I went');
    });

    test('null and nonsense are simply absent', () {
      expect(TutorCorrection.fromJson(null), isNull);
      expect(TutorCorrection.fromJson(42), isNull);
      expect(TutorCorrection.fromJson(<String, Object?>{}), isNull);
    });
  });
}
