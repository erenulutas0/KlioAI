import 'dart:ui' show TextRange;

import 'package:flutter/foundation.dart';

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
  static ClozePrompt? build(String sentence, String word) {
    final String target = SentenceTokens.word(word);
    if (target.isEmpty || sentence.trim().isEmpty) return null;

    final List<String> tokens = SentenceTokens.split(sentence);
    final StringBuffer blanked = StringBuffer();
    final StringBuffer filled = StringBuffer();
    final List<TextRange> answers = <TextRange>[];

    for (final String token in tokens) {
      if (token.trim().isEmpty) {
        blanked.write(token);
        filled.write(token);
        continue;
      }
      if (_matches(token, target)) {
        // Punctuation attached to the word stays: blanking "gate!" to "_____"
        // would quietly remove the exclamation mark the sentence was written
        // with, and the learner is being asked for a word, not a full stop.
        final _Split split = _split(token);
        blanked.write('${split.before}$blank${split.after}');
        filled.write(split.before);
        answers.add(TextRange(
          start: filled.length,
          end: filled.length + split.word.length,
        ));
        filled..write(split.word)..write(split.after);
      } else {
        blanked.write(token);
        filled.write(token);
      }
    }

    if (answers.isEmpty) return null;
    return ClozePrompt(
      blanked: blanked.toString(),
      filled: filled.toString(),
      answers: List<TextRange>.unmodifiable(answers),
    );
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

  /// A token pulled apart into its leading punctuation, its letters, and its
  /// trailing punctuation.
  static _Split _split(String token) {
    final RegExpMatch? match =
        RegExp(r'^(\W*)(.*?)(\W*)$', dotAll: true).firstMatch(token);
    if (match == null) return _Split('', token, '');
    return _Split(match.group(1)!, match.group(2)!, match.group(3)!);
  }
}

/// Both halves of one fill-in-the-blank question.
///
/// [blanked] is what is asked; [filled] is the same line with the word back in
/// it, and [answers] says where. Revealing used to replace the whole sentence
/// with the bare word, which put the answer somewhere the reader was not
/// looking — the gap is where their eye is, so the gap is where the answer has
/// to appear.
@immutable
class ClozePrompt {
  const ClozePrompt({
    required this.blanked,
    required this.filled,
    required this.answers,
  });

  final String blanked;
  final String filled;

  /// Where the word sits inside [filled], so it can be marked when shown. More
  /// than one when the sentence uses the word more than once.
  final List<TextRange> answers;
}

class _Split {
  const _Split(this.before, this.word, this.after);
  final String before;
  final String word;
  final String after;
}
