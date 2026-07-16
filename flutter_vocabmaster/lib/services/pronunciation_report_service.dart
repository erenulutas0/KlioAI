class PronunciationReport {
  final String targetText;
  final String transcript;
  final int durationMs;
  final int accuracyScore;
  final int paceScore;
  final int overallScore;
  final List<String> missingWords;
  final List<String> extraWords;
  final List<String> matchedWords;
  final List<PronunciationWordMark> targetWordMarks;
  final double wordsPerMinute;
  final String clarityLabel;
  final String summary;
  final String paceFeedback;
  final String nextStep;

  const PronunciationReport({
    required this.targetText,
    required this.transcript,
    required this.durationMs,
    required this.accuracyScore,
    required this.paceScore,
    required this.overallScore,
    required this.missingWords,
    required this.extraWords,
    required this.matchedWords,
    required this.targetWordMarks,
    required this.wordsPerMinute,
    required this.clarityLabel,
    required this.summary,
    required this.paceFeedback,
    required this.nextStep,
  });
}

enum PronunciationWordStatus { matched, missing, unclear }

class PronunciationWordMark {
  final String word;
  final PronunciationWordStatus status;

  /// Yalnızca [PronunciationWordStatus.unclear] için: Whisper'ın bu kelime
  /// yerine duyduğu kelime ("ship" beklenirken "sheep" gibi). Kanıt olmadan
  /// "net değil" demek kullanıcıya hiçbir şey öğretmiyordu - bu çift zaten
  /// hizalamada hesaplanıyordu ama rapora taşınmıyordu.
  final String? heardAs;

  const PronunciationWordMark({
    required this.word,
    required this.status,
    this.heardAs,
  });
}

class PronunciationReportService {
  PronunciationReport evaluate({
    required String targetText,
    required String transcript,
    required int durationMs,
  }) {
    final targetWords = _tokenize(targetText);
    final spokenWords = _tokenize(transcript);
    final alignment = _align(targetWords, spokenWords);

    final matchedWords = <String>[];
    final missingWords = <String>[];
    final extraWords = <String>[];
    final targetWordMarks = <PronunciationWordMark>[];
    var substitutions = 0;

    for (final step in alignment) {
      switch (step.type) {
        case _AlignmentType.match:
          matchedWords.add(step.target!);
          targetWordMarks.add(PronunciationWordMark(
            word: step.target!,
            status: PronunciationWordStatus.matched,
          ));
          break;
        case _AlignmentType.delete:
          missingWords.add(step.target!);
          targetWordMarks.add(PronunciationWordMark(
            word: step.target!,
            status: PronunciationWordStatus.missing,
          ));
          break;
        case _AlignmentType.insert:
          extraWords.add(step.spoken!);
          break;
        case _AlignmentType.substitute:
          missingWords.add(step.target!);
          extraWords.add(step.spoken!);
          targetWordMarks.add(PronunciationWordMark(
            word: step.target!,
            status: PronunciationWordStatus.unclear,
            heardAs: step.spoken,
          ));
          substitutions++;
          break;
      }
    }

    final total = targetWords.isEmpty ? 1 : targetWords.length;
    final editDistance =
        missingWords.length + extraWords.length - substitutions;
    final rawAccuracy = ((total - editDistance).clamp(0, total) / total) * 100;
    final accuracyScore = rawAccuracy.round().clamp(0, 100);
    final wordsPerMinute = _wordsPerMinute(spokenWords.length, durationMs);
    final paceScore = _paceScore(wordsPerMinute);
    final overallScore =
        ((accuracyScore * 0.75) + (paceScore * 0.25)).round().clamp(0, 100);

    return PronunciationReport(
      targetText: targetText,
      transcript: transcript,
      durationMs: durationMs,
      accuracyScore: accuracyScore,
      paceScore: paceScore,
      overallScore: overallScore,
      missingWords: _dedupePreserveOrder(missingWords),
      extraWords: _dedupePreserveOrder(extraWords),
      matchedWords: matchedWords,
      targetWordMarks: targetWordMarks,
      wordsPerMinute: wordsPerMinute,
      clarityLabel: _clarityLabel(overallScore),
      summary: _summary(overallScore, missingWords, extraWords, wordsPerMinute),
      paceFeedback: _paceFeedback(wordsPerMinute),
      nextStep: _nextStep(
        overallScore,
        missingWords,
        extraWords,
        wordsPerMinute,
        targetWordMarks,
      ),
    );
  }

