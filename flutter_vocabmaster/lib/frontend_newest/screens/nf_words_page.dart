import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/word.dart';
import '../../models/word_maturity.dart';
import '../../models/word_origins.dart';
import '../../providers/app_state_provider.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_button.dart';
import '../widgets/nf_card.dart';
import '../widgets/nf_chip.dart';
import '../widgets/nf_progress.dart';

/// How long the amber review row takes to travel its 4px. Matches the buttons
/// in `nf_button.dart` so every pushable surface in the frontend feels the same.
const Duration _kPressDuration = Duration(milliseconds: 70);

/// The explainer sits after this many rows.
///
/// The strength dots are a new affordance, so the sentence that explains them
/// has to be read — a footer under two hundred cards never is. Four rows puts
/// it at the bottom of the first screenful on a phone, exactly where the design
/// places it, and out of the way from then on.
const int _kExplainerAfterRows = 4;

/// The lowest ease the scheduler will go to. Mirrors `MIN_EASE_FACTOR` in the
/// backend's `SRSService`; used only to sanitise values read back from storage.
const double _kMinEase = 1.3;

/// The ease a word starts at, per `SRSService.initializeWordForSRS`.
const double _kDefaultEase = 2.5;

/// The fixed second-review interval, per `SRSService.SECOND_INTERVAL`.
const int _kSecondInterval = 6;

/// The words tab.
///
/// Read-only over [AppStateProvider]: every mutation a learner can start from
/// here leaves through one of the three callbacks, so the shell decides what
/// "open a word" or "start a review" actually navigates to. All three are
/// optional — a row with no [onOpenWord] simply is not tappable, and the two
/// buttons hide themselves rather than pretending to work.
class NfWordsPage extends StatefulWidget {
  const NfWordsPage({
    super.key,
    this.onOpenWord,
    this.onOpenDictionary,
    this.onStartReview,
    this.onReviewWords,
  });

  /// Tapping a row hands the word back to the shell.
  final ValueChanged<Word>? onOpenWord;

  /// The way out of the empty state.
  final VoidCallback? onOpenDictionary;

  /// Starts a review session over everything the scheduler has brought up.
  final VoidCallback? onStartReview;

  /// Review one part of the deck: the words at a chosen maturity.
  ///
  /// Separate from [onStartReview] rather than a widening of it, because the
  /// two are different requests. "Review what is due" is about today; "review
  /// the ones I am still learning" is about the deck, and nothing new is ever
  /// due, so the band a learner most wants to practise would come back empty
  /// from the other one.
  final ValueChanged<List<Word>>? onReviewWords;

  @override
  State<NfWordsPage> createState() => _NfWordsPageState();
}

