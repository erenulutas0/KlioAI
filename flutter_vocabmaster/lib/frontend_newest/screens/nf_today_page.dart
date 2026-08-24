import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/language_profile.dart';
import '../../models/sentence_view_model.dart';
import '../../models/voice_model.dart';
import '../../models/word.dart';
import '../../providers/app_state_provider.dart';
import '../../services/learning_language_service.dart';
import '../../services/local_database_service.dart';
import '../../services/xp_manager.dart';
import '../services/nf_tutor_voice.dart';
import '../theme/nf_theme_scope.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_button.dart';
import '../widgets/nf_card.dart';
import '../widgets/nf_chip.dart';
import '../widgets/nf_progress.dart';

/// How many XP ledger rows to scan when working out what the learner already
/// did today. Rows come back newest-first and a heavy day is a few dozen rows,
/// so this reaches back several days — far more than "today" needs.
const int _kXpHistoryScan = 200;

/// Used only when `userStats['dailyGoal']` is missing or unreadable. Matches
/// the provider's own fallback (`AppStateProvider._loadDailyGoal`), so the plan
/// and the goal celebration cannot disagree even in that case.
const int _kDefaultDailyGoal = 5;

/// How many sentences a quick translation set contains.
const int _kTranslationSetSize = 5;

/// Fallback review target when the deck carries no SRS schedule at all (a fresh
/// install, or a backend that omits `nextReviewDate`). Mirrors what
/// `RepeatPage` does: rather than claim "nothing due", offer a sane batch.
const int _kUnscheduledReviewTarget = 10;

/// Rough per-item pacing used for the "about N minutes" pill. Deliberately
/// generous — a plan that overruns its own estimate is worse than one that
/// finishes early.
const double _kMinutesPerReviewCard = 0.25;
const double _kMinutesPerNewWord = 0.5;
const double _kMinutesPerTranslation = 0.7;

const List<String> _kFallbackWeekdayLetters = <String>[
  'M',
  'T',
  'W',
  'T',
  'F',
  'S',
  'S',
];

/// The home tab of the new frontend.
///
/// Everything on this page is derived from [AppStateProvider] plus one read of
/// the local XP ledger; the page owns no learner data of its own. Navigation is
/// handed out through [onStartSession] / [onOpenTutor] so that the page never
/// has to know which shell is hosting it.
class NfTodayPage extends StatefulWidget {
  const NfTodayPage({
    super.key,
    this.onStartSession,
    this.onOpenTutor,
    this.onAddFirstWord,
  });

  /// Fired by the "Start session" button. Null leaves the button disabled,
  /// which is the honest state while the shell has nowhere to send the learner.
  final VoidCallback? onStartSession;

  /// Fired by the tutor card's button.
  final VoidCallback? onOpenTutor;

  /// Fired when the learner has no words yet and the plan button becomes "Add
  /// your first word".
  final VoidCallback? onAddFirstWord;

  @override
  State<NfTodayPage> createState() => _NfTodayPageState();
}

class _NfTodayPageState extends State<NfTodayPage> {
  /// `actionId` -> times that action was awarded XP today. Empty means "not
  /// read yet / unreadable", which callers must treat as *no signal* rather
  /// than as "nothing done" — a wrong green check is worse than no check.
  Map<String, int> _todayXpActions = const <String, int>{};

  /// Last [AppStateProvider.xpGainSeq] the ledger was read at. The ledger only
  /// changes when XP is awarded, so this is the exact edge to re-read on.
  int _lastSeenXpSeq = -1;

  @override
  void initState() {
    super.initState();
    // The tutor card names the speaker. Today can be the first tab a learner
    // sees, so it must not wait for the tutor tab to read the stored choice.
    unawaited(NfTutorVoice.ensureLoaded());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final int seq = context.read<AppStateProvider>().xpGainSeq;
    if (seq != _lastSeenXpSeq) {
      _lastSeenXpSeq = seq;
      _loadTodayActions();
    }
  }

  Future<void> _loadTodayActions() async {
    try {
      final List<Map<String, dynamic>> rows =
          await LocalDatabaseService().getXpHistory(limit: _kXpHistoryScan);
      final DateTime today = DateTime.now();
      final Map<String, int> counts = <String, int>{};
      for (final Map<String, dynamic> row in rows) {
        final DateTime? at =
            DateTime.tryParse(row['createdAt']?.toString() ?? '');
        if (at == null || !DateUtils.isSameDay(at, today)) {
          continue;
        }
        final String id = row['actionId']?.toString() ?? '';
        if (id.isEmpty) {
          continue;
        }
        counts[id] = (counts[id] ?? 0) + 1;
      }
      if (!mounted) {
        return;
      }
      setState(() => _todayXpActions = counts);
    } catch (error) {
      // The ledger is a nicety, not a dependency: without it the plan simply
      // shows XP rewards instead of completion checks.
      debugPrint('NfTodayPage: XP ledger unavailable ($error)');
    }
  }

