import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/word.dart';
import '../models/word_galaxy_background_preset.dart';
import '../providers/app_state_provider.dart';
import '../services/ai_error_message_formatter.dart';
import '../services/ai_paywall_handler.dart';
import '../services/api_service.dart';
import '../services/chatbot_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';
import '../widgets/word_sentences_modal.dart';

class WordGalaxyPage extends StatefulWidget {
  const WordGalaxyPage({super.key, this.initialWordId});

  final int? initialWordId;

  @override
  State<WordGalaxyPage> createState() => _WordGalaxyPageState();
}

DateTime _startOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

int? _daysUntilReview(Word word, {DateTime? referenceDate}) {
  if (word.nextReviewDate == null) {
    return null;
  }
  final today = _startOfDay(referenceDate ?? DateTime.now());
  final nextReview = _startOfDay(word.nextReviewDate!);
  return nextReview.difference(today).inDays;
}

bool _isDueWord(Word word, {DateTime? referenceDate}) {
  final days = _daysUntilReview(word, referenceDate: referenceDate);
  return days != null && days <= 0;
}

bool _isOverdueWord(Word word, {DateTime? referenceDate}) {
  final days = _daysUntilReview(word, referenceDate: referenceDate);
  return days != null && days < 0;
}

double _dueUrgencyScore(Word word, {DateTime? referenceDate}) {
  final days = _daysUntilReview(word, referenceDate: referenceDate);
  if (days == null) {
    return word.reviewCount > 0 ? 0.18 : 0.0;
  }
  if (days <= 0) {
    return (0.82 + (math.min(days.abs(), 7) / 7 * 0.18)).clamp(0.0, 1.0);
  }
  return ((1 - (days.clamp(0, 14) / 14)) * 0.72).clamp(0.0, 0.72);
}

double _reviewHistoryScore(Word word, {DateTime? referenceDate}) {
  final reviewCountScore = (word.reviewCount.clamp(0, 10) / 10).toDouble();
  final lastReviewScore = word.lastReviewDate == null
      ? 0.0
      : (1 -
              ((_startOfDay(referenceDate ?? DateTime.now())
                          .difference(_startOfDay(word.lastReviewDate!))
                          .inDays)
                      .clamp(0, 30) /
                  30))
          .clamp(0.0, 1.0);
  return ((reviewCountScore * 0.7) + (lastReviewScore * 0.3)).clamp(0.0, 1.0);
}

String? _reviewStatusBadgeLabel(Word word, bool isTurkish) {
  final days = _daysUntilReview(word);
  if (days == null) {
    return null;
  }
  if (days < 0) {
    return isTurkish ? '${days.abs()}g gecikmis' : '${days.abs()}d overdue';
  }
  if (days == 0) {
    return isTurkish ? 'Bugun' : 'Due today';
  }
  if (days <= 3) {
    return isTurkish ? '$days g sonra' : 'In $days d';
  }
  return null;
}

String _reviewCountBadgeLabel(Word word, bool isTurkish) {
  return isTurkish
      ? '${word.reviewCount} tekrar'
      : '${word.reviewCount} reviews';
}

String? _nextReviewDetailLabel(Word word, bool isTurkish) {
  final days = _daysUntilReview(word);
  if (days == null) {
    return null;
  }
  if (days < 0) {
    return isTurkish
        ? 'Tekrar ${days.abs()} gun gecikti'
        : 'Review overdue by ${days.abs()} days';
  }
  if (days == 0) {
    return isTurkish ? 'Bugun tekrar zamani' : 'Review is due today';
  }
  return isTurkish ? '$days gun sonra tekrar' : 'Review in $days days';
}

class _WordGalaxyPageState extends State<WordGalaxyPage> {
  static const String _presetStorageKey = 'word_galaxy_background_preset';
  static const Size _canvasSize = Size(1080, 820);

  final TransformationController _transformationController =
      TransformationController();
  WordGalaxyBackgroundPreset _preset = WordGalaxyBackgroundPreset.galaxy;
  bool _isFullscreen = false;
  int? _focusedWordId;
  Size? _canvasViewportSize;
  bool _hasInitializedCanvasView = false;
  int? _lastAutoCenteredFocusId;

  bool get _isTurkish => Localizations.localeOf(context).languageCode == 'tr';

  AppThemeConfig _currentTheme({bool listen = true}) {
    try {
      final provider = Provider.of<ThemeProvider?>(context, listen: listen);
      return provider?.currentTheme ?? VocabThemes.defaultTheme;
    } catch (_) {
      return VocabThemes.defaultTheme;
    }
  }

  String _text(String tr, String en) => _isTurkish ? tr : en;

  @override
  void initState() {
    super.initState();
    _focusedWordId = widget.initialWordId;
    _loadPreset();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _loadPreset() async {
    final prefs = await SharedPreferences.getInstance();
    final preset = WordGalaxyBackgroundPresetX.fromStorageValue(
      prefs.getString(_presetStorageKey),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _preset = preset;
    });
  }

