import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/writing_practice_models.dart';
import '../../providers/app_state_provider.dart';
import '../../services/ai_error_message_formatter.dart';
import '../../services/ai_paywall_handler.dart';
import '../../services/api_service.dart';
import '../../services/daily_practice_progress_service.dart';
import '../../services/groq_service.dart';
import '../../services/learning_language_service.dart';
import '../../services/xp_manager.dart';
import '../../widgets/feedback_prompt_sheet.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_button.dart';
import '../widgets/nf_card.dart';
import '../widgets/nf_chip.dart';

/// Writing practice in the new frontend's paint.
///
/// Behaviour is a replica of `lib/screens/writing_practice_page.dart`, which
/// stays untouched: a three-step flow (choose a level → write on the daily
/// topic → read the evaluation), the daily-topic contract (one topic per level
/// per day, reopening a level brings the same topic back), the completion map
/// from [DailyPracticeProgressService], the fallback-evaluation guard (a
/// stand-in payload scoring 0 is an error to retry with the text kept, never a
/// recorded result), XP for completion and a >= 90 score, the paywall and
/// quota handling, and the ten-character floor before "Evaluate" arms.
class NfWritingPracticePage extends StatefulWidget {
  const NfWritingPracticePage({super.key});

  @override
  State<NfWritingPracticePage> createState() => _NfWritingPracticePageState();
}

enum _NfWritingStep { setup, writing, evaluation }

class _NfWritingPracticePageState extends State<NfWritingPracticePage> {
  _NfWritingStep _step = _NfWritingStep.setup;

  /// Starts from the profile's CEFR level so the picker does not fall back to
  /// B1 every session — same seed as the legacy screen.
  String _selectedLevel = LearningLanguageService.englishLevel;

  String _userText = '';
  int _wordCountActual = 0;
  bool _isLoading = false;
  late final TextEditingController _textController;

  TopicData? _topic;
  EvaluationData? _evaluation;
  final DailyPracticeProgressService _progressService =
      DailyPracticeProgressService();
  Map<String, bool> _completedLevels = <String, bool>{};