  /// Opens the language-profile switcher. The sheet lives above the shell's
  /// navigator, so it wraps itself in [NfThemeScope] the same way pushed nf
  /// routes do — without it the sheet would follow the device brightness
  /// instead of the learner's in-app choice.
  void _openLanguageSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: NfTokens.transparent,
      builder: (_) => const NfThemeScope(child: _LanguageSheet()),
    );
  }

  Future<void> _refresh() async {
    final AppStateProvider appState = context.read<AppStateProvider>();
    await Future.wait(<Future<void>>[
      appState.refreshWords(),
      appState.refreshUserData(),
    ]);
    await _loadTodayActions();
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final AppStateProvider appState = context.watch<AppStateProvider>();
    final _TodayModel model = _TodayModel.from(appState, _todayXpActions);

    return ColoredBox(
      color: t.ground,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: t.primary,
          backgroundColor: t.surface,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              NfSpace.s16,
              NfSpace.s18,
              NfSpace.s16,
              NfSpace.s26,
            ),
            children: <Widget>[
              _GreetingRow(
                name: model.userName,
                streak: model.streak,
                cefrLevel: model.cefrLevel,
                targetLanguage: model.targetLanguage,
                onOpenLanguages: _openLanguageSheet,
              ),
              const SizedBox(height: NfSpace.s20),
              _WeekStrip(
                completed: model.weekCompleted,
                todayIndex: model.todayIndex,
              ),
              const SizedBox(height: NfSpace.s16),
              _PlanCard(
                model: model,
                onStartSession: widget.onStartSession,
                onAddFirstWord: widget.onAddFirstWord,
              ),
              const SizedBox(height: NfSpace.s16),
              _TutorCard(onOpenTutor: widget.onOpenTutor),
              const SizedBox(height: NfSpace.s16),
              _StatRow(model: model),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DERIVED STATE
// ═══════════════════════════════════════════════════════════════════════════

/// Everything the page shows, derived once per build from the providers.
///
/// Keeping the arithmetic here means the widgets below are pure layout, and the
/// rules ("when is a task done?") live in one readable place.
@immutable
class _TodayModel {
  const _TodayModel({
    required this.isLoading,
    required this.userName,
    required this.streak,
    required this.cefrLevel,
    required this.targetLanguage,
    required this.weekCompleted,
    required this.todayIndex,
    required this.reviewTarget,
    required this.reviewDone,
    required this.hasWords,
    required this.newTarget,
    required this.learnedToday,
    required this.learnDone,
    required this.translationTarget,
    required this.translationDone,
    required this.wordsKept,
    required this.weeklyXp,
    required this.level,
    required this.levelProgress,
  });

  factory _TodayModel.from(
    AppStateProvider appState,
    Map<String, int> todayXpActions,
  ) {
    final List<Word> words = appState.allWords;
    final Map<String, dynamic> stats = appState.userStats;

    // ── Review ─────────────────────────────────────────────────────────────
    // A word counts as due once its scheduled date has arrived; anything with
    // no schedule cannot be judged, so a deck without any schedule falls back
    // to a fixed batch instead of pretending the learner is caught up.
    final DateTime endOfToday = DateUtils.dateOnly(DateTime.now())
        .add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1));
    int scheduled = 0;
    int due = 0;
    for (final Word word in words) {
      final DateTime? next = word.nextReviewDate;
      if (next == null) {
        continue;
      }
      scheduled++;
      if (!next.isAfter(endOfToday)) {
        due++;
      }
    }
    final bool hasSchedule = scheduled > 0;
    final int reviewTarget = hasSchedule
        ? due
        : math.min(words.length, _kUnscheduledReviewTarget);
    final bool reviewDone = hasSchedule && due == 0;

    // ── New words ──────────────────────────────────────────────────────────
    // The target is the learner's configured daily goal (5, 10 or 20 — see
    // `AppStateProvider.dailyGoalOptions`), never the size of the generated
    // daily-words set. The provider fires its goal celebration at this exact
    // number, so anything else here would put a green check on the plan while
    // the app still considered the day unfinished.
    //
    // `learnedToday` counts every word added today whatever the source, which
    // is exactly what "learn N new words" asks for and what the provider
    // compares against the goal.
    final int storedGoal = _asInt(
      stats['dailyGoal'],
      fallback: _kDefaultDailyGoal,
    );
    final int newTarget = storedGoal > 0 ? storedGoal : _kDefaultDailyGoal;
    final int learnedToday = _asInt(stats['learnedToday']);

    // ── Translation ────────────────────────────────────────────────────────
    // The set is built from sentences attached to the learner's own words, so
    // practice sentences (word == null) do not count towards it.
    int ownSentences = 0;
    for (final SentenceViewModel sentence in appState.allSentences) {
      if (sentence.word != null) {
        ownSentences++;
      }
    }
    final int translationTarget =
        math.min(ownSentences, _kTranslationSetSize);
    // The only record that a translation exercise happened is the XP it paid
    // out, so an unreadable ledger leaves this false and the row keeps its XP
    // label.
    final int translationsToday =
        todayXpActions[XPActionTypes.translationComplete.id] ?? 0;

    // ── Week strip ─────────────────────────────────────────────────────────
    final int todayIndex = DateTime.now().weekday - 1;
    final List<Map<String, dynamic>> activity = appState.weeklyActivity;
    final List<bool> weekCompleted;
    if (activity.length == 7) {
      weekCompleted = <bool>[
        for (final Map<String, dynamic> day in activity)
          day['learned'] == true || _asInt(day['count']) > 0,
      ];
    } else {
      // TODO(data): AppStateProvider.weeklyActivity is the only per-day history
      //   the app keeps, and it is empty until user data has loaded. Until a
      //   real practice log exists, mark today from the streak and leave the
      //   rest muted rather than inventing days.
      weekCompleted = List<bool>.generate(
        7,
        (int i) => i == todayIndex && _asInt(stats['streak']) > 0,
      );
    }

    final int xp = _asInt(stats['xp']);

    // The chip names what the learner is actually studying: the active
    // language profile. Until profiles have loaded (or against a backend that
    // does not serve them) it falls back to the app-wide constants, which is
    // exactly what the whole app means in that state.
    final LanguageProfile? profile = appState.activeProfile;

    return _TodayModel(
      isLoading: !appState.isInitialized ||
          (appState.isLoadingWords && words.isEmpty),
      userName: appState.userName.trim(),
      streak: _asInt(stats['streak']),
      cefrLevel: profile?.level ?? LearningLanguageService.englishLevel,
      targetLanguage:
          profile?.targetLanguage ?? LearningLanguageService.targetLanguage,
      weekCompleted: weekCompleted,
      todayIndex: todayIndex,
      reviewTarget: reviewTarget,
      reviewDone: reviewDone,
      hasWords: words.isNotEmpty,
      newTarget: newTarget,
      learnedToday: learnedToday,
      learnDone: newTarget > 0 && learnedToday >= newTarget,
      translationTarget: translationTarget,
      translationDone: translationTarget > 0 &&
          translationsToday >= translationTarget,
      wordsKept: words.length,
      weeklyXp: _asInt(stats['weeklyXP']),
      level: math.max(1, _asInt(stats['level'], fallback: 1)),
      levelProgress: appState.xpManager.levelProgress(xp),
    );
  }

  final bool isLoading;
  final String userName;
  final int streak;
  final String cefrLevel;

  /// The active profile's target language ("English", …), used with
  /// [cefrLevel] to label the language chip in the header.
  final String targetLanguage;

  /// Seven flags, Monday first.
  final List<bool> weekCompleted;
  final int todayIndex;

  final int reviewTarget;
  final bool reviewDone;
  final bool hasWords;

  final int newTarget;
  final int learnedToday;
  final bool learnDone;

  final int translationTarget;
  final bool translationDone;

  final int wordsKept;
  final int weeklyXp;
  final int level;
  final double levelProgress;

  bool get allDone => reviewDone && learnDone && translationDone;

  /// XP the learner stands to earn, taken from the same table that will
  /// actually pay it out. `max(target, 1)` keeps a blocked row showing the
  /// per-item rate instead of a meaningless "+0 XP".
  int get reviewXp =>
      XPActionTypes.reviewComplete.xpAmount * math.max(reviewTarget, 1);
  int get newWordsXp =>
      XPActionTypes.dailyWordLearn.xpAmount * math.max(newTarget, 1);
  int get translationXp =>
      XPActionTypes.translationComplete.xpAmount *
      math.max(translationTarget, 1);

  /// Minutes left in the plan, ignoring what is already finished. Zero means
  /// there is nothing outstanding, and the duration pill hides itself.
  int get remainingMinutes {
    double minutes = 0;
    if (!reviewDone) {
      minutes += reviewTarget * _kMinutesPerReviewCard;
    }
    if (!learnDone) {
      minutes +=
          math.max(0, newTarget - learnedToday) * _kMinutesPerNewWord;
    }
    if (!translationDone) {
      minutes += translationTarget * _kMinutesPerTranslation;
    }
    return math.min(60, minutes.ceil());
  }
}

