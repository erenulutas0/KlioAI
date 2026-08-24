import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/word.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/feedback_prompt_sheet.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_button.dart';
import '../widgets/nf_card.dart';
import '../widgets/nf_chip.dart';

/// What one guided session produced. Built by `NfSessionPage`, consumed here.
///
/// Grading is self-reported, so nothing in this object claims to be an
/// accuracy figure — it carries exactly what happened: how many cards were
/// graded, how the learner graded them, and what the grades paid out.
@immutable
class NfSessionResult {
  const NfSessionResult({
    required this.totalWords,
    required this.reviewedCount,
    required this.xpEarned,
    required this.hardCount,
    required this.goodCount,
    required this.easyCount,
    this.hardWord,
  });

  /// How many cards the session held.
  final int totalWords;

  /// How many of them were actually graded. Equal to [totalWords] for a
  /// finished session; the summary never shows for an abandoned one, but the
  /// two are kept separate so "n/total" is always a statement of record.
  final int reviewedCount;

  /// Sum of the per-review XP the legacy flow awards
  /// (`XPActionTypes.reviewComplete` per graded card — the award itself is
  /// made inside `AppStateProvider.submitWordReview`, this is the tally).
  final int xpEarned;

  final int hardCount;
  final int goodCount;
  final int easyCount;

  /// The first word the learner graded Hard, offered back as "worth another
  /// look". Null when nothing was graded Hard.
  final Word? hardWord;
}

/// The screen after the last card: what the session earned and what to revisit.
///
/// Replaces `SessionSummarySheet` (legacy `lib/widgets/session_summary_sheet.dart`
/// shown by `RepeatPage`) as a full page in the new design. It shows only
/// honestly-derived numbers: reviewed count, XP, streak, and the self-reported
/// grade split — never an invented accuracy percentage.
class NfSessionSummaryPage extends StatelessWidget {
  const NfSessionSummaryPage({
    super.key,
    required this.result,
    this.onContinue,
  });

  final NfSessionResult result;

  /// What the Continue button does. Defaults to popping this route, which
  /// lands back on the shell the session was started from.
  final VoidCallback? onContinue;

