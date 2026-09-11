import 'dart:typed_data';

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
  const TutorCorrection({
    required this.said,
    required this.better,
    this.note,
    this.sentence,
    this.more = const <TutorCorrection>[],
  });

  /// What the learner actually said, as the transcript heard it.
  final String said;

  /// The same thing, said correctly.
  final String better;

  /// Why the first line was wrong, in the language the learner reads.
  ///
  /// Two lines with one word changed between them tell a learner that they
  /// were wrong and not what they got wrong: "I am boring" against "I'm bored"
  /// is a joke to anyone who already knows the difference and a mystery to
  /// everyone else, which is the entire audience for this screen. The model
  /// writes this sentence in the learner's own language and the server sends
  /// it through already written, so nothing on this side translates it or ever
  /// should.
  ///
  /// Null is the ordinary case: the model is asked for a note and frequently
  /// has nothing short to say, and every correction that predates the field
  /// has none. It stays distinct from an empty string because a blank line
  /// under a correction is indistinguishable, on a phone, from a card that
  /// failed to draw.
  final String? note;

  /// The learner's whole message as a native speaker would say it, or null.
  ///
  /// A tester at B2 said a sentence with five mistakes in it and got a card that showed
  /// one, which he read -- fairly -- as the other four being fine. The card now leads with
  /// the whole sentence fixed, so however few changes it has room to explain, it never
  /// implies that the rest of what was said was right.
  final String? sentence;

  /// The other changes in the same message, in order of importance, each with its own note.
  ///
  /// This object is the most important change and these are the ones after it, so every
  /// place that has only ever read one correction -- the recall line, the deck, saved
  /// conversations -- keeps reading the one it read before.
  final List<TutorCorrection> more;

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
    // The note is the one part of a correction the model composes freely, in a
    // language nobody on this side of the wire can read, and it goes onto the
    // screen unedited. Length is the only thing that can be checked without
    // understanding it: asked for a clause, a model that decides to teach the
    // present perfect instead pushes the corrected line off the top of a
    // phone, and the corrected line is the reason the card exists. So an
    // oversized note is dropped and the correction is kept. Never the reverse,
    // and never the whole card -- a bad explanation must not cost a learner
    // the fix it was explaining.
    //
    // Read more strictly than the two lines above it for the same reason. A
    // said or better that arrived as the wrong type is worth stringifying,
    // because the alternative is losing the correction; a note is worth
    // nothing stringified, so anything that is not already text is simply not
    // an explanation.
    final Object? rawNote = value['note'];
    final String note = rawNote is String ? rawNote.trim() : '';
    return TutorCorrection(
      said: said,
      better: better,
      note: note.isEmpty || note.length > _maxNoteLength ? null : note,
      // Present only in what this app wrote itself, a saved conversation; the server sends
      // them beside the correction rather than inside it, which fromResponse reads.
      sentence: _sentenceFrom(value['sentence']),
      more: _moreFrom(value['more']),
    );
  }

  /// Roughly two lines under the correction on a phone. The prompt asks for a
  /// short clause, so anything past this is a model that stopped answering the
  /// question it was asked.
  static const int _maxNoteLength = 160;

  /// Roughly three lines on a phone: a spoken turn, not a paragraph.
  static const int _maxSentenceLength = 400;

  /// Three changes on a card at most: the main one and two more.
  static const int _maxMore = 2;

  /// The correction a chat response carries, or null.
  ///
  /// Reads `corrections` -- every change the card lists, most important first -- and
  /// `correctedSentence`, the learner's whole message fixed. Falls back to the single
  /// `correction` a server before them sent, so an older server draws the card it always
  /// drew. Every change passes [fromJson]'s rules on its own, and one that fails costs
  /// only itself.
  static TutorCorrection? fromResponse(Object? body) {
    if (body is! Map) {
      return null;
    }
    final List<TutorCorrection> changes = <TutorCorrection>[];
    final Object? listed = body['corrections'];
    if (listed is List) {
      for (final Object? item in listed) {
        final TutorCorrection? change = _flat(item);
        if (change == null) {
          continue;
        }
        final String key = _normalise(change.said);
        if (changes.any((TutorCorrection c) => _normalise(c.said) == key)) {
          continue;
        }
        changes.add(change);
      }
    }
    if (changes.isEmpty) {
      final TutorCorrection? single = _flat(body['correction']);
      if (single == null) {
        return null;
      }
      changes.add(single);
    }
    final TutorCorrection main = changes.first;
    return TutorCorrection(
      said: main.said,
      better: main.better,
      note: main.note,
      sentence: _sentenceFrom(body['correctedSentence']),
      more: List<TutorCorrection>.unmodifiable(changes.skip(1).take(_maxMore)),
    );
  }

  /// One change on its own: [fromJson] with anything nested in it left behind.
  static TutorCorrection? _flat(Object? value) {
    final TutorCorrection? parsed = fromJson(value);
    return parsed == null
        ? null
        : TutorCorrection(said: parsed.said, better: parsed.better, note: parsed.note);
  }

  static String? _sentenceFrom(Object? value) {
    if (value is! String) {
      return null;
    }
    final String trimmed = value.trim();
    return trimmed.isEmpty || trimmed.length > _maxSentenceLength ? null : trimmed;
  }

  static List<TutorCorrection> _moreFrom(Object? value) {
    if (value is! List) {
      return const <TutorCorrection>[];
    }
    final List<TutorCorrection> out = <TutorCorrection>[];
    for (final Object? item in value) {
      final TutorCorrection? change = _flat(item);
      if (change != null && out.length < _maxMore) {
        out.add(change);
      }
    }
    return List<TutorCorrection>.unmodifiable(out);
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

  /// Every change on the card, the main one first.
  List<TutorCorrection> get changes => <TutorCorrection>[
        TutorCorrection(said: said, better: better, note: note),
        ...more,
      ];

  /// Whether the whole sentence says more than the main change already does.
  ///
  /// When the change IS the sentence -- "I go to Paris yesterday" -> "I went to Paris
  /// yesterday" -- leading with it would draw the same words twice.
  bool get showsSentence {
    final String? whole = sentence;
    return whole != null && _normalise(whole) != _normalise(better);
  }

  /// This correction keeping only what is about [transcript], or null if its main change
  /// is not.
  ///
  /// [isAbout] has always guarded the main change: a correction of words the learner never
  /// said is drawn struck through as if they had. The rest of the card gets the same guard.
  /// A further change that is not about the sentence is dropped on its own, and the whole
  /// sentence has to share most of its words with what was said -- a model that wrote a
  /// different sentence has not corrected this one.
  TutorCorrection? about(String transcript) {
    if (!isAbout(transcript)) {
      return null;
    }
    final String? whole = sentence;
    return TutorCorrection(
      said: said,
      better: better,
      note: note,
      sentence: whole != null && _sharesMostWords(whole, transcript) ? whole : null,
      more: List<TutorCorrection>.unmodifiable(
          more.where((TutorCorrection change) => change.isAbout(transcript))),
    );
  }

  /// Half. A corrected sentence keeps the learner's words and changes the wrong ones, so it
  /// shares most of them; an unrelated sentence shares almost none.
  static const double _minSentenceOverlap = 0.5;

  static bool _sharesMostWords(String sentence, String transcript) {
    final List<String> words = _words(sentence);
    if (words.isEmpty) {
      return false;
    }
    final Set<String> heard = _words(transcript).toSet();
    return words.where(heard.contains).length / words.length >= _minSentenceOverlap;
  }

  /// As a saved conversation keeps it: each key only when there is something in it.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'said': said,
        'better': better,
        if (note != null) 'note': note,
        if (sentence != null) 'sentence': sentence,
        if (more.isNotEmpty)
          'more': <Map<String, dynamic>>[
            for (final TutorCorrection change in more) change.toJson(),
          ],
      };

  @override
  String toString() => 'TutorCorrection($said -> $better)';
}

/// A reply, and whatever came back with it.
class TutorReply {
  const TutorReply({required this.text, this.correction, this.audio});

  final String text;
  final TutorCorrection? correction;

  /// The reply already spoken, when the server sent it with the text -- see
  /// [ApiService.chatbotChatTurn]. Null means nothing more than "ask for it".
  final Uint8List? audio;

  bool get isEmpty => text.trim().isEmpty;
}
