/// Splitting a sentence into tappable words, and deciding which one is the searched word.
///
/// Both were inline in the quick dictionary and both were wrong in ways that only show up
/// on screen: the sentence lost every space, and the highlight painted single letters.
class SentenceTokens {
  const SentenceTokens._();

  /// Words and the whitespace between them, in order.
  ///
  /// The previous version used `split(RegExp(r'(\s+)'))` with a capture group, which is a
  /// JavaScript idiom: Dart does not re-insert captured separators, so every space was
  /// discarded and the sentence rendered as "Shehasabeautiful voice." The branch meant to
  /// render the gaps could never run, because no gap was ever produced.
  static List<String> split(String sentence) =>
      RegExp(r'\s+|\S+').allMatches(sentence).map((match) => match[0]!).toList();

  /// A token reduced to the word a learner would look up.
  ///
  /// Strips punctuation from the ends only. Stripping it everywhere turned "It's" into
  /// "its" and "well-known" into "wellknown", and that mangled form was both sent to the
  /// backend — which was then asked about a word the sentence does not contain — and shown
  /// as the dialog's title, presenting the answer to a different question as authoritative.
  static String word(String token) =>
      token.replaceAll(RegExp(r'^\W+|\W+$'), '').toLowerCase();

  /// Whether this token is the word that was searched for.
  ///
  /// Was a pair of substring checks, so searching "delay" highlighted every "a" in the
  /// sentence — and highlighted tokens are not tappable, so the articles and prepositions
  /// a learner is most likely to want defined were exactly the ones they could not tap.
  /// A prefix match with a floor allows delay/delayed without allowing a/delay.
  static bool isSearched(String token, String searched) {
    final left = token.toLowerCase();
    final right = searched.toLowerCase();
    if (left.isEmpty || right.isEmpty) return false;
    if (left == right) return true;

    final shorter = left.length <= right.length ? left : right;
    final longer = left.length <= right.length ? right : left;
    if (shorter.length < 4) return false;
    return longer.startsWith(shorter) && longer.length - shorter.length <= 3;
  }
}