/// Localizes a stored language name ("English", "en", "Turkish", …) through
/// the existing `language.*` keys. A language the normalizer does not know is
/// shown as stored rather than hidden — the learner named it, so it must
/// appear.
String _localizedLanguageName(BuildContext context, String raw) {
  final String trimmed = raw.trim();
  final String canonical =
      LearningLanguageService.normalizeSupported(trimmed, trimmed);
  final String? key = switch (canonical) {
    'English' => 'language.english',
    'German' => 'language.german',
    'Spanish' => 'language.spanish',
    'Portuguese' => 'language.portuguese',
    'Indonesian' => 'language.indonesian',
    'French' => 'language.french',
    'Turkish' => 'language.turkish',
    _ => null,
  };
  return key == null ? canonical : context.tr(key);
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

// ═══════════════════════════════════════════════════════════════════════════
// GREETING
// ═══════════════════════════════════════════════════════════════════════════

class _GreetingRow extends StatelessWidget {
  const _GreetingRow({
    required this.name,
    required this.streak,
    required this.cefrLevel,
    required this.targetLanguage,
    required this.onOpenLanguages,
  });

  final String name;
  final int streak;
  final String cefrLevel;
  final String targetLanguage;

  /// Fired by the language chip; opens the profile switcher sheet.
  final VoidCallback onOpenLanguages;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final String welcome = context.tr('home.welcome');
    final String greeting = name.isEmpty ? welcome : '$welcome, $name';

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            greeting,
            style: NfTokens.display(size: NfFont.s23, color: t.ink),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: NfSpace.s10),
        NfChip(
          label: '$streak',
          icon: LucideIcons.flame,
          // A cold streak stays neutral: amber is a reward, not a label.
          variant: streak > 0
              ? NfChipVariant.streak
              : NfChipVariant.unselected,
          dense: true,
        ),
        const SizedBox(width: NfSpace.s6),
        NfChip(
          label: '${_localizedLanguageName(context, targetLanguage)}'
              ' · $cefrLevel',
          icon: LucideIcons.globe,
          variant: NfChipVariant.selected,
          dense: true,
          onTap: onOpenLanguages,
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LANGUAGE SWITCHER SHEET
// ═══════════════════════════════════════════════════════════════════════════

/// Bottom sheet listing the learner's language profiles.
///
/// Tapping an inactive profile calls [AppStateProvider.switchProfile] and
/// closes the sheet once the server has confirmed; the provider then reloads
/// words, daily words and stats, so the page behind updates by itself. A
/// failed switch keeps the sheet open and says so inline — a snackbar would
/// appear behind the sheet.
class _LanguageSheet extends StatefulWidget {
  const _LanguageSheet();

  @override
  State<_LanguageSheet> createState() => _LanguageSheetState();
}

class _LanguageSheetState extends State<_LanguageSheet> {
  /// Profile id a switch is in flight for; only that row shows the spinner.
  int? _pendingId;
  bool _failed = false;

  Future<void> _switchTo(LanguageProfile profile) async {
    final AppStateProvider appState = context.read<AppStateProvider>();
    if (appState.isSwitchingProfile) {
      return;
    }
    if (profile.isActive) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _pendingId = profile.id;
      _failed = false;
    });
    final bool ok = await appState.switchProfile(profile.id);
    if (!mounted) {
      return;
    }
    setState(() => _pendingId = null);
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final AppStateProvider appState = context.watch<AppStateProvider>();
    final List<LanguageProfile> profiles = appState.languageProfiles;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(NfRadius.card),
          ),
          border: Border.fromBorderSide(t.sideOf(t.border)),
        ),
        padding: const EdgeInsets.fromLTRB(
          NfSpace.s16,
          NfSpace.s10,
          NfSpace.s16,
          NfSpace.s16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: t.border,
                  borderRadius: NfRadius.pillAll,
                ),
              ),
            ),
            const SizedBox(height: NfSpace.s14),
            Text(
              context.tr('home.language.sheetTitle'),
              style: NfTokens.display(size: NfFont.s18, color: t.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: NfSpace.s4),
            Text(
              context.tr('home.language.sheetSubtitle'),
              style: NfTokens.body(size: NfFont.s125, color: t.inkMuted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: NfSpace.s16),
            for (final LanguageProfile profile in profiles) ...<Widget>[
              _LanguageRow(
                profile: profile,
                pending: _pendingId == profile.id,
                enabled: !appState.isSwitchingProfile,
                onTap: () => _switchTo(profile),
              ),
              const SizedBox(height: NfSpace.s10),
            ],
            const _AddLanguageRow(),
            if (_failed) ...<Widget>[
              const SizedBox(height: NfSpace.s12),
              Row(
                children: <Widget>[
                  Icon(LucideIcons.alertCircle, size: 16, color: t.wrong),
                  const SizedBox(width: NfSpace.s6),
                  Expanded(
                    child: Text(
                      context.tr('home.language.switchFailed'),
                      style: NfTokens.body(size: NfFont.s125, color: t.wrong),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.profile,
    required this.pending,
    required this.enabled,
    required this.onTap,
  });

  static const double _tileSize = 40;

  final LanguageProfile profile;

  /// True while [AppStateProvider.switchProfile] runs for *this* profile.
  final bool pending;

  /// False while any switch is in flight, so a second row cannot start one.
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final bool active = profile.isActive;

    final Widget trailing;
    if (pending) {
      trailing = SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: NfStroke.border,
          color: t.primary,
        ),
      );
    } else if (active) {
      trailing = NfChip(
        label: context.tr('home.language.active'),
        icon: LucideIcons.check,
        variant: NfChipVariant.selected,
        dense: true,
      );
    } else {
      trailing = Icon(LucideIcons.chevronRight, size: 18, color: t.inkFaint);
    }

    return NfCard(
      onTap: enabled ? onTap : null,
      padding: const EdgeInsets.all(NfSpace.s12),
      borderRadius: NfRadius.tileAll,
      backgroundColor: active ? t.primarySoft : t.surface,
      borderColor: active ? t.primary : t.border,
      child: Row(
        children: <Widget>[
          Container(
            width: _tileSize,
            height: _tileSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? t.surface : t.raised,
              borderRadius: NfRadius.iconTileAll,
              border: Border.fromBorderSide(
                t.sideOf(active ? t.primary : t.border),
              ),
            ),
            child: Icon(
              LucideIcons.globe,
              size: 20,
              color: active ? t.primaryText : t.inkMuted,
            ),
          ),
          const SizedBox(width: NfSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _localizedLanguageName(context, profile.targetLanguage),
                  style: NfTokens.body(
                    size: NfFont.s15,
                    weight: NfTokens.bodyEmphasisWeight,
                    color: t.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: NfSpace.s4),
                Text(
                  profile.level,
                  style: NfTokens.body(size: NfFont.s125, color: t.inkMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: NfSpace.s10),
          trailing,
        ],
      ),
    );
  }
}

/// The "Add a language" row. Deliberately inert: creating a second profile is
/// a later phase, and a dead-looking row is more honest than a button that
/// apologizes when tapped.
class _AddLanguageRow extends StatelessWidget {
  const _AddLanguageRow();

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return NfCard(
      padding: const EdgeInsets.all(NfSpace.s12),
      borderRadius: NfRadius.tileAll,
      child: Row(
        children: <Widget>[
          Container(
            width: _LanguageRow._tileSize,
            height: _LanguageRow._tileSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.raised,
              borderRadius: NfRadius.iconTileAll,
              border: Border.fromBorderSide(t.sideOf(t.border)),
            ),
            child: Icon(LucideIcons.plus, size: 20, color: t.inkFaint),
          ),
          const SizedBox(width: NfSpace.s12),
          Expanded(
            child: Text(
              context.tr('home.language.addSoon'),
              style: NfTokens.body(
                size: NfFont.s15,
                weight: NfTokens.bodyEmphasisWeight,
                color: t.inkFaint,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: NfSpace.s10),
          NfChip(
            label: context.tr('home.language.comingSoon'),
            dense: true,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WEEK STRIP
// ═══════════════════════════════════════════════════════════════════════════

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.completed,
    required this.todayIndex,
  });

  final List<bool> completed;
  final int todayIndex;

  /// Single-letter weekday labels for the current locale, rotated so the week
  /// starts on Monday like [AppStateProvider.weeklyActivity] does.
  static List<String> _letters(BuildContext context) {
    final MaterialLocalizations? l10n =
        Localizations.of<MaterialLocalizations>(context, MaterialLocalizations);
    if (l10n == null) {
      return _kFallbackWeekdayLetters;
    }
    // `narrowWeekdays` is Sunday-first.
    return List<String>.generate(7, (int i) => l10n.narrowWeekdays[(i + 1) % 7]);
  }

  @override
  Widget build(BuildContext context) {
    final List<String> letters = _letters(context);

    return NfCard(
      padding: const EdgeInsets.symmetric(
        horizontal: NfSpace.s10,
        vertical: NfSpace.s14,
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < 7; i++)
            Expanded(
              child: _DayMark(
                letter: letters[i],
                done: i < completed.length && completed[i],
                isToday: i == todayIndex,
              ),
            ),
        ],
      ),
    );
  }
}

class _DayMark extends StatelessWidget {
  const _DayMark({
    required this.letter,
    required this.done,
    required this.isToday,
  });

  static const double _diameter = 34;

  final String letter;
  final bool done;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    final Widget? mark = done
        ? Icon(
            LucideIcons.check,
            size: 18,
            color: isToday ? t.primaryText : t.primaryInk,
          )
        : null;

    final Widget circle;
    if (isToday) {
      // Today is always the dashed ring so it stays findable; finishing it
      // fills the ring rather than replacing the marker.
      circle = CustomPaint(
        painter: _DashedRingPainter(
          color: t.primary,
          fill: done ? t.primarySoft : null,
        ),
        child: SizedBox(
          width: _diameter,
          height: _diameter,
          child: Center(child: mark),
        ),
      );
    } else {
      circle = Container(
        width: _diameter,
        height: _diameter,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: done ? t.streak : t.raised,
          shape: BoxShape.circle,
          border: Border.fromBorderSide(
            t.sideOf(done ? t.streak : t.border),
          ),
        ),
        child: mark,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          letter,
          style: NfTokens.body(
            size: NfFont.s115,
            weight: NfTokens.bodyEmphasisWeight,
            color: isToday ? t.primaryText : t.inkFaint,
            height: 1,
          ),
          maxLines: 1,
          overflow: TextOverflow.clip,
        ),
        const SizedBox(height: NfSpace.s8),
        circle,
      ],
    );
  }
}

