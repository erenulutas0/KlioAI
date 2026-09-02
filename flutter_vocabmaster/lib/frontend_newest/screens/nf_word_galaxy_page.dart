import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/word.dart';
import '../../providers/app_state_provider.dart';
import '../../services/ai_error_message_formatter.dart';
import '../../services/ai_paywall_handler.dart';
import '../../services/api_service.dart';
import '../../services/chatbot_service.dart';
// The ring geometry helper was extracted pure and fixed once; the brief for
// this frontend is explicit: import it, never rewrite it. Nothing else from the
// legacy screen is referenced.
import '../../screens/word_galaxy_page.dart'
    show GalaxyRingLayout, galaxyRingCounts;
import '../theme/nf_theme.dart';
import '../theme/nf_theme_scope.dart';
import '../theme/nf_tokens.dart';
import 'nf_word_detail_page.dart';
import '../widgets/nf_button.dart';
import '../widgets/nf_card.dart';
import '../widgets/nf_chip.dart';

/// Word Galaxy in the new design language.
///
/// Behaviour is replicated from `lib/screens/word_galaxy_page.dart` (the spec):
/// ranking by due-urgency then relatedness, node sizing, ring placement via the
/// imported [GalaxyRingLayout], pan/zoom canvas with fit-and-center opening,
/// minimap, fullscreen toggle, tap → preview sheet (sentences, AI examples,
/// add sentence, SRS review), long-press → quick actions. Presentation is
/// rebuilt on NfTokens: no gradients, no glow, 2px borders, Fredoka/Nunito.
/// The three cosmetic background presets of the legacy screen are gone — they
/// were pure decoration (gradients and star fields, both banned here), and the
/// canvas now sits on the token surfaces like every other screen.
///
/// Grading writes through `AppStateProvider.submitWordReview` with
/// `source: 'word_galaxy'` and the same quality values the legacy galaxy sheet
/// used (1 = show again, 3 = struggled, 5 = got it).
class NfWordGalaxyPage extends StatefulWidget {
  const NfWordGalaxyPage({super.key, this.initialWordId, this.onOpenDictionary});

  final int? initialWordId;

  /// Where "add your first word" goes. Null draws the empty state without a
  /// button rather than one that does nothing.
  final VoidCallback? onOpenDictionary;

  @override
  State<NfWordGalaxyPage> createState() => _NfWordGalaxyPageState();
}

// -----------------------------------------------------------------------------
// Pure helpers, carried over from the legacy screen (they are private there,
// so they are duplicated rather than imported).
// -----------------------------------------------------------------------------

DateTime _startOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

int? _daysUntilReview(Word word, {DateTime? referenceDate}) {
  if (word.nextReviewDate == null) {
    return null;
  }
  final DateTime today = _startOfDay(referenceDate ?? DateTime.now());
  final DateTime nextReview = _startOfDay(word.nextReviewDate!);
  return nextReview.difference(today).inDays;
}

bool _isDueWord(Word word, {DateTime? referenceDate}) {
  final int? days = _daysUntilReview(word, referenceDate: referenceDate);
  return days != null && days <= 0;
}

bool _isOverdueWord(Word word, {DateTime? referenceDate}) {
  final int? days = _daysUntilReview(word, referenceDate: referenceDate);
  return days != null && days < 0;
}

double _dueUrgencyScore(Word word, {DateTime? referenceDate}) {
  final int? days = _daysUntilReview(word, referenceDate: referenceDate);
  if (days == null) {
    return word.reviewCount > 0 ? 0.18 : 0.0;
  }
  if (days <= 0) {
    return (0.82 + (math.min(days.abs(), 7) / 7 * 0.18)).clamp(0.0, 1.0);
  }
  return ((1 - (days.clamp(0, 14) / 14)) * 0.72).clamp(0.0, 0.72);
}