  // Rakam yazımı farkları puanı düşürmesin: hedef "two" derken Whisper "2"
  // yazabilir (veya tersi). İki taraf da aynı normalize edildiği için tek
  // yönlü bir sözlük yakınsamaya yeter.
  static const Map<String, String> _digitWords = {
    '0': 'zero',
    '1': 'one',
    '2': 'two',
    '3': 'three',
    '4': 'four',
    '5': 'five',
    '6': 'six',
    '7': 'seven',
    '8': 'eight',
    '9': 'nine',
    '10': 'ten',
    '11': 'eleven',
    '12': 'twelve',
  };

  List<String> _tokenize(String text) {
    var working = text.toLowerCase().replaceAll(RegExp(r'[’`´]'), "'");
    // Guvenli kısaltma açılımları: "don't" vs "do not" farkı telaffuz hatası
    // değildir. Belirsiz olanlar ('s = is/possessive, 'd = would/had) bilinçli
    // olarak açılmıyor.
    working = working
        .replaceAll("won't", 'will not')
        .replaceAll("can't", 'cannot')
        .replaceAllMapped(RegExp(r"(\w+)n't\b"), (m) => '${m[1]} not')
        .replaceAllMapped(RegExp(r"(\w+)'re\b"), (m) => '${m[1]} are')
        .replaceAllMapped(RegExp(r"(\w+)'ve\b"), (m) => '${m[1]} have')
        .replaceAllMapped(RegExp(r"(\w+)'ll\b"), (m) => '${m[1]} will')
        .replaceAll("i'm", 'i am');
    final normalized = working
        .replaceAll(RegExp(r"[']"), '')
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) {
      return const [];
    }
    return normalized
        .split(' ')
        .map((token) => _digitWords[token] ?? token)
        .toList();
  }

  List<_AlignmentStep> _align(List<String> target, List<String> spoken) {
    final rows = target.length + 1;
    final cols = spoken.length + 1;
    final dp = List.generate(rows, (_) => List<int>.filled(cols, 0));

    for (var i = 0; i < rows; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j < cols; j++) {
      dp[0][j] = j;
    }

    for (var i = 1; i < rows; i++) {
      for (var j = 1; j < cols; j++) {
        final substitutionCost = target[i - 1] == spoken[j - 1] ? 0 : 1;
        final substitute = dp[i - 1][j - 1] + substitutionCost;
        final delete = dp[i - 1][j] + 1;
        final insert = dp[i][j - 1] + 1;
        dp[i][j] = [substitute, delete, insert].reduce(
          (a, b) => a < b ? a : b,
        );
      }
    }

    final steps = <_AlignmentStep>[];
    var i = target.length;
    var j = spoken.length;
    while (i > 0 || j > 0) {
      if (i > 0 && j > 0) {
        final isMatch = target[i - 1] == spoken[j - 1];
        final cost = isMatch ? 0 : 1;
        if (dp[i][j] == dp[i - 1][j - 1] + cost) {
          steps.add(_AlignmentStep(
            isMatch ? _AlignmentType.match : _AlignmentType.substitute,
            target: target[i - 1],
            spoken: spoken[j - 1],
          ));
          i--;
          j--;
          continue;
        }
      }
      if (i > 0 && dp[i][j] == dp[i - 1][j] + 1) {
        steps.add(_AlignmentStep(_AlignmentType.delete, target: target[i - 1]));
        i--;
        continue;
      }
      if (j > 0) {
        steps.add(_AlignmentStep(_AlignmentType.insert, spoken: spoken[j - 1]));
        j--;
      }
    }

    return steps.reversed.toList();
  }

  double _wordsPerMinute(int wordCount, int durationMs) {
    if (wordCount <= 0 || durationMs <= 0) {
      return 0;
    }
    return wordCount / (durationMs / 60000.0);
  }

  int _paceScore(double wpm) {
    if (wpm <= 0) return 0;
    if (wpm >= 95 && wpm <= 155) return 100;
    if (wpm < 95) {
      return (100 - ((95 - wpm) * 1.2)).round().clamp(45, 100);
    }
    return (100 - ((wpm - 155) * 0.9)).round().clamp(45, 100);
  }

  List<String> _dedupePreserveOrder(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      if (seen.add(value)) {
        result.add(value);
      }
    }
    return result;
  }

  String _clarityLabel(int score) {
    if (score >= 90) return 'Excellent';
    if (score >= 75) return 'Clear';
    if (score >= 60) return 'Needs polish';
    return 'Try again';
  }

  String _summary(
    int score,
    List<String> missingWords,
    List<String> extraWords,
    double wordsPerMinute,
  ) {
    final buffer = StringBuffer();
    if (score >= 85) {
      buffer.write('Strong reading. Most words were captured clearly.');
    } else if (score >= 65) {
      buffer.write('Good attempt. Focus on the highlighted missing words.');
    } else {
      buffer.write('Try one slower repetition and separate each word clearly.');
    }

    if (wordsPerMinute > 0 && wordsPerMinute < 85) {
      buffer.write(' Your pace was a little slow.');
    } else if (wordsPerMinute > 165) {
      buffer.write(' Your pace was a little fast.');
    }

    if (missingWords.isEmpty && extraWords.isEmpty) {
      buffer.write(' The transcript matched the target closely.');
    }

    return buffer.toString();
  }

  String _paceFeedback(double wordsPerMinute) {
    if (wordsPerMinute <= 0) {
      return 'No pace detected yet.';
    }
    if (wordsPerMinute < 85) {
      return 'Aim for a slightly smoother pace. A natural reading pace is usually around 95-155 WPM.';
    }
    if (wordsPerMinute > 165) {
      return 'Slow down a little and give each word more space.';
    }
    return 'Your pace is inside the natural reading range.';
  }

  String _nextStep(
    int score,
    List<String> missingWords,
    List<String> extraWords,
    double wordsPerMinute,
    List<PronunciationWordMark> targetWordMarks,
  ) {
    // Somut kanıt en öğreticisi: "ship yerine sheep duyuldu" belirli bir sesi
    // işaret eder; genel "daha net söyle" tavsiyesinden önce gelir.
    for (final mark in targetWordMarks) {
      if (mark.status == PronunciationWordStatus.unclear &&
          mark.heardAs != null &&
          mark.heardAs != mark.word) {
        return "Expected '${mark.word}' but heard '${mark.heardAs}'. "
            'Repeat that word slowly, exaggerating each sound once.';
      }
    }
    if (missingWords.isNotEmpty) {
      final focus = _dedupePreserveOrder(missingWords).take(3).join(', ');
      return 'Repeat once and make these words clearer: $focus.';
    }
    if (extraWords.isNotEmpty) {
      final focus = _dedupePreserveOrder(extraWords).take(3).join(', ');
      return 'Repeat once while avoiding extra filler words like: $focus.';
    }
    if (wordsPerMinute > 0 && wordsPerMinute < 85) {
      return 'Try the same text again with a smoother, less hesitant rhythm.';
    }
    if (wordsPerMinute > 165) {
      return 'Try the same text again a little slower, especially around commas.';
    }
    if (score >= 90) {
      return 'Good result. Change the text or move to a harder level.';
    }
    return 'Repeat once and focus on steady rhythm plus clear word endings.';
  }
}

enum _AlignmentType { match, delete, insert, substitute }

class _AlignmentStep {
  final _AlignmentType type;
  final String? target;
  final String? spoken;

  const _AlignmentStep(this.type, {this.target, this.spoken});
}
