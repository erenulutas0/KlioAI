import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/word_sets.dart';
import '../models/neural_game_mode.dart';
import '../models/word_node.dart';
import '../models/word_set.dart';
import '../utils/node_position_calculator.dart';
import 'neural_game_event.dart';
import 'neural_game_state.dart';

class NeuralGameBloc extends Bloc<NeuralGameEvent, NeuralGameState> {
  static const int _gameDurationSeconds = 60;
  static const Set<String> _stopWords = <String>{
    'a',
    'an',
    'and',
    'or',
    'the',
    'to',
    'of',
    'for',
    'in',
    'on',
    'at',
    'by',
    'is',
    'are',
    'be',
    'am',
    'it',
    'this',
    'that',
    'with',
    'from',
    'as',
    'you',
    'your',
    'my',
    'our',
    'their',
    'his',
    'her',
  };

  static const Map<String, List<String>> _softAssociations =
      <String, List<String>>{
    'travel': <String>[
      'plane',
      'flight',
      'airport',
      'abroad',
      'holiday',
      'vacation',
      'tourist',
      'tour',
      'hotel',
      'ticket',
      'luggage',
      'visa',
      'map',
      'roadtrip',
      'trip',
      'beach',
      'city',
      'country',
      'culture',
      'adrenaline',
    ],
    'learn': <String>[
      'teacher',
      'student',
      'lesson',
      'course',
      'class',
      'book',
      'reading',
      'focus',
      'memory',
      'language',
      'training',
      'homework',
    ],
    'success': <String>[
      'goal',
      'result',
      'winner',
      'career',
      'money',
      'effort',
      'discipline',
      'focus',
      'mindset',
      'motivation',
    ],
    'innovation': <String>[
      'technology',
      'startup',
      'future',
      'idea',
      'prototype',
      'design',
      'creative',
      'research',
      'ai',
      'software',
      'product',
      'improvement',
      'progress',
      'upgrade',
      'development',
    ],
    'connect': <String>[
      'friend',
      'friendship',
      'community',
      'social',
      'team',
      'message',
      'call',
      'conversation',
      'chat',
      'relationship',
    ],
    'health': <String>[
      'sleep',
      'water',
      'doctor',
      'medicine',
      'diet',
      'mind',
      'body',
      'routine',
      'walking',
      'yoga',
    ],
    'career': <String>[
      'job',
      'office',
      'company',
      'salary',
      'manager',
      'project',
      'teamwork',
      'cv',
      'linkedin',
      'interview',
    ],
    'science': <String>[
      'lab',
      'scientist',
      'data',
      'physics',
      'biology',
      'chemistry',
      'math',
      'experimenting',
      'observation',
      'method',
    ],
  };

  final Random _random = Random();
  Timer? _gameTimer;

  NeuralGameBloc() : super(const NeuralGameInitial()) {
    on<StartGameEvent>(_onStartGame);
    on<SubmitWordEvent>(_onSubmitWord);
    on<TimerTickEvent>(_onTimerTick);
    on<DismissFeedbackEvent>(_onDismissFeedback);
    on<ResetGameEvent>(_onResetGame);
  }

