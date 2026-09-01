import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/tutor_correction.dart';

/// One turn of a saved conversation.
///
/// Deliberately not the page's own `_NfTurn`: that carries an `id` which is a
/// widget-key counter and means nothing between runs, and writing it out would
/// invite someone to restore it and collide with the live counter.
@immutable
class NfSavedTurn {
  const NfSavedTurn({
    required this.text,
    required this.fromTutor,
    this.hasAudio = false,
    this.note,
    this.correction,
  });

  final String text;
  final bool fromTutor;
  final bool hasAudio;
  final String? note;
  final TutorCorrection? correction;

  Map<String, dynamic> toJson() => <String, dynamic>{
        't': text,
        'm': fromTutor,
        if (hasAudio) 'a': true,
        if (note != null) 'n': note,
        if (correction != null)
          'c': <String, String>{
            'said': correction!.said,
            'better': correction!.better,
          },
      };

  /// Null for anything unreadable. A conversation that half-loads is worse
  /// than one that does not: the turns that survived would sit under a
  /// timestamp claiming to be the whole thing.
  static NfSavedTurn? fromJson(Object? value) {
    if (value is! Map) return null;
    final String text = value['t']?.toString() ?? '';
    if (text.isEmpty) return null;
    return NfSavedTurn(
      text: text,
      fromTutor: value['m'] == true,
      hasAudio: value['a'] == true,
      note: value['n']?.toString(),
      correction: TutorCorrection.fromJson(value['c']),
    );
  }
}

/// A whole conversation, as it will be found again.
@immutable
class NfTutorSession {
  const NfTutorSession({
    required this.id,
    required this.startedAt,
    required this.voiceId,
    required this.sceneId,
    required this.turns,
  });

  final String id;
  final DateTime startedAt;

  /// Which speaker was talking. Restoring a thread under a different face
  /// would read as one person having changed voice mid-conversation.
  final String voiceId;

  /// The scene, or null for free chat.
  final String? sceneId;

  final List<NfSavedTurn> turns;

  /// What the learner actually said first, for the history list. The opening
  /// line is the same sentence in every session and names none of them.
  String get preview {
    for (final NfSavedTurn turn in turns) {
      if (!turn.fromTutor && turn.text.trim().isNotEmpty) {
        return turn.text.trim();
      }
    }
    return turns.isEmpty ? '' : turns.first.text.trim();
  }

  /// Whether this is worth keeping. A thread where nobody spoke is the
  /// greeting and nothing else, and five of those would push out five real
  /// conversations.
  bool get hasLearnerTurn => turns.any((NfSavedTurn t) => !t.fromTutor);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'at': startedAt.toIso8601String(),
        'voice': voiceId,
        if (sceneId != null) 'scene': sceneId,
        'turns': turns.map((NfSavedTurn t) => t.toJson()).toList(),
      };

  static NfTutorSession? fromJson(Object? value) {
    if (value is! Map) return null;
    final DateTime? at = DateTime.tryParse(value['at']?.toString() ?? '');
    final Object? rawTurns = value['turns'];
    if (at == null || rawTurns is! List) return null;

    final List<NfSavedTurn> turns = <NfSavedTurn>[
      for (final Object? t in rawTurns)
        if (NfSavedTurn.fromJson(t) case final NfSavedTurn turn) turn,
    ];
    if (turns.isEmpty) return null;

    return NfTutorSession(
      id: value['id']?.toString() ?? at.microsecondsSinceEpoch.toString(),
      startedAt: at,
      voiceId: value['voice']?.toString() ?? '',
      sceneId: value['scene']?.toString(),
      turns: turns,
    );
  }
}

/// The last few spoken conversations, kept across launches.
///
/// The tutor tab held its thread in memory only. It survived tab switches --
/// the shell keeps the page alive in an IndexedStack -- and nothing else: a
/// restart, or picking a different speaker or scene, and the conversation was
/// gone with no way back to it.
///
/// Five, because that was the number asked for and it is the right order of
/// magnitude anyway: a spoken turn is a sentence, so a long conversation is a
/// couple of kilobytes and five of them are ten. [maxTurnsPerSession] and
/// [_maxBytes] are backstops rather than expectations -- SharedPreferences on
/// Android is one XML file read whole at startup, and an unbounded write here
/// would slow down every launch of the app, not just this tab.
class NfTutorSessions {
  const NfTutorSessions._();

  static const String prefsKey = 'nf_tutor_sessions_v1';
  static const int maxSessions = 5;

  /// Long conversations are trimmed from the front, keeping the recent end.
  /// The beginning of a hundred-turn thread is not what anyone comes back for.
  static const int maxTurnsPerSession = 120;

  /// A ceiling on the whole store. Nothing should reach it; if something does,
  /// the oldest sessions go rather than the app carrying an unbounded blob it
  /// re-reads on every launch.
  static const int _maxBytes = 256 * 1024;

  static Future<List<NfTutorSession>> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return const <NfTutorSession>[];

      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return const <NfTutorSession>[];

      return <NfTutorSession>[
        for (final Object? item in decoded)
          if (NfTutorSession.fromJson(item) case final NfTutorSession s) s,
      ];
    } catch (error) {
      // A conversation history is a convenience. Nothing here is worth
      // failing a screen over, so unreadable storage reads as empty.
      debugPrint('NfTutorSessions: could not read history ($error)');
      return const <NfTutorSession>[];
    }
  }

  /// Writes [session] as the newest, replacing any earlier copy of it.
  ///
  /// Called on every turn, so it is an upsert rather than an append: a thread
  /// being added to is the same thread, not five copies of itself at five
  /// lengths.
  static Future<void> save(NfTutorSession session) async {
    if (!session.hasLearnerTurn) return;

    final List<NfTutorSession> existing = await load();
    final NfTutorSession trimmed = session.turns.length <= maxTurnsPerSession
        ? session
        : NfTutorSession(
            id: session.id,
            startedAt: session.startedAt,
            voiceId: session.voiceId,
            sceneId: session.sceneId,
            turns: session.turns
                .sublist(session.turns.length - maxTurnsPerSession),
          );

    final List<NfTutorSession> next = <NfTutorSession>[
      trimmed,
      ...existing.where((NfTutorSession s) => s.id != session.id),
    ];
    await _write(next.take(maxSessions).toList());
  }

  static Future<void> delete(String id) async {
    final List<NfTutorSession> rest = (await load())
        .where((NfTutorSession s) => s.id != id)
        .toList();
    await _write(rest);
  }

  static Future<void> clear() => _write(const <NfTutorSession>[]);

  static Future<void> _write(List<NfTutorSession> sessions) async {
    try {
      List<NfTutorSession> keep = sessions;
      String encoded = _encode(keep);
      // Drop from the old end until it fits, rather than refusing to save.
      while (encoded.length > _maxBytes && keep.length > 1) {
        keep = keep.sublist(0, keep.length - 1);
        encoded = _encode(keep);
      }

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, encoded);
    } catch (error) {
      debugPrint('NfTutorSessions: could not write history ($error)');
    }
  }

  static String _encode(List<NfTutorSession> sessions) => jsonEncode(
      sessions.map((NfTutorSession s) => s.toJson()).toList());
}