double _reviewHistoryScore(Word word, {DateTime? referenceDate}) {
  final double reviewCountScore =
      (word.reviewCount.clamp(0, 10) / 10).toDouble();
  final double lastReviewScore = word.lastReviewDate == null
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

/// The badge on a node: overdue, due today, or due within three days. Null
/// means the word is far enough out that the badge would be noise.
String? _reviewStatusBadgeLabel(BuildContext context, Word word) {
  final int? days = _daysUntilReview(word);
  if (days == null) {
    return null;
  }
  if (days < 0) {
    return context
        .tr('galaxy.badge.overdue')
        .replaceAll('{n}', '${days.abs()}');
  }
  if (days == 0) {
    return context.tr('galaxy.badge.dueToday');
  }
  if (days <= 3) {
    return context.tr('galaxy.badge.inDays').replaceAll('{n}', '$days');
  }
  return null;
}

/// A count and its noun. Split into a one/many pair because English needs the
/// singular after 1 ("1 sentence", not "1 sentences"), while Turkish nouns
/// after a numeral never take the plural suffix — so both keys read the same
/// there, and each language decides for itself.
String _countLabel(
  BuildContext context,
  int count,
  String oneKey,
  String manyKey,
) {
  return context.tr(count == 1 ? oneKey : manyKey).replaceAll('{n}', '$count');
}

String _sentenceCountBadgeLabel(BuildContext context, int count) {
  return _countLabel(
    context,
    count,
    'galaxy.badge.sentenceCountOne',
    'galaxy.badge.sentenceCount',
  );
}

String _reviewCountBadgeLabel(BuildContext context, Word word) {
  return _countLabel(
    context,
    word.reviewCount,
    'galaxy.badge.reviewCountOne',
    'galaxy.badge.reviewCount',
  );
}

String? _nextReviewDetailLabel(BuildContext context, Word word) {
  final int? days = _daysUntilReview(word);
  if (days == null) {
    return null;
  }
  if (days < 0) {
    return context
        .tr('galaxy.next.overdue')
        .replaceAll('{n}', '${days.abs()}');
  }
  if (days == 0) {
    return context.tr('galaxy.next.today');
  }
  return context.tr('galaxy.next.inDays').replaceAll('{n}', '$days');
}

class _NfWordGalaxyPageState extends State<NfWordGalaxyPage> {
  /// Sized by [GalaxyRingLayout] each time the nodes are rebuilt, so the canvas
  /// holds the rings rather than the rings being squeezed into the canvas.
  Size _canvasSize = GalaxyRingLayout.minCanvasSize;

  /// Shared by the InteractiveViewer and the opening fit, so the view can never
  /// start at a zoom the viewer would refuse to hold.
  static const double _minCanvasScale = 0.55;

  final TransformationController _transformationController =
      TransformationController();
  bool _isFullscreen = false;
  int? _focusedWordId;
  Size? _canvasViewportSize;
  bool _hasInitializedCanvasView = false;
  int? _lastAutoCenteredFocusId;

  @override
  void initState() {
    super.initState();
    _focusedWordId = widget.initialWordId;
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _syncCanvasViewport(Size viewportSize, {required int? focusWordId}) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) {
      return;
    }
    final bool shouldCenter = !_hasInitializedCanvasView ||
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

  /// Scale that brings the whole canvas into view, clamped to the viewer's own
  /// minimum so this can never zoom out further than the InteractiveViewer
  /// allows.
  double _fitScaleFor(Size viewportSize) {
    if (_canvasSize.width <= 0 || _canvasSize.height <= 0) return 1;
    final double scale = math.min(
      viewportSize.width / _canvasSize.width,
      viewportSize.height / _canvasSize.height,
    );
    return scale.clamp(_minCanvasScale, 1.0);
  }

  void _centerCanvasInViewport(Size viewportSize) {
    final double scale = _fitScaleFor(viewportSize);
    if (scale < 1.0) {
      final double scaledWidth = _canvasSize.width * scale;
      final double scaledHeight = _canvasSize.height * scale;
      _transformationController.value = Matrix4.identity()
        ..translateByDouble(
          (viewportSize.width - scaledWidth) / 2,
          (viewportSize.height - scaledHeight) / 2,
          0,
          1,
        )
        ..scaleByDouble(scale, scale, 1, 1);
      return;
    }

    final double dx = (viewportSize.width - _canvasSize.width) / 2;
    final double dy = (viewportSize.height - _canvasSize.height) / 2;
    _transformationController.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1);
  }

  void _recenterCanvas() {
    final Size? viewportSize = _canvasViewportSize;
    if (viewportSize == null) {
      _transformationController.value = Matrix4.identity();
      return;
    }
    _lastAutoCenteredFocusId = _focusedWordId;
    _centerCanvasInViewport(viewportSize);
  }

  // ---------------------------------------------------------------------------
  // Ranking, relatedness and node building — logic identical to the legacy
  // screen; geometry via the imported GalaxyRingLayout.
  // ---------------------------------------------------------------------------

  List<Word> _filteredWords(List<Word> words) {
    final List<Word> sorted = List<Word>.from(words)
      ..sort((Word a, Word b) {
        final int dueCompare =
            _dueUrgencyScore(b).compareTo(_dueUrgencyScore(a));
        if (dueCompare != 0) {
          return dueCompare;
        }
        final int reviewCompare = b.reviewCount.compareTo(a.reviewCount);
        if (reviewCompare != 0) {
          return reviewCompare;
        }
        final int sentenceCompare =
            b.sentences.length.compareTo(a.sentences.length);
        if (sentenceCompare != 0) {
          return sentenceCompare;
        }
        return b.learnedDate.compareTo(a.learnedDate);
      });

    return sorted;
  }

  Word _resolvedFocus(List<Word> words) {
    final Word? focused = words.cast<Word?>().firstWhere(
          (Word? word) => word?.id == _focusedWordId,
          orElse: () => null,
        );
    return focused ?? words.first;
  }

  Set<String> _tokensFor(String value) {
    return value
        .toLowerCase()
        .split(RegExp(r'[^a-zA-ZçğıöşüÇĞİÖŞÜ]+'))
        .where((String token) => token.trim().length > 1)
        .map((String token) => token.trim())
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
    final Set<String> focusTokens = <String>{
      ..._tokensFor(focusWord.englishWord),
      ..._tokensFor(focusWord.turkishMeaning),
    };
    final Set<String> candidateTokens = <String>{
      ..._tokensFor(candidate.englishWord),
      ..._tokensFor(candidate.turkishMeaning),
    };
    if (focusTokens.isEmpty || candidateTokens.isEmpty) {
      return 0;
    }
    final int overlap = focusTokens.intersection(candidateTokens).length;
    final int union = focusTokens.union(candidateTokens).length;
    if (union == 0) {
      return 0;
    }
    return overlap / union;
  }

  double _relatednessScore(Word focusWord, Word candidate) {
    final double dayDiff =
        (focusWord.learnedDate.difference(candidate.learnedDate).inHours.abs() /
            24.0);
    final double recencyScore =
        (1 - (dayDiff.clamp(0, 30) / 30)).clamp(0.0, 1.0);

    final int difficultyGap = (_difficultyRank(focusWord.difficulty) -
            _difficultyRank(candidate.difficulty))
        .abs();
    final double difficultyScore = switch (difficultyGap) {
      0 => 1.0,
      1 => 0.55,
      _ => 0.18,
    };

    final int maxSentenceCount = math.max(
      1,
      math.max(focusWord.sentences.length, candidate.sentences.length),
    );
    final double sentenceBalance = 1 -
        ((focusWord.sentences.length - candidate.sentences.length).abs() /
            maxSentenceCount);
    final double sameLearnDay =
        focusWord.learnedDate.toIso8601String().split('T')[0] ==
                candidate.learnedDate.toIso8601String().split('T')[0]
            ? 1.0
            : 0.0;
    final double sentencePresence =
        candidate.sentences.isNotEmpty ? 1.0 : 0.0;
    final double dueScore = _dueUrgencyScore(candidate);
    final double reviewScore = _reviewHistoryScore(candidate);

    const double difficultyWeight = 0.18;
    const double recencyWeight = 0.16;
    const double sentenceBalanceWeight = 0.14;
    const double tokenWeight = 0.12;
    const double sameLearnDayWeight = 0.04;
    const double sentencePresenceWeight = 0.04;
    const double dueWeight = 0.22;
    const double reviewWeight = 0.10;

    final double score = (difficultyScore * difficultyWeight) +
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
        .where((Word word) => word.id != focusWord.id)
        .map((Word word) => (
              word: word,
              score: _relatednessScore(focusWord, word),
              urgency: _dueUrgencyScore(word),
            ))
        .toList()
      ..sort((a, b) {
        final int dueCompare = b.urgency.compareTo(a.urgency);
        if (dueCompare != 0) {
          return dueCompare;
        }
        return b.score.compareTo(a.score);
      });

    final visibleWords = rankedWords.take(18).toList();

    // Sizes first: a radius cannot be chosen before it is known what has to
    // fit at it. (Ranking already puts overdue words in the inner rings, so
    // there is no radial "pull" — see the note in the legacy screen.)
    final List<double> sizes = visibleWords
        .map((entry) => (104 +
                math.min(entry.word.sentences.length, 4) * 6 +
                (18 * entry.score) +
                (entry.urgency * 14) +
                (math.min(entry.word.reviewCount, 6) * 1.5))
            .toDouble())
        .toList();

    final GalaxyRingLayout plan = GalaxyRingLayout.solve(
      nodeSizes: sizes,
      ringCounts: galaxyRingCounts,
    );
    final List<double> ringRadii = plan.ringRadii;
    _canvasSize = plan.canvasSize;

    final List<_GalaxyNode> nodes = <_GalaxyNode>[
      _GalaxyNode(
        word: focusWord,
        center: Offset(_canvasSize.width / 2, _canvasSize.height / 2),
        size: GalaxyRingLayout.focusNodeSize,
        isFocus: true,
        relatedness: 1,
        ringIndex: 0,
      ),
    ];

    int index = 0;
    for (int ring = 0;
        ring < ringRadii.length && index < visibleWords.length;
        ring++) {
      final int count = galaxyRingCounts[ring];
      final int itemsInRing = math.min(count, visibleWords.length - index);
      final double radius = ringRadii[ring];
      for (int slot = 0; slot < itemsInRing; slot++) {
        final entry = visibleWords[index];
        final Word word = entry.word;
        final double angle =
            (-math.pi / 2) + ((2 * math.pi * slot) / itemsInRing);
        final Offset center = Offset(
          (_canvasSize.width / 2) + (math.cos(angle) * radius),
          (_canvasSize.height / 2) +
              (math.sin(angle) * radius * GalaxyRingLayout.verticalSquash),
        );
        final double size = sizes[index];
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
      return const <_GalaxyLink>[];
    }

    final List<_GalaxyLink> links = <_GalaxyLink>[];
    for (int i = 1; i < nodes.length; i++) {
      links.add(_GalaxyLink(
        fromIndex: 0,
        toIndex: i,
        strength: nodes[i].relatedness,
        isHighlight: nodes[i].relatedness >= 0.62,
      ));
    }

    final Map<int, List<int>> nodesByRing = <int, List<int>>{};
    for (int i = 1; i < nodes.length; i++) {
      nodesByRing.putIfAbsent(nodes[i].ringIndex, () => <int>[]).add(i);
    }

    for (final MapEntry<int, List<int>> ringEntry in nodesByRing.entries) {
      final List<int> indexes = ringEntry.value;
      for (int i = 0; i < indexes.length - 1; i++) {
        final int currentIndex = indexes[i];
        final int nextIndex = indexes[i + 1];
        final double strength =
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

  // ---------------------------------------------------------------------------
  // Interactions.
  // ---------------------------------------------------------------------------

  Word _latestWordFor(int wordId, Word fallback) {
    final Word? latestWord = context
        .read<AppStateProvider>()
        .allWords
        .cast<Word?>()
        .firstWhere((Word? item) => item?.id == wordId, orElse: () => null);
    return latestWord ?? fallback;
  }

  /// A modal sheet is built under the root navigator, above the page's
  /// `NfTheme`; without re-installing the tokens the sheet would fall back to
  /// the device brightness and ignore the learner's in-app choice.
  Future<T?> _showNfSheet<T>({
    required WidgetBuilder builder,
    bool isScrollControlled = false,
  }) {
    final NfTokens tokens = NfTokens.of(context);
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: NfTokens.transparent,
      builder: (BuildContext sheetContext) => NfTheme(
        tokens: tokens,
        child: Builder(builder: builder),
      ),
    );
  }

  Future<void> _openWordPreview(
    Word word, {
    bool autoGenerateAi = false,
  }) async {
    setState(() {
      _focusedWordId = word.id;
    });

    final _WordSheetAction? action = await _showNfSheet<_WordSheetAction>(
      isScrollControlled: true,
      builder: (BuildContext context) => _NfWordPreviewSheet(
        word: _latestWordFor(word.id, word),
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

    final _WordNodeQuickAction? action =
        await _showNfSheet<_WordNodeQuickAction>(
      builder: (BuildContext context) => _NfWordQuickActionSheet(word: word),
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

  /// Opens the word's own screen, the same one the Words tab opens. A word's
  /// sentences now hang off its individual meanings, which is more than a sheet
  /// can show — and it keeps one word looking like one word everywhere.
  void _showSentencesDialog(Word word) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NfThemeScope(child: NfWordDetailPage(word: word)),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build.
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final List<Word> allWords = context.watch<AppStateProvider>().allWords;
    final List<Word> filteredWords = _filteredWords(allWords);
    final Word? focusWord =
        filteredWords.isEmpty ? null : _resolvedFocus(filteredWords);
    final List<_GalaxyNode> nodes = focusWord == null
        ? const <_GalaxyNode>[]
        : _buildNodes(filteredWords, focusWord);
    final List<_GalaxyLink> links =
        nodes.isEmpty ? const <_GalaxyLink>[] : _buildLinks(nodes);

    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop && _isFullscreen) {
          setState(() => _isFullscreen = false);
        }
      },
      child: Scaffold(
        backgroundColor: t.ground,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (!_isFullscreen)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NfSpace.s16,
                    NfSpace.s16,
                    NfSpace.s16,
                    NfSpace.s12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _NfGalaxyIconButton(
                        icon: Icons.arrow_back_rounded,
                        semanticLabel: MaterialLocalizations.of(context)
                            .backButtonTooltip,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: NfSpace.s12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              context.tr('practice.wordGalaxy.title'),
                              style: NfTokens.display(
                                size: NfFont.s22,
                                color: t.ink,
                              ),
                            ),
                            const SizedBox(height: NfSpace.s4),
                            Text(
                              context.tr('galaxy.subtitle'),
                              style: NfTokens.body(
                                size: NfFont.s13,
                                color: t.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final Size viewportSize =
                        Size(constraints.maxWidth, constraints.maxHeight);
                    if (focusWord != null) {
                      _syncCanvasViewport(viewportSize,
                          focusWordId: focusWord.id);
                    }
                    return Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: _isFullscreen ? 0 : NfSpace.s16),
                      child: ClipRRect(
                        borderRadius: NfRadius.cardAll,
                        child: Stack(
                          children: <Widget>[
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.fromBorderSide(t.side),
                                  borderRadius: NfRadius.cardAll,
                                  color: t.raised,
                                ),
                              ),
                            ),
                            if (focusWord == null)
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(NfSpace.s26),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Text(
                                        context.tr('galaxy.empty'),
                                        textAlign: TextAlign.center,
                                        style: NfTokens.body(
                                          size: NfFont.s16,
                                          color: t.inkMuted,
                                        ),
                                      ),
                                      // Every control on this screen is hidden
                                      // while there is nothing to draw, so
                                      // without this the page was one grey
                                      // sentence and a back arrow -- and it
                                      // sits in the practice grid as a game,
                                      // which is the tile a new learner with
                                      // no words taps first.
                                      if (widget.onOpenDictionary != null) ...<Widget>[
                                        const SizedBox(height: NfSpace.s16),
                                        NfPrimaryButton(
                                          label: context.tr('words.openDictionary'),
                                          icon: Icons.search_rounded,
                                          expand: false,
                                          onPressed: widget.onOpenDictionary,
                                        ),
                                      ],
                                    ],
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
                                  minScale: _minCanvasScale,
                                  maxScale: 1.8,
                                  boundaryMargin: const EdgeInsets.all(280),
                                  child: SizedBox(
                                    width: _canvasSize.width,
                                    height: _canvasSize.height,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: <Widget>[
                                        CustomPaint(
                                          size: _canvasSize,
                                          painter: _GalaxyLinkPainter(
                                            nodes: nodes,
                                            links: links,
                                            linkColor: t.primary
                                                .withValues(alpha: 0.30),
                                            highlightColor: t.streak
                                                .withValues(alpha: 0.45),
                                          ),
                                        ),
                                        ...nodes.map(
                                          (_GalaxyNode node) =>
                                              AnimatedPositioned(
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
                                              child: _NfGalaxyNodeCard(
                                                word: node.word,
                                                isFocus: node.isFocus,
                                                onTap: () =>
                                                    _handleWordTap(node.word),
                                                onLongPress: () =>
                                                    _handleWordLongPress(
                                                        node.word),
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
                                left: NfSpace.s12,
                                top: NfSpace.s12,
                                child: NfChip(
                                  label: context.tr('galaxy.dragZoom'),
                                  icon: Icons.open_with_rounded,
                                  dense: true,
                                ),
                              ),
                            if (focusWord != null)
                              Positioned(
                                right: NfSpace.s12,
                                top: NfSpace.s12,
                                child: NfChip(
                                  label: _isFullscreen
                                      ? context.tr('galaxy.shrink')
                                      : context.tr('galaxy.expand'),
                                  icon: _isFullscreen
                                      ? Icons.fullscreen_exit_rounded
                                      : Icons.fullscreen_rounded,
                                  variant: NfChipVariant.selected,
                                  onTap: () {
                                    setState(() {
                                      _isFullscreen = !_isFullscreen;
                                    });
                                  },
                                ),
                              ),
                            if (focusWord != null)
                              Positioned(
                                right: NfSpace.s12,
                                bottom: NfSpace.s12,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: <Widget>[
                                    _NfGalaxyMinimap(
                                      controller: _transformationController,
                                      canvasSize: _canvasSize,
                                      viewportSize: viewportSize,
                                      nodes: nodes,
                                    ),
                                    const SizedBox(height: NfSpace.s8),
                                    NfChip(
                                      label: context.tr('galaxy.recenter'),
                                      icon: Icons.center_focus_strong_rounded,
                                      variant: NfChipVariant.selected,
                                      onTap: _recenterCanvas,
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
              if (!_isFullscreen) const SizedBox(height: NfSpace.s16),
            ],
          ),
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

/// Links between nodes. Flat strokes — the legacy painter's blur (glow) is
/// banned in this design language, so strength maps to width and opacity only.
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

    final Paint paint = Paint()..style = PaintingStyle.stroke;

    for (final _GalaxyLink link in links) {
      final Offset from = nodes[link.fromIndex].center;
      final Offset to = nodes[link.toIndex].center;
      final double opacity = (0.35 + (link.strength * 0.55)).clamp(0.0, 1.0);
      paint
        ..color = (link.isHighlight ? highlightColor : linkColor)
            .withValues(alpha: opacity)
        ..strokeWidth = NfStroke.border * (0.6 + link.strength);
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

/// One word card on the canvas.
///
/// State → colour, all semantic: focus = primary, overdue = wrong, due today =
/// streak (attention, not an error), everything else neutral surface.
class _NfGalaxyNodeCard extends StatelessWidget {
  const _NfGalaxyNodeCard({
    required this.word,
    required this.isFocus,
    required this.onTap,
    required this.onLongPress,
  });

  final Word word;
  final bool isFocus;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final String? dueLabel = _reviewStatusBadgeLabel(context, word);
    final bool isDue = _isDueWord(word);
    final bool isOverdue = _isOverdueWord(word);

    final Color background = isFocus
        ? t.primarySoft
        : isOverdue
            ? t.wrongSoft
            : isDue
                ? t.streakSoft
                : t.surface;
    final Color borderColor = isFocus
        ? t.primary
        : isOverdue
            ? t.wrong
            : isDue
                ? t.streak
                : t.border;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: NfRadius.cardAll,
          color: background,
          border: Border.fromBorderSide(t.sideOf(borderColor)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(NfSpace.s12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                word.englishWord,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: NfTokens.display(
                  size: isFocus ? NfFont.s18 : NfFont.s145,
                  color: t.ink,
                ),
              ),
              const SizedBox(height: NfSpace.s6),
              Text(
                word.displayMeaning,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: NfTokens.body(size: NfFont.s12, color: t.inkMuted),
              ),
              const SizedBox(height: NfSpace.s8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: NfSpace.s4,
                runSpacing: NfSpace.s4,
                children: <Widget>[
                  _NfTinyBadge(label: word.difficulty.toUpperCase()),
                  _NfTinyBadge(
                    label: _sentenceCountBadgeLabel(
                      context,
                      word.sentences.length,
                    ),
                  ),
                  if (dueLabel != null)
                    _NfTinyBadge(
                      label: dueLabel,
                      emphasis: isOverdue
                          ? _NfBadgeEmphasis.wrong
                          : _NfBadgeEmphasis.streak,
                    )
                  else if (word.reviewCount > 0)
                    _NfTinyBadge(
                      label: _reviewCountBadgeLabel(context, word),
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

/// Miniature of the whole canvas with the visible window outlined.
class _NfGalaxyMinimap extends StatelessWidget {
  const _NfGalaxyMinimap({
    required this.controller,
    required this.canvasSize,
    required this.viewportSize,
    required this.nodes,
  });

  final TransformationController controller;
  final Size canvasSize;
  final Size viewportSize;
  final List<_GalaxyNode> nodes;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    const double minimapWidth = 132.0;
    final double minimapHeight =
        minimapWidth * (canvasSize.height / canvasSize.width);

    return ValueListenableBuilder<Matrix4>(
      valueListenable: controller,
      builder: (BuildContext context, Matrix4 matrix, _) {
        final double scale = matrix.getMaxScaleOnAxis().clamp(0.0001, 10.0);
        final double tx = matrix.storage[12];
        final double ty = matrix.storage[13];
        final double visibleWidth =
            math.min(canvasSize.width, viewportSize.width / scale);
        final double visibleHeight =
            math.min(canvasSize.height, viewportSize.height / scale);
        final double sceneLeft = (-tx / scale)
            .clamp(0.0, math.max(0.0, canvasSize.width - visibleWidth));
        final double sceneTop = (-ty / scale)
            .clamp(0.0, math.max(0.0, canvasSize.height - visibleHeight));

        final double ratioX = minimapWidth / canvasSize.width;
        final double ratioY = minimapHeight / canvasSize.height;

        return Container(
          width: minimapWidth,
          height: minimapHeight,
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: NfRadius.tileAll,
            border: Border.fromBorderSide(t.side),
          ),
          child: Stack(
            children: <Widget>[
              ...nodes.map(
                (_GalaxyNode node) => Positioned(
                  left: (node.center.dx * ratioX) - (node.isFocus ? 3 : 2),
                  top: (node.center.dy * ratioY) - (node.isFocus ? 3 : 2),
                  child: Container(
                    width: node.isFocus ? 6 : 4,
                    height: node.isFocus ? 6 : 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: node.isFocus ? t.primary : t.inkFaint,
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
                    borderRadius: const BorderRadius.all(Radius.circular(4)),
                    border: Border.all(color: t.primary, width: 1.2),
                    color: t.primarySoft,
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

/// Long-press quick actions.
class _NfWordQuickActionSheet extends StatelessWidget {
  const _NfWordQuickActionSheet({required this.word});

  final Word word;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(NfRadius.card),
          topRight: Radius.circular(NfRadius.card),
        ),
        border: Border.fromBorderSide(t.side),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            NfSpace.s18,
            NfSpace.s16,
            NfSpace.s18,
            NfSpace.s20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.border,
                    borderRadius: NfRadius.pillAll,
                  ),
                ),
              ),
              const SizedBox(height: NfSpace.s16),
              Text(
                word.englishWord,
                style: NfTokens.display(size: NfFont.s22, color: t.ink),
              ),
              const SizedBox(height: NfSpace.s4),
              Text(
                word.displayMeaning,
                style: NfTokens.body(size: NfFont.s14, color: t.inkMuted),
              ),
              const SizedBox(height: NfSpace.s16),
              _NfQuickActionTile(
                icon: Icons.adjust_rounded,
                title: context.tr('galaxy.action.focus'),
                subtitle: context.tr('galaxy.action.focusDesc'),
                onTap: () =>
                    Navigator.of(context).pop(_WordNodeQuickAction.focus),
              ),
              _NfQuickActionTile(
                icon: Icons.visibility_outlined,
                title: context.tr('galaxy.action.preview'),
                subtitle: context.tr('galaxy.action.previewDesc'),
                onTap: () =>
                    Navigator.of(context).pop(_WordNodeQuickAction.preview),
              ),
              _NfQuickActionTile(
                icon: Icons.auto_awesome_rounded,
                title: context.tr('galaxy.action.ai'),
                subtitle: context.tr('galaxy.action.aiDesc'),
                onTap: () =>
                    Navigator.of(context).pop(_WordNodeQuickAction.aiPreview),
              ),
              _NfQuickActionTile(
                icon: Icons.article_outlined,
                title: context.tr('galaxy.action.allSentences'),
                subtitle: context.tr('galaxy.action.allSentencesDesc'),
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

class _NfQuickActionTile extends StatelessWidget {
  const _NfQuickActionTile({
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
    final NfTokens t = NfTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: NfSpace.s8),
      child: NfCard(
        padding: const EdgeInsets.all(NfSpace.s14),
        backgroundColor: t.raised,
        borderRadius: NfRadius.tileAll,
        onTap: onTap,
        child: Row(
          children: <Widget>[
            Icon(icon, color: t.primaryText, size: 22),
            const SizedBox(width: NfSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: NfTokens.display(size: NfFont.s15, color: t.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: NfTokens.body(size: NfFont.s12, color: t.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: NfSpace.s8),
            Icon(Icons.chevron_right_rounded, color: t.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// Tap → the word's preview: sentences, AI examples, add-sentence form and the
/// SRS review buttons. Behaviour mirrors the legacy `_WordPreviewSheet`.
class _NfWordPreviewSheet extends StatefulWidget {
  const _NfWordPreviewSheet({
    required this.word,
    this.autoGenerateAi = false,
  });

  final Word word;
  final bool autoGenerateAi;

  @override
  State<_NfWordPreviewSheet> createState() => _NfWordPreviewSheetState();
}

class _NfWordPreviewSheetState extends State<_NfWordPreviewSheet> {
  late final TextEditingController _sentenceController;
  late final TextEditingController _translationController;
  late Word _word;
  late List<Sentence> _sentences;
  final ChatbotService _chatbotService = ChatbotService();
  List<_AiSentenceSuggestion> _generatedSuggestions =
      const <_AiSentenceSuggestion>[];
  bool _isSaving = false;
  bool _isGeneratingAi = false;
  bool _isReviewing = false;

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

  List<Sentence> _sortedSentences(List<Sentence> sentences) {
    final List<Sentence> items = List<Sentence>.from(sentences);
    items.sort((Sentence a, Sentence b) {
      final DateTime aDate =
          a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final DateTime bDate =
          b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
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
      final Map<String, dynamic> result =
          await _chatbotService.generateSentences(
        word: _word.englishWord,
        levels: <String>[_levelForDifficulty()],
        lengths: const <String>['medium'],
        fresh: true,
      );

      if (!mounted) {
        return;
      }

      final List<String> sentences =
          List<String>.from(result['sentences'] ?? const <String>[]);
      final List<String> translations =
          List<String>.from(result['translations'] ?? const <String>[]);
      final List<_AiSentenceSuggestion> suggestions =
          <_AiSentenceSuggestion>[];
      for (int i = 0; i < sentences.length && suggestions.length < 3; i++) {
        final String sentence = sentences[i].trim();
        if (sentence.isEmpty) {
          continue;
        }
        final String translation =
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
          SnackBar(content: Text(context.tr('galaxy.err.aiEmpty'))),
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
      final String message = e is ApiQuotaExceededException
          ? AiErrorMessageFormatter.forQuota(e)
          : context.tr('galaxy.err.aiFailed');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _saveSentence() async {
    final String sentence = _sentenceController.text.trim();
    final String translation = _translationController.text.trim();

    if (sentence.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('galaxy.err.emptySentence'))),
      );
      return;
    }

    // Both outcomes are resolved before the save round-trip, so neither
    // message depends on a context that has moved on while it ran.
    final String saveFailed = context.tr('word.err.sentenceAdd');
    final String saved = context.tr('galaxy.sentenceAdded');

    setState(() {
      _isSaving = true;
    });

    final Word? updatedWord =
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
        SnackBar(content: Text(saveFailed)),
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
      SnackBar(content: Text(saved)),
    );
  }

  String _reviewLabel(BuildContext context, int quality) {
    switch (quality) {
      case 1:
        return context.tr('galaxy.review.again');
      case 3:
        return context.tr('galaxy.review.struggled');
      case 5:
        return context.tr('galaxy.review.gotIt');
      default:
        return context.tr('nav.repeat');
    }
  }

  Future<void> _submitReview(int quality) async {
    // The grade name and both outcome templates are read before the review is
    // written, so the snackbar copy never depends on a stale context.
    final String grade = _reviewLabel(context, quality);
    final String reviewFailed = context.tr('galaxy.err.reviewSave');
    final String savedWithGrade =
        context.tr('galaxy.reviewSaved').replaceAll('{grade}', grade);
    final String savedTemplate = context.tr('galaxy.reviewSavedNext');

    setState(() {
      _isReviewing = true;
    });

    // Same review path and source as the legacy galaxy sheet, including its
    // 1/3/5 quality values.
    final Word? updatedWord =
        await context.read<AppStateProvider>().submitWordReview(
              wordId: _word.id,
              quality: quality,
              source: 'word_galaxy',
            );

    if (!mounted) {
      return;
    }

    if (updatedWord == null) {
      setState(() {
        _isReviewing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reviewFailed)),
      );
      return;
    }

    setState(() {
      _word = updatedWord;
      _sentences = _sortedSentences(updatedWord.sentences);
      _isReviewing = false;
    });

    final String? nextReviewMessage = _nextReviewDetailLabel(context, _word);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nextReviewMessage == null
              ? savedWithGrade
              : savedTemplate.replaceAll('{next}', nextReviewMessage),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(NfTokens t, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: NfTokens.body(size: NfFont.s14, color: t.inkFaint),
      filled: true,
      fillColor: t.raised,
      contentPadding: const EdgeInsets.all(NfSpace.s12),
      enabledBorder: OutlineInputBorder(
        borderRadius: NfRadius.tileAll,
        borderSide: t.side,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: NfRadius.tileAll,
        borderSide: t.sideOf(t.primary),
      ),
      border: OutlineInputBorder(
        borderRadius: NfRadius.tileAll,
        borderSide: t.side,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final List<Sentence> previewSentences = _sentences.take(3).toList();
    return Container(
      height: MediaQuery.of(context).size.height * 0.86,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(NfRadius.card),
          topRight: Radius.circular(NfRadius.card),
        ),
        border: Border.fromBorderSide(t.side),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            NfSpace.s20,
            NfSpace.s16,
            NfSpace.s20,
            NfSpace.s20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.border,
                    borderRadius: NfRadius.pillAll,
                  ),
                ),
              ),
              const SizedBox(height: NfSpace.s16),
              Text(
                _word.englishWord,
                style: NfTokens.display(size: NfFont.s23, color: t.ink),
              ),
              const SizedBox(height: NfSpace.s4),
              Text(
                _word.displayMeaning,
                style: NfTokens.body(size: NfFont.s145, color: t.inkMuted),
              ),
              const SizedBox(height: NfSpace.s12),
              Wrap(
                spacing: NfSpace.s8,
                runSpacing: NfSpace.s8,
                children: <Widget>[
                  _NfTinyBadge(label: _word.difficulty.toUpperCase()),
                  _NfTinyBadge(
                    label: _sentenceCountBadgeLabel(
                      context,
                      _sentences.length,
                    ),
                  ),
                  if (_word.reviewCount > 0)
                    _NfTinyBadge(
                      label: _reviewCountBadgeLabel(context, _word),
                    ),
                  if (_reviewStatusBadgeLabel(context, _word) != null)
                    _NfTinyBadge(
                      label: _reviewStatusBadgeLabel(context, _word)!,
                      emphasis: _isOverdueWord(_word)
                          ? _NfBadgeEmphasis.wrong
                          : _NfBadgeEmphasis.streak,
                    ),
                ],
              ),
              if (_nextReviewDetailLabel(context, _word) != null) ...<Widget>[
                const SizedBox(height: NfSpace.s10),
                Text(
                  _nextReviewDetailLabel(context, _word)!,
                  style: NfTokens.body(
                    size: NfFont.s13,
                    weight: NfTokens.bodyEmphasisWeight,
                    color: t.primaryText,
                  ),
                ),
              ],
              const SizedBox(height: NfSpace.s16),
              Expanded(
                child: ListView(
                  children: <Widget>[
                    Text(
                      context.tr('nav.repeat'),
                      style: NfTokens.display(size: NfFont.s16, color: t.ink),
                    ),
                    const SizedBox(height: NfSpace.s12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: NfSecondaryButton(
                            label: _reviewLabel(context, 1),
                            tone: NfButtonTone.wrong,
                            busy: _isReviewing,
                            onPressed:
                                _isReviewing ? null : () => _submitReview(1),
                          ),
                        ),
                        const SizedBox(width: NfSpace.s10),
                        Expanded(
                          child: NfSecondaryButton(
                            label: _reviewLabel(context, 3),
                            tone: NfButtonTone.neutral,
                            busy: _isReviewing,
                            onPressed:
                                _isReviewing ? null : () => _submitReview(3),
                          ),
                        ),
                        const SizedBox(width: NfSpace.s10),
                        Expanded(
                          child: NfSecondaryButton(
                            label: _reviewLabel(context, 5),
                            tone: NfButtonTone.correct,
                            busy: _isReviewing,
                            onPressed:
                                _isReviewing ? null : () => _submitReview(5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: NfSpace.s18),
                    Text(
                      context.tr('nav.sentences'),
                      style: NfTokens.display(size: NfFont.s16, color: t.ink),
                    ),
                    const SizedBox(height: NfSpace.s12),
                    if (previewSentences.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(NfSpace.s16),
                        decoration: BoxDecoration(
                          color: t.raised,
                          borderRadius: NfRadius.tileAll,
                          border: Border.fromBorderSide(t.side),
                        ),
                        child: Text(
                          context.tr('galaxy.noSentences'),
                          style: NfTokens.body(
                            size: NfFont.s135,
                            color: t.inkMuted,
                            height: 1.4,
                          ),
                        ),
                      )
                    else
                      ...previewSentences.map(
                        (Sentence sentence) => Padding(
                          padding: const EdgeInsets.only(bottom: NfSpace.s10),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(NfSpace.s14),
                            decoration: BoxDecoration(
                              color: t.raised,
                              borderRadius: NfRadius.tileAll,
                              border: Border.fromBorderSide(t.side),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  sentence.sentence,
                                  style: NfTokens.body(
                                    size: NfFont.s14,
                                    weight: NfTokens.bodyEmphasisWeight,
                                    color: t.ink,
                                  ),
                                ),
                                const SizedBox(height: NfSpace.s6),
                                Text(
                                  sentence.translation,
                                  style: NfTokens.body(
                                    size: NfFont.s13,
                                    color: t.inkMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: NfSpace.s14),
                    Text(
                      context.tr('word.addSentence'),
                      style: NfTokens.display(size: NfFont.s16, color: t.ink),
                    ),
                    const SizedBox(height: NfSpace.s12),
                    NfSecondaryButton(
                      label: context.tr('galaxy.generateAi'),
                      icon: Icons.auto_awesome_rounded,
                      tone: NfButtonTone.primary,
                      busy: _isGeneratingAi,
                      onPressed:
                          _isGeneratingAi ? null : _generateAiSuggestions,
                    ),
                    if (_generatedSuggestions.isNotEmpty) ...<Widget>[
                      const SizedBox(height: NfSpace.s12),
                      ..._generatedSuggestions.map(
                        (_AiSentenceSuggestion suggestion) => Padding(
                          padding: const EdgeInsets.only(bottom: NfSpace.s8),
                          child: _NfAiSuggestionCard(
                            suggestion: suggestion,
                            useLabel: context.tr('galaxy.use'),
                            onUse: () =>
                                setState(() => _applySuggestion(suggestion)),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: NfSpace.s12),
                    TextField(
                      controller: _sentenceController,
                      minLines: 2,
                      maxLines: 4,
                      style: NfTokens.body(size: NfFont.s14, color: t.ink),
                      decoration: _fieldDecoration(
                        t,
                        context.tr('galaxy.sentenceHint'),
                      ),
                    ),
                    const SizedBox(height: NfSpace.s10),
                    TextField(
                      controller: _translationController,
                      minLines: 2,
                      maxLines: 3,
                      style: NfTokens.body(size: NfFont.s14, color: t.ink),
                      decoration: _fieldDecoration(
                        t,
                        context.tr('word.translationLabel'),
                      ),
                    ),
                    const SizedBox(height: NfSpace.s12),
                    NfPrimaryButton(
                      label: context.tr('galaxy.saveSentence'),
                      busy: _isSaving,
                      onPressed: _isSaving ? null : _saveSentence,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: NfSpace.s14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: NfSecondaryButton(
                      label: context.tr('galaxy.viewAll'),
                      onPressed: () =>
                          Navigator.of(context).pop(_WordSheetAction.viewAll),
                    ),
                  ),
                  const SizedBox(width: NfSpace.s10),
                  Expanded(
                    child: NfSecondaryButton(
                      label: context.tr('common.close'),
                      onPressed: () => Navigator.of(context).maybePop(),
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

class _NfAiSuggestionCard extends StatelessWidget {
  const _NfAiSuggestionCard({
    required this.suggestion,
    required this.useLabel,
    required this.onUse,
  });

  final _AiSentenceSuggestion suggestion;
  final String useLabel;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(NfSpace.s12),
      decoration: BoxDecoration(
        color: t.primarySoft,
        borderRadius: NfRadius.tileAll,
        border: Border.fromBorderSide(t.sideOf(t.primary)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            suggestion.sentence,
            style: NfTokens.body(
              size: NfFont.s14,
              weight: NfTokens.bodyEmphasisWeight,
              color: t.ink,
            ),
          ),
          if (suggestion.translation.isNotEmpty) ...<Widget>[
            const SizedBox(height: NfSpace.s6),
            Text(
              suggestion.translation,
              style: NfTokens.body(size: NfFont.s13, color: t.inkMuted),
            ),
          ],
          const SizedBox(height: NfSpace.s10),
          Align(
            alignment: Alignment.centerRight,
            child: NfChip(
              label: useLabel,
              icon: Icons.south_west_rounded,
              dense: true,
              variant: NfChipVariant.selected,
              onTap: onUse,
            ),
          ),
        ],
      ),
    );
  }
}

/// What a tiny badge is flagging. Neutral is metadata; wrong = overdue,
/// streak = due attention — the same meanings those colours carry everywhere
/// else in this frontend.
enum _NfBadgeEmphasis { neutral, wrong, streak }

class _NfTinyBadge extends StatelessWidget {
  const _NfTinyBadge({
    required this.label,
    this.emphasis = _NfBadgeEmphasis.neutral,
  });

  final String label;
  final _NfBadgeEmphasis emphasis;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final Color background;
    final Color border;
    final Color foreground;
    switch (emphasis) {
      case _NfBadgeEmphasis.neutral:
        background = t.raised;
        border = t.border;
        foreground = t.inkMuted;
        break;
      case _NfBadgeEmphasis.wrong:
        background = t.wrongSoft;
        border = t.wrong;
        foreground = t.wrong;
        break;
      case _NfBadgeEmphasis.streak:
        background = t.streakSoft;
        border = t.streak;
        foreground = t.streakText;
        break;
    }
    return Container(
      constraints: const BoxConstraints(maxWidth: 116),
      padding: const EdgeInsets.symmetric(
        horizontal: NfSpace.s8,
        vertical: NfSpace.s4,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: NfRadius.pillAll,
        border: Border.fromBorderSide(t.sideOf(border)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: NfTokens.body(
          size: NfFont.s105,
          weight: NfTokens.bodyEmphasisWeight,
          color: foreground,
          height: 1.1,
        ),
      ),
    );
  }
}

/// 44px bordered icon tile, the shared back/utility control of this page.
class _NfGalaxyIconButton extends StatelessWidget {
  const _NfGalaxyIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Container(
            width: NfSize.minTap,
            height: NfSize.minTap,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: NfRadius.iconTileAll,
              border: Border.fromBorderSide(t.side),
            ),
            child: Icon(icon, color: t.ink, size: 22),
          ),
        ),
      ),
    );
  }
}