class _NfWordsPageState extends State<NfWordsPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  String _query = '';

  /// The source the list is narrowed to, or null for the whole deck.
  ///
  /// The origin label on each row was information with nothing to do: it said
  /// where a word came from and left the learner to scroll for the others. This
  /// is the "words from books" group as something you can actually open.
  String? _origin;

  @override
  void initState() {
    super.initState();
    // The border is the focus ring in this direction, so focus has to repaint.
    _searchFocus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _searchFocus.removeListener(_onFocusChanged);
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onFocusChanged() => setState(() {});

  void _onQueryChanged(String value) {
    if (value == _query) {
      return;
    }
    setState(() => _query = value);
  }

  void _selectOrigin(String? origin) {
    if (origin == _origin) {
      return;
    }
    setState(() => _origin = origin);
  }

  void _clearQuery() {
    _searchController.clear();
    _onQueryChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final AppStateProvider appState = context.watch<AppStateProvider>();

    final List<Word> all = appState.allWords;
    final DateTime today = _startOfDay(DateTime.now());
    final List<Word> visible = _applyQuery(_applyOrigin(all, _origin), _query);
    final int dueCount = all.where((Word w) => _isDue(w, today)).length;

    final bool hasWords = all.isNotEmpty;
    // Only the sources this learner actually has. A filter offering a group
    // that would come back empty is a promise the deck cannot keep, and one
    // lone source is not a choice worth showing at all.
    final List<String> origins = <String>[
      for (final String key in <String>[
        WordOrigins.reader,
        WordOrigins.dailyWords,
        WordOrigins.manual,
      ])
        if (all.any((Word w) => w.origin == key)) key,
    ];
    // Only the very first load blocks the screen; a background refresh keeps
    // the list a learner already has on screen.
    final bool loadingFirstList = appState.isLoadingWords && !hasWords;

    return ColoredBox(
      color: t.ground,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => context.read<AppStateProvider>().refreshWords(),
          color: t.primary,
          backgroundColor: t.surface,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: <Widget>[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  NfSpace.s16,
                  NfSpace.s18,
                  NfSpace.s16,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: _buildHeader(
                    listedCount: visible.length,
                    dueCount: dueCount,
                    showControls: hasWords,
                    // The whole deck, not the filtered view. A bar that moved
                    // while the learner typed a search would be reporting the
                    // search rather than their progress.
                    maturity: MaturityCounts.of(all),
                    all: all,
                    origins: origins,
                  ),
                ),
              ),
              if (loadingFirstList)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _LoadingBlock(),
                )
              else if (!hasWords)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyBlock(onOpenDictionary: widget.onOpenDictionary),
                )
              else if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _NoMatchBlock(onClear: _clearQuery),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    NfSpace.s16,
                    0,
                    NfSpace.s16,
                    NfSpace.s26,
                  ),
                  sliver: _buildList(visible, today),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader({
    required int listedCount,
    required int dueCount,
    required bool showControls,
    required MaturityCounts maturity,
    required List<Word> all,
    required List<String> origins,
  }) {
    final bool showReview = showControls && dueCount > 0 && widget.onStartReview != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _TitleRow(count: listedCount, onAddWord: widget.onOpenDictionary),
        if (maturity.total > 0) ...<Widget>[
          const SizedBox(height: NfSpace.s14),
          _MaturityBar(
            counts: maturity,
            onReview: widget.onReviewWords == null
                ? null
                : (WordMaturity stage) => widget.onReviewWords!(
                      all.where((Word w) => maturityFor(w) == stage).toList(),
                    ),
          ),
        ],
        if (showControls && origins.length > 1) ...<Widget>[
          const SizedBox(height: NfSpace.s12),
          _OriginFilter(
            origins: origins,
            selected: _origin,
            onSelect: _selectOrigin,
          ),
        ],
        if (showControls) ...<Widget>[
          const SizedBox(height: NfSpace.s14),
          _SearchField(
            controller: _searchController,
            focusNode: _searchFocus,
            onChanged: _onQueryChanged,
            onClear: _clearQuery,
            hasText: _query.isNotEmpty,
          ),
        ],
        if (showReview) ...<Widget>[
          const SizedBox(height: NfSpace.s14),
          _ReviewDueRow(
            count: dueCount,
            onTap: widget.onStartReview!,
          ),
        ],
        SizedBox(height: showControls ? NfSpace.s16 : NfSpace.s8),
      ],
    );
  }

  Widget _buildList(List<Word> words, DateTime today) {
    // The explainer takes one slot in the middle of the list rather than a
    // sliver of its own, so the rows below it stay lazily built.
    final int explainerIndex = math.min(_kExplainerAfterRows, words.length);

    return SliverList.builder(
      itemCount: words.length + 1,
      itemBuilder: (BuildContext context, int index) {
        if (index == explainerIndex) {
          return const _DotsExplainer();
        }
        final Word word = words[index > explainerIndex ? index - 1 : index];
        return Padding(
          padding: const EdgeInsets.only(bottom: NfSpace.s10),
          child: _WordRow(
            word: word,
            status: _statusOf(word, today),
            strength: strengthDotsFor(word),
            onTap: widget.onOpenWord == null
                ? null
                : () => widget.onOpenWord!(word),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Header pieces
// ---------------------------------------------------------------------------

/// The deck as three stages: new, learning, known.
///
/// The list already answers "how well do I know this word" one row at a time,
/// five dots each. What it has never answered is the question a learner
/// actually asks — how much of all this has stuck. Counting dots down a
/// scrolling list is not an answer.
///
/// The bands come from [maturityFor], which reads the same interval the dots
/// read, so a word counted as known is a word showing three dots. The app
/// already carries three disagreeing opinions about word strength on three
/// screens; a fourth invented here would be the worst of them, because this one
/// is a summary and summaries get believed.
class _MaturityBar extends StatelessWidget {
  const _MaturityBar({required this.counts, this.onReview});

  final MaturityCounts counts;

  /// Called with the stage the learner asked to practise. Null leaves the bar
  /// a read-only summary.
  final ValueChanged<WordMaturity>? onReview;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    final List<_MaturityBand> bands = <_MaturityBand>[
      _MaturityBand(
        label: context.tr('words.maturity.known'),
        count: counts.known,
        color: t.correct,
        soft: t.correctSoft,
        stage: WordMaturity.known,
      ),
      _MaturityBand(
        label: context.tr('words.maturity.learning'),
        count: counts.learning,
        color: t.streak,
        soft: t.streakSoft,
        stage: WordMaturity.learning,
      ),
      _MaturityBand(
        label: context.tr('words.maturity.fresh'),
        count: counts.fresh,
        color: t.inkFaint,
        soft: t.border,
        stage: WordMaturity.fresh,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ClipRRect(
          borderRadius: NfRadius.pillAll,
          child: SizedBox(
            height: 8,
            child: Row(
              // stretch, or the bar draws nothing at all. Expanded settles the
              // width; the height comes from the cross axis, and a ColoredBox
              // with no child takes the smallest size it is allowed -- which
              // under the default centre alignment is zero. The learner saw an
              // 8px gap where the bar should be, and the test that passed was
              // only reading the labels underneath it.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final _MaturityBand band in bands)
                  if (band.count > 0)
                    Expanded(
                      flex: band.count,
                      child: ColoredBox(color: band.color),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: NfSpace.s10),
        Wrap(
          spacing: NfSpace.s14,
          runSpacing: NfSpace.s6,
          children: <Widget>[
            for (final _MaturityBand band in bands)
              // The legend is the tap target, not the bar. The bar is eight
              // pixels tall, which is a fine thing to look at and a poor thing
              // to hit; this row is the size of the text it holds.
              //
              // An empty band is still shown — "0 Yeni" is true and worth
              // knowing — but it is not tappable, because a session over no
              // words dead-ends on a screen the shell is built never to reach.
              InkWell(
                onTap: onReview == null || band.count == 0
                    ? null
                    : () => onReview!(band.stage),
                borderRadius: NfRadius.pillAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NfSpace.s6,
                    vertical: NfSpace.s4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: band.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: NfSpace.s6),
                      Text(
                        // Digits read the same in all three languages, so only
                        // the stage needs translating.
                        '${band.count} ${band.label}',
                        style:
                            NfTokens.body(size: NfFont.s125, color: t.inkMuted),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _MaturityBand {
  const _MaturityBand({
    required this.label,
    required this.count,
    required this.color,
    required this.soft,
    required this.stage,
  });

  final String label;
  final int count;
  final Color color;
  final Color soft;
  final WordMaturity stage;
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.count, this.onAddWord});

  /// How many words the list is showing. With no search running that is the
  /// total; while a search filters, a badge that disagreed with the rows under
  /// it would look like a bug.
  final int count;

  /// Opens the dictionary. Null hides the control rather than offering a
  /// button that does nothing.
  final VoidCallback? onAddWord;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            context.tr('words.title'),
            style: NfTokens.display(size: NfFont.s25, color: t.ink),
          ),
        ),
        // The only way to add a word once the deck is not empty. The dictionary
        // used to be reachable solely from the empty state on this tab and on
        // Today, so a learner who had saved their first word could never save
        // a second one - in an app whose whole loop is collecting words.
        if (onAddWord != null) ...<Widget>[
          const SizedBox(width: NfSpace.s8),
          Semantics(
            button: true,
            label: context.tr('words.addWord'),
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAddWord,
              child: Container(
                width: NfSize.minTap,
                height: NfSize.minTap,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.primarySoft,
                  borderRadius: NfRadius.iconTileAll,
                ),
                child: Icon(Icons.add_rounded, size: 22, color: t.primaryText),
              ),
            ),
          ),
        ],
        const SizedBox(width: NfSpace.s12),
        Semantics(
          label: '$count ${context.tr('words.unit')}',
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: NfSpace.s12,
              vertical: NfSpace.s6,
            ),
            decoration: BoxDecoration(
              color: t.raised,
              borderRadius: NfRadius.pillAll,
              border: Border.fromBorderSide(t.side),
            ),
            child: Text(
              '$count',
              style: NfTokens.display(size: NfFont.s15, color: t.inkMuted),
            ),
          ),
        ),
      ],
    );
  }
}

/// Which source the list is showing.
///
/// Shown only when the deck holds more than one, because a filter with a single
/// option is a control that cannot change anything.
class _OriginFilter extends StatelessWidget {
  const _OriginFilter({
    required this.origins,
    required this.selected,
    required this.onSelect,
  });

  final List<String> origins;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          NfChip(
            key: const ValueKey<String>('words-origin-all'),
            label: context.tr('grammar.filter.all'),
            dense: true,
            variant: selected == null
                ? NfChipVariant.selected
                : NfChipVariant.unselected,
            onTap: () => onSelect(null),
          ),
          for (final String origin in origins) ...<Widget>[
            const SizedBox(width: NfSpace.s6),
            NfChip(
              key: ValueKey<String>('words-origin-$origin'),
              label: context.tr(WordOrigins.labelKeyFor(origin)!),
              dense: true,
              variant: origin == selected
                  ? NfChipVariant.selected
                  : NfChipVariant.unselected,
              onTap: () => onSelect(origin),
            ),
          ],
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
    required this.hasText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool hasText;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final bool focused = focusNode.hasFocus;

    return Container(
      // A search field is a control, so it takes the secondary control height
      // rather than a number of its own — it then lines up with every other
      // non-primary control in the frontend, and clears the 44px tap floor.
      height: NfSize.buttonSecondary,
      decoration: BoxDecoration(
        color: t.raised,
        // The design calls this corner 14; the token set stops at control (16).
        // Rounding to the nearest token beats introducing a loose literal.
        borderRadius: NfRadius.controlAll,
        border: Border.fromBorderSide(focused ? t.sideOf(t.primary) : t.side),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(width: NfSpace.s12),
          Icon(
            Icons.search_rounded,
            size: 20,
            color: focused ? t.primaryText : t.inkFaint,
          ),
          const SizedBox(width: NfSpace.s8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              cursorColor: t.primary,
              style: NfTokens.body(size: NfFont.s15, color: t.ink),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: context.tr('words.search'),
                hintStyle: NfTokens.body(size: NfFont.s15, color: t.inkFaint),
              ),
            ),
          ),
          if (hasText)
            Semantics(
              button: true,
              label: context.tr('words.clearSearch'),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClear,
                child: SizedBox(
                  width: NfSize.minTap,
                  height: NfSize.minTap,
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: t.inkMuted,
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: NfSpace.s12),
        ],
      ),
    );
  }
}

