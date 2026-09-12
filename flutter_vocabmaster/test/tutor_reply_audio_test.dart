import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/models/tutor_correction.dart';
import 'package:vocabmaster/services/api_service.dart';
import 'package:vocabmaster/services/auth_service.dart';

/// The reply arrives already spoken.
///
/// Timed on a device, the phone asked for a reply's audio 0.34 s after the
/// reply reached it, on a new connection. Naming a voice in the chat request
/// now brings the audio back in the same response. What these pin is the wire:
/// the voice is asked for only when there is one, the audio is read when it is
/// there, and nothing about it can ever cost the reply itself.
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

  Map<String, dynamic>? sent;

  ApiService serving(Map<String, Object?> body) => ApiService(
        baseUrl: 'http://localhost:8080/api',
        client: MockClient((http.Request request) async {
          sent = Map<String, dynamic>.from(json.decode(request.body) as Map);
          return http.Response(
            json.encode(body),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );

  test('a named voice is asked for, and the audio comes back with the reply',
      () async {
    final TutorReply reply = await serving(<String, Object?>{
      'response': 'Sure!',
      'audio': base64Encode(<int>[82, 73, 70, 70]),
    }).chatbotChatTurn(message: 'Hi', voice: 'amy');

    expect(sent!['voice'], 'amy');
    expect(reply.text, 'Sure!');
    expect(reply.audio, <int>[82, 73, 70, 70]);
  });

  test('no voice, no field: the request is what it always was', () async {
    await serving(<String, Object?>{'response': 'Sure!'})
        .chatbotChatTurn(message: 'Hi');

    expect(sent!.containsKey('voice'), isFalse);
    expect(sent!.containsKey('audioSplit'), isFalse);
  });

  test('asking for a voice says this build can play the reply in two parts',
      () async {
    // What keeps the server from splitting a reply for a build that would play
    // the opening and then fall silent.
    await serving(<String, Object?>{'response': 'Sure!'})
        .chatbotChatTurn(message: 'Hi', voice: 'amy');

    expect(sent!['audioSplit'], 'true');
  });

  test('the variant a scene was dealt travels with every turn', () async {
    // What keeps one conversation's complication the same from turn to turn.
    await serving(<String, Object?>{'response': 'Sure!'}).chatbotChatTurn(
      message: 'A latte, please',
      scenario: 'cafe_order',
      scenarioVariant: 7,
    );

    expect(sent!['scenario'], 'cafe_order');
    expect(sent!['scenarioVariant'], '7');
  });

  test('free chat sends no variant', () async {
    await serving(<String, Object?>{'response': 'Sure!'})
        .chatbotChatTurn(message: 'Hi');

    expect(sent!.containsKey('scenarioVariant'), isFalse);
  });

  test('a server that sends no audio is a server that never did', () async {
    // Every backend before this one: the app asks /api/tts as it always has.
    final TutorReply reply = await serving(<String, Object?>{'response': 'Sure!'})
        .chatbotChatTurn(message: 'Hi', voice: 'amy');

    expect(reply.audio, isNull);
    expect(reply.text, 'Sure!');
  });

  test('a long reply comes back opening-first, with the rest to say after',
      () async {
    // What the server sends when speaking the whole reply would have been six
    // seconds of silence: the first sentence spoken, the remainder as text for
    // the app to ask for while that sentence plays.
    final TutorReply reply = await serving(<String, Object?>{
      'response': 'I am afraid the lasagne is sold out tonight. '
          'The penne arrabbiata is very good though.',
      'audio': base64Encode(<int>[82, 73, 70, 70]),
      'audioRest': 'The penne arrabbiata is very good though.',
    }).chatbotChatTurn(message: 'The lasagne please', voice: 'amy');

    expect(reply.audio, <int>[82, 73, 70, 70]);
    expect(reply.audioRest, 'The penne arrabbiata is very good though.');
  });

  test('a short reply is spoken whole and leaves nothing over', () async {
    final TutorReply reply = await serving(<String, Object?>{
      'response': 'Sure!',
      'audio': base64Encode(<int>[82, 73, 70, 70]),
    }).chatbotChatTurn(message: 'Hi', voice: 'amy');

    expect(reply.audioRest, isNull);
  });

  test('a malformed rest costs the rest, never the reply', () async {
    for (final Object junk in <Object>[42, '', '   ', <int>[1]]) {
      final TutorReply reply = await serving(<String, Object?>{
        'response': 'Sure!',
        'audio': base64Encode(<int>[82, 73, 70, 70]),
        'audioRest': junk,
      }).chatbotChatTurn(message: 'Hi', voice: 'amy');

      expect(reply.audioRest, isNull, reason: 'read $junk as the rest');
      expect(reply.text, 'Sure!', reason: '$junk cost the reply');
    }
  });

  test('a malformed audio field costs the audio, never the reply', () async {
    for (final Object junk in <Object>['not base64 at all!', 42, '', <int>[1]]) {
      final TutorReply reply = await serving(<String, Object?>{
        'response': 'Sure!',
        'audio': junk,
      }).chatbotChatTurn(message: 'Hi', voice: 'amy');

      expect(reply.audio, isNull, reason: 'read $junk as audio');
      expect(reply.text, 'Sure!', reason: '$junk cost the reply');
    }
  });
}
