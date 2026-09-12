import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/frontend_newest/screens/nf_tutor_page.dart';
import 'package:vocabmaster/frontend_newest/services/nf_speech_capture.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/services/api_service.dart';
import 'package:vocabmaster/services/auth_service.dart';
import 'package:vocabmaster/services/chatbot_service.dart';

/// The transcript the learner never said.
///
/// Captured on a real device: "I am agree with you" came back as "I am angry
/// with you", and "I very like this app" as "I'm very naked". Whisper does not
/// hedge — it returns a fluent, confident sentence whether or not it heard one
/// — and this screen sent whatever arrived straight to the tutor. The tutor
/// then corrected a sentence the learner had never spoken, struck their words
/// through and explained why they were wrong about something they had not
/// said. That is the one feature justifying the whole screen, lying to the
/// learner in their own conversation.
///
/// The server now says when it is unsure. Three things have to hold, and the
/// third is the one most likely to be broken by accident: a doubted transcript
/// must be checked first, a checked transcript must reach the tutor as the
/// learner left it, and everybody else — including every learner on a server
/// that has never heard of this field — must notice nothing at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    await AuthService().saveSession('t', 'r', <String, dynamic>{
      'id': 4,
      'userId': 4,
      'email': 'speaker@test.local',
      'displayName': 'Speaker',
      'userTag': '#00004',
      'role': 'USER',
    });
  });

  // ---------------------------------------------------------------------------
  // Off the wire
  // ---------------------------------------------------------------------------

  group('what the server now sends', () {
    late File clip;

    setUp(() async {
      // A real file, because the request is a multipart upload and
      // MultipartFile.fromPath will not invent one. The bytes are never
      // listened to by anything in this test; only the path has to exist.
      clip = File(
        '${Directory.systemTemp.path}/klioai_low_confidence_test.m4a',
      );
      await clip.writeAsBytes(<int>[0, 1, 2, 3], flush: true);
    });

    tearDown(() async {
      if (clip.existsSync()) await clip.delete();
    });

    Future<SpeechTranscription> transcribe(Map<String, Object?> body) {
      return ChatbotService(
        api: ApiService(
          baseUrl: 'http://localhost:8080/api',
          client: MockClient((http.Request request) async => http.Response(
                json.encode(body),
                200,
                headers: <String, String>{'content-type': 'application/json'},
              )),
        ),
      ).transcribeSpeechDetailed(audioPath: clip.path, durationMs: 1400);
    }

    test('a transcript the server doubted arrives marked as doubted', () async {
      final SpeechTranscription heard = await transcribe(<String, Object?>{
        'text': 'I am angry with you',
        'lowConfidence': true,
        'avgLogprob': -0.91,
      });

      expect(heard.text, 'I am angry with you');
      expect(heard.lowConfidence, isTrue);
    });

    test('a server that never sends the field is a server that is sure',
        () async {
      // Every backend older than this feature, which on the day it ships is
      // every backend a learner is actually talking to. They must go on
      // behaving exactly as they do today: a confirmation step nothing on that
      // server can ever raise would put a second tap in front of every single
      // turn, forever.
      final SpeechTranscription heard = await transcribe(<String, Object?>{
        'text': 'I would like a coffee please',
        'measuredDurationMs': 1400,
      });

      expect(heard.lowConfidence, isFalse);
      expect(heard.avgLogprob, isNull);
    });

    test('the server saying it is sure is the same as saying nothing',
        () async {
      final SpeechTranscription heard = await transcribe(<String, Object?>{
        'text': 'I would like a coffee please',
        'lowConfidence': false,
        'avgLogprob': -0.11,
      });

      expect(heard.lowConfidence, isFalse);
    });

    test('anything that is not a boolean is not a doubt', () async {
      // The contract says boolean. A stringly-typed value arriving by accident
      // must fall to the safe side, and the safe side is today's behaviour:
      // treating junk as a doubt would show the confirmation step on every
      // turn, which is the common path and the one thing this must not slow.
      for (final Object? junk in <Object?>['true', 1, 'yes', <String>[]]) {
        final SpeechTranscription heard = await transcribe(<String, Object?>{
          'text': 'I am agree with you',
          'lowConfidence': junk,
        });
        expect(heard.lowConfidence, isFalse, reason: 'read $junk as a doubt');
      }
    });

    test('a doubt raised by the language says so', () async {
      // Measured on a device: "Merhaba, biraz su alabilir miyiz?" came back as
      // "Hello, can you be able to do it?" -- confident English invented from
      // audio that was never English. The transcription is pinned to the
      // language being learned, so only the second, unpinned pass can notice,
      // and the footer needs to know: there is nothing to correct in that
      // sentence, and telling the learner they were misheard is telling them
      // the wrong thing.
      final SpeechTranscription heard = await transcribe(<String, Object?>{
        'text': 'Hello, can you be able to do it?',
        'lowConfidence': true,
        'avgLogprob': -0.91,
        'otherLanguage': true,
        'detectedLanguage': 'turkish',
      });

      expect(heard.lowConfidence, isTrue);
      expect(heard.otherLanguage, isTrue);
    });

    test('a doubt raised by the words alone is not a language verdict',
        () async {
      final SpeechTranscription heard = await transcribe(<String, Object?>{
        'text': 'I am angry with you',
        'lowConfidence': true,
        'avgLogprob': -0.91,
        'otherLanguage': false,
      });

      expect(heard.lowConfidence, isTrue);
      expect(heard.otherLanguage, isFalse);
    });

    test('a server that never sends the verdict has not given one', () async {
      for (final Object? junk in <Object?>[null, 'true', 1, <String>[]]) {
        final SpeechTranscription heard = await transcribe(<String, Object?>{
          'text': 'I am agree with you',
          'lowConfidence': true,
          if (junk != null) 'otherLanguage': junk,
        });
        expect(heard.otherLanguage, isFalse,
            reason: 'read $junk as a language verdict');
      }
    });

    test('the debugging score never becomes part of what was said', () async {
      // avgLogprob is for the log. "-0.82" beside their own sentence would be
      // read by a learner as a score of their pronunciation, which it is not.
      final SpeechTranscription heard = await transcribe(<String, Object?>{
        'text': 'I am angry with you',
        'lowConfidence': true,
        'avgLogprob': -0.82,
      });

      expect(heard.avgLogprob, closeTo(-0.82, 0.0001));
      expect(heard.text, 'I am angry with you',
          reason: 'the score leaked into the transcript');
    });
  });

  // ---------------------------------------------------------------------------
  // The fork
  // ---------------------------------------------------------------------------

  group('which transcripts get checked first', () {
    test('a doubted transcript does not go straight to the tutor', () {
      expect(
        NfCaptureResult.forTest(
          NfCaptureOutcome.transcribed,
          transcript: 'I am angry with you',
          lowConfidence: true,
        ).needsChecking,
        isTrue,
      );
    });

    test('a confident transcript takes the route it always has', () {
      // The common case, and the constraint that matters most: no extra tap,
      // no extra screen, no delay for the learner who was simply heard.
      expect(
        NfCaptureResult.forTest(
          NfCaptureOutcome.transcribed,
          transcript: 'I would like a coffee please',
        ).needsChecking,
        isFalse,
      );
    });

    test('an outcome with no words in it has nothing to check', () {
      // Silence, a tapped button and a failed upload all end the gesture with
      // no transcript. Routing one of those into the confirmation step would
      // put an empty text field in the footer with no way to explain itself.
      for (final NfCaptureOutcome outcome in <NfCaptureOutcome>[
        NfCaptureOutcome.silent,
        NfCaptureOutcome.tooShort,
        NfCaptureOutcome.notRecording,
        NfCaptureOutcome.failed,
      ]) {
        expect(
          NfCaptureResult.forTest(outcome, lowConfidence: true).needsChecking,
          isFalse,
          reason: '$outcome was sent to be confirmed',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // The footer while a doubtful sentence waits
  // ---------------------------------------------------------------------------

  group('what the footer says, and why', () {
    test('a mishearing is introduced as a mishearing', () {
      expect(nfConfirmHintKey(false), 'tutor.confirm.hint');
      expect(nfConfirmCaptionKey(false), 'tutor.confirm.caption');
    });

    test('another language is not', () {
      // There is nothing in "Hello, can you be able to do it?" for somebody who
      // said "Merhaba, biraz su alabilir miyiz?" to correct.
      expect(nfConfirmHintKey(true), 'tutor.confirm.hint.language');
      expect(nfConfirmCaptionKey(true), 'tutor.confirm.caption.language');
    });

    test('every interface language has both of them', () {
      for (final Locale locale in AppLocalizations.supportedLocales) {
        final AppLocalizations strings = AppLocalizations(locale);
        for (final bool otherLanguage in <bool>[true, false]) {
          final String hint = strings.t(nfConfirmHintKey(otherLanguage));
          final String caption = strings.t(nfConfirmCaptionKey(otherLanguage));
          expect(hint, isNotEmpty, reason: '${locale.languageCode} hint');
          expect(caption, isNotEmpty, reason: '${locale.languageCode} caption');
          expect(hint, isNot(contains('tutor.confirm')),
              reason: '${locale.languageCode} fell through to the key itself');
        }
      }
    });
  });

  group('checking the sentence', () {
    late TextEditingController controller;
    late int sent;
    late int discarded;

    setUp(() {
      sent = 0;
      discarded = 0;
    });

    tearDown(() => controller.dispose());

    Future<void> pump(WidgetTester tester, String transcript) async {
      controller = TextEditingController(text: transcript);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: nfConfirmTranscriptForTest(
            controller: controller,
            onSend: () => sent++,
            onDiscard: () => discarded++,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the sentence is shown to be read, not sent',
        (WidgetTester tester) async {
      await pump(tester, 'I am angry with you');

      expect(find.text('I am angry with you'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget,
          reason: 'the transcript cannot be corrected, only accepted');
      expect(sent, 0, reason: 'the mishearing reached the tutor anyway');
    });

    testWidgets('accepting it is one tap', (WidgetTester tester) async {
      // Somebody who was heard correctly and merely tripped the threshold has
      // done nothing wrong. Making them retype, re-read or double-confirm
      // their own sentence turns a safety net into a toll, and the threshold
      // is not tight enough for that to be rare.
      await pump(tester, 'I would like a coffee please');

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(sent, 1);
      expect(controller.text, 'I would like a coffee please',
          reason: 'accepting as-is changed the sentence');
    });

    testWidgets('the fix a learner came here to make survives the tap',
        (WidgetTester tester) async {
      // The entire point. "angry" is not what they said and the tutor must
      // never see it: what leaves this footer is what the learner left in the
      // field, not what the server guessed.
      await pump(tester, 'I am angry with you');

      await tester.enterText(find.byType(TextField), 'I am agree with you');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(sent, 1);
      expect(controller.text, 'I am agree with you');
    });

    testWidgets('the keyboard does not open over the conversation',
        (WidgetTester tester) async {
      // What keeps accepting to one tap. An autofocused field raises the
      // keyboard across the thread the sentence belongs to, so the learner who
      // was heard perfectly has to dismiss it before they can agree — two taps
      // and a covered screen, paid by the majority for the minority's benefit.
      await pump(tester, 'I would like a coffee please');

      final TextField field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autofocus, isFalse);
      // The field's own focus node, not whatever the framework happens to be
      // parking focus on: that node is what raises the software keyboard.
      final EditableText editable =
          tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.focusNode.hasFocus, isFalse,
          reason: 'the field took focus and raised the keyboard');
    });

    testWidgets('there is a way out that sends nothing',
        (WidgetTester tester) async {
      // A learner heard so badly that the sentence is not worth repairing has
      // to be able to say so. Without this the only exits are sending nonsense
      // to the tutor, and paying for it out of their daily tokens, or leaving.
      await pump(tester, "I'm very naked");

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();

      expect(discarded, 1);
      expect(sent, 0);
    });

    testWidgets('the sentence can be edited down to nothing without sending it',
        (WidgetTester tester) async {
      // Clearing the field is a second way of saying "forget it". The screen
      // treats an empty field as an abandoned turn rather than posting a blank
      // message the tutor has to answer.
      await pump(tester, 'I am angry with you');

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(controller.text.trim(), isEmpty);
      expect(sent, 1, reason: 'the screen decides what an empty field means');
    });
  });
}