/// The dashed outline that marks today. Drawn rather than composed because
/// Flutter has no dashed border, and the direction forbids a shadow or glow
/// standing in for it.
class _DashedRingPainter extends CustomPainter {
  const _DashedRingPainter({required this.color, this.fill});

  static const int _dashCount = 10;
  static const double _gapFraction = 0.42;

  final Color color;
  final Color? fill;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius =
        (math.min(size.width, size.height) - NfStroke.border) / 2;
    if (radius <= 0) {
      return;
    }

    final Color? fillColor = fill;
    if (fillColor != null) {
      canvas.drawCircle(center, radius, Paint()..color = fillColor);
    }

    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = NfStroke.border
      ..strokeCap = StrokeCap.round;

    final Rect box = Rect.fromCircle(center: center, radius: radius);
    const double step = 2 * math.pi / _dashCount;
    for (int i = 0; i < _dashCount; i++) {
      canvas.drawArc(box, i * step, step * (1 - _gapFraction), false, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRingPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.fill != fill;
}

// ═══════════════════════════════════════════════════════════════════════════
// TODAY'S PLAN
// ═══════════════════════════════════════════════════════════════════════════

/// Which token family a plan row wears. Stored as an enum so the row resolves
/// colours from the palette in scope instead of carrying a [Color] around.
enum _Accent { primary, streak, done }

@immutable
class _AccentColors {
  const _AccentColors(this.fill, this.line, this.ink);

  final Color fill;
  final Color line;
  final Color ink;

  static _AccentColors of(NfTokens t, _Accent accent) {
    switch (accent) {
      case _Accent.primary:
        return _AccentColors(t.primarySoft, t.primary, t.primaryText);
      case _Accent.streak:
        return _AccentColors(t.streakSoft, t.streak, t.streakText);
      case _Accent.done:
        return _AccentColors(t.correctSoft, t.correct, t.correct);
    }
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.model,
    this.onStartSession,
    this.onAddFirstWord,
  });

  final _TodayModel model;
  final VoidCallback? onStartSession;

  /// Where an empty deck sends the learner. A review session over no words is
  /// two navigation steps to a "you have no words" screen, so the card offers
  /// the only action that can actually move them forward instead.
  final VoidCallback? onAddFirstWord;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final int minutes = model.remainingMinutes;

    return NfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  // TODO(i18n): needs a key
                  "Today's plan",
                  style: NfTokens.display(size: NfFont.s18, color: t.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!model.isLoading && minutes > 0) ...<Widget>[
                const SizedBox(width: NfSpace.s10),
                NfChip(
                  // TODO(i18n): needs a key
                  label: '~$minutes min',
                  icon: LucideIcons.clock,
                  dense: true,
                ),
              ],
            ],
          ),
          const SizedBox(height: NfSpace.s16),
          if (model.isLoading)
            const _PlanSkeleton()
          else ...<Widget>[
            _PlanRow(
              icon: LucideIcons.repeat,
              accent: _Accent.primary,
              title: model.reviewTarget > 0
                  // TODO(i18n): needs a key
                  ? 'Review ${model.reviewTarget} words'
                  // TODO(i18n): needs a key
                  : 'Review words',
              subtitle: _reviewSubtitle(),
              xpReward: model.reviewXp,
              done: model.reviewDone,
            ),
            const SizedBox(height: NfSpace.s14),
            _PlanRow(
              icon: LucideIcons.sparkles,
              accent: _Accent.streak,
              // TODO(i18n): needs a key
              title: 'Learn ${model.newTarget} new words',
              subtitle: _learnSubtitle(),
              xpReward: model.newWordsXp,
              done: model.learnDone,
            ),
            const SizedBox(height: NfSpace.s14),
            _PlanRow(
              icon: LucideIcons.languages,
              accent: _Accent.primary,
              // TODO(i18n): needs a key
              title: 'Quick translation set',
              subtitle: _translationSubtitle(),
              xpReward: model.translationXp,
              done: model.translationDone,
            ),
          ],
          const SizedBox(height: NfSpace.s18),
          if (model.allDone) ...<Widget>[
            Row(
              children: <Widget>[
                Icon(LucideIcons.checkCheck, size: 16, color: t.correct),
                const SizedBox(width: NfSpace.s6),
                Expanded(
                  child: Text(
                    // TODO(i18n): needs a key
                    'Plan finished — anything else is a bonus.',
                    style: NfTokens.body(size: NfFont.s13, color: t.correct),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: NfSpace.s12),
          ],
          if (model.isLoading)
            const NfPrimaryButton(
              // TODO(i18n): needs a key
              label: 'Start session',
              icon: LucideIcons.play,
              onPressed: null,
            )
          else if (!model.hasWords)
            // A session cannot be started over a deck that does not exist. The
            // review flow does survive it, but only by dead-ending on an empty
            // screen two pushes away, so the first thing a new learner needs is
            // offered here instead.
            NfPrimaryButton(
              // TODO(i18n): needs a key
              label: 'Add your first word',
              icon: LucideIcons.plus,
              onPressed: onAddFirstWord,
            )
          else
            NfPrimaryButton(
              // TODO(i18n): needs a key
              label: 'Start session',
              icon: LucideIcons.play,
              onPressed: onStartSession,
            ),
        ],
      ),
    );
  }

  String _reviewSubtitle() {
    if (!model.hasWords) {
      // TODO(i18n): needs a key
      return 'Add your first word to start reviewing';
    }
    if (model.reviewDone) {
      // TODO(i18n): needs a key
      return 'Nothing due — your deck is ahead of schedule';
    }
    // TODO(i18n): needs a key
    return 'The ones your memory is about to drop';
  }

  String _learnSubtitle() {
    if (!model.learnDone && model.learnedToday > 0) {
      // TODO(i18n): needs a key
      return '${model.learnedToday} of ${model.newTarget} added today';
    }
    // TODO(i18n): needs a key
    return "Fresh picks from today's word set";
  }

  String _translationSubtitle() {
    if (model.translationTarget == 0) {
      // TODO(i18n): needs a key
      return 'Add sentences to your words to unlock this';
    }
    // TODO(i18n): needs a key
    return '${model.translationTarget} sentences built from your own words';
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.xpReward,
    required this.done,
  });

  static const double _tileSize = 40;

  final IconData icon;
  final _Accent accent;
  final String title;
  final String subtitle;
  final int xpReward;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final _AccentColors colors =
        _AccentColors.of(t, done ? _Accent.done : accent);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          width: _tileSize,
          height: _tileSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.fill,
            borderRadius: NfRadius.iconTileAll,
            border: Border.fromBorderSide(t.sideOf(colors.line)),
          ),
          child: Icon(icon, size: 20, color: colors.ink),
        ),
        const SizedBox(width: NfSpace.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                style: NfTokens.body(
                  size: NfFont.s15,
                  weight: NfTokens.bodyEmphasisWeight,
                  color: t.ink,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: NfSpace.s4),
              Text(
                subtitle,
                style: NfTokens.body(size: NfFont.s125, color: t.inkMuted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: NfSpace.s10),
        if (done)
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.correctSoft,
              shape: BoxShape.circle,
              border: Border.fromBorderSide(t.sideOf(t.correct)),
            ),
            child: Icon(LucideIcons.check, size: 15, color: t.correct),
          )
        else
          Text(
            // TODO(i18n): needs a key
            '+$xpReward XP',
            style: NfTokens.display(size: NfFont.s135, color: t.primaryText),
          ),
      ],
    );
  }
}

