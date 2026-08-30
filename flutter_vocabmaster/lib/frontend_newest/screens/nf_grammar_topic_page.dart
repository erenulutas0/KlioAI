import 'package:flutter/material.dart';

import '../../data/grammar_data.dart';
import '../../l10n/app_localizations.dart';
import '../theme/nf_theme_scope.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_button.dart';
import '../widgets/nf_card.dart';
import 'nf_grammar_quiz_page.dart';

/// One grammar topic's guide, redrawn from `GrammarTopicDetailPage`.
///
/// Behaviour is unchanged: expandable subtopic cards (the first — or
/// [initialSubtopicId] — starts open), a formula block per subtopic, worked
/// examples with correct/incorrect marking, and the Turkish-only extras
/// (the exam tip) that exists in the data in Turkish alone. The floating "Practice" action becomes a pinned bottom
/// button in this frontend's language.
class NfGrammarTopicPage extends StatefulWidget {
  const NfGrammarTopicPage({
    super.key,
    required this.topic,
    this.initialSubtopicId,
  });

  final GrammarTopic topic;
  final String? initialSubtopicId;

  @override
  State<NfGrammarTopicPage> createState() => _NfGrammarTopicPageState();
}

class _NfGrammarTopicPageState extends State<NfGrammarTopicPage> {
  String? _expandedSubtopicId;

  bool get _isTurkish => Localizations.localeOf(context).languageCode == 'tr';

  /// The `explanation` field is a multi-line Turkish block, not a short
  /// formula; showing it to a non-TR reader produced an unreadable wall. The
  /// formula itself is shown right below in its own section, so every other
  /// locale gets a short framing sentence instead.
  String _overviewFallback(GrammarSubtopic subtopic) {
    return context
        .tr('grammar.topic.overview')
        .replaceAll('{title}', subtopic.title.trim());
  }

  @override
  void initState() {
    super.initState();
    _expandedSubtopicId = widget.initialSubtopicId ??
        (widget.topic.subtopics.isNotEmpty
            ? widget.topic.subtopics.first.id
            : null);
  }

  /// The subtopic whose card is open, or null when the learner has collapsed
  /// them all. Practice is a single button at the bottom of the topic page,
  /// and the card above it is what they have been reading.
  GrammarSubtopic? get _openSubtopic {
    for (final GrammarSubtopic subtopic in widget.topic.subtopics) {
      if (subtopic.id == _expandedSubtopicId) {
        return subtopic;
      }
    }
    return null;
  }