/// The amber call to action.
///
/// Built here rather than reusing `NfPrimaryButton` because that button is
/// brand-coloured by contract, and repainting a shared widget while other
/// screens are being written on top of it is not worth the coupling. If a
/// second amber CTA ever appears, promote this into `nf_button.dart`.
class _ReviewDueRow extends StatefulWidget {
  const _ReviewDueRow({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  State<_ReviewDueRow> createState() => _ReviewDueRowState();
}

class _ReviewDueRowState extends State<_ReviewDueRow> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    const double depth = NfSize.pressDepth;

    final String label = widget.count == 1
        ? context.tr('words.reviewDueOne')
        : context.tr('words.reviewDue').replaceAll('{n}', '${widget.count}');

    final Widget face = Container(
      height: NfSize.buttonPrimary,
      padding: const EdgeInsets.symmetric(horizontal: NfSpace.s18),
      decoration: BoxDecoration(
        color: t.streak,
        borderRadius: NfRadius.controlAll,
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.replay_rounded, size: 20, color: _onStreak),
          const SizedBox(width: NfSpace.s10),
          Expanded(
            child: Text(
              label,
              style: NfTokens.display(size: NfFont.s16, color: _onStreak),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 20, color: _onStreak),
        ],
      ),
    );

    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onTap: widget.onTap,
          child: SizedBox(
            width: double.infinity,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  top: depth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _underStreak,
                      borderRadius: NfRadius.controlAll,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    AnimatedContainer(
                      duration: _kPressDuration,
                      curve: Curves.easeOut,
                      height: _pressed ? depth : 0,
                    ),
                    face,
                    AnimatedContainer(
                      duration: _kPressDuration,
                      curve: Curves.easeOut,
                      height: _pressed ? 0 : depth,
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

/// Ink drawn on top of the amber face.
///
/// `streak` is the one token deliberately identical in light and dark, so
/// whatever sits on it has to be identical too: the usual `ink` flips to
/// near-white in dark mode and would leave a pale label on a pale amber. Taking
/// the light palette's values invents no colour — it pins the two that are
/// legible against #FFB020 in either theme.
Color get _onStreak => NfTokens.light.ink;

/// The solid slab under the amber face: the darker amber of the same family.
Color get _underStreak => NfTokens.light.streakText;

// ---------------------------------------------------------------------------
// List pieces
// ---------------------------------------------------------------------------

class _WordRow extends StatelessWidget {
  const _WordRow({
    required this.word,
    required this.status,
    required this.strength,
    required this.onTap,
  });

  final Word word;
  final _WordStatus status;
  final int strength;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    // `displayMeaning` drops the star that marks a Daily Words import; the raw
    // field carries provenance, not something to read.
    final String meaning = word.displayMeaning;
    final String? originKey = WordOrigins.labelKeyFor(word.origin);

    return NfCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: NfSpace.s14,
        vertical: NfSpace.s12,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        word.englishWord,
                        style: NfTokens.body(
                          size: NfFont.s16,
                          weight: NfTokens.bodyEmphasisWeight,
                          color: t.ink,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (status != _WordStatus.none) ...<Widget>[
                      const SizedBox(width: NfSpace.s8),
                      NfChip(
                        label: status.label(context),
                        variant: status.variant,
                        dense: true,
                      ),
                    ],
                  ],
                ),
                if (originKey != null) ...<Widget>[
                  const SizedBox(height: NfSpace.s6),
                  // Where this word came from, when the app knows. A word
                  // tapped out of a novel and one typed into the dictionary box
                  // used to look identical in this list, and the book is
                  // usually the reason the learner remembers saving it.
                  //
                  // Absent, not "unknown", for the words saved before any of
                  // this was recorded: a guess presented as a fact reads worse
                  // than an honest gap.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.sell_outlined, size: 12, color: t.inkFaint),
                      const SizedBox(width: NfSpace.s4),
                      Text(
                        context.tr(originKey),
                        style:
                            NfTokens.body(size: NfFont.s12, color: t.inkFaint),
                      ),
                    ],
                  ),
                ],
                if (meaning.isNotEmpty) ...<Widget>[
                  const SizedBox(height: NfSpace.s4),
                  Text(
                    meaning,
                    style: NfTokens.body(size: NfFont.s135, color: t.inkMuted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: NfSpace.s12),
          NfStrengthDots(strength: strength),
        ],
      ),
    );
  }
}