/// Placeholder rows for the moment before words and stats have loaded. Flat
/// blocks, no shimmer — the direction has no gradients to shimmer with.
class _PlanSkeleton extends StatelessWidget {
  const _PlanSkeleton();

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    Widget bar(double widthFactor, double height) {
      return FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: widthFactor,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: t.raised,
            borderRadius: NfRadius.pillAll,
          ),
        ),
      );
    }

    return Column(
      children: <Widget>[
        for (int i = 0; i < 3; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: NfSpace.s14),
          Row(
            children: <Widget>[
              Container(
                width: _PlanRow._tileSize,
                height: _PlanRow._tileSize,
                decoration: BoxDecoration(
                  color: t.raised,
                  borderRadius: NfRadius.iconTileAll,
                ),
              ),
              const SizedBox(width: NfSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    bar(0.55, NfFont.s14),
                    const SizedBox(height: NfSpace.s8),
                    bar(0.8, NfFont.s105),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TUTOR
// ═══════════════════════════════════════════════════════════════════════════

class _TutorCard extends StatelessWidget {
  const _TutorCard({this.onOpenTutor});

  final VoidCallback? onOpenTutor;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    // The speaker is the learner's own persisted choice, so this card follows
    // the switcher on the tutor tab instead of naming whoever is first in the
    // list. Rebuilding on the notifier keeps the two in step without the tab
    // having to know this card exists.
    return ValueListenableBuilder<VoiceModel>(
      valueListenable: NfTutorVoice.current,
      builder: (BuildContext context, VoiceModel voice, _) {
        final String name = voice.name.trim();
        final String initial =
            name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();

        return NfCard(
          child: Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.primarySoft,
                  shape: BoxShape.circle,
                  border: Border.fromBorderSide(t.sideOf(t.primary)),
                ),
                child: Text(
                  initial,
                  style:
                      NfTokens.display(size: NfFont.s20, color: t.primaryText),
                ),
              ),
              const SizedBox(width: NfSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      // TODO(i18n): needs a key (the speaker's name is data)
                      'Talk with $name',
                      style: NfTokens.display(size: NfFont.s16, color: t.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: NfSpace.s4),
                    Text(
                      context.tr('chat.ai.subtitle'),
                      style:
                          NfTokens.body(size: NfFont.s125, color: t.inkMuted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: NfSpace.s12),
              NfSecondaryButton(
                // TODO(i18n): needs a key
                label: 'Chat',
                icon: LucideIcons.messageCircle,
                tone: NfButtonTone.primary,
                expand: false,
                onPressed: onOpenTutor,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STATS
// ═══════════════════════════════════════════════════════════════════════════

class _StatRow extends StatelessWidget {
  const _StatRow({required this.model});

  final _TodayModel model;

  @override
  Widget build(BuildContext context) {
    // Loading shows a dash rather than a zero: "0 words kept" is a claim, and
    // it is the wrong one for a learner whose deck simply has not loaded.
    String value(int number) => model.isLoading ? '—' : '$number';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: _StatTile(
            icon: LucideIcons.bookmark,
            value: value(model.wordsKept),
            // TODO(i18n): needs a key
            label: 'Words kept',
          ),
        ),
        const SizedBox(width: NfSpace.s10),
        Expanded(
          child: _StatTile(
            icon: LucideIcons.zap,
            value: value(model.weeklyXp),
            label: context.tr('home.thisWeek'),
          ),
        ),
        const SizedBox(width: NfSpace.s10),
        Expanded(
          child: _StatTile(
            icon: LucideIcons.award,
            value: value(model.level),
            label: context.tr('common.level'),
            progress: model.isLoading ? null : model.levelProgress,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    this.progress,
  });

  final IconData icon;
  final String value;
  final String label;

  /// 0..1. Only the level tile has a meaningful denominator; the other two
  /// still reserve the strip's height so the three tiles line up.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final double? fraction = progress;

    return NfCard(
      padding: const EdgeInsets.all(NfSpace.s12),
      borderRadius: NfRadius.tileAll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: t.primaryText),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: NfSpace.s8),
          if (fraction == null)
            const SizedBox(height: NfSize.progressQuiet)
          else
            NfProgressBar(
              value: fraction,
              height: NfSize.progressQuiet,
              semanticsLabel: label,
            ),
        ],
      ),
    );
  }
}
