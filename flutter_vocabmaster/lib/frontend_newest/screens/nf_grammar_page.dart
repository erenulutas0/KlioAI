import 'package:flutter/material.dart';

import '../../data/grammar_data.dart';
import '../../data/grammar_repository.dart';
import '../../l10n/app_localizations.dart';
import '../theme/nf_theme_scope.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_card.dart';
import '../widgets/nf_chip.dart';
import 'nf_grammar_topic_page.dart';

/// The grammar topic catalogue, redrawn from `GrammarTab`.
///
/// Same content, same behaviour: the static topic list from
/// `GrammarRepository`, a difficulty filter row, coming-soon topics that
/// explain themselves instead of navigating, and a tap that opens the topic's
/// detail page. Only the paint is new — every colour resolves through
/// [NfTokens], and the per-topic accent colours the legacy data carries are
/// deliberately not used.
///
/// Note on the 'exam' filter: it is a *difficulty label* on topics
/// (core / advanced / exam / bonus), not the removed exam simulator. It stays.
class NfGrammarPage extends StatefulWidget {
  const NfGrammarPage({super.key});

  @override
  State<NfGrammarPage> createState() => _NfGrammarPageState();
}

class _NfGrammarPageState extends State<NfGrammarPage> {
  static const List<String> _filters = <String>[
    'all',
    'core',
    'advanced',
    'exam',
    'bonus',
  ];

  String _selectedFilter = 'all';

  bool get _isTurkish =>
      Localizations.localeOf(context).languageCode == 'tr';

  List<GrammarTopic> _filterTopics(List<GrammarTopic> all) {
    if (_selectedFilter == 'all') {
      return all;
    }
    return all.where((GrammarTopic t) => t.level == _selectedFilter).toList();
  }

  /// Filter labels. The difficulty names are ours, so they resolve through the
  /// key table; the topic *data* underneath still carries only English and
  /// Turkish titles, which is why [_isTurkish] survives below.
  String _filterLabel(String key) {
    switch (key) {
      case 'core':
        return context.tr('grammar.filter.core');
      case 'advanced':
        return context.tr('grammar.filter.advanced');
      case 'exam':
        // Difficulty label, not the exam simulator.
        return context.tr('grammar.filter.exam');
      case 'bonus':
        return context.tr('grammar.filter.bonus');
      default:
        return context.tr('grammar.filter.all');
    }
  }

  void _openTopic(GrammarTopic topic) {
    final bool isComingSoon =
        topic.subtopics.isNotEmpty && topic.subtopics.first.id == 'coming_soon';
    if (isComingSoon) {
      final NfTokens t = NfTokens.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('grammar.comingSoonSnack'),
            style: NfTokens.body(size: NfFont.s135, color: t.primaryInk),
          ),
          backgroundColor: t.ink,
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }
    // Wrapped in the theme scope because this route lands above the shell's
    // NfTheme — the same reason NfShell._pushNf exists.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NfThemeScope(child: NfGrammarTopicPage(topic: topic)),
      ),
    );
  }

  /// The palette comes from the `NfThemeScope` the caller wraps this route in.
  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final List<GrammarTopic> topics =
        _filterTopics(GrammarRepository.getAllTopics());

    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _buildHeader(t),
            _buildFilterRow(),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(
                  NfSpace.s16,
                  NfSpace.s8,
                  NfSpace.s16,
                  NfSpace.s26 + MediaQuery.paddingOf(context).bottom,
                ),
                itemCount: topics.length,
                itemBuilder: (BuildContext context, int index) =>
                    _buildTopicCard(t, topics[index]),
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
        NfSpace.s4,
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.tr('practice.mode.grammar'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NfTokens.display(size: NfFont.s20, color: t.ink),
                ),
                Text(
                  context.tr('grammar.subtitle'),
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

  Widget _buildFilterRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        NfSpace.s16,
        NfSpace.s4,
        NfSpace.s16,
        NfSpace.s8,
      ),
      child: Row(
        children: <Widget>[
          for (final String key in _filters) ...<Widget>[
            NfChip(
              label: _filterLabel(key),
              variant: _selectedFilter == key
                  ? NfChipVariant.selected
                  : NfChipVariant.unselected,
              onTap: () => setState(() => _selectedFilter = key),
            ),
            if (key != _filters.last) const SizedBox(width: NfSpace.s8),
          ],
        ],
      ),
    );
  }

  Widget _buildTopicCard(NfTokens t, GrammarTopic topic) {
    final bool isComingSoon =
        topic.subtopics.isNotEmpty && topic.subtopics.first.id == 'coming_soon';
    final int subtopicCount = topic.subtopics.length;
    final int exampleCount = isComingSoon
        ? 0
        : topic.subtopics
            .fold(0, (int sum, GrammarSubtopic sub) => sum + sub.examples.length);

    return Padding(
      padding: const EdgeInsets.only(bottom: NfSpace.s12),
      child: NfCard(
        onTap: () => _openTopic(topic),
        padding: const EdgeInsets.all(NfSpace.s14),
        backgroundColor: isComingSoon ? t.raised : null,
        child: Row(
          children: <Widget>[
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isComingSoon ? t.surface : t.primarySoft,
                borderRadius: NfRadius.iconTileAll,
                border: isComingSoon ? Border.fromBorderSide(t.side) : null,
              ),
              child: Icon(
                topic.icon,
                size: 24,
                color: isComingSoon ? t.inkFaint : t.primaryText,
              ),
            ),
            const SizedBox(width: NfSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _isTurkish ? topic.titleTr : topic.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: NfTokens.display(
                      size: NfFont.s16,
                      color: isComingSoon ? t.inkMuted : t.ink,
                    ),
                  ),
                  const SizedBox(height: NfSpace.s4),
                  Text(
                    // TR users see the English name as the subtitle (the title
                    // above is Turkish); everyone else sees the difficulty.
                    _isTurkish ? topic.title : _filterLabel(topic.level),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NfTokens.body(
                      size: NfFont.s12,
                      color: t.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: NfSpace.s8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                NfChip(
                  label: isComingSoon
                      ? context.tr('grammar.soon')
                      : context
                          .tr('grammar.topicCount')
                          .replaceAll('{n}', '$subtopicCount'),
                  dense: true,
                  variant: NfChipVariant.unselected,
                ),
                if (!isComingSoon && exampleCount > 10)
                  Padding(
                    padding: const EdgeInsets.only(top: NfSpace.s4),
                    child: Text(
                      context
                          .tr('grammar.exampleCount')
                          .replaceAll('{n}', '$exampleCount'),
                      style: NfTokens.body(
                        size: NfFont.s105,
                        color: t.primaryText,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: NfSpace.s6),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: t.inkFaint,
            ),
          ],
        ),
      ),
    );
  }
}