  /// The legacy flow asks for feedback right after the summary — the one
  /// moment the learner has just finished something and has an opinion. The
  /// service behind `maybeShow` owns the "how often" decision, so calling it
  /// on every Continue is safe.
  Future<void> _handleContinue(BuildContext context) async {
    await FeedbackPromptSheet.maybeShow(context);
    if (!context.mounted) {
      return;
    }
    final VoidCallback? custom = onContinue;
    if (custom != null) {
      custom();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final AppStateProvider appState = context.watch<AppStateProvider>();
    final int streak = _asInt(appState.userStats['streak']);
    final Word? hardWord = result.hardWord;

    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  NfSpace.s16,
                  NfSpace.s26,
                  NfSpace.s16,
                  NfSpace.s16,
                ),
                children: <Widget>[
                  _CompletionBadge(tokens: t),
                  const SizedBox(height: NfSpace.s16),
                  Text(
                    context.tr('session.summary.title'),
                    textAlign: TextAlign.center,
                    style: NfTokens.display(size: NfFont.s23, color: t.ink),
                  ),
                  const SizedBox(height: NfSpace.s8),
                  Text(
                    context.tr('session.summary.subtitle'),
                    textAlign: TextAlign.center,
                    style: NfTokens.body(size: NfFont.s14, color: t.inkMuted),
                  ),
                  const SizedBox(height: NfSpace.s20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: _SummaryTile(
                          icon: LucideIcons.zap,
                          value: '+${result.xpEarned}',
                          label: context.tr('session.summary.xp'),
                          accent: _TileAccent.primary,
                        ),
                      ),
                      const SizedBox(width: NfSpace.s10),
                      Expanded(
                        child: _SummaryTile(
                          icon: LucideIcons.layers,
                          value:
                              '${result.reviewedCount}/${result.totalWords}',
                          label: context.tr('session.summary.items'),
                          accent: _TileAccent.neutral,
                        ),
                      ),
                      const SizedBox(width: NfSpace.s10),
                      Expanded(
                        child: _SummaryTile(
                          icon: LucideIcons.flame,
                          value: '$streak',
                          label: context.tr('session.summary.streak'),
                          accent: streak > 0
                              ? _TileAccent.streak
                              : _TileAccent.neutral,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: NfSpace.s16),
                  _GradeSplitCard(result: result),
                  if (hardWord != null) ...<Widget>[
                    const SizedBox(height: NfSpace.s16),
                    _HardWordCard(word: hardWord),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NfSpace.s16,
                NfSpace.s8,
                NfSpace.s16,
                NfSpace.s16,
              ),
              child: NfPrimaryButton(
                label: context.tr('common.continue'),
                icon: LucideIcons.arrowRight,
                onPressed: () => _handleContinue(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

/// The big green check. A bordered circle rather than confetti — this design
/// celebrates with colour and type, not effects.
class _CompletionBadge extends StatelessWidget {
  const _CompletionBadge({required this.tokens});

  static const double _diameter = 84;

  final NfTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: _diameter,
        height: _diameter,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.correctSoft,
          shape: BoxShape.circle,
          border: Border.fromBorderSide(tokens.sideOf(tokens.correct)),
        ),
        child: Icon(LucideIcons.check, size: 40, color: tokens.correct),
      ),
    );
  }
}

enum _TileAccent { primary, streak, neutral }

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.accent,
  });

  final IconData icon;
  final String value;
  final String label;
  final _TileAccent accent;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final Color iconColor;
    switch (accent) {
      case _TileAccent.primary:
        iconColor = t.primaryText;
        break;
      case _TileAccent.streak:
        iconColor = t.streakText;
        break;
      case _TileAccent.neutral:
        iconColor = t.inkMuted;
        break;
    }

    return NfCard(
      padding: const EdgeInsets.all(NfSpace.s12),
      borderRadius: NfRadius.tileAll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(height: NfSpace.s10),
          Text(
            value,
            style: NfTokens.display(size: NfFont.s20, color: t.ink),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: NfSpace.s4),
          Text(
            label,
            style: NfTokens.body(size: NfFont.s115, color: t.inkMuted),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// The self-reported grade split, shown as what it is — "how you rated them" —
/// never dressed up as an accuracy score.
class _GradeSplitCard extends StatelessWidget {
  const _GradeSplitCard({required this.result});

  final NfSessionResult result;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return NfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.tr('session.summary.ratings'),
            style: NfTokens.display(size: NfFont.s16, color: t.ink),
          ),
          const SizedBox(height: NfSpace.s12),
          Wrap(
            spacing: NfSpace.s8,
            runSpacing: NfSpace.s8,
            children: <Widget>[
              NfChip(
                label: '${result.hardCount} ${context.tr('session.grade.hard')}',
                icon: LucideIcons.rotateCcw,
                variant: NfChipVariant.wrong,
              ),
              NfChip(
                label: '${result.goodCount} ${context.tr('session.grade.good')}',
                icon: LucideIcons.check,
                variant: NfChipVariant.selected,
              ),
              NfChip(
                label: '${result.easyCount} ${context.tr('session.grade.easy')}',
                icon: LucideIcons.checkCheck,
                variant: NfChipVariant.correct,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The one word the learner said was hard, offered back with its meaning in
/// the open — after the session there is nothing left to recall.
class _HardWordCard extends StatelessWidget {
  const _HardWordCard({required this.word});

  final Word word;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return NfCard(
      backgroundColor: t.streakSoft,
      borderColor: t.streak,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(LucideIcons.eye, size: 16, color: t.streakText),
              const SizedBox(width: NfSpace.s6),
              Expanded(
                child: Text(
                  context.tr('session.summary.worthReview'),
                  style: NfTokens.body(
                    size: NfFont.s125,
                    weight: NfTokens.bodyEmphasisWeight,
                    color: t.streakText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: NfSpace.s10),
          Text(
            word.englishWord,
            style: NfTokens.display(size: NfFont.s20, color: t.ink),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: NfSpace.s4),
          Text(
            word.displayMeaning,
            style: NfTokens.body(size: NfFont.s14, color: t.inkMuted),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