class _DotsExplainer extends StatelessWidget {
  const _DotsExplainer();

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Padding(
      padding: const EdgeInsets.only(
        top: NfSpace.s4,
        bottom: NfSpace.s14,
        left: NfSpace.s4,
      ),
      child: Text(
        context.tr('words.dotsHint'),
        style: NfTokens.body(size: NfFont.s125, color: t.inkFaint),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Non-list states
// ---------------------------------------------------------------------------

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock();

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: NfSpace.s26),
      child: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: NfStroke.iconHeavy,
            valueColor: AlwaysStoppedAnimation<Color>(t.primary),
          ),
        ),
      ),
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({required this.onOpenDictionary});

  final VoidCallback? onOpenDictionary;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return _CentredBlock(
      children: <Widget>[
        const _IconTile(icon: Icons.auto_stories_outlined),
        const SizedBox(height: NfSpace.s20),
        Text(
          context.tr('words.emptyTitle'),
          style: NfTokens.display(size: NfFont.s20, color: t.ink),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: NfSpace.s10),
        Text(
          context.tr('words.emptyBody'),
          style: NfTokens.body(size: NfFont.s14, color: t.inkMuted),
          textAlign: TextAlign.center,
        ),
        if (onOpenDictionary != null) ...<Widget>[
          const SizedBox(height: NfSpace.s22),
          SizedBox(
            width: 220,
            child: NfPrimaryButton(
              label: context.tr('words.openDictionary'),
              icon: Icons.search_rounded,
              onPressed: onOpenDictionary,
            ),
          ),
        ],
      ],
    );
  }
}

