import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/frontend_newest/services/nf_tutor_sessions.dart';
import 'package:vocabmaster/models/tutor_correction.dart';

/// The tutor's conversation used to live in memory and nowhere else. It
/// survived tab switches, because the shell keeps that page alive, and nothing
/// else: a restart, or picking a different speaker, and it was gone.
///
/// What this store has to get right is mostly about what it refuses to keep.
/// An upsert rather than an append, because it is written on every turn and
/// the alternative is five copies of one conversation at five lengths. No
/// greeting-only threads, because five of those would push out five real ones.
/// And nothing unreadable, because a history that half-loads is worse than an
/// empty one: the turns that survived would sit under a timestamp claiming to
/// be the whole conversation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  NfTutorSession session(
    String id, {
    List<NfSavedTurn>? turns,
    String? scene,
    DateTime? at,
  }) =>
      NfTutorSession(
        id: id,
        startedAt: at ?? DateTime(2026, 1, 1),
        voiceId: 'amy',
        sceneId: scene,
        turns: turns ??
            const <NfSavedTurn>[
              NfSavedTurn(text: 'Hi, I am Amy.', fromTutor: true),
              NfSavedTurn(text: 'I go to school yesterday', fromTutor: false),
            ],
      );

  test('a conversation comes back with its turns and its speaker', () async {
    await NfTutorSessions.save(session('a', scene: 'cafe_order', turns: const [
      NfSavedTurn(text: 'What can I get you?', fromTutor: true, hasAudio: true),
      NfSavedTurn(
        text: 'I want a coffee',
        fromTutor: false,
        note: '+5 XP',
        correction: TutorCorrection(
            said: 'I want a coffee', better: "I'd like a coffee"),
      ),
    ]));

    final List<NfTutorSession> back = await NfTutorSessions.load();
    expect(back, hasLength(1));
    expect(back.single.sceneId, 'cafe_order');
    expect(back.single.voiceId, 'amy');
    expect(back.single.turns, hasLength(2));
    expect(back.single.turns.first.hasAudio, isTrue);
    expect(back.single.turns.last.note, '+5 XP');
    expect(back.single.turns.last.correction?.better, "I'd like a coffee");
  });

  test('saving the same conversation again replaces it', () async {
    await NfTutorSessions.save(session('a'));
    await NfTutorSessions.save(session('a', turns: const <NfSavedTurn>[
      NfSavedTurn(text: 'Hi, I am Amy.', fromTutor: true),
      NfSavedTurn(text: 'I went to school yesterday', fromTutor: false),
      NfSavedTurn(text: 'How was it?', fromTutor: true),
    ]));

    final List<NfTutorSession> back = await NfTutorSessions.load();
    expect(back, hasLength(1),
        reason: 'the same conversation was stored twice, at two lengths');
    expect(back.single.turns, hasLength(3));
  });

  test('only the last five are kept, newest first', () async {
    for (int i = 1; i <= 7; i++) {
      await NfTutorSessions.save(session('s$i'));
    }
    final List<NfTutorSession> back = await NfTutorSessions.load();
    expect(back.map((NfTutorSession s) => s.id).toList(),
        <String>['s7', 's6', 's5', 's4', 's3']);
  });

  test('a conversation nobody spoke in is not kept', () async {
    // The greeting alone. Five of these would evict five real conversations.
    await NfTutorSessions.save(session('empty', turns: const <NfSavedTurn>[
      NfSavedTurn(text: 'Hi, I am Amy.', fromTutor: true),
    ]));
    expect(await NfTutorSessions.load(), isEmpty);
  });

  test('a very long conversation keeps its recent end', () async {
    final List<NfSavedTurn> many = <NfSavedTurn>[
      for (int i = 0; i < NfTutorSessions.maxTurnsPerSession + 40; i++)
        NfSavedTurn(text: 'turn $i', fromTutor: i.isEven),
    ];
    await NfTutorSessions.save(session('long', turns: many));

    final NfTutorSession back = (await NfTutorSessions.load()).single;
    expect(back.turns, hasLength(NfTutorSessions.maxTurnsPerSession));
    expect(back.turns.last.text, many.last.text,
        reason: 'the end was trimmed, so it kept the part nobody returns for');
  });

  test('the preview is what the learner said, not the greeting', () async {
    // Every session opens with the same sentence, so a preview taken from the
    // first turn would label all five identically.
    final NfTutorSession s = session('a', turns: const <NfSavedTurn>[
      NfSavedTurn(text: 'Hi, I am Amy.', fromTutor: true),
      NfSavedTurn(text: 'I go to school yesterday', fromTutor: false),
    ]);
    expect(s.preview, 'I go to school yesterday');
  });

  test('unreadable storage reads as no history, not as a crash', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      NfTutorSessions.prefsKey: 'not json at all',
    });
    expect(await NfTutorSessions.load(), isEmpty);

    SharedPreferences.setMockInitialValues(<String, Object>{
      NfTutorSessions.prefsKey: jsonEncode(<String>['a string, not a map']),
    });
    expect(await NfTutorSessions.load(), isEmpty);
  });

  test('one damaged conversation does not take the others with it', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      NfTutorSessions.prefsKey: jsonEncode(<Object>[
        <String, Object>{'id': 'broken', 'turns': 'not a list'},
        session('good').toJson(),
      ]),
    });
    final List<NfTutorSession> back = await NfTutorSessions.load();
    expect(back, hasLength(1));
    expect(back.single.id, 'good');
  });

  test('a turn with no text is dropped rather than restored blank', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      NfTutorSessions.prefsKey: jsonEncode(<Object>[
        <String, Object>{
          'id': 'a',
          'at': DateTime(2026).toIso8601String(),
          'voice': 'amy',
          'turns': <Object>[
            <String, Object>{'t': '', 'm': true},
            <String, Object>{'t': 'I went there', 'm': false},
          ],
        },
      ]),
    });
    final NfTutorSession back = (await NfTutorSessions.load()).single;
    expect(back.turns, hasLength(1));
    expect(back.turns.single.text, 'I went there');
  });

  test('deleting removes one and leaves the rest', () async {
    await NfTutorSessions.save(session('a'));
    await NfTutorSessions.save(session('b'));
    await NfTutorSessions.delete('a');

    final List<NfTutorSession> back = await NfTutorSessions.load();
    expect(back.map((NfTutorSession s) => s.id), <String>['b']);
  });

  test('the stored form stays small', () async {
    // The whole reason five was affordable. SharedPreferences on Android is
    // one XML file read whole at startup, so this is app launch time, not
    // just this tab's.
    for (int i = 1; i <= NfTutorSessions.maxSessions; i++) {
      await NfTutorSessions.save(session('s$i', turns: <NfSavedTurn>[
        for (int t = 0; t < 30; t++)
          NfSavedTurn(
            text: 'A sentence of about the length someone actually speaks $t',
            fromTutor: t.isEven,
          ),
      ]));
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int bytes = prefs.getString(NfTutorSessions.prefsKey)!.length;
    expect(bytes, lessThan(64 * 1024),
        reason: 'five full conversations came to $bytes bytes, which is more '
            'than this should ever cost at launch');
  });
}
