import 'sentence_tokens.dart';

/// Turning a saved sentence into a fill-in-the-blank prompt.
///
/// The review card asks a word and expects its meaning: recognition. A sentence
/// with the word taken out asks the opposite — the meaning is there in the
/// context and the word is what has to be produced. Recall in that direction is
/// harder and holds better, and the sentences are already there: every word
/// saved from a book arrives with the line it came from.
///
/// The whole thing has one way to be wrong, and it is quiet: a blank punched
/// in the wrong place, or a word that is still visible somewhere else in the
/// sentence, turns a recall exercise into a reading exercise and nobody
/// notices. So this refuses more often than it guesses.
class Cloze {
  const Cloze._();

  /// What replaces the word. Long enough to read as a gap rather than a dash.
  static const String blank = '_____';

  /// The sentence with [word] blanked out, or null when it cannot be done
  /// safely.
  ///
  /// Returns null when the word does not appear in the sentence at all — which
  /// happens for words saved by hand with an unrelated example, and for
  /// inflections the matcher will not stretch to. A card with no blank in it is
  /// worse than no cloze card, so the caller falls back to asking the word
  /// itself.
  static String? build(String sentence, String word) {
    final String target = SentenceTokens.word(word);
    if (target.isEmpty || sentence.trim().isEmpty) return null;

    final List<String> tokens = SentenceTokens.split(sentence);
    bool replacedAny = false;

    final StringBuffer out = StringBuffer();
    for (final String token in tokens) {
      if (token.trim().isEmpty) {
        out.write(token);
        continue;
      }
      if (_matches(token, target)) {
        // Punctuation attached to the word stays: blanking "gate!" to "_____"
        // would quietly remove the exclamation mark the sentence was written
        // with, and the learner is being asked for a word, not a full stop.
        out.write(_maskKeepingPunctuation(token));
        replacedAny = true;
      } else {
        out.write(token);
      }
    }

    return replacedAny ? out.toString() : null;
  }

  /// Whether this token is the word being asked for.
  ///
  /// Deliberately the same rule the dictionary highlight uses, so a word that
  /// counts as "the searched word" in one place counts in the other. It allows
  /// delay/delayed without allowing a/delay.
  static bool _matches(String token, String target) {
    final String bare = SentenceTokens.word(token);
    if (bare.isEmpty) return false;
    return SentenceTokens.isSearched(bare, target);
  }

  /// Replaces the letters of a token and leaves whatever was hanging off it.
  static String _maskKeepingPunctuation(String token) {
    final RegExpMatch? match =
        RegExp(r'^(\W*)(.*?)(\W*)$', dotAll: true).firstMatch(token);
    if (match == null) return blank;
    return '${match.group(1)}$blank${match.group(3)}';
  }
}