class _NoMatchBlock extends StatelessWidget {
  const _NoMatchBlock({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return _CentredBlock(
      children: <Widget>[
        const _IconTile(icon: Icons.search_off_rounded),
        const SizedBox(height: NfSpace.s20),
        Text(
          context.tr('words.noMatch'),
          style: NfTokens.display(size: NfFont.s18, color: t.ink),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: NfSpace.s22),
        SizedBox(
          width: 200,
          child: NfSecondaryButton(
            label: context.tr('words.clearSearch'),
            onPressed: onClear,
          ),
        ),
      ],
    );
  }
}

class _CentredBlock extends StatelessWidget {
  const _CentredBlock({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NfSpace.s26,
        NfSpace.s20,
        NfSpace.s26,
        NfSpace.s26,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: children,
          ),
        ),
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.raised,
        borderRadius: NfRadius.iconTileAll,
        border: Border.fromBorderSide(t.side),
      ),
      child: Icon(icon, size: 26, color: t.inkMuted),
    );
  }
}

// ---------------------------------------------------------------------------
// Status
// ---------------------------------------------------------------------------

enum _WordStatus {
  none,
  /// The scheduler has brought this word up today or earlier.
  due,
  /// Saved but never graded, so the scheduler has no opinion on it yet.
  isNew;

