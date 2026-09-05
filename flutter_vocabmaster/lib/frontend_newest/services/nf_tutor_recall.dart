import 'nf_tutor_sessions.dart';
import '../../models/tutor_correction.dart';

/// One sentence about the last conversation, for the tutor's system prompt.
///
/// The app has kept the last five sessions since they became persistent, and
/// used them for exactly one thing: a list to reopen. The tutor itself never
/// saw them, so every conversation opened as if the learner had arrived for
/// the first time — which is the difference between a tool and somebody who
/// knows you, and it is the cheapest reason a person has to come back.
///
/// Written in English, not the interface language, for the same reason
/// [NfScene.freeChatOpening] is: this text is read by the model and shapes an
/// English reply. A Turkish sentence here would invite a Turkish answer, and
/// Piper would then read it with an English voice.
///
/// Deliberately small. It names when, what scene, and at most two corrections
/// that came up. Long recall makes the model dwell on the past instead of
/// starting the conversation, and every character is a token on every thread.
class NfTutorRecall {
  const NfTutorRecall._();

  /// Sessions older than this are not "last time" in any useful sense.
  static const Duration _staleAfter = Duration(days: 30);

  /// Corrections carry the teaching; more than two turns the opener into a
  /// list of the learner's mistakes, which is not how anyone wants to be met.
  static const int _maxCorrections = 2;

  /// A ceiling the caller cannot accidentally blow past. Roughly 80 tokens.
  static const int _maxChars = 320;

  /// The recall line for [sessions], or null when there is nothing to recall.
  ///
  /// [currentThreadId] is skipped: the thread being started is not a memory
  /// of itself, and it is already in the store by the time a second one
  /// begins. [now] is a parameter so the relative wording is testable.
  static String? build(
    List<NfTutorSession> sessions, {
    required String currentThreadId,
    required DateTime now,
  }) {
    final NfTutorSession? last = _mostRecentBefore(sessions, currentThreadId);
    if (last == null) {
      return null;
    }

    final Duration age = now.difference(last.startedAt);
    if (age.isNegative || age > _staleAfter) {
      return null;
    }

    final StringBuffer line = StringBuffer()
      ..write(_when(age))
      ..write(' the learner practised ')
      ..write(last.sceneId == null
          ? 'free conversation'
          : 'the "${_readable(last.sceneId!)}" scene')
      ..write(' with you.');

    final List<String> fixes = _corrections(last);
    if (fixes.isNotEmpty) {
      line
        ..write(' Corrections that came up: ')
        ..write(fixes.map((String f) => '"$f"').join('; '))
        ..write('.');
    }

    final String text = _tidy(line.toString());
    return text.isEmpty ? null : text;
  }

  /// The newest session that is not the current thread and that somebody
  /// actually spoke in.
  static NfTutorSession? _mostRecentBefore(
    List<NfTutorSession> sessions,
    String currentThreadId,
  ) {
    NfTutorSession? best;
    for (final NfTutorSession session in sessions) {
      if (session.id == currentThreadId || !session.hasLearnerTurn) {
        continue;
      }
      if (best == null || session.startedAt.isAfter(best.startedAt)) {
        best = session;
      }
    }
    return best;
  }

  /// The last corrections of the session, newest first.
  static List<String> _corrections(NfTutorSession session) {
    final List<String> found = <String>[];
    for (int i = session.turns.length - 1; i >= 0; i--) {
      final TutorCorrection? fix = session.turns[i].correction;
      final String better = fix?.better.trim() ?? '';
      if (better.isEmpty || found.contains(better)) {
        continue;
      }
      found.add(better);
      if (found.length == _maxCorrections) {
        break;
      }
    }
    return found;
  }

  /// `airport_checkin` -> `airport checkin`.
  ///
  /// The id rather than the scene's translated name, because this is read by
  /// the model in English, and because it keeps working for a scene added
  /// after this file was written.
  static String _readable(String sceneId) =>
      sceneId.replaceAll('_', ' ').trim();

  static String _when(Duration age) {
    final int days = age.inDays;
    if (days < 1) return 'Earlier today';
    if (days == 1) return 'Yesterday';
    if (days < 7) return '$days days ago';
    if (days < 14) return 'A week ago';
    return '${days ~/ 7} weeks ago';
  }

  /// Flattens the line and clips it.
  ///
  /// Newlines and braces come out because this is pasted into a prompt beside
  /// instructions; the server sanitises it again, and neither layer trusts the
  /// other to have done it. The clip is on a word boundary so a truncated
  /// correction does not read as a different sentence.
  static String _tidy(String text) {
    final String flat =
        text.replaceAll(RegExp(r'[\r\n{}]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= _maxChars) {
      return flat;
    }
    final String cut = flat.substring(0, _maxChars);
    final int lastSpace = cut.lastIndexOf(' ');
    return '${lastSpace > 40 ? cut.substring(0, lastSpace) : cut}…';
  }
}
