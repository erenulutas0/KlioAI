/// One thing the learner said, and the way to say it.
///
/// The speaking tab has always had corrections and never shown them. The server
/// tells the model to recast a mistake naturally inside its reply, so the fix is
/// in there somewhere, folded into a sentence about coffee — which is exactly
/// where someone practising a language will not notice it. This is the same
/// correction, pulled out where it can be read, and later counted.
///
/// Absent means the model had nothing worth correcting, which is the ordinary
/// case and must stay distinguishable from an empty one: a chip that says
/// nothing still tells the learner they got something wrong.
class TutorCorrection {
  const TutorCorrection({required this.said, required this.better});

  /// What the learner actually said, as the transcript heard it.
  final String said;

  /// The same thing, said correctly.
  final String better;

  /// Reads the `correction` object off a chat response, or null.
  ///
  /// Tolerant on purpose. This is model output that has been through a marker,
  /// a server and a JSON body, and the screen it lands on is the app's most
  /// important one: anything malformed becomes no correction, never a broken
  /// turn. A correction that repeats the learner word for word is dropped too —
  /// being told you were wrong and shown the same sentence back teaches nothing.
  static TutorCorrection? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final String said = value['said']?.toString().trim() ?? '';
    final String better = value['better']?.toString().trim() ?? '';
    if (said.isEmpty || better.isEmpty) {
      return null;
    }
    // Compared with punctuation and spacing removed, because the model is
    // asked to reproduce "their exact words" and drifts by a full stop. A
    // lowercase-only comparison passed "I go to school." against "I go to
    // school" and drew a correction chip whose two lines were identical --
    // being told you were wrong and shown your own sentence back teaches
    // nothing and reads as a bug.
    if (_normalise(said) == _normalise(better)) {
      return null;
    }
    return TutorCorrection(said: said, better: better);
  }

  /// Whether this correction is about [transcript], the sentence actually
  /// sent to the model.
  ///
  /// Nothing else checks. The prompt asks the model to correct only what the
  /// learner said and never to invent a mistake, and that request was the
  /// entire enforcement: a hallucinated `said` was attached to the last
  /// learner turn and drawn struck through, under "Say it like this". Being
  /// shown words you never spoke, crossed out, is the fastest way to lose
  /// somebody's trust in the one feature that justifies this screen.
  ///
  /// Word overlap rather than string distance, because the two texts come
  /// from different places -- one from Whisper, one echoed back by the model
  /// -- and disagree about punctuation, casing and the odd filler. A quote
  /// shares nearly all of its words with the original; an invention shares
  /// almost none, so anything in between is rare and the threshold is not
  /// delicate.
  bool isAbout(String transcript) {
    final List<String> quoted = _words(said);
    if (quoted.isEmpty) {
      return false;
    }
    final Set<String> heard = _words(transcript).toSet();
    if (heard.isEmpty) {
      return false;
    }
    final int shared = quoted.where(heard.contains).length;
    return shared / quoted.length >= _minWordOverlap;
  }

  /// Six in ten. A model quoting the learner lands at or near one; a model
  /// inventing a sentence lands near zero.
  static const double _minWordOverlap = 0.6;

  static final RegExp _notWord = RegExp(r"[^a-z0-9']+");

  static List<String> _words(String text) => text
      .toLowerCase()
      .split(_notWord)
      .where((String w) => w.isNotEmpty)
      .toList();

  static String _normalise(String text) => _words(text).join(' ');

  @override
  String toString() => 'TutorCorrection($said -> $better)';
}

/// A reply, and whatever came back with it.
class TutorReply {
  const TutorReply({required this.text, this.correction});

  final String text;
  final TutorCorrection? correction;

  bool get isEmpty => text.trim().isEmpty;
}