  /// Takes the context rather than being a getter: the labels are translated,
  /// and a getter on an enum has nowhere to read the locale from.
  String label(BuildContext context) {
    switch (this) {
      case _WordStatus.none:
        return '';
      case _WordStatus.due:
        return context.tr('words.dueBadge');
      case _WordStatus.isNew:
        return context.tr('words.newBadge');
    }
  }

  NfChipVariant get variant {
    switch (this) {
      case _WordStatus.due:
        return NfChipVariant.streak;
      case _WordStatus.isNew:
      case _WordStatus.none:
        return NfChipVariant.selected;
    }
  }
}

/// A word can be both never-graded and overdue — a new word is scheduled for
/// tomorrow, and tomorrow arrives whether or not the learner does. DUE wins,
/// because it is the one of the two that asks for something.
_WordStatus _statusOf(Word word, DateTime today) {
  if (_isDue(word, today)) {
    return _WordStatus.due;
  }
  if (word.reviewCount <= 0) {
    return _WordStatus.isNew;
  }
  return _WordStatus.none;
}

/// Matches the backend's own query (`next_review_date <= today`) and the
/// existing repeat screen, so the count on the amber row is the same set of
/// words the review session will hand out.
bool _isDue(Word word, DateTime today) {
  final DateTime? next = word.nextReviewDate;
  return next != null && !_startOfDay(next).isAfter(today);
}

DateTime _startOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

// Strength moved to lib/models/word_maturity.dart, where it can be tested.
// It was the app's de-facto answer to "how well does this learner know this
// word", read by two screens, and living in a screen file meant nothing could
// ask it a question without building a list first. It had no tests at all.

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

/// The deck narrowed to one source, or all of it.
///
/// A word saved before provenance was recorded has no origin, and no filter
/// matches it: it appears under "all" and nowhere else. Filing it under a guess
/// would be the one thing worse than leaving it unlabelled.
@visibleForTesting
List<Word> applyOriginForTest(List<Word> words, String? origin) =>
    _applyOrigin(words, origin);

List<Word> _applyOrigin(List<Word> words, String? origin) {
  if (origin == null) {
    return words;
  }
  return words
      .where((Word w) => w.origin == origin)
      .toList(growable: false);
}

List<Word> _applyQuery(List<Word> words, String query) {
  final String needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return words;
  }
  return words
      .where((Word w) =>
          w.englishWord.toLowerCase().contains(needle) ||
          w.displayMeaning.toLowerCase().contains(needle))
      .toList(growable: false);
}