  void _onStartGame(StartGameEvent event, Emitter<NeuralGameState> emit) {
    _cancelTimer();

    final selectedWordSet =
        WordSetsData.wordSets[_random.nextInt(WordSetsData.wordSets.length)];

    emit(NeuralGamePlaying(
      currentWordSet: selectedWordSet,
      discoveredNodes: const [],
      usedWords: const [],
      score: 0,
      combo: 0,
      maxCombo: 0,
      timeLeft: _gameDurationSeconds,
      mode: event.mode,
      feedbackMessage: null,
      isError: false,
    ));

    _gameTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      add(const TimerTickEvent());
    });
  }

  void _onSubmitWord(SubmitWordEvent event, Emitter<NeuralGameState> emit) {
    final currentState = state;
    if (currentState is! NeuralGamePlaying) {
      return;
    }

    final inputWord = _normalizeToken(event.word);
    if (inputWord.isEmpty) {
      return;
    }

    final match = _matchInput(
      wordSet: currentState.currentWordSet,
      mode: currentState.mode,
      normalizedInput: inputWord,
    );

    if (match == null) {
      final sampleHint = _buildAdaptiveHint(currentState);
      final decreasedCombo =
          currentState.combo > 0 ? currentState.combo - 1 : 0;
      _logDecision(
        type: 'REJECT',
        mode: currentState.mode,
        input: event.word,
      );
      emit(currentState.copyWith(
        combo: decreasedCombo,
        feedbackMessage: currentState.mode == NeuralGameMode.turkishTranslation
            ? 'Tam olmadi. Ipucu: $sampleHint'
            : 'Close one. Try one of these: $sampleHint',
        isError: true,
      ));
      _scheduleFeedbackClear();
      return;
    }

    if (currentState.usedWords.contains(match.canonicalWord)) {
      _logDecision(
        type: 'DUPLICATE',
        mode: currentState.mode,
        input: event.word,
        canonicalWord: match.canonicalWord,
      );
      emit(currentState.copyWith(
        feedbackMessage: 'Already used',
        isError: true,
      ));
      _scheduleFeedbackClear();
      return;
    }

    final newCombo = currentState.combo + 1;
    final nextMaxCombo = max(currentState.maxCombo, newCombo);
    final comboMultiplier = match.isLooseAssociation
        ? 1.0 + ((newCombo - 1) * 0.10)
        : 1.0 + ((newCombo - 1) * 0.20);
    final basePoints = match.isLooseAssociation ? 70 : 100;
    final points = (basePoints * comboMultiplier).round();

    final nodePosition = NodePositionCalculator.calculate(
      index: currentState.discoveredNodes.length,
      total: max(
        currentState.currentWordSet.relatedWords.length + 4,
        currentState.discoveredNodes.length + 1,
      ),
      screenSize: event.playAreaSize,
      center: event.centerPosition,
    );

    final newNode = NeuralWordNodeModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      word: match.displayWord,
      subtitle: currentState.mode == NeuralGameMode.turkishTranslation
          ? match.subtitle
          : null,
      position: nodePosition,
    );

    _logDecision(
      type: 'ACCEPT',
      mode: currentState.mode,
      input: event.word,
      canonicalWord: match.canonicalWord,
    );
    emit(currentState.copyWith(
      discoveredNodes: [...currentState.discoveredNodes, newNode],
      usedWords: [...currentState.usedWords, match.canonicalWord],
      score: currentState.score + points,
      combo: newCombo,
      maxCombo: nextMaxCombo,
      feedbackMessage: match.isLooseAssociation
          ? 'Nice association +$points  Combo x$newCombo'
          : '+$points points  Combo x$newCombo',
      isError: false,
    ));
    _scheduleFeedbackClear();
  }

  void _onTimerTick(TimerTickEvent event, Emitter<NeuralGameState> emit) {
    final currentState = state;
    if (currentState is! NeuralGamePlaying) {
      return;
    }

    final nextTime = currentState.timeLeft - 1;
    if (nextTime <= 0) {
      _cancelTimer();
      emit(NeuralGameFinished(
        centerWord: currentState.currentWordSet.centerWord,
        finalScore: currentState.score,
        totalWords: currentState.discoveredNodes.length,
        maxCombo: currentState.maxCombo,
        discoveredWords: currentState.usedWords,
        mode: currentState.mode,
      ));
      return;
    }

    emit(currentState.copyWith(timeLeft: nextTime));
  }

  void _onDismissFeedback(
      DismissFeedbackEvent event, Emitter<NeuralGameState> emit) {
    final currentState = state;
    if (currentState is! NeuralGamePlaying) {
      return;
    }
    if (currentState.feedbackMessage == null) {
      return;
    }

    emit(currentState.copyWith(
      feedbackMessage: null,
      isError: false,
    ));
  }

  void _onResetGame(ResetGameEvent event, Emitter<NeuralGameState> emit) {
    _cancelTimer();
    emit(const NeuralGameInitial());
  }

  void _scheduleFeedbackClear() {
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      add(const DismissFeedbackEvent());
    });
  }

  void _cancelTimer() {
    _gameTimer?.cancel();
    _gameTimer = null;
  }

  _WordMatch? _matchInput({
    required WordSet wordSet,
    required NeuralGameMode mode,
    required String normalizedInput,
  }) {
    final relatedWords = wordSet.relatedWords.cast<String>();
    final aliasesRaw = wordSet.relatedWordAliases;
    final trRaw = wordSet.turkishTranslations;

    for (final relatedWord in relatedWords) {
      final canonical = _normalizeToken(relatedWord);
      if (canonical.isEmpty) {
        continue;
      }

      final aliases = aliasesRaw[relatedWord.toLowerCase()] ?? const <String>[];
      final turkishList = trRaw[relatedWord.toLowerCase()] ?? const <String>[];

      if (mode == NeuralGameMode.relatedWords) {
        final accepted = <String>{canonical};
        accepted
            .addAll(aliases.map(_normalizeToken).where((e) => e.isNotEmpty));
        accepted.add(_stemToken(canonical));
        accepted.addAll(
          aliases
              .map(_normalizeToken)
              .map(_stemToken)
              .where((e) => e.isNotEmpty),
        );
        if (_containsToken(accepted, normalizedInput)) {
          return _WordMatch(
            canonicalWord: canonical,
            displayWord: relatedWord.toLowerCase(),
            subtitle: turkishList.isNotEmpty ? turkishList.first : null,
          );
        }
      } else {
        final acceptedTr =
            turkishList.map(_normalizeToken).where((e) => e.isNotEmpty).toSet();
        final acceptedTrStems =
            acceptedTr.map(_stemToken).where((e) => e.isNotEmpty).toList();
        acceptedTr.addAll(acceptedTrStems);
        if (_containsToken(acceptedTr, normalizedInput)) {
          return _WordMatch(
            canonicalWord: canonical,
            displayWord: relatedWord.toLowerCase(),
            subtitle: turkishList.isNotEmpty ? turkishList.first : null,
          );
        }
      }
    }

    if (mode == NeuralGameMode.relatedWords) {
      return _matchLooseAssociation(
        wordSet: wordSet,
        normalizedInput: normalizedInput,
      );
    }

    return null;
  }

  String _normalizeToken(String value) {
    final normalizedTr = value
        .trim()
        .toLowerCase()
        .replaceAll('ç', 'c')
        .replaceAll('ğ', 'g')
        .replaceAll('ı', 'i')
        .replaceAll('ö', 'o')
        .replaceAll('ş', 's')
        .replaceAll('ü', 'u');
    return normalizedTr
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _containsToken(Set<String> accepted, String input) {
    if (accepted.isEmpty || input.isEmpty) {
      return false;
    }

    if (accepted.contains(input)) {
      return true;
    }

    final inputTokens = _tokenizeInput(input);
    final stemmedInput = _stemToken(input);

    for (final token in inputTokens) {
      if (accepted.contains(token)) {
        return true;
      }
    }

    for (final candidate in accepted) {
      if (_isNearMatch(candidate, input)) {
        return true;
      }
      if (_isNearMatch(_stemToken(candidate), stemmedInput)) {
        return true;
      }
      for (final token in inputTokens) {
        if (_isNearMatch(candidate, token)) {
          return true;
        }
        if (_isNearMatch(_stemToken(candidate), _stemToken(token))) {
          return true;
        }
      }

      // Phrase tolerance: "very innovative idea" should still match "innovation".
      if ((candidate.length >= 5 || input.length >= 5) &&
          (candidate.contains(input) || input.contains(candidate))) {
        final delta = (candidate.length - input.length).abs();
        if (delta <= 3) {
          return true;
        }
      }
    }
    return false;
  }

  List<String> _tokenizeInput(String input) {
    return input
        .split(' ')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  _WordMatch? _matchLooseAssociation({
    required WordSet wordSet,
    required String normalizedInput,
  }) {
    final candidates = _extractCandidateTokens(normalizedInput);
    if (candidates.isEmpty) {
      return null;
    }

    final centerKey = _normalizeToken(wordSet.centerWord);
    final centerSoft = (_softAssociations[centerKey] ?? const <String>[])
        .map(_normalizeToken)
        .where((e) => e.isNotEmpty)
        .toSet();

    for (final candidate in candidates) {
      final stemCandidate = _stemToken(candidate);
      final isCenterSoftMatch = centerSoft.contains(candidate) ||
          centerSoft.contains(stemCandidate) ||
          centerSoft.any((w) => _isNearMatch(w, candidate));
      final isNatural = _looksLikeNaturalWord(candidate);
      if (!isCenterSoftMatch && !isNatural) {
        continue;
      }

      return _WordMatch(
        canonicalWord: 'soft:$candidate',
        displayWord: candidate,
        subtitle: isCenterSoftMatch ? 'strong link' : 'open link',
        isLooseAssociation: true,
      );
    }

    return null;
  }

  List<String> _extractCandidateTokens(String normalizedInput) {
    if (normalizedInput.trim().isEmpty) {
      return const <String>[];
    }

    final tokens = _tokenizeInput(normalizedInput);
    if (tokens.isEmpty) {
      return const <String>[];
    }

    final sorted = List<String>.from(tokens.toSet())
      ..sort(
          (a, b) => b.length.compareTo(a.length)); // Prefer meaningful words.

    final accepted = <String>[];
    for (final token in sorted) {
      if (_stopWords.contains(token)) {
        continue;
      }
      if (token.length < 3) {
        continue;
      }
      if (!RegExp(r'^[a-z]+$').hasMatch(token)) {
        continue;
      }
      accepted.add(token);
    }
    return accepted;
  }

  bool _looksLikeNaturalWord(String token) {
    if (token.length < 3) {
      return false;
    }
    if (_stopWords.contains(token)) {
      return false;
    }
    if (!RegExp(r'^[a-z]+$').hasMatch(token)) {
      return false;
    }
    if (!RegExp(r'[aeiou]').hasMatch(token)) {
      return false;
    }
    if (RegExp(r'(.)\1\1').hasMatch(token)) {
      return false;
    }
    return true;
  }

  String _stemToken(String value) {
    var token = value.trim();
    if (token.isEmpty) {
      return token;
    }

    const suffixes = <String>[
      'ments',
      'ment',
      'tions',
      'tion',
      'sions',
      'sion',
      'ities',
      'ity',
      'ness',
      'ings',
      'ing',
      'edly',
      'ed',
      'ers',
      'er',
      'ies',
      'es',
      's',
      'ly',
      'al',
    ];

    if (token.endsWith('ies') && token.length > 4) {
      return '${token.substring(0, token.length - 3)}y';
    }

    for (final suffix in suffixes) {
      if (token.endsWith(suffix) && token.length > suffix.length + 2) {
        token = token.substring(0, token.length - suffix.length);
        break;
      }
    }

    return token;
  }

  bool _isNearMatch(String a, String b) {
    if (a == b) {
      return true;
    }
    if (a.isEmpty || b.isEmpty) {
      return false;
    }

    // Plural / suffix tolerance (innovation -> innovations, connect -> connected)
    if (a.startsWith(b) || b.startsWith(a)) {
      final delta = (a.length - b.length).abs();
      if (delta <= 3) {
        return true;
      }
    }

    final distance = _levenshteinDistance(a, b);
    final maxLen = max(a.length, b.length);
    if (maxLen >= 10) {
      return distance <= 3;
    }
    if (maxLen >= 7) {
      return distance <= 2;
    }
    return distance <= 1;
  }

  String _buildAdaptiveHint(NeuralGamePlaying state) {
    final used = state.usedWords.toSet();
    final suggestions = <String>[];

    for (final word in state.currentWordSet.relatedWords) {
      final normalized = _normalizeToken(word);
      if (used.contains(normalized)) {
        continue;
      }
      if (state.mode == NeuralGameMode.turkishTranslation) {
        final tr = state.currentWordSet.turkishTranslations[word.toLowerCase()];
        if (tr != null && tr.isNotEmpty) {
          suggestions.add(tr.first.toLowerCase());
          continue;
        }
      }
      suggestions.add(word.toLowerCase());
    }

    if (state.mode == NeuralGameMode.relatedWords) {
      final centerKey = _normalizeToken(state.currentWordSet.centerWord);
      final soft = (_softAssociations[centerKey] ?? const <String>[])
          .map(_normalizeToken)
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      for (final candidate in soft) {
        final softKey = 'soft:$candidate';
        if (used.contains(softKey) || suggestions.contains(candidate)) {
          continue;
        }
        suggestions.add(candidate);
      }
    }

    if (suggestions.isEmpty) {
      return state.mode == NeuralGameMode.turkishTranslation
          ? 'Tum baglantilar bulundu.'
          : 'All links are already found.';
    }

    final preview = suggestions.take(3).join(', ');
    return '$preview (${state.usedWords.length} found)';
  }

  void _logDecision({
    required String type,
    required NeuralGameMode mode,
    required String input,
    String? canonicalWord,
  }) {
    if (!kDebugMode) {
      return;
    }

    final now = DateTime.now().toIso8601String();
    debugPrint(
      '[NeuralGame][$now][$type] mode=${mode.name} input="${input.trim()}" canonical=${canonicalWord ?? "-"}',
    );
  }

  int _levenshteinDistance(String s, String t) {
    if (s == t) {
      return 0;
    }
    if (s.isEmpty) {
      return t.length;
    }
    if (t.isEmpty) {
      return s.length;
    }

    final rows = s.length + 1;
    final cols = t.length + 1;
    final dp = List.generate(rows, (_) => List<int>.filled(cols, 0));

    for (var i = 0; i < rows; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j < cols; j++) {
      dp[0][j] = j;
    }

    for (var i = 1; i < rows; i++) {
      for (var j = 1; j < cols; j++) {
        final cost = s[i - 1] == t[j - 1] ? 0 : 1;
        dp[i][j] = [
          dp[i - 1][j] + 1,
          dp[i][j - 1] + 1,
          dp[i - 1][j - 1] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
    }
    return dp[s.length][t.length];
  }

  @override
  Future<void> close() {
    _cancelTimer();
    return super.close();
  }
}

class _WordMatch {
  const _WordMatch({
    required this.canonicalWord,
    required this.displayWord,
    required this.subtitle,
    this.isLooseAssociation = false,
  });

  final String canonicalWord;
  final String displayWord;
  final String? subtitle;
  final bool isLooseAssociation;
}