  void _openQuiz() {
    // Wrapped in the theme scope because this route lands above the shell's
    // NfTheme — the same reason NfShell._pushNf exists.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NfThemeScope(
          child: NfGrammarQuizPage(
            topic: widget.topic,
            subtopic: _openSubtopic,
          ),
        ),
      ),
    );
  }

  /// The palette comes from the `NfThemeScope` the caller wraps this route in.
  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _buildHeader(t),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                  NfSpace.s16,
                  NfSpace.s8,
                  NfSpace.s16,
                  NfSpace.s26,
                ),
                itemCount: widget.topic.subtopics.length,
                itemBuilder: (BuildContext context, int index) =>
                    _buildSubtopicCard(t, widget.topic.subtopics[index]),
              ),
            ),
            // Pinned rather than floating: the quiz is the topic's one call to
            // action, and a solid bottom bar keeps it reachable without
            // covering the notes the learner is reading.
            DecoratedBox(
              decoration: BoxDecoration(
                color: t.surface,
                border: Border(top: t.side),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NfSpace.s16,
                    NfSpace.s12,
                    NfSpace.s16,
                    NfSpace.s12,
                  ),
                  child: NfPrimaryButton(
                    key: const ValueKey('grammar-practice-quiz'),
                    label: context.tr('grammar.practice'),
                    icon: Icons.quiz_outlined,
                    onPressed: _openQuiz,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(NfTokens t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NfSpace.s12,
        NfSpace.s8,
        NfSpace.s16,
        NfSpace.s8,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            iconSize: NfFont.s22,
            color: t.ink,
            // The default 48px IconButton already clears the tap floor.
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          ),
          const SizedBox(width: NfSpace.s4),
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.primarySoft,
              borderRadius: NfRadius.iconTileAll,
            ),
            child: Icon(widget.topic.icon, size: 22, color: t.primaryText),
          ),
          const SizedBox(width: NfSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _isTurkish ? widget.topic.titleTr : widget.topic.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NfTokens.display(size: NfFont.s18, color: t.ink),
                ),
                if (_isTurkish)
                  Text(
                    widget.topic.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NfTokens.body(size: NfFont.s12, color: t.inkMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtopicCard(NfTokens t, GrammarSubtopic subtopic) {
    final bool isExpanded = _expandedSubtopicId == subtopic.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: NfSpace.s12),
      child: NfCard(
        padding: EdgeInsets.zero,
        borderColor: isExpanded ? t.primary : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              button: true,
              expanded: isExpanded,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() {
                      _expandedSubtopicId = isExpanded ? null : subtopic.id;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(NfSpace.s16),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                _isTurkish ? subtopic.titleTr : subtopic.title,
                                style: NfTokens.display(
                                  size: NfFont.s16,
                                  color: isExpanded ? t.primaryText : t.ink,
                                ),
                              ),
                              if (_isTurkish &&
                                  subtopic.titleTr != subtopic.title)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(top: NfSpace.s4),
                                  child: Text(
                                    subtopic.title,
                                    style: NfTokens.body(
                                      size: NfFont.s125,
                                      color: t.inkMuted,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Icon(
                          isExpanded
                              ? Icons.remove_circle_outline_rounded
                              : Icons.add_circle_outline_rounded,
                          size: 22,
                          color: isExpanded ? t.primaryText : t.inkFaint,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (isExpanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  NfSpace.s16,
                  0,
                  NfSpace.s16,
                  NfSpace.s18,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Divider(color: t.border, height: 1, thickness: 1),
                    const SizedBox(height: NfSpace.s12),
                    Text(
                      // The Turkish explanation is the body of the guide, and
                      // for a long time nobody but a Turkish reader saw it:
                      // every other language got one generic sentence,
                      // identical on all eighty-three subtopics. Where an
                      // English version has been written it goes here; where
                      // it has not, the generic sentence still stands in.
                      subtopic.explanationFor(
                            Localizations.localeOf(context).languageCode,
                          ) ??
                          _overviewFallback(subtopic),
                      style: NfTokens.body(
                        size: NfFont.s145,
                        weight: FontWeight.w600,
                        color: t.ink,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: NfSpace.s18),
                    _buildSectionHeader(
                      t,
                      context.tr('grammar.section.formula'),
                      Icons.functions_rounded,
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(NfSpace.s12),
                      decoration: BoxDecoration(
                        color: t.raised,
                        borderRadius: NfRadius.tileAll,
                        border: Border.fromBorderSide(t.side),
                      ),
                      child: Text(
                        // Forty-five of the eighty-three formulas were
                        // written in Turkish -- "Olumlu: Subject + V1
                        // (he/she/it icin +s/es)" -- and were shown to
                        // every language exactly as written. Each has
                        // an English twin now, and formulaFor picks.
                        subtopic.formulaFor(
                          Localizations.localeOf(context).languageCode,
                        ),
                        // The legacy screen set this in monospace; this
                        // frontend has exactly two faces (Fredoka / Nunito),
                        // so the block reads as "structure" through its raised
                        // tile and brand-coloured emphasis instead of a third
                        // font.
                        style: NfTokens.body(
                          size: NfFont.s135,
                          weight: NfTokens.bodyEmphasisWeight,
                          color: t.primaryText,
                          height: 1.6,
                        ),
                      ),
                    ),
                    // Genuinely Turkish, unlike the mistake lists: 244 of
                    // the 297 lines. So this is gated on there being
                    // something written in the reader's language rather than
                    // on the reader being Turkish.
                    if (subtopic
                        .keyPointsFor(
                          Localizations.localeOf(context).languageCode,
                        )
                        .isNotEmpty) ...<Widget>[
                      const SizedBox(height: NfSpace.s18),
                      _buildSectionHeader(
                        t,
                        context.tr('grammar.section.keyPoints'),
                        Icons.vpn_key_outlined,
                      ),
                      ...subtopic
                          .keyPointsFor(
                            Localizations.localeOf(context).languageCode,
                          )
                          .map(
                            (String point) => Padding(
                              padding:
                                  const EdgeInsets.only(bottom: NfSpace.s8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Icon(Icons.star_rounded,
                                      color: t.streak, size: 16),
                                  const SizedBox(width: NfSpace.s8),
                                  Expanded(
                                    child: Text(
                                      point,
                                      style: NfTokens.body(
                                        size: NfFont.s135,
                                        color: t.inkMuted,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                    ],
                    const SizedBox(height: NfSpace.s18),
                    _buildSectionHeader(
                      t,
                      context.tr('grammar.section.examples'),
                      Icons.check_circle_outline_rounded,
                    ),
                    ...subtopic.examples.map(
                      (GrammarExample example) => _buildExampleRow(t, example),
                    ),
                    // No longer gated on Turkish. Of the 209 mistake lines
                    // in this app only 32 held any Turkish; the rest were
                    // wrong-then-right pairs in plain English, hidden from
                    // every other language for no reason.
                    if (subtopic
                        .commonMistakesFor(
                          Localizations.localeOf(context).languageCode,
                        )
                        .isNotEmpty) ...<Widget>[
                      const SizedBox(height: NfSpace.s10),
                      _buildSectionHeader(
                        t,
                        context.tr('grammar.section.mistakes'),
                        Icons.warning_amber_rounded,
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(NfSpace.s12),
                        decoration: BoxDecoration(
                          color: t.wrongSoft,
                          borderRadius: NfRadius.tileAll,
                          border: Border.fromBorderSide(t.sideOf(t.wrong)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: subtopic
                              .commonMistakesFor(
                                Localizations.localeOf(context).languageCode,
                              )
                              .map(
                                (String mistake) => Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: NfSpace.s8),
                                  child: Text(
                                    mistake,
                                    style: NfTokens.body(
                                      size: NfFont.s135,
                                      color: t.ink,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                    if (subtopic.comparisonFor(
                          Localizations.localeOf(context).languageCode,
                        ) !=
                        null) ...<Widget>[
                      const SizedBox(height: NfSpace.s18),
                      _buildSectionHeader(
                        t,
                        context.tr('grammar.section.comparison'),
                        Icons.compare_arrows_rounded,
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(NfSpace.s12),
                        decoration: BoxDecoration(
                          color: t.raised,
                          borderRadius: NfRadius.tileAll,
                          border: Border.fromBorderSide(t.side),
                        ),
                        child: Text(
                          subtopic.comparisonFor(
                            Localizations.localeOf(context).languageCode,
                          )!,
                          style: NfTokens.body(
                            size: NfFont.s135,
                            color: t.inkMuted,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                    if (_isTurkish && subtopic.examTip != null) ...<Widget>[
                      const SizedBox(height: NfSpace.s18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(NfSpace.s14),
                        decoration: BoxDecoration(
                          color: t.streakSoft,
                          borderRadius: NfRadius.tileAll,
                          border: Border.fromBorderSide(t.sideOf(t.streak)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(Icons.lightbulb_outline_rounded,
                                color: t.streakText, size: 20),
                            const SizedBox(width: NfSpace.s10),
                            Expanded(
                              child: Text(
                                subtopic.examTip!,
                                style: NfTokens.body(
                                  size: NfFont.s135,
                                  color: t.ink,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(NfTokens t, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: NfSpace.s10),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: t.primaryText),
          const SizedBox(width: NfSpace.s6),
          Text(
            title.toUpperCase(),
            style: NfTokens.body(
              size: NfFont.s115,
              weight: NfTokens.bodyEmphasisWeight,
              color: t.primaryText,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExampleRow(NfTokens t, GrammarExample example) {
    final Color accent = example.isCorrect ? t.correct : t.wrong;
    return Padding(
      padding: const EdgeInsets.only(bottom: NfSpace.s10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(NfSpace.s12),
        decoration: BoxDecoration(
          color: example.isCorrect ? t.surface : t.wrongSoft,
          borderRadius: NfRadius.tileAll,
          border: Border.fromBorderSide(
            example.isCorrect ? t.side : t.sideOf(t.wrong),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  example.isCorrect
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  color: accent,
                  size: 16,
                ),
                const SizedBox(width: NfSpace.s8),
                Expanded(
                  child: Text(
                    example.english,
                    style: NfTokens.body(
                      size: NfFont.s145,
                      weight: NfTokens.bodyEmphasisWeight,
                      color: t.ink,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
            // The translation line only means something to a TR user; for
            // other locales it would be repeated filler under every example.
            if (_isTurkish)
              Padding(
                padding: const EdgeInsets.only(left: 24, top: NfSpace.s4),
                child: Text(
                  example.turkish,
                  style: NfTokens.body(
                    size: NfFont.s135,
                    weight: FontWeight.w600,
                    color: t.inkMuted,
                    height: 1.4,
                  ).copyWith(fontStyle: FontStyle.italic),
                ),
              ),
            if (_isTurkish && example.note != null)
              Padding(
                padding: const EdgeInsets.only(left: 24, top: NfSpace.s6),
                child: Text(
                  example.note!,
                  style: NfTokens.body(
                    size: NfFont.s125,
                    color: t.primaryText,
                    height: 1.4,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
