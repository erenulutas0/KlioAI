import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/word.dart';
import '../../utils/cloze.dart';
import '../../providers/app_state_provider.dart';
import '../../services/in_app_review_service.dart';
import '../../services/xp_manager.dart';
import '../theme/nf_theme_scope.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_button.dart';
import '../widgets/nf_card.dart';
import '../widgets/nf_chip.dart';
import 'nf_session_summary_page.dart';

/// A card left open longer than this says nothing about recall; the timing is
/// dropped rather than poisoning the scheduler's data. Same threshold the
/// legacy `RepeatPage` uses.
const int _kMaxResponseMs = 120000;

/// How many cards a session over an unscheduled deck holds. Matches the Today
/// page's fallback review target, so the plan's "Review N words" and the deck
/// the session actually opens with cannot disagree.
const int _kUnscheduledBatch = 10;

/// SM-2 quality values, exactly as the legacy `RepeatPage` grade buttons map
/// them: 2 = hard/lapse, 4 = good, 5 = easy.
const int _kQualityHard = 2;
const int _kQualityGood = 4;
const int _kQualityEasy = 5;

/// Deck selection for the guided session, exported so the shell can decide
/// whether "Start session" has anywhere real to go *before* pushing the page.
///
/// The rules mirror `RepeatPage._selectDueWords`: due words first, and when
/// nothing is due (or the backend omits `nextReviewDate`) fall back to the
/// deck rather than opening a mysteriously empty session. The one deliberate
/// difference is that the fallback is capped at [_kUnscheduledBatch] — the
/// legacy screen fell back to *every* word, which over a large deck turns "a
/// quick session" into a slog with no end in sight.
class NfSessionDeck {
  NfSessionDeck._();

  static DateTime _endOfToday() => DateUtils.dateOnly(DateTime.now())
      .add(const Duration(days: 1))
      .subtract(const Duration(microseconds: 1));

  /// Words the SM-2 scheduler has raised for today. Strict: no fallback.
  static List<Word> dueWords(List<Word> all) {
    final DateTime endOfToday = _endOfToday();
    return all
        .where((Word word) =>
            word.nextReviewDate != null &&
            !word.nextReviewDate!.isAfter(endOfToday))
        .toList();
  }

  /// How many words are actually due — what a "N words due" label may claim.
  static int dueCount(List<Word> all) => dueWords(all).length;

  /// Whether a session can start at all. The only impossible state is an
  /// empty deck; everything else falls back per [select].
  static bool canStart(List<Word> all) => all.isNotEmpty;

  /// The deck a session opens with: due words, else a bounded batch.
  static List<Word> select(List<Word> all) {
    final List<Word> due = dueWords(all);
    if (due.isNotEmpty) {
      return due;
    }
    return all.take(_kUnscheduledBatch).toList();
  }
}

/// The guided review session the Today tab's "Start session" promises.
///
/// Behaviour is `RepeatPage`'s (lib/screens/repeat_page.dart), redesigned:
/// front-of-card recall — the word alone, the meaning revealed only on a
/// deliberate tap — then Hard/Good/Easy grading through
/// `AppStateProvider.submitWordReview` with the legacy quality mapping
/// (2/4/5). The grade buttons stay locked until the reveal, because a grade
/// given with the answer on screen measures reading speed, not recall.
///
/// When the last card is graded the session replaces itself with
/// [NfSessionSummaryPage].
class NfSessionPage extends StatefulWidget {
  const NfSessionPage({super.key});

  @override
  State<NfSessionPage> createState() => _NfSessionPageState();
}

class _NfSessionPageState extends State<NfSessionPage> {
  late final List<Word> _deck;

  int _index = 0;
  bool _revealed = false;
  bool _sentenceTranslationShown = false;
  bool _submitting = false;

  /// When the current card was first shown. Response time is measured from
  /// the word appearing — the retrieval attempt starts there, not at the
  /// reveal — exactly as the legacy screen reasons.
  DateTime? _cardShownAt;

