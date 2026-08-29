/// Where a saved word came from.
///
/// Mirrors `WordOrigin` on the server, which is deliberately a plain string
/// column rather than an enum so a new source costs no migration. These are the
/// values this client sends or expects to read back.
///
/// The server has only ever *inferred* provenance: daily words if the meaning
/// text carries a star, everything else "manual". That was fine when there were
/// two ways to save a word. A word tapped out of a novel has been filed
/// identically to one typed into the dictionary box, which is the one thing a
/// learner would most want to tell apart — the book is why they saved it.
class WordOrigins {
  const WordOrigins._();

  /// Saved from the daily-words set.
  static const String dailyWords = 'daily_words';

  /// Typed in, or taken from the dictionary.
  static const String manual = 'manual';

  /// Tapped out of a book in the reader.
  static const String reader = 'reader';

  /// The label key for [origin], or null when there is nothing to say.
  ///
  /// Null for a word saved before provenance was recorded, which is every word
  /// on an upgrading install. Those group as unlabelled rather than being filed
  /// under whichever source happens to sort first — a guess presented as a
  /// fact is worse here than an honest gap.
  static String? labelKeyFor(String? origin) {
    switch (origin) {
      case dailyWords:
        return 'words.origin.dailyWords';
      case manual:
        return 'words.origin.manual';
      case reader:
        return 'words.origin.reader';
      default:
        return null;
    }
  }
}
