/// The word a learner saved, recognised in the form a book happens to use it.
///
/// Someone saves "flight" and then reads "The flights were delayed". Matching
/// the two strings says they are unrelated, so the reader would neither mark
/// the word nor know it was already saved — and the learner is offered a word
/// they already own, in the one place the app should be showing them that their
/// own vocabulary is paying off.
///
/// This is deliberately not a stemmer. A stemmer is built to collapse a corpus
/// and is happy to be wrong about any single word; here a wrong answer is a
/// wrong mark on the page, in front of someone learning the language. So it
/// only undoes the regular English endings, keeps the surface form as its own
/// first candidate, and refuses to work on words short enough for the ending to
/// be most of the word — which is what keeps "sing" from being a form of "s".
class WordFamily {
  const WordFamily._();

  /// Every base form [surface] could be an inflection of, plus [surface].
  ///
  /// Candidates, not a decision: the caller checks them against words the
  /// learner actually saved, so an extra candidate that is not a real word
  /// costs nothing, while a missing one costs a mark on the page.
  static Set<String> baseForms(String surface) {
    final String word = surface.trim().toLowerCase();
    if (word.isEmpty) return const <String>{};

    final Set<String> forms = <String>{word};

    void addStem(String stem) {
      if (stem.length < 3) return;
      forms.add(stem);
      // stopped -> stopp -> stop, running -> runn -> run. Only a doubled
      // consonant: "pass" and "miss" end in one too, so the undoubled form is
      // offered alongside rather than instead of.
      final int last = stem.length - 1;
      if (stem[last] == stem[last - 1] && !_vowels.contains(stem[last])) {
        if (last >= 3) forms.add(stem.substring(0, last));
      }
    }

    if (word.endsWith('ies') && word.length >= 5) {
      forms.add('${word.substring(0, word.length - 3)}y');
    }
    if (word.endsWith('es') && word.length >= 5) {
      addStem(word.substring(0, word.length - 2));
    }
    // Not after 'ss': "class" and "glass" are not plurals, and offering "clas"
    // is harmless but offering it instead of the word would not be.
    if (word.endsWith('s') && !word.endsWith('ss') && word.length >= 4) {
      addStem(word.substring(0, word.length - 1));
    }
    if (word.endsWith('ied') && word.length >= 5) {
      forms.add('${word.substring(0, word.length - 3)}y');
    }
    // Four, not five: "used" is a four-letter past tense of a real word, and
    // the length floor inside addStem already refuses the two-letter stem it
    // produces. "bed" stays out because it is three.
    if (word.endsWith('ed') && word.length >= 4) {
      addStem(word.substring(0, word.length - 2));
      // used -> use, liked -> like: the e belongs to the stem, not the ending.
      addStem(word.substring(0, word.length - 1));
    }
    if (word.endsWith('ing') && word.length >= 6) {
      final String stem = word.substring(0, word.length - 3);
      addStem(stem);
      // making -> make, writing -> write.
      addStem('${stem}e');
    }

    forms.removeWhere((String form) => form.length < 3);
    forms.add(word);
    return forms;
  }

  /// Whether [surface] is [saved], or a regular inflection of it.
  static bool matches(String surface, String saved) {
    final String target = saved.trim().toLowerCase();
    if (target.isEmpty) return false;
    return baseForms(surface).contains(target);
  }

  static const String _vowels = 'aeiouy';
}