  static const List<String> _levels = <String>[
    'A1',
    'A2',
    'B1',
    'B2',
    'C1',
    'C2',
  ];

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _textController.addListener(_updateWordCount);
    unawaited(_loadCompletionMap());
  }

  @override
  void dispose() {
    _textController.removeListener(_updateWordCount);
    _textController.dispose();
    super.dispose();
  }

  void _updateWordCount() {
    final String text = _textController.text;
    setState(() {
      _userText = text;
      _wordCountActual = text
          .trim()
          .split(RegExp(r'\s+'))
          .where((String w) => w.isNotEmpty)
          .length;
    });
  }

  Future<void> _loadCompletionMap() async {
    final Map<String, bool> completed =
        await _progressService.getCompletedLevels('writing');
    if (!mounted) return;
    setState(() => _completedLevels = completed);
  }

  // ---------------------------------------------------------------------------
  // Flow
  // ---------------------------------------------------------------------------

  Future<void> _handleGenerateTopic() async {
    setState(() => _isLoading = true);

    try {
      final TopicData topic =
          await GroqService.generateDailyWritingTopic(_selectedLevel);
      if (mounted) {
        setState(() {
          _topic = topic;
          _step = _NfWritingStep.writing;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (await AiPaywallHandler.handleIfUpgradeRequired(context, e)) {
        return;
      }
      if (!mounted) return;
      final String msg = e is ApiQuotaExceededException
          ? AiErrorMessageFormatter.forQuota(e)
          : AiErrorMessageFormatter.forError(e);
      _showMessage(msg);
    }
  }

  Future<void> _handleSubmitWriting() async {
    setState(() => _isLoading = true);
    try {
      final EvaluationData evaluation =
          await GroqService.evaluateWriting(_userText, _selectedLevel, _topic!);

      // A fallback payload is the absence of a judgement, not a judgement.
      // Recording it would put a permanent zero on text the learner actually
      // wrote, and paying XP for it would reward a failure — so it is treated
      // as the error it is, with the text kept in the field for a retry.
      if (evaluation.isFallback) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _showMessage(context.tr('practice.writing.evalUnavailable'));
        return;
      }

      await _progressService.saveWritingResult(
        level: _selectedLevel,
        topic: _topic?.topic ?? '',
        score: evaluation.score,
      );
      if (mounted) {
        final AppStateProvider appState = context.read<AppStateProvider>();
        final String txBase =
            'writing_${_selectedLevel}_${(_topic?.topic ?? '').hashCode}_${_userText.hashCode}';
        await appState.addXPForAction(
          XPActionTypes.writingComplete,
          source: 'Yazma Pratiği',
          transactionId: '$txBase:complete',
        );
        if (evaluation.score >= 90) {
          await appState.addXPForAction(
            XPActionTypes.writingPerfect,
            source: 'Mükemmel Yazım',
            transactionId: '$txBase:perfect',
          );
        }
      }
      await _loadCompletionMap();
      if (mounted) {
        setState(() {
          _evaluation = evaluation;
          _step = _NfWritingStep.evaluation;
          _isLoading = false;
        });
      }
      if (mounted) {
        await FeedbackPromptSheet.maybeShow(context);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (await AiPaywallHandler.handleIfUpgradeRequired(context, e)) {
        return;
      }
      if (!mounted) return;
      final String msg = e is ApiQuotaExceededException
          ? AiErrorMessageFormatter.forQuota(e)
          : AiErrorMessageFormatter.forError(e);
      _showMessage(msg);
    }
  }

  void _handleReset() {
    setState(() {
      _step = _NfWritingStep.setup;
      _topic = null;
      _userText = '';
      _textController.clear();
      _evaluation = null;
      _wordCountActual = 0;
    });
  }

  void _resetCurrentWritingAttempt() {
    setState(() {
      _step = _NfWritingStep.writing;
      _evaluation = null;
      _userText = '';
      _wordCountActual = 0;
      _textController.clear();
    });
  }

  void _showMessage(String text) {
    final NfTokens t = NfTokens.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: NfTokens.body(size: NfFont.s135, color: t.primaryInk),
        ),
        backgroundColor: t.ink,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _NfPageHeader(
              title: context.tr('practice.writing.title'),
              tokens: t,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  NfSpace.s16,
                  NfSpace.s8,
                  NfSpace.s16,
                  NfSpace.s26 + MediaQuery.paddingOf(context).bottom,
                ),
                child: switch (_step) {
                  _NfWritingStep.setup => _buildSetupStep(t),
                  _NfWritingStep.writing => _buildWritingStep(t),
                  _NfWritingStep.evaluation => _buildEvaluationStep(t),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 1: setup
  // ---------------------------------------------------------------------------

  Widget _buildSetupStep(NfTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NfCard(
          child: Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.primarySoft,
                  borderRadius: NfRadius.iconTileAll,
                ),
                child:
                    Icon(Icons.edit_outlined, size: 23, color: t.primaryText),
              ),
              const SizedBox(width: NfSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      context.tr('practice.writing.aiTitle'),
                      style: NfTokens.display(size: NfFont.s17, color: t.ink),
                    ),
                    const SizedBox(height: NfSpace.s4),
                    Text(
                      context.tr('practice.writing.card.desc'),
                      style:
                          NfTokens.body(size: NfFont.s125, color: t.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: NfSpace.s14),
        _buildDifficultyCard(t),
      ],
    );
  }

  Widget _buildDifficultyCard(NfTokens t) {
    return NfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.gps_fixed_rounded, size: 18, color: t.primaryText),
              const SizedBox(width: NfSpace.s8),
              Text(
                context.tr('practice.writing.chooseLevel'),
                style: NfTokens.display(size: NfFont.s16, color: t.ink),
              ),
            ],
          ),
          const SizedBox(height: NfSpace.s14),
          for (int i = 0; i < _levels.length; i += 3) ...<Widget>[
            Row(
              children: <Widget>[
                for (int j = i; j < i + 3; j++) ...<Widget>[
                  _buildLevelTile(t, _levels[j]),
                  if (j < i + 2) const SizedBox(width: NfSpace.s8),
                ],
              ],
            ),
            if (i + 3 < _levels.length) const SizedBox(height: NfSpace.s8),
          ],
          const SizedBox(height: NfSpace.s14),
          if (_completedLevels[_selectedLevel] == true) ...<Widget>[
            NfCard(
              padding: const EdgeInsets.all(NfSpace.s12),
              borderRadius: NfRadius.tileAll,
              backgroundColor: t.correctSoft,
              borderColor: t.correct,
              child: Text(
                context.tr('practice.writing.levelDone'),
                style: NfTokens.body(size: NfFont.s125, color: t.ink),
              ),
            ),
            const SizedBox(height: NfSpace.s12),
          ],
          NfPrimaryButton(
            label: _isLoading
                ? context.tr('practice.writing.preparingTopic')
                : context.tr('practice.writing.getTopic'),
            icon: Icons.auto_awesome,
            busy: _isLoading,
            onPressed: _isLoading ? null : _handleGenerateTopic,
          ),
          const SizedBox(height: NfSpace.s10),
          Text(
            context.tr('practice.writing.dailyNote'),
            style: NfTokens.body(size: NfFont.s12, color: t.inkFaint),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelTile(NfTokens t, String level) {
    final bool isSelected = _selectedLevel == level;
    final bool isCompleted = _completedLevels[level] == true;

    return Expanded(
      child: NfCard(
        padding: const EdgeInsets.symmetric(vertical: NfSpace.s12),
        borderRadius: NfRadius.tileAll,
        backgroundColor: isSelected ? t.primarySoft : t.raised,
        borderColor: isSelected ? t.primary : t.border,
        onTap: () => setState(() => _selectedLevel = level),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: <Widget>[
            Text(
              level,
              style: NfTokens.display(
                size: NfFont.s15,
                color: isSelected ? t.primaryText : t.inkMuted,
              ),
            ),
            if (isCompleted)
              Positioned(
                top: -NfSpace.s6,
                right: 0,
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 15,
                  color: t.correct,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 2: writing
  // ---------------------------------------------------------------------------

  Widget _buildWritingStep(NfTokens t) {
    final TopicData topic = _topic!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NfCard(
          backgroundColor: t.primarySoft,
          borderColor: t.primary,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.lightbulb_outline,
                      size: 20, color: t.primaryText),
                  const SizedBox(width: NfSpace.s8),
                  NfChip(
                    label: topic.level,
                    dense: true,
                    variant: NfChipVariant.selected,
                  ),
                ],
              ),
              const SizedBox(height: NfSpace.s10),
              Text(
                topic.topic,
                style: NfTokens.display(size: NfFont.s22, color: t.ink),
              ),
              const SizedBox(height: NfSpace.s8),
              Text(
                topic.description,
                style: NfTokens.body(
                    size: NfFont.s135, color: t.inkMuted, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: NfSpace.s14),
        _buildWritingArea(t),
        const SizedBox(height: NfSpace.s16),
        Row(
          children: <Widget>[
            Expanded(
              child: NfSecondaryButton(
                label: context.tr('practice.writing.retryTopic'),
                icon: Icons.refresh_rounded,
                onPressed: _resetCurrentWritingAttempt,
              ),
            ),
            const SizedBox(width: NfSpace.s10),
            Expanded(
              child: NfPrimaryButton(
                label: _isLoading
                    ? context.tr('practice.writing.evaluating')
                    : context.tr('practice.writing.evaluate'),
                icon: Icons.check_rounded,
                busy: _isLoading,
                height: NfSize.buttonSecondary,
                // Same floor as the legacy screen: fewer than ten characters
                // is not a writing sample, so the button stays disarmed.
                onPressed: _userText.trim().length < 10 || _isLoading
                    ? null
                    : _handleSubmitWriting,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWritingArea(NfTokens t) {
    return NfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: NfSpace.s8,
            spacing: NfSpace.s10,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.edit_outlined, size: 18, color: t.primaryText),
                  const SizedBox(width: NfSpace.s8),
                  Text(
                    context.tr('practice.writing.writeHere'),
                    style: NfTokens.display(size: NfFont.s16, color: t.ink),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    context.tr('practice.writing.wordsLabel'),
                    style: NfTokens.body(size: NfFont.s13, color: t.inkMuted),
                  ),
                  Text(
                    '$_wordCountActual',
                    style: NfTokens.body(
                      size: NfFont.s13,
                      weight: NfTokens.bodyEmphasisWeight,
                      color: t.primaryText,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: NfSpace.s12),
          Container(
            height: 320,
            padding: const EdgeInsets.all(NfSpace.s12),
            decoration: BoxDecoration(
              color: t.raised,
              borderRadius: NfRadius.tileAll,
              border: Border.fromBorderSide(t.side),
            ),
            child: TextField(
              controller: _textController,
              maxLines: null,
              expands: true,
              cursorColor: t.primary,
              style: NfTokens.body(
                  size: NfFont.s15, color: t.ink, height: 1.7),
              decoration: InputDecoration(
                hintText: context.tr('practice.writing.hint'),
                hintStyle: NfTokens.body(size: NfFont.s145, color: t.inkFaint),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(height: NfSpace.s12),
          NfCard(
            padding: const EdgeInsets.all(NfSpace.s12),
            borderRadius: NfRadius.tileAll,
            backgroundColor: t.raised,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.auto_awesome, size: 18, color: t.primaryText),
                const SizedBox(width: NfSpace.s10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: NfTokens.body(
                          size: NfFont.s125, color: t.inkMuted, height: 1.5),
                      children: <TextSpan>[
                        TextSpan(
                          text: context.tr('practice.writing.tipsLabel'),
                          style: NfTokens.body(
                            size: NfFont.s125,
                            weight: NfTokens.bodyEmphasisWeight,
                            color: t.ink,
                          ),
                        ),
                        TextSpan(
                          text: context.tr('practice.writing.tipsBody'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 3: evaluation
  // ---------------------------------------------------------------------------

  Widget _buildEvaluationStep(NfTokens t) {
    final EvaluationData evaluation = _evaluation!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildScoreCard(t, evaluation),
        const SizedBox(height: NfSpace.s14),
        if (evaluation.strengths.isNotEmpty) ...<Widget>[
          _buildListCard(
            t,
            title: context.tr('practice.writing.strengths'),
            entries: evaluation.strengths,
            accent: t.correct,
            background: t.correctSoft,
            icon: Icons.check_circle_outline,
            entryIcon: Icons.check_rounded,
          ),
          const SizedBox(height: NfSpace.s14),
        ],
        if (evaluation.improvements.isNotEmpty) ...<Widget>[
          _buildListCard(
            t,
            title: context.tr('practice.writing.improvements'),
            entries: evaluation.improvements,
            accent: t.streakText,
            background: t.streakSoft,
            icon: Icons.lightbulb_outline,
            entryIcon: Icons.priority_high_rounded,
          ),
          const SizedBox(height: NfSpace.s14),
        ],
        _buildDetailedFeedback(t, evaluation),
        const SizedBox(height: NfSpace.s16),
        NfPrimaryButton(
          label: context.tr('practice.writing.anotherLevel'),
          icon: Icons.refresh_rounded,
          onPressed: _handleReset,
        ),
      ],
    );
  }

  Widget _buildScoreCard(NfTokens t, EvaluationData evaluation) {
    return NfCard(
      padding: const EdgeInsets.all(NfSpace.s22),
      child: Column(
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.streakSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.emoji_events_outlined,
                size: 32, color: t.streakText),
          ),
          const SizedBox(height: NfSpace.s12),
          Text(
            context.tr('practice.writing.greatWork'),
            textAlign: TextAlign.center,
            style: NfTokens.display(size: NfFont.s22, color: t.ink),
          ),
          const SizedBox(height: NfSpace.s10),
          // The score badge. s25 is the ceiling of the type scale, so the
          // number earns its prominence from the tinted disc instead of an
          // off-scale font size.
          Container(
            width: 88,
            height: 88,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.primarySoft,
              shape: BoxShape.circle,
              border: Border.fromBorderSide(t.sideOf(t.primary)),
            ),
            child: Text(
              '${evaluation.score}',
              style: NfTokens.display(size: NfFont.s25, color: t.primaryText),
            ),
          ),
          const SizedBox(height: NfSpace.s8),
          Text(
            context.tr('practice.writing.scoreOutOf'),
            style: NfTokens.body(size: NfFont.s135, color: t.inkMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildListCard(
    NfTokens t, {
    required String title,
    required List<String> entries,
    required Color accent,
    required Color background,
    required IconData icon,
    required IconData entryIcon,
  }) {
    return NfCard(
      backgroundColor: background,
      borderColor: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: NfSpace.s8),
              Text(
                title,
                style: NfTokens.display(size: NfFont.s16, color: t.ink),
              ),
            ],
          ),
          const SizedBox(height: NfSpace.s12),
          for (final String entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: NfSpace.s8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: NfSpace.s4),
                    child: Icon(entryIcon, size: 14, color: accent),
                  ),
                  const SizedBox(width: NfSpace.s8),
                  Expanded(
                    child: Text(
                      entry,
                      style: NfTokens.body(size: NfFont.s135, color: t.ink),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailedFeedback(NfTokens t, EvaluationData evaluation) {
    final List<(String, String)> sections = <(String, String)>[
      (context.tr('practice.mode.grammar'), evaluation.grammar),
      (context.tr('practice.writing.vocabulary'), evaluation.vocabulary),
      (context.tr('practice.writing.coherence'), evaluation.coherence),
      if (evaluation.contextRelevance.isNotEmpty)
        (
          context.tr('practice.writing.topicRelevance'),
          evaluation.contextRelevance
        ),
      (context.tr('practice.writing.overall'), evaluation.overall),
    ];

    return NfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.auto_awesome, size: 18, color: t.primaryText),
              const SizedBox(width: NfSpace.s8),
              Text(
                context.tr('practice.writing.detailedFeedback'),
                style: NfTokens.display(size: NfFont.s16, color: t.ink),
              ),
            ],
          ),
          const SizedBox(height: NfSpace.s12),
          for (int i = 0; i < sections.length; i++) ...<Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(NfSpace.s12),
              decoration: BoxDecoration(
                color: t.raised,
                borderRadius: NfRadius.tileAll,
                border: Border.fromBorderSide(t.side),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    sections[i].$1,
                    style: NfTokens.body(
                      size: NfFont.s125,
                      weight: NfTokens.bodyEmphasisWeight,
                      color: t.primaryText,
                    ),
                  ),
                  const SizedBox(height: NfSpace.s6),
                  Text(
                    sections[i].$2,
                    style: NfTokens.body(
                        size: NfFont.s135, color: t.ink, height: 1.5),
                  ),
                ],
              ),
            ),
            if (i < sections.length - 1) const SizedBox(height: NfSpace.s10),
          ],
        ],
      ),
    );
  }
}

/// Back arrow + title, same shape as the header the other pushed nf pages use.
class _NfPageHeader extends StatelessWidget {
  const _NfPageHeader({
    required this.title,
    required this.tokens,
    required this.onBack,
  });

  final String title;
  final NfTokens tokens;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
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
            onPressed: onBack,
            iconSize: NfFont.s22,
            color: tokens.ink,
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          ),
          const SizedBox(width: NfSpace.s4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NfTokens.display(size: NfFont.s20, color: tokens.ink),
            ),
          ),
        ],
      ),
    );
  }
}