  Future<void> _setPreset(WordGalaxyBackgroundPreset preset) async {
    if (_preset == preset) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_presetStorageKey, preset.storageValue);
    if (!mounted) {
      return;
    }
    setState(() {
      _preset = preset;
    });
  }

  _WordGalaxySurfacePalette get _surfacePalette =>
      _WordGalaxySurfacePalette.forPreset(_preset);

  void _syncCanvasViewport(Size viewportSize, {required int? focusWordId}) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) {
      return;
    }
    final shouldCenter = !_hasInitializedCanvasView ||
        _canvasViewportSize != viewportSize ||
        _lastAutoCenteredFocusId != focusWordId;
    _canvasViewportSize = viewportSize;
    if (!shouldCenter) {
      return;
    }
    _hasInitializedCanvasView = true;
    _lastAutoCenteredFocusId = focusWordId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _centerCanvasInViewport(viewportSize);
    });
  }

  void _centerCanvasInViewport(Size viewportSize) {
    final dx = (viewportSize.width - _canvasSize.width) / 2;
    final dy = (viewportSize.height - _canvasSize.height) / 2;
    _transformationController.value = Matrix4.identity()..translate(dx, dy);
  }

  void _recenterCanvas() {
    final viewportSize = _canvasViewportSize;
    if (viewportSize == null) {
      _transformationController.value = Matrix4.identity();
      return;
    }
    _lastAutoCenteredFocusId = _focusedWordId;
    _centerCanvasInViewport(viewportSize);
  }

  List<Word> _filteredWords(List<Word> words) {
    final sorted = List<Word>.from(words)
      ..sort((a, b) {
        final dueCompare = _dueUrgencyScore(b).compareTo(_dueUrgencyScore(a));
        if (dueCompare != 0) {
          return dueCompare;
        }
        final reviewCompare = b.reviewCount.compareTo(a.reviewCount);
        if (reviewCompare != 0) {
          return reviewCompare;
        }
        final sentenceCompare =
            b.sentences.length.compareTo(a.sentences.length);
        if (sentenceCompare != 0) {
          return sentenceCompare;
        }
        return b.learnedDate.compareTo(a.learnedDate);
      });

    return sorted;
  }

  Word _resolvedFocus(List<Word> words) {
    final focused = words.cast<Word?>().firstWhere(
          (word) => word?.id == _focusedWordId,
          orElse: () => null,
        );
    return focused ?? words.first;
  }

  Set<String> _tokensFor(String value) {
    return value
        .toLowerCase()
        .split(RegExp(r'[^a-zA-ZçğıöşüÇĞİÖŞÜ]+'))
        .where((token) => token.trim().length > 1)
        .map((token) => token.trim())
        .toSet();
  }

  int _difficultyRank(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'hard':
        return 3;
      case 'medium':
        return 2;
      default:
        return 1;
    }
  }

  double _tokenSimilarity(Word focusWord, Word candidate) {
    final focusTokens = <String>{
      ..._tokensFor(focusWord.englishWord),
      ..._tokensFor(focusWord.turkishMeaning),
    };
    final candidateTokens = <String>{
      ..._tokensFor(candidate.englishWord),
      ..._tokensFor(candidate.turkishMeaning),
    };
    if (focusTokens.isEmpty || candidateTokens.isEmpty) {
      return 0;
    }
    final overlap = focusTokens.intersection(candidateTokens).length;
    final union = focusTokens.union(candidateTokens).length;
    if (union == 0) {
      return 0;
    }
    return overlap / union;
  }

  double _relatednessScore(Word focusWord, Word candidate) {
    final dayDiff =
        (focusWord.learnedDate.difference(candidate.learnedDate).inHours.abs() /
            24.0);
    final recencyScore = (1 - (dayDiff.clamp(0, 30) / 30)).clamp(0.0, 1.0);

    final difficultyGap = (_difficultyRank(focusWord.difficulty) -
            _difficultyRank(candidate.difficulty))
        .abs();
    final difficultyScore = switch (difficultyGap) {
      0 => 1.0,
      1 => 0.55,
      _ => 0.18,
    };

    final maxSentenceCount = math.max(
      1,
      math.max(focusWord.sentences.length, candidate.sentences.length),
    );
    final sentenceBalance = 1 -
        ((focusWord.sentences.length - candidate.sentences.length).abs() /
            maxSentenceCount);
    final sameLearnDay =
        focusWord.learnedDate.toIso8601String().split('T')[0] ==
                candidate.learnedDate.toIso8601String().split('T')[0]
            ? 1.0
            : 0.0;
    final sentencePresence = candidate.sentences.isNotEmpty ? 1.0 : 0.0;
    final dueScore = _dueUrgencyScore(candidate);
    final reviewScore = _reviewHistoryScore(candidate);

    double difficultyWeight;
    double recencyWeight;
    double sentenceBalanceWeight;
    double tokenWeight;
    double sameLearnDayWeight;
    double sentencePresenceWeight;
    double dueWeight;
    double reviewWeight;

    difficultyWeight = 0.18;
    recencyWeight = 0.16;
    sentenceBalanceWeight = 0.14;
    tokenWeight = 0.12;
    sameLearnDayWeight = 0.04;
    sentencePresenceWeight = 0.04;
    dueWeight = 0.22;
    reviewWeight = 0.10;

    final score = (difficultyScore * difficultyWeight) +
        (recencyScore * recencyWeight) +
        (sentenceBalance.clamp(0.0, 1.0) * sentenceBalanceWeight) +
        (_tokenSimilarity(focusWord, candidate) * tokenWeight) +
        (sameLearnDay * sameLearnDayWeight) +
        (sentencePresence * sentencePresenceWeight) +
        (dueScore * dueWeight) +
        (reviewScore * reviewWeight);
    return score.clamp(0.0, 1.0);
  }

  List<_GalaxyNode> _buildNodes(List<Word> words, Word focusWord) {
    final rankedWords = words
        .where((word) => word.id != focusWord.id)
        .map((word) => (
              word: word,
              score: _relatednessScore(focusWord, word),
              urgency: _dueUrgencyScore(word),
            ))
        .toList()
      ..sort((a, b) {
        final dueCompare = b.urgency.compareTo(a.urgency);
        if (dueCompare != 0) {
          return dueCompare;
        }
        return b.score.compareTo(a.score);
      });

    final visibleWords = rankedWords.take(18).toList();

    final nodes = <_GalaxyNode>[
      _GalaxyNode(
        word: focusWord,
        center: Offset(_canvasSize.width / 2, _canvasSize.height / 2),
        size: 180,
        isFocus: true,
        relatedness: 1,
        ringIndex: 0,
      ),
    ];

    final ringCounts = <int>[6, 8, 10];
    var index = 0;
    for (var ring = 0;
        ring < ringCounts.length && index < visibleWords.length;
        ring++) {
      final baseRadius = 180.0 + (ring * 140);
      final count = ringCounts[ring];
      final itemsInRing = math.min(count, visibleWords.length - index);
      for (var slot = 0; slot < itemsInRing; slot++) {
        final entry = visibleWords[index];
        final word = entry.word;
        final angle = (-math.pi / 2) + ((2 * math.pi * slot) / itemsInRing);
        final radiusPull = entry.urgency * 48;
        final radius = math.max(140.0, baseRadius - radiusPull);
        final center = Offset(
          (_canvasSize.width / 2) + (math.cos(angle) * radius),
          (_canvasSize.height / 2) + (math.sin(angle) * radius * 0.72),
        );
        final emphasis = 18 * entry.score;
        final reviewBoost =
            (entry.urgency * 14) + (math.min(word.reviewCount, 6) * 1.5);
        final size = (104 +
                math.min(word.sentences.length, 4) * 6 +
                emphasis +
                reviewBoost)
            .toDouble();
        nodes.add(_GalaxyNode(
          word: word,
          center: center,
          size: size,
          isFocus: false,
          relatedness: entry.score,
          ringIndex: ring + 1,
        ));
        index++;
      }
    }

    return nodes;
  }

  List<_GalaxyLink> _buildLinks(List<_GalaxyNode> nodes) {
    if (nodes.length < 2) {
      return const [];
    }

    final links = <_GalaxyLink>[];
    for (var i = 1; i < nodes.length; i++) {
      links.add(_GalaxyLink(
        fromIndex: 0,
        toIndex: i,
        strength: nodes[i].relatedness,
        isHighlight: nodes[i].relatedness >= 0.62,
      ));
    }

    final nodesByRing = <int, List<int>>{};
    for (var i = 1; i < nodes.length; i++) {
      nodesByRing.putIfAbsent(nodes[i].ringIndex, () => <int>[]).add(i);
    }

    for (final ringEntry in nodesByRing.entries) {
      final indexes = ringEntry.value;
      for (var i = 0; i < indexes.length - 1; i++) {
        final currentIndex = indexes[i];
        final nextIndex = indexes[i + 1];
        final strength =
            ((nodes[currentIndex].relatedness + nodes[nextIndex].relatedness) /
                    2)
                .clamp(0.0, 1.0);
        if (strength < 0.48) {
          continue;
        }
        links.add(_GalaxyLink(
          fromIndex: currentIndex,
          toIndex: nextIndex,
          strength: strength * 0.72,
          isHighlight: false,
        ));
      }
    }

    return links;
  }

  Word _latestWordFor(int wordId, Word fallback) {
    final latestWord = context
        .read<AppStateProvider>()
        .allWords
        .cast<Word?>()
        .firstWhere((item) => item?.id == wordId, orElse: () => null);
    return latestWord ?? fallback;
  }

  Future<void> _openWordPreview(
    Word word, {
    bool autoGenerateAi = false,
  }) async {
    setState(() {
      _focusedWordId = word.id;
    });

    final action = await showModalBottomSheet<_WordSheetAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _WordPreviewSheet(
        word: _latestWordFor(word.id, word),
        isTurkish: _isTurkish,
        accentColor: _preset.accentColor,
        autoGenerateAi: autoGenerateAi,
      ),
    );

    if (!mounted || action == null) {
      return;
    }

    if (action == _WordSheetAction.viewAll) {
      _showSentencesDialog(_latestWordFor(word.id, word));
    }
  }

  Future<void> _handleWordTap(Word word) async {
    await _openWordPreview(word);
  }

  Future<void> _handleWordLongPress(Word word) async {
    setState(() {
      _focusedWordId = word.id;
    });

    final action = await showModalBottomSheet<_WordNodeQuickAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _WordQuickActionSheet(
        word: word,
        isTurkish: _isTurkish,
      ),
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _WordNodeQuickAction.focus:
        setState(() {
          _focusedWordId = word.id;
        });
        break;
      case _WordNodeQuickAction.preview:
        await _openWordPreview(word);
        break;
      case _WordNodeQuickAction.viewAllSentences:
        _showSentencesDialog(_latestWordFor(word.id, word));
        break;
      case _WordNodeQuickAction.aiPreview:
        await _openWordPreview(word, autoGenerateAi: true);
        break;
    }
  }

  void _showSentencesDialog(Word word) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => WordSentencesModal(word: word),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedTheme = _currentTheme(listen: true);
    final surfacePalette = _surfacePalette;
    final allWords = context.watch<AppStateProvider>().allWords;
    final filteredWords = _filteredWords(allWords);
    final focusWord =
        filteredWords.isEmpty ? null : _resolvedFocus(filteredWords);
    final nodes = focusWord == null
        ? const <_GalaxyNode>[]
        : _buildNodes(filteredWords, focusWord);
    final links = nodes.isEmpty ? const <_GalaxyLink>[] : _buildLinks(nodes);

    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isFullscreen) {
          setState(() => _isFullscreen = false);
        }
      },
      child: Scaffold(
        backgroundColor: selectedTheme.colors.background,
        body: Stack(
          children: [
            _WordGalaxyBackdrop(preset: _preset),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.08),
                          ),
                          icon: const Icon(Icons.arrow_back_rounded,
                              color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _text('Kelime Evreni', 'Word Galaxy'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _text(
                                  'Kartlara dokun, cumlelerini ac ve yeni cumle ekle.',
                                  'Tap a card to open its sentences and add new ones.',
                                ),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_isFullscreen)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: surfacePalette.panelColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: surfacePalette.borderColor),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  surfacePalette.panelColor.withOpacity(0.28),
                              blurRadius: 20,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children:
                                WordGalaxyBackgroundPreset.values.map((preset) {
                              final isSelected = preset == _preset;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label:
                                      Text(preset.label(isTurkish: _isTurkish)),
                                  selected: isSelected,
                                  onSelected: (_) => _setPreset(preset),
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? Colors.black
                                        : Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  backgroundColor:
                                      surfacePalette.chipBackgroundColor,
                                  selectedColor: preset.accentColor,
                                  side: BorderSide(
                                    color: isSelected
                                        ? preset.accentColor
                                        : surfacePalette.borderColor,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  if (!_isFullscreen) const SizedBox(height: 10),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final viewportSize =
                            Size(constraints.maxWidth, constraints.maxHeight);
                        if (focusWord != null) {
                          _syncCanvasViewport(viewportSize,
                              focusWordId: focusWord.id);
                        }
                        return Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: _isFullscreen ? 0 : 16),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: surfacePalette.borderColor,
                                      ),
                                      color: surfacePalette.canvasFillColor,
                                    ),
                                  ),
                                ),
                                if (focusWord == null)
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Text(
                                        _text(
                                          'Bu alan icin henuz kelime yok.',
                                          'There are no words here yet.',
                                        ),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  Positioned.fill(
                                    child: InteractiveViewer(
                                      transformationController:
                                          _transformationController,
                                      constrained: false,
                                      panEnabled: true,
                                      scaleEnabled: true,
                                      clipBehavior: Clip.none,
                                      minScale: 0.55,
                                      maxScale: 1.8,
                                      boundaryMargin: const EdgeInsets.all(280),
                                      child: SizedBox(
                                        width: _canvasSize.width,
                                        height: _canvasSize.height,
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            CustomPaint(
                                              size: _canvasSize,
                                              painter: _GalaxyLinkPainter(
                                                nodes: nodes,
                                                links: links,
                                                linkColor: _preset.accentColor
                                                    .withOpacity(0.32),
                                                highlightColor: _preset
                                                    .highlightColor
                                                    .withOpacity(0.28),
                                              ),
                                            ),
                                            ...nodes.map(
                                              (node) => AnimatedPositioned(
                                                duration: const Duration(
                                                    milliseconds: 260),
                                                curve: Curves.easeOutCubic,
                                                left: node.center.dx -
                                                    (node.size / 2),
                                                top: node.center.dy -
                                                    (node.size / 2),
                                                width: node.size,
                                                height: node.size,
                                                child: AnimatedScale(
                                                  duration: const Duration(
                                                      milliseconds: 220),
                                                  scale:
                                                      node.isFocus ? 1.0 : 0.97,
                                                  child: AnimatedOpacity(
                                                    duration: const Duration(
                                                        milliseconds: 220),
                                                    opacity: node.isFocus
                                                        ? 1.0
                                                        : 0.96,
                                                    child: _WordGalaxyNodeCard(
                                                      word: node.word,
                                                      isFocus: node.isFocus,
                                                      accentColor:
                                                          _preset.accentColor,
                                                      highlightColor: _preset
                                                          .highlightColor,
                                                      isTurkish: _isTurkish,
                                                      onTap: () =>
                                                          _handleWordTap(
                                                              node.word),
                                                      onLongPress: () =>
                                                          _handleWordLongPress(
                                                              node.word),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                if (focusWord != null)
                                  Positioned(
                                    left: 12,
                                    top: 12,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: surfacePalette.overlayColor,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.12),
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        child: Text(
                                          _text('Surukle ve yakinlastir',
                                              'Drag and zoom'),
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (focusWord != null)
                                  Positioned(
                                    right: 12,
                                    top: 12,
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          _isFullscreen = !_isFullscreen;
                                        });
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            surfacePalette.overlayColor,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        side: BorderSide(
                                          color: surfacePalette.borderColor,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      icon: Icon(
                                        _isFullscreen
                                            ? Icons.fullscreen_exit_rounded
                                            : Icons.fullscreen_rounded,
                                        size: 18,
                                      ),
                                      label: Text(
                                        _isFullscreen
                                            ? _text('Küçült', 'Shrink')
                                            : _text('Genişlet', 'Expand'),
                                      ),
                                    ),
                                  ),
                                if (focusWord != null)
                                  Positioned(
                                    right: 12,
                                    bottom: 12,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        _WordGalaxyMinimap(
                                          controller: _transformationController,
                                          canvasSize: _canvasSize,
                                          viewportSize: viewportSize,
                                          nodes: nodes,
                                          accentColor: _preset.accentColor,
                                          highlightColor:
                                              _preset.highlightColor,
                                        ),
                                        const SizedBox(height: 8),
                                        ElevatedButton.icon(
                                          onPressed: _recenterCanvas,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                surfacePalette.overlayColor,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            side: BorderSide(
                                              color: surfacePalette.borderColor,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.center_focus_strong,
                                            size: 18,
                                          ),
                                          label: Text(
                                            _text('Merkeze Don', 'Recenter'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (!_isFullscreen) const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _WordSheetAction { viewAll }

enum _WordNodeQuickAction {
  focus,
  preview,
  viewAllSentences,
  aiPreview,
}

class _GalaxyNode {
  const _GalaxyNode({
    required this.word,
    required this.center,
    required this.size,
    required this.isFocus,
    required this.relatedness,
    required this.ringIndex,
  });

  final Word word;
  final Offset center;
  final double size;
  final bool isFocus;
  final double relatedness;
  final int ringIndex;
}

class _GalaxyLink {
  const _GalaxyLink({
    required this.fromIndex,
    required this.toIndex,
    required this.strength,
    required this.isHighlight,
  });

  final int fromIndex;
  final int toIndex;
  final double strength;
  final bool isHighlight;
}

class _GalaxyLinkPainter extends CustomPainter {
  const _GalaxyLinkPainter({
    required this.nodes,
    required this.links,
    required this.linkColor,
    required this.highlightColor,
  });

  final List<_GalaxyNode> nodes;
  final List<_GalaxyLink> links;
  final Color linkColor;
  final Color highlightColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.length < 2 || links.isEmpty) {
      return;
    }

    final paint = Paint()..style = PaintingStyle.stroke;

    for (final link in links) {
      final from = nodes[link.fromIndex].center;
      final to = nodes[link.toIndex].center;
      final opacity = (0.14 + (link.strength * 0.38)).clamp(0.0, 1.0);
      paint
        ..color =
            (link.isHighlight ? highlightColor : linkColor).withOpacity(opacity)
        ..strokeWidth = 0.8 + (link.strength * 2.2)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          2 + (link.strength * 5),
        );
      canvas.drawLine(from, to, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GalaxyLinkPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.links != links ||
        oldDelegate.linkColor != linkColor ||
        oldDelegate.highlightColor != highlightColor;
  }
}

class _WordGalaxyNodeCard extends StatelessWidget {
  const _WordGalaxyNodeCard({
    required this.word,
    required this.isFocus,
    required this.accentColor,
    required this.highlightColor,
    required this.isTurkish,
    required this.onTap,
    required this.onLongPress,
  });

  final Word word;
  final bool isFocus;
  final Color accentColor;
  final Color highlightColor;
  final bool isTurkish;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final dueLabel = _reviewStatusBadgeLabel(word, isTurkish);
    final isDue = _isDueWord(word);
    final isOverdue = _isOverdueWord(word);
    final glowStrength = isFocus
        ? 1.0
        : isDue
            ? 0.82
            : word.sentences.isEmpty
                ? 0.42
                : 0.68;
    final background = isFocus
        ? accentColor.withOpacity(0.34)
        : isDue
            ? accentColor.withOpacity(0.16)
            : Colors.white.withOpacity(0.08);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                background,
                Colors.black.withOpacity(isFocus ? 0.18 : 0.28),
              ],
            ),
            border: Border.all(
              color: isFocus
                  ? highlightColor.withOpacity(0.9)
                  : isOverdue
                      ? highlightColor.withOpacity(0.72)
                      : isDue
                          ? accentColor.withOpacity(0.72)
                          : Colors.white.withOpacity(0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: (isFocus ? highlightColor : accentColor)
                    .withOpacity(0.18 + (glowStrength * 0.18)),
                blurRadius: isFocus ? 22 : 10 + (glowStrength * 8),
                spreadRadius: 1,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  word.englishWord,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isFocus ? 18 : 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  word.turkishMeaning.replaceAll('⭐', '').trim(),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _TinyBadge(label: word.difficulty.toUpperCase()),
                    _TinyBadge(
                      label: isTurkish
                          ? '${word.sentences.length} cumle'
                          : '${word.sentences.length} sentences',
                    ),
                    if (dueLabel != null)
                      _TinyBadge(label: dueLabel)
                    else if (word.reviewCount > 0)
                      _TinyBadge(
                        label: _reviewCountBadgeLabel(word, isTurkish),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WordGalaxyMinimap extends StatelessWidget {
  const _WordGalaxyMinimap({
    required this.controller,
    required this.canvasSize,
    required this.viewportSize,
    required this.nodes,
    required this.accentColor,
    required this.highlightColor,
  });

  final TransformationController controller;
  final Size canvasSize;
  final Size viewportSize;
  final List<_GalaxyNode> nodes;
  final Color accentColor;
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    const minimapWidth = 132.0;
    final minimapHeight = minimapWidth * (canvasSize.height / canvasSize.width);

    return ValueListenableBuilder<Matrix4>(
      valueListenable: controller,
      builder: (context, matrix, _) {
        final scale = matrix.getMaxScaleOnAxis().clamp(0.0001, 10.0);
        final tx = matrix.storage[12];
        final ty = matrix.storage[13];
        final visibleWidth =
            math.min(canvasSize.width, viewportSize.width / scale);
        final visibleHeight =
            math.min(canvasSize.height, viewportSize.height / scale);
        final sceneLeft = (-tx / scale)
            .clamp(0.0, math.max(0.0, canvasSize.width - visibleWidth));
        final sceneTop = (-ty / scale)
            .clamp(0.0, math.max(0.0, canvasSize.height - visibleHeight));

        final ratioX = minimapWidth / canvasSize.width;
        final ratioY = minimapHeight / canvasSize.height;

        return Container(
          width: minimapWidth,
          height: minimapHeight,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.34),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Stack(
            children: [
              ...nodes.map(
                (node) => Positioned(
                  left: (node.center.dx * ratioX) - (node.isFocus ? 3 : 2),
                  top: (node.center.dy * ratioY) - (node.isFocus ? 3 : 2),
                  child: Container(
                    width: node.isFocus ? 6 : 4,
                    height: node.isFocus ? 6 : 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: node.isFocus
                          ? highlightColor.withOpacity(0.95)
                          : accentColor.withOpacity(0.68),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: sceneLeft * ratioX,
                top: sceneTop * ratioY,
                child: Container(
                  width: math.max(18, visibleWidth * ratioX),
                  height: math.max(14, visibleHeight * ratioY),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.92),
                      width: 1.2,
                    ),
                    color: Colors.white.withOpacity(0.05),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WordQuickActionSheet extends StatelessWidget {
  const _WordQuickActionSheet({
    required this.word,
    required this.isTurkish,
  });

  final Word word;
  final bool isTurkish;

  String _text(String tr, String en) => isTurkish ? tr : en;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF091019),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                word.englishWord,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                word.turkishMeaning.replaceAll('⭐', '').trim(),
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              _QuickActionTile(
                icon: Icons.adjust_rounded,
                title: _text('Odak Yap', 'Focus Node'),
                subtitle: _text(
                    'Bu kelimeyi merkeze al', 'Bring this word to the center'),
                onTap: () =>
                    Navigator.of(context).pop(_WordNodeQuickAction.focus),
              ),
              _QuickActionTile(
                icon: Icons.visibility_outlined,
                title: _text('Onizleme Ac', 'Open Preview'),
                subtitle: _text(
                    'Cumleleri ve formu ac', 'Open sentences and the form'),
                onTap: () =>
                    Navigator.of(context).pop(_WordNodeQuickAction.preview),
              ),
              _QuickActionTile(
                icon: Icons.auto_awesome_rounded,
                title: _text('AI Cumle Ac', 'Open AI Preview'),
                subtitle: _text('Ornek cumleleri AI ile doldur',
                    'Open preview and generate AI examples'),
                onTap: () =>
                    Navigator.of(context).pop(_WordNodeQuickAction.aiPreview),
              ),
              _QuickActionTile(
                icon: Icons.article_outlined,
                title: _text('Tum Cumleler', 'View All Sentences'),
                subtitle: _text('Bu kelimenin tum cumle gecmisini ac',
                    'Open the full sentence history'),
                onTap: () => Navigator.of(context)
                    .pop(_WordNodeQuickAction.viewAllSentences),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(icon, color: Colors.white, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded,
                      color: Colors.white54),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WordPreviewSheet extends StatefulWidget {
  const _WordPreviewSheet({
    required this.word,
    required this.isTurkish,
    required this.accentColor,
    this.autoGenerateAi = false,
  });

  final Word word;
  final bool isTurkish;
  final Color accentColor;
  final bool autoGenerateAi;

  @override
  State<_WordPreviewSheet> createState() => _WordPreviewSheetState();
}

class _WordPreviewSheetState extends State<_WordPreviewSheet> {
  late final TextEditingController _sentenceController;
  late final TextEditingController _translationController;
  late Word _word;
  late List<Sentence> _sentences;
  final ChatbotService _chatbotService = ChatbotService();
  List<_AiSentenceSuggestion> _generatedSuggestions = const [];
  bool _isSaving = false;
  bool _isGeneratingAi = false;
  bool _isReviewing = false;

  bool get _isTurkish => widget.isTurkish;

  @override
  void initState() {
    super.initState();
    _sentenceController = TextEditingController();
    _translationController = TextEditingController();
    _word = widget.word;
    _sentences = _sortedSentences(_word.sentences);
    if (widget.autoGenerateAi) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _generateAiSuggestions();
        }
      });
    }
  }

  @override
  void dispose() {
    _sentenceController.dispose();
    _translationController.dispose();
    super.dispose();
  }

  String _text(String tr, String en) => _isTurkish ? tr : en;

  List<Sentence> _sortedSentences(List<Sentence> sentences) {
    final items = List<Sentence>.from(sentences);
    items.sort((a, b) {
      final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return items;
  }

  String _levelForDifficulty() {
    switch (_word.difficulty.toLowerCase()) {
      case 'hard':
        return 'B2';
      case 'medium':
        return 'B1';
      default:
        return 'A2';
    }
  }

  void _applySuggestion(_AiSentenceSuggestion suggestion) {
    _sentenceController.text = suggestion.sentence;
    _translationController.text = suggestion.translation;
  }

  Future<void> _generateAiSuggestions() async {
    setState(() {
      _isGeneratingAi = true;
    });

    try {
      final result = await _chatbotService.generateSentences(
        word: _word.englishWord,
        levels: [_levelForDifficulty()],
        lengths: const ['medium'],
        fresh: true,
      );

      if (!mounted) {
        return;
      }

      final sentences = List<String>.from(result['sentences'] ?? const []);
      final translations =
          List<String>.from(result['translations'] ?? const []);
      final suggestions = <_AiSentenceSuggestion>[];
      for (var i = 0; i < sentences.length && suggestions.length < 3; i++) {
        final sentence = sentences[i].trim();
        if (sentence.isEmpty) {
          continue;
        }
        final translation =
            i < translations.length ? translations[i].trim() : '';
        suggestions.add(_AiSentenceSuggestion(
          sentence: sentence,
          translation: translation,
        ));
      }

      setState(() {
        _generatedSuggestions = suggestions;
        _isGeneratingAi = false;
      });

      if (suggestions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _text(
                'AI ornek cumle uretemedi. Tekrar dene.',
                'AI could not generate example sentences. Try again.',
              ),
            ),
          ),
        );
        return;
      }

      _applySuggestion(suggestions.first);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isGeneratingAi = false;
      });
      if (await AiPaywallHandler.handleIfUpgradeRequired(context, e)) {
        return;
      }
      if (!mounted) {
        return;
      }
      final message = e is ApiQuotaExceededException
          ? AiErrorMessageFormatter.forQuota(e)
          : _text('AI cumle uretimi su an basarisiz.',
              'AI sentence generation failed right now.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _saveSentence() async {
    final sentence = _sentenceController.text.trim();
    final translation = _translationController.text.trim();

    if (sentence.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              'Lutfen cumleyi gir.',
              'Enter the sentence.',
            ),
          ),
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final updatedWord =
        await context.read<AppStateProvider>().addSentenceToWord(
              wordId: _word.id,
              sentence: sentence,
              translation: translation,
              difficulty: _word.difficulty,
            );

    if (!mounted) {
      return;
    }

    if (updatedWord == null) {
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              'Cumle kaydedilemedi. Tekrar dene.',
              'The sentence could not be saved. Try again.',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _word = updatedWord;
      _sentences = _sortedSentences(updatedWord.sentences);
      _isSaving = false;
      _sentenceController.clear();
      _translationController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _text('Cumle eklendi. (+5 XP)', 'Sentence added. (+5 XP)'),
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  String _reviewLabel(int quality) {
    switch (quality) {
      case 1:
        return _text('Yine Goster', 'Show Again');
      case 3:
        return _text('Zorlandim', 'Struggled');
      case 5:
        return _text('Bildim', 'Got It');
      default:
        return _text('Tekrar', 'Review');
    }
  }

  Future<void> _submitReview(int quality) async {
    setState(() {
      _isReviewing = true;
    });

    final updatedWord = await context.read<AppStateProvider>().submitWordReview(
          wordId: _word.id,
          quality: quality,
        );

    if (!mounted) {
      return;
    }

    if (updatedWord == null) {
      setState(() {
        _isReviewing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              'Tekrar sonucu kaydedilemedi. Tekrar dene.',
              'The review result could not be saved. Try again.',
            ),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _word = updatedWord;
      _sentences = _sortedSentences(updatedWord.sentences);
      _isReviewing = false;
    });

    final nextReviewMessage = _nextReviewDetailLabel(_word, _isTurkish);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nextReviewMessage == null
              ? _text(
                  'Tekrar kaydedildi: ${_reviewLabel(quality)}',
                  'Review saved: ${_reviewLabel(quality)}',
                )
              : _text(
                  'Tekrar kaydedildi. $nextReviewMessage',
                  'Review saved. $nextReviewMessage',
                ),
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewSentences = _sentences.take(3).toList();
    return Container(
      height: MediaQuery.of(context).size.height * 0.86,
      decoration: BoxDecoration(
        color: const Color(0xFF091019),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _word.englishWord,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _word.turkishMeaning.replaceAll('⭐', '').trim(),
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TinyBadge(label: _word.difficulty.toUpperCase()),
                  _TinyBadge(
                    label: _isTurkish
                        ? '${_sentences.length} cumle'
                        : '${_sentences.length} sentences',
                  ),
                  if (_word.reviewCount > 0)
                    _TinyBadge(
                      label: _reviewCountBadgeLabel(_word, _isTurkish),
                    ),
                  if (_reviewStatusBadgeLabel(_word, _isTurkish) != null)
                    _TinyBadge(
                      label: _reviewStatusBadgeLabel(_word, _isTurkish)!,
                    ),
                ],
              ),
              if (_nextReviewDetailLabel(_word, _isTurkish) != null) ...[
                const SizedBox(height: 10),
                Text(
                  _nextReviewDetailLabel(_word, _isTurkish)!,
                  style: TextStyle(
                    color: widget.accentColor.withOpacity(0.92),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Expanded(
                child: ListView(
                  children: [
                    Text(
                      _text('Tekrar', 'Review'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _ReviewActionButton(
                            label: _reviewLabel(1),
                            icon: Icons.refresh_rounded,
                            accentColor: const Color(0xFFFF7A7A),
                            isLoading: _isReviewing,
                            onPressed:
                                _isReviewing ? null : () => _submitReview(1),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ReviewActionButton(
                            label: _reviewLabel(3),
                            icon: Icons.psychology_alt_rounded,
                            accentColor: const Color(0xFFF6C667),
                            isLoading: _isReviewing,
                            onPressed:
                                _isReviewing ? null : () => _submitReview(3),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ReviewActionButton(
                            label: _reviewLabel(5),
                            icon: Icons.check_circle_rounded,
                            accentColor: const Color(0xFF7BF1B0),
                            isLoading: _isReviewing,
                            onPressed:
                                _isReviewing ? null : () => _submitReview(5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _text('Cumleler', 'Sentences'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (previewSentences.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: Text(
                          _text(
                            'Bu kelime icin henuz cumle yok. Asagidan ilk cumleni ekleyebilirsin.',
                            'There are no sentences for this word yet. Add the first one below.',
                          ),
                          style: const TextStyle(
                              color: Colors.white70, height: 1.4),
                        ),
                      )
                    else
                      ...previewSentences.map(
                        (sentence) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.08)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  sentence.sentence,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  sentence.translation,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    Text(
                      _text('Yeni Cumle', 'New Sentence'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed:
                            _isGeneratingAi ? null : _generateAiSuggestions,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side:
                              BorderSide(color: Colors.white.withOpacity(0.16)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: _isGeneratingAi
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.auto_awesome_rounded),
                        label: Text(
                          _text('AI Ornek Cumle Uret', 'Generate AI Example'),
                        ),
                      ),
                    ),
                    if (_generatedSuggestions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ..._generatedSuggestions.map(
                        (suggestion) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _AiSuggestionCard(
                            suggestion: suggestion,
                            onUse: () =>
                                setState(() => _applySuggestion(suggestion)),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _sentenceController,
                      minLines: 2,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: _text(
                          'Ingilizce cumleyi yaz',
                          'Write the English sentence',
                        ),
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _translationController,
                      minLines: 2,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: _text('Çeviri', 'Translation'),
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveSentence,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.accentColor,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : Text(_text('Cumleyi Kaydet', 'Save Sentence')),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_WordSheetAction.viewAll),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withOpacity(0.16)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(_text('Tum Cumleler', 'View All')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withOpacity(0.12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(_text('Kapat', 'Close')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiSentenceSuggestion {
  const _AiSentenceSuggestion({
    required this.sentence,
    required this.translation,
  });

  final String sentence;
  final String translation;
}

class _AiSuggestionCard extends StatelessWidget {
  const _AiSuggestionCard({
    required this.suggestion,
    required this.onUse,
  });

  final _AiSentenceSuggestion suggestion;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            suggestion.sentence,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (suggestion.translation.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              suggestion.translation,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onUse,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.south_west_rounded, size: 18),
              label: const Text('Kullan / Use'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewActionButton extends StatelessWidget {
  const _ReviewActionButton({
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color accentColor;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor.withOpacity(0.16),
          foregroundColor: accentColor,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: accentColor.withOpacity(0.28)),
          ),
        ),
        icon: isLoading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: accentColor,
                ),
              )
            : Icon(icon, size: 18),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _WordGalaxySurfacePalette {
  const _WordGalaxySurfacePalette({
    required this.panelColor,
    required this.searchFillColor,
    required this.chipBackgroundColor,
    required this.selectedChipBackgroundColor,
    required this.canvasFillColor,
    required this.overlayColor,
    required this.borderColor,
  });

  final Color panelColor;
  final Color searchFillColor;
  final Color chipBackgroundColor;
  final Color selectedChipBackgroundColor;
  final Color canvasFillColor;
  final Color overlayColor;
  final Color borderColor;

  factory _WordGalaxySurfacePalette.forPreset(
    WordGalaxyBackgroundPreset preset,
  ) {
    switch (preset) {
      case WordGalaxyBackgroundPreset.galaxy:
        return const _WordGalaxySurfacePalette(
          panelColor: Color(0xE0141C42),
          searchFillColor: Color(0xCC1B2558),
          chipBackgroundColor: Color(0xB026326B),
          selectedChipBackgroundColor: Color(0xCC394C8A),
          canvasFillColor: Color(0x70091324),
          overlayColor: Color(0xCC17214A),
          borderColor: Color(0x6676A8FF),
        );
      case WordGalaxyBackgroundPreset.blackHole:
        return const _WordGalaxySurfacePalette(
          panelColor: Color(0xE0080809),
          searchFillColor: Color(0xCC151515),
          chipBackgroundColor: Color(0xB0262626),
          selectedChipBackgroundColor: Color(0xCC3D3329),
          canvasFillColor: Color(0x7A050505),
          overlayColor: Color(0xCC151515),
          borderColor: Color(0x66F59E0B),
        );
      case WordGalaxyBackgroundPreset.milkyWay:
        return const _WordGalaxySurfacePalette(
          panelColor: Color(0xE0122430),
          searchFillColor: Color(0xCC1A3544),
          chipBackgroundColor: Color(0xB0274854),
          selectedChipBackgroundColor: Color(0xCC3A6470),
          canvasFillColor: Color(0x700B1720),
          overlayColor: Color(0xCC183340),
          borderColor: Color(0x66A7F3D0),
        );
    }
  }
}

class _WordGalaxyBackdrop extends StatelessWidget {
  const _WordGalaxyBackdrop({required this.preset});

  final WordGalaxyBackgroundPreset preset;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: preset.gradientColors,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              left: -90,
              top: -30,
              child: _GlowOrb(
                color: preset.accentColor.withOpacity(0.22),
                size: 280,
              ),
            ),
            Positioned(
              right: -80,
              top: 120,
              child: _GlowOrb(
                color: preset.highlightColor.withOpacity(0.18),
                size: 220,
              ),
            ),
            Positioned(
              right: -110,
              bottom: -10,
              child: _GlowOrb(
                color: preset.accentColor.withOpacity(0.16),
                size: 300,
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _StarFieldPainter(
                    starColor: Colors.white.withOpacity(0.36),
                    accentColor: preset.highlightColor.withOpacity(0.22),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, Colors.transparent],
        ),
      ),
    );
  }
}

class _StarFieldPainter extends CustomPainter {
  const _StarFieldPainter({required this.starColor, required this.accentColor});

  final Color starColor;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    const points = <Offset>[
      Offset(0.08, 0.12),
      Offset(0.16, 0.34),
      Offset(0.23, 0.71),
      Offset(0.31, 0.18),
      Offset(0.38, 0.52),
      Offset(0.46, 0.82),
      Offset(0.57, 0.14),
      Offset(0.63, 0.58),
      Offset(0.72, 0.3),
      Offset(0.81, 0.7),
      Offset(0.9, 0.24),
      Offset(0.94, 0.56),
    ];

    for (var i = 0; i < points.length; i++) {
      final point =
          Offset(points[i].dx * size.width, points[i].dy * size.height);
      paint.color = i.isEven ? starColor : accentColor;
      canvas.drawCircle(point, i.isEven ? 1.4 : 1.8, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarFieldPainter oldDelegate) {
    return oldDelegate.starColor != starColor ||
        oldDelegate.accentColor != accentColor;
  }
}

class _TinyBadge extends StatelessWidget {
  const _TinyBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 116),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