  // Session tally, all honestly derived from grades actually submitted.
  int _reviewed = 0;
  int _xpEarned = 0;
  int _hardCount = 0;
  int _goodCount = 0;
  int _easyCount = 0;
  Word? _firstHardWord;

  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    // The provider's deck is the same one the Today plan counted; reading it
    // here (instead of refetching like the legacy page) keeps the "Review N
    // words" promise and the session contents in step.
    _deck = NfSessionDeck.select(context.read<AppStateProvider>().allWords);
    _cardShownAt = DateTime.now();
    _initTts();
  }

  /// Same voice settings as the legacy review card.
  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  int? _millisSinceCardShown() {
    final DateTime? shown = _cardShownAt;
    if (shown == null) {
      return null;
    }
    final int elapsed = DateTime.now().difference(shown).inMilliseconds;
    return elapsed > 0 && elapsed < _kMaxResponseMs ? elapsed : null;
  }

  Future<void> _speak() async {
    if (_deck.isEmpty) {
      return;
    }
    await _tts.speak(_deck[_index].englishWord);
  }

  void _reveal() {
    if (_revealed) {
      return;
    }
    setState(() => _revealed = true);
  }

  /// Submits one grade and moves on. Offline/temp-id failures are tolerated
  /// exactly as in the legacy flow: the session keeps flowing either way.
  /// XP and streak credit live inside `submitWordReview`; the tally here only
  /// mirrors what that award pays, for the summary.
  Future<void> _grade(int quality) async {
    if (_submitting || !_revealed || _deck.isEmpty) {
      return;
    }
    final Word word = _deck[_index];
    setState(() => _submitting = true);
    try {
      await context.read<AppStateProvider>().submitWordReview(
            wordId: word.id,
            quality: quality,
            // The same source the previous review screen sent, on purpose. This
            // is the same activity graded the same way, and it is one of the
            // two sources the scheduler actually reads
            // (`ReviewSource.CLASSIC_REVIEW`). A new name would have split one
            // learner's review history across two labels at the redesign.
            source: 'classic_review',
            responseMs: _millisSinceCardShown(),
          );
    } catch (error) {
      debugPrint('NfSessionPage: SRS submit failed (offline?): $error');
    }
    if (!mounted) {
      return;
    }

    _reviewed++;
    _xpEarned += XPActionTypes.reviewComplete.xpAmount;
    switch (quality) {
      case _kQualityHard:
        _hardCount++;
        _firstHardWord ??= word;
        break;
      case _kQualityEasy:
        _easyCount++;
        break;
      default:
        _goodCount++;
    }

    if (_index + 1 >= _deck.length) {
      await _finish();
      return;
    }
    setState(() {
      _index++;
      _revealed = false;
      _sentenceTranslationShown = false;
      _submitting = false;
      _cardShownAt = DateTime.now();
    });
  }

  Future<void> _finish() async {
    // A finished review session counts as a completed practice — the same
    // bookkeeping the legacy flow does before showing its summary sheet.
    await InAppReviewService().recordPracticeCompletion();
    if (!mounted) {
      return;
    }
    final NfSessionResult result = NfSessionResult(
      totalWords: _deck.length,
      reviewedCount: _reviewed,
      xpEarned: _xpEarned,
      hardCount: _hardCount,
      goodCount: _goodCount,
      easyCount: _easyCount,
      hardWord: _firstHardWord,
    );
    // Replace rather than push: back from the summary must not land on a
    // spent session. The scope re-installs the palette, because this new
    // route is built above the shell's `NfTheme` (see `NfShell._pushNf`).
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => NfThemeScope(
          child: NfSessionSummaryPage(result: result),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  /// Whether this card asks the word or asks for it.
  ///
  /// Alternating rather than always: the two directions are different work.
  /// The plain card asks what a word means, which is recognition; a sentence
  /// with the word missing asks the learner to produce it, which is harder and
  /// holds better. A session made only of one loses the other, so cards take
  /// turns — and a word with no usable sentence always gets the plain card,
  /// which is most of a deck built before the reader existed.
  ///
  /// Keyed on position, not chance: the same card twice in one session should
  /// not change the question between visits.
  ClozePrompt? _clozeFor(Word word, int index) {
    if (index.isEven) return null;
    if (word.sentences.isEmpty) return null;
    for (final Sentence sentence in word.sentences) {
      final ClozePrompt? cloze =
          Cloze.build(sentence.sentence, word.englishWord);
      if (cloze != null) return cloze;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        child: _deck.isEmpty ? _buildEmpty(t) : _buildSession(t),
      ),
    );
  }

  /// The shell should never send anyone here with an empty deck — that is what
  /// [NfSessionDeck.canStart] is for — but a guard beats a dead screen.
  Widget _buildEmpty(NfTokens t) {
    return Padding(
      padding: const EdgeInsets.all(NfSpace.s26),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Icon(LucideIcons.inbox, size: 40, color: t.inkFaint),
          const SizedBox(height: NfSpace.s16),
          Text(
            context.tr('session.empty'),
            textAlign: TextAlign.center,
            style: NfTokens.body(size: NfFont.s15, color: t.inkMuted),
          ),
          const SizedBox(height: NfSpace.s20),
          NfSecondaryButton(
            label: context.tr('common.back'),
            icon: LucideIcons.arrowLeft,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _buildSession(NfTokens t) {
    final Word word = _deck[_index];

    return Column(
      children: <Widget>[
        _SessionHeader(
          index: _index,
          total: _deck.length,
          onClose: () => Navigator.of(context).maybePop(),
        ),
        // Centred when the card fits, scrollable when it does not. A plain
        // ListView pinned the card to the top, so on a tall phone an unrevealed
        // card — a single word — sat in the upper third with the rest of the
        // screen empty, and the thing the learner is trying to recall was as
        // far from their thumbs as it could be. Revealed cards with a long
        // example sentence still scroll rather than overflow.
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              const double verticalPadding = NfSpace.s8 + NfSpace.s16;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  NfSpace.s16,
                  NfSpace.s8,
                  NfSpace.s16,
                  NfSpace.s16,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.max(
                      0,
                      constraints.maxHeight - verticalPadding,
                    ),
                  ),
                  child: Center(
                    child: _RecallCard(
                      // A new card must not inherit the previous card's reveal
                      // animation state.
                      key: ValueKey<int>(_index),
                      word: word,
                      cloze: _clozeFor(word, _index),
                      revealed: _revealed,
                      sentenceTranslationShown: _sentenceTranslationShown,
                      onReveal: _reveal,
                      onSpeak: _speak,
                      onShowSentenceTranslation: () =>
                          setState(() => _sentenceTranslationShown = true),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        _GradeBar(
          revealed: _revealed,
          submitting: _submitting,
          onHard: () => _grade(_kQualityHard),
          onGood: () => _grade(_kQualityGood),
          onEasy: () => _grade(_kQualityEasy),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HEADER + SEGMENTED PROGRESS
// ═══════════════════════════════════════════════════════════════════════════

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({
    required this.index,
    required this.total,
    required this.onClose,
  });

  final int index;
  final int total;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NfSpace.s8,
        NfSpace.s8,
        NfSpace.s16,
        NfSpace.s8,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: onClose,
            iconSize: NfFont.s22,
            color: t.ink,
            // The default 48px IconButton already clears the tap floor.
            icon: const Icon(Icons.close_rounded),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          ),
          const SizedBox(width: NfSpace.s8),
          Expanded(child: _SegmentedProgress(done: index, total: total)),
          const SizedBox(width: NfSpace.s12),
          NfChip(
            label: '${index + 1}/$total',
            variant: NfChipVariant.unselected,
            dense: true,
          ),
        ],
      ),
    );
  }
}

/// One segment per card: filled for graded cards, brand-tinted for the card on
/// screen, track colour for what is still ahead.
class _SegmentedProgress extends StatelessWidget {
  const _SegmentedProgress({required this.done, required this.total});

  static const double _height = 8;
  static const double _gap = NfSpace.s4;

  /// Past this many cards, per-segment ticks are thinner than their gaps and
  /// the bar reads better as one continuous fill.
  static const int _maxSegments = 20;

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    if (total > _maxSegments) {
      final double fraction = total == 0 ? 0 : done / total;
      return Semantics(
        label: context.tr('session.progress'),
        value: '$done of $total',
        child: SizedBox(
          height: _height,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: t.border,
                  borderRadius: NfRadius.pillAll,
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FractionallySizedBox(
                  widthFactor: math.min(1, fraction),
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.primary,
                      borderRadius: NfRadius.pillAll,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      label: context.tr('session.progress'),
      value: '$done of $total',
      child: Row(
        children: <Widget>[
          for (int i = 0; i < total; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: _gap),
            Expanded(
              child: Container(
                height: _height,
                decoration: BoxDecoration(
                  color: i < done
                      ? t.primary
                      : (i == done ? t.primarySoft : t.border),
                  borderRadius: NfRadius.pillAll,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// RECALL CARD
// ═══════════════════════════════════════════════════════════════════════════

class _RecallCard extends StatelessWidget {
  const _RecallCard({
    super.key,
    required this.word,
    required this.cloze,
    required this.revealed,
    required this.sentenceTranslationShown,
    required this.onReveal,
    required this.onSpeak,
    required this.onShowSentenceTranslation,
  });

  final Word word;

  /// The word's own sentence, blanked and filled, or null to ask the word
  /// itself. Null whenever no sentence contains it, which is most hand-added
  /// words and every word saved before the reader existed.
  final ClozePrompt? cloze;

  final bool revealed;
  final bool sentenceTranslationShown;
  final VoidCallback onReveal;
  final VoidCallback onSpeak;
  final VoidCallback onShowSentenceTranslation;

  /// The legacy card scales the word down as it gets longer so it never
  /// wraps mid-glyph; same idea, the new type scale.
  static double _wordFontSize(String text) {
    final int length = text.length;
    if (length <= 8) {
      return 34;
    }
    if (length <= 12) {
      return 28;
    }
    if (length <= 18) {
      return NfFont.s23;
    }
    return NfFont.s18;
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return NfCard(
      // The whole card is the reveal target: the deliberate tap that turns
      // "read the answer" into "check your answer" is the product's core.
      onTap: revealed ? null : onReveal,
      padding: const EdgeInsets.all(NfSpace.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              // Difficulty is data from the word record, not copy.
              NfChip(label: word.difficulty.toUpperCase(), dense: true),
              const Spacer(),
              // Hidden while the word is the thing being recalled: a button
              // that says the answer out loud is not a hint, it is the answer.
              if (cloze == null || revealed)
                Semantics(
                button: true,
                label: context.tr('common.pronounce'),
                child: InkWell(
                  onTap: onSpeak,
                  borderRadius: NfRadius.tileAll,
                  child: Container(
                    width: NfSize.minTap,
                    height: NfSize.minTap,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.primarySoft,
                      borderRadius: NfRadius.tileAll,
                      border: Border.fromBorderSide(t.sideOf(t.primary)),
                    ),
                    child:
                        Icon(LucideIcons.volume2, size: 20, color: t.primaryText),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: NfSpace.s26),
          if (cloze != null)
            // Before and after the reveal this is the same line in the same
            // place; only the gap changes. Swapping it for the bare word put
            // the answer where the reader was not looking, and the card read as
            // though it had moved on to something else.
            //
            // Prose, not a headline: the display face at 34pt wraps one
            // sentence into three.
            _ClozeLine(prompt: cloze!, revealed: revealed)
          else
            Text(
              word.englishWord,
              textAlign: TextAlign.center,
              style: NfTokens.display(
                size: _wordFontSize(word.englishWord),
                color: t.ink,
              ),
            ),
          const SizedBox(height: NfSpace.s20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: revealed
                ? _buildAnswer(context, t)
                : _buildPrompt(context, t),
          ),
        ],
      ),
    );
  }

  /// The front of the card: an invitation to recall, never the answer.
  Widget _buildPrompt(BuildContext context, NfTokens t) {
    return Column(
      key: const ValueKey<String>('prompt'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NfSpace.s16,
            vertical: NfSpace.s20,
          ),
          decoration: BoxDecoration(
            color: t.raised,
            borderRadius: NfRadius.controlAll,
            border: Border.fromBorderSide(t.side),
          ),
          child: Column(
            children: <Widget>[
              Icon(LucideIcons.eye, size: 22, color: t.primaryText),
              const SizedBox(height: NfSpace.s8),
              Text(
                context.tr('session.reveal'),
                textAlign: TextAlign.center,
                style: NfTokens.display(size: NfFont.s15, color: t.primaryText),
              ),
            ],
          ),
        ),
        const SizedBox(height: NfSpace.s12),
        Text(
          context.tr('session.recallHint'),
          textAlign: TextAlign.center,
          style: NfTokens.body(size: NfFont.s125, color: t.inkMuted),
        ),
      ],
    );
  }

  Widget _buildAnswer(BuildContext context, NfTokens t) {
    // On a cloze card the sentence is already on screen, filled in, right above
    // this. Printing it again in a box says the same thing twice and pushes the
    // meaning off the bottom of a small phone.
    final Sentence? example = cloze != null
        ? null
        : (word.sentences.isNotEmpty ? word.sentences.first : null);

    return Column(
      key: const ValueKey<String>('answer'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          word.displayMeaning,
          textAlign: TextAlign.center,
          style: NfTokens.body(
            size: NfFont.s17,
            weight: NfTokens.bodyEmphasisWeight,
            color: t.ink,
          ),
        ),
        if (example != null) ...<Widget>[
          const SizedBox(height: NfSpace.s16),
          Container(
            padding: const EdgeInsets.all(NfSpace.s14),
            decoration: BoxDecoration(
              color: t.raised,
              borderRadius: NfRadius.controlAll,
              border: Border.fromBorderSide(t.side),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  '"${example.sentence}"',
                  textAlign: TextAlign.center,
                  style: NfTokens.body(size: NfFont.s135, color: t.inkMuted),
                ),
                const SizedBox(height: NfSpace.s8),
                if (sentenceTranslationShown)
                  Text(
                    example.translation,
                    textAlign: TextAlign.center,
                    style: NfTokens.body(
                      size: NfFont.s125,
                      color: t.primaryText,
                    ),
                  )
                else
                  Semantics(
                    button: true,
                    child: InkWell(
                      onTap: onShowSentenceTranslation,
                      borderRadius: NfRadius.tileAll,
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(minHeight: NfSize.minTap),
                        child: Center(
                          child: Text(
                            context.tr('session.revealTranslation'),
                            style: NfTokens.body(
                              size: NfFont.s125,
                              color: t.primaryText,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GRADE BAR
// ═══════════════════════════════════════════════════════════════════════════

/// Hard / Good / Easy, locked until the reveal.
///
/// Grading before the answer is on screen would record how fast the learner
/// can read, and that number becomes the SM-2 ease factor — the legacy screen
/// learned this the hard way, so the lock is behaviour, not styling.
class _GradeBar extends StatelessWidget {
  const _GradeBar({
    required this.revealed,
    required this.submitting,
    required this.onHard,
    required this.onGood,
    required this.onEasy,
  });

  final bool revealed;
  final bool submitting;
  final VoidCallback onHard;
  final VoidCallback onGood;
  final VoidCallback onEasy;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final bool enabled = revealed && !submitting;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NfSpace.s16,
        NfSpace.s8,
        NfSpace.s16,
        NfSpace.s16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            revealed
                ? context.tr('session.gradePrompt')
                : context.tr('session.gradeLocked'),
            textAlign: TextAlign.center,
            style: NfTokens.body(size: NfFont.s125, color: t.inkMuted),
          ),
          const SizedBox(height: NfSpace.s10),
          Row(
            children: <Widget>[
              Expanded(
                child: NfSecondaryButton(
                  label: context.tr('session.grade.hard'),
                  icon: LucideIcons.rotateCcw,
                  tone: NfButtonTone.wrong,
                  compact: true,
                  onPressed: enabled ? onHard : null,
                ),
              ),
              const SizedBox(width: NfSpace.s10),
              Expanded(
                child: NfSecondaryButton(
                  label: context.tr('session.grade.good'),
                  icon: LucideIcons.check,
                  tone: NfButtonTone.primary,
                  compact: true,
                  onPressed: enabled ? onGood : null,
                ),
              ),
              const SizedBox(width: NfSpace.s10),
              Expanded(
                child: NfSecondaryButton(
                  label: context.tr('session.grade.easy'),
                  icon: LucideIcons.checkCheck,
                  tone: NfButtonTone.correct,
                  compact: true,
                  onPressed: enabled ? onEasy : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One sentence with a gap in it, before and after the gap is filled.
///
/// The same widget in the same place either way: only the gap changes. Built as
/// a single RichText rather than two so the line does not re-wrap when the
/// answer arrives — a sentence that reflows as it is answered reads as a
/// different sentence.
class _ClozeLine extends StatelessWidget {
  const _ClozeLine({required this.prompt, required this.revealed});

  final ClozePrompt prompt;
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final TextStyle base = NfTokens.body(
      size: NfFont.s17,
      weight: NfTokens.bodyEmphasisWeight,
      color: t.ink,
    );

    if (!revealed) {
      return Text(prompt.blanked, textAlign: TextAlign.center, style: base);
    }

    // The word is marked where it sits, so the eye lands on the answer in the
    // place it was just asked for.
    final List<InlineSpan> spans = <InlineSpan>[];
    int cursor = 0;
    for (final TextRange answer in prompt.answers) {
      if (answer.start > cursor) {
        spans.add(TextSpan(text: prompt.filled.substring(cursor, answer.start)));
      }
      spans.add(TextSpan(
        text: prompt.filled.substring(answer.start, answer.end),
        style: base.copyWith(color: t.primaryText),
      ));
      cursor = answer.end;
    }
    if (cursor < prompt.filled.length) {
      spans.add(TextSpan(text: prompt.filled.substring(cursor)));
    }

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(style: base, children: spans),
    );
  }
}
