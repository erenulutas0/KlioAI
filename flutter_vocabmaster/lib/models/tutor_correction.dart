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
    if (said.toLowerCase() == better.toLowerCase()) {
      return null;
    }
    return TutorCorrection(said: said, better: better);
  }

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
