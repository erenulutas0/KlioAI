import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/app_state_provider.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_button.dart';
import '../widgets/nf_card.dart';

/// The practice mode ids.
///
/// These are the ids the existing practice screen already understands (see
/// `PracticePage._normalizeModeId`), so whatever the shell wires
/// [NfPracticePage.onOpenMode] to can hand one straight through without a
/// translation table.
class NfPracticeModes {
  const NfPracticeModes._();

  static const String translate = 'translate';
  static const String reading = 'reading';
  static const String writing = 'writing';
  static const String grammar = 'grammar';
  static const String speaking = 'speaking';
  static const String pronunciation = 'pronunciation';
  static const String wordGalaxy = 'word_galaxy';

  /// Core modes first, diversions last — the order the tab renders them in.
  ///
  /// The Neural game is deliberately absent. It was never redrawn for this
  /// frontend, and a mode tile that opens a screen in the old paint is worse
  /// than one that is not offered. Its code still exists under `lib/screens/`.
  static const List<String> all = <String>[
    translate,
    reading,
    writing,
    grammar,
    speaking,
    pronunciation,
    wordGalaxy,
  ];
}

/// Remembers which practice mode the learner opened last.
///
/// Nothing in the existing data layer records this: [AppStateProvider] tracks
/// words, XP and streak, not which screen was opened. So the new frontend keeps
/// its own one-line note. The keys are `nf_`-prefixed so they cannot collide
/// with anything the current frontend stores.
///
/// Public because the shell (or the home tab's "Today's plan") may also open a
/// mode, and this card is only honest if every entry point records itself.
class NfLastPracticeStore {
  const NfLastPracticeStore._();

  static const String _modeKey = 'nf_practice_last_mode';
  static const String _timestampKey = 'nf_practice_last_mode_at';

  /// After this long, "continue where you left off" stops being a helpful
  /// shortcut and starts being a stale suggestion — the tab falls back to the
  /// today's-plan call to action instead.
  static const Duration _freshFor = Duration(days: 7);

  /// The last mode opened, or null when there is nothing worth resuming.
  static Future<String?> read() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? modeId = prefs.getString(_modeKey);
      if (modeId == null || !NfPracticeModes.all.contains(modeId)) {
        return null;
      }
      final int? openedAtMs = prefs.getInt(_timestampKey);
      if (openedAtMs == null) {
        // Mode without a timestamp: an interrupted write, not a stale entry.
        // Offering it is the friendlier reading of ambiguous data.
        return modeId;
      }
      final DateTime openedAt =
          DateTime.fromMillisecondsSinceEpoch(openedAtMs);
      final Duration age = DateTime.now().difference(openedAt);
      // A negative age means the device clock moved backwards; treat it as
      // fresh rather than hiding a mode the learner just opened.
      return age > _freshFor ? null : modeId;
    } catch (error) {
      debugPrint('NfLastPracticeStore.read failed: $error');
      return null;
    }
  }

  /// Notes that [modeId] was just opened.
  static Future<void> record(String modeId) async {
    if (!NfPracticeModes.all.contains(modeId)) {
      return;
    }
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modeKey, modeId);
      await prefs.setInt(
        _timestampKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (error) {
      // A lost note costs the learner one extra tap next time; never a crash.
      debugPrint('NfLastPracticeStore.record failed: $error');
    }
  }
}

/// The practice tab: a library of modes, not the front door.
///
/// The current app puts eight equal modes behind a chip row and makes choosing
/// one the price of entry. Here the daily decision lives on the home tab
/// ("Today's plan"), so this tab only has to answer "what else can I do?" — and
/// the one card at the top means the common case (carry on with the same thing)
/// is still a single tap.
class NfPracticePage extends StatefulWidget {
  const NfPracticePage({
    super.key,
    required this.onOpenMode,
    this.onStartTodaysPlan,
  });

  /// Opens a practice mode. Receives one of [NfPracticeModes].
  final ValueChanged<String> onOpenMode;

  /// Jumps to the home tab's "Today's plan". When the shell does not supply
  /// one, the call to action falls back to the translation mode so the tab is
  /// never a dead end.
  final VoidCallback? onStartTodaysPlan;

  @override
  State<NfPracticePage> createState() => _NfPracticePageState();
}

class _NfPracticePageState extends State<NfPracticePage> {
  String? _lastModeId;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreLastMode());
  }

  /// While this is in flight the hero shows the today's-plan call to action.
  /// That is the safe default: preferences are already warm by the time this
  /// tab can be reached, so the swap lands within a frame — and if the read
  /// ever fails or hangs, the learner sees a working CTA rather than a gap.
  Future<void> _restoreLastMode() async {
    final String? modeId = await NfLastPracticeStore.read();
    if (!mounted || modeId == null) {
      return;
    }
    setState(() => _lastModeId = modeId);
  }

  void _openMode(String modeId) {
    // Recorded before handing over, so the card is correct even if the learner
    // backs straight out of the mode. Fire-and-forget: the navigation must not
    // wait on a disk write.
    unawaited(NfLastPracticeStore.record(modeId));
    if (_lastModeId != modeId) {
      setState(() => _lastModeId = modeId);
    }
    widget.onOpenMode(modeId);
  }

  void _startTodaysPlan() {
    final VoidCallback? openPlan = widget.onStartTodaysPlan;
    if (openPlan != null) {
      openPlan();
      return;
    }
    _openMode(NfPracticeModes.translate);
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    // Nullable lookup on purpose: this tab must still render inside a preview
    // harness that has no provider above it, the same guard the existing
    // screens use for ThemeProvider. `select` rather than `watch` because a
    // tab host keeps this page alive off-screen, and it has no business
    // rebuilding on every XP tick during a practice session.
    //
    // Only claims the library is empty once that is actually known — an
    // in-flight load must not flash the beginner copy at a returning learner.
    final bool libraryIsEmpty =
        context.select<AppStateProvider?, bool>((AppStateProvider? state) {
      return state != null && state.allWords.isEmpty && !state.isLoadingWords;
    });

    final List<_NfModeSpec> specs = _modeSpecs(context);
    final List<_NfModeSpec> core =
        specs.where((_NfModeSpec spec) => !spec.isGame).toList();
    final List<_NfModeSpec> games =
        specs.where((_NfModeSpec spec) => spec.isGame).toList();

    final _NfModeSpec? resume = _lastModeId == null
        ? null
        : specs.cast<_NfModeSpec?>().firstWhere(
              (_NfModeSpec? spec) => spec?.id == _lastModeId,
              orElse: () => null,
            );

    // Expanded on purpose: a scroll view shrink-wraps under the loose
    // constraints a tab host hands out, which would leave the ground unpainted
    // below the content on a tall screen.
    return SizedBox.expand(
      child: ColoredBox(
        color: t.ground,
        child: SafeArea(
          // The shell owns the bottom edge (nav bar); the scroll padding below
          // keeps the last row clear of it either way.
          bottom: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              NfSpace.s16,
              NfSpace.s18,
              NfSpace.s16,
              NfSpace.s26 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  context.tr('practice.title'),
                  style: NfTokens.display(size: NfFont.s25, color: t.ink),
                ),
                const SizedBox(height: NfSpace.s6),
                Text(
                  // TODO(i18n): needs a key
                  'Every way to practise, in one place.',
                  style: NfTokens.body(size: NfFont.s135, color: t.inkMuted),
                ),
                const SizedBox(height: NfSpace.s18),
                if (resume != null)
                  _NfResumeCard(spec: resume, onContinue: _openMode)
                else
                  _NfTodaysPlanCard(
                    libraryIsEmpty: libraryIsEmpty,
                    onStart: _startTodaysPlan,
                  ),
                const SizedBox(height: NfSpace.s22),
                _NfModeGrid(specs: core, onOpenMode: _openMode),
                const SizedBox(height: NfSpace.s22),
                Text(
                  // TODO(i18n): needs a key
                  'Games',
                  style: NfTokens.body(
                    size: NfFont.s125,
                    weight: NfTokens.bodyEmphasisWeight,
                    color: t.inkFaint,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: NfSpace.s10),
                _NfModeGrid(specs: games, onOpenMode: _openMode),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The eight modes, described by what they actually do.
///
/// Names reuse the existing localisation keys where they exist. The
/// descriptions mostly do not have keys yet: the two that do
/// (`practice.reading.subtitle`, `practice.writing.subtitle`) are already
/// exactly the one-liners this grid needs, so they are used rather than
/// duplicated in English.
List<_NfModeSpec> _modeSpecs(BuildContext context) {
  return <_NfModeSpec>[
    _NfModeSpec(
      id: NfPracticeModes.translate,
      icon: Icons.translate_rounded,
      name: context.tr('practice.mode.translate'),
      // TODO(i18n): needs a key
      description: 'Translate sentences built from your own words.',
    ),
    _NfModeSpec(
      id: NfPracticeModes.reading,
      icon: Icons.menu_book_outlined,
      name: context.tr('practice.mode.reading'),
      description: context.tr('practice.reading.subtitle'),
    ),
    _NfModeSpec(
      id: NfPracticeModes.writing,
      icon: Icons.edit_outlined,
      name: context.tr('practice.mode.writing'),
      description: context.tr('practice.writing.subtitle'),
    ),
    _NfModeSpec(
      id: NfPracticeModes.grammar,
      icon: Icons.rule_rounded,
      name: context.tr('practice.mode.grammar'),
      // TODO(i18n): needs a key
      description: 'Topic guides, examples and a quiz per topic.',
    ),
    _NfModeSpec(
      id: NfPracticeModes.speaking,
      icon: Icons.forum_outlined,
      name: context.tr('practice.mode.speaking'),
      // TODO(i18n): needs a key
      description: 'Hold a spoken conversation with the AI tutor.',
    ),
    // const only until these strings get keys; `context.tr` is not const.
    const _NfModeSpec(
      id: NfPracticeModes.pronunciation,
      icon: Icons.mic_none_rounded,
      // TODO(i18n): needs a key
      name: 'Pronunciation',
      // Deliberately says "clarity": the score compares the target text with
      // what was heard, it is not phoneme-level pronunciation diagnosis.
      // TODO(i18n): needs a key
      description: 'Read aloud, record, and get a clarity report.',
    ),
    const _NfModeSpec(
      id: NfPracticeModes.wordGalaxy,
      icon: Icons.hub_outlined,
      // TODO(i18n): needs a key
      name: 'Word Galaxy',
      // TODO(i18n): needs a key
      description: 'Explore your words as a network of sentences.',
      isGame: true,
    ),
  ];
}

@immutable
class _NfModeSpec {
  const _NfModeSpec({
    required this.id,
    required this.icon,
    required this.name,
    required this.description,
    this.isGame = false,
  });

  final String id;
  final IconData icon;
  final String name;
  final String description;

  /// Games are a diversion, not a peer of the core modes: they sit last and
  /// render quieter.
  final bool isGame;
}

/// The hero when there is something to resume.
class _NfResumeCard extends StatelessWidget {
  const _NfResumeCard({required this.spec, required this.onContinue});

  final _NfModeSpec spec;
  final ValueChanged<String> onContinue;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return NfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              _NfIconTile(icon: spec.icon, size: _kHeroIconTile),
              const SizedBox(width: NfSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      // TODO(i18n): needs a key
                      'Continue where you left off',
                      style: NfTokens.body(
                        size: NfFont.s125,
                        weight: NfTokens.bodyEmphasisWeight,
                        color: t.inkMuted,
                      ),
                    ),
                    const SizedBox(height: NfSpace.s4),
                    Text(
                      spec.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NfTokens.display(size: NfFont.s20, color: t.ink),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: NfSpace.s10),
          Text(
            spec.description,
            style: NfTokens.body(size: NfFont.s135, color: t.inkMuted),
          ),
          const SizedBox(height: NfSpace.s14),
          NfPrimaryButton(
            label: context.tr('common.continue'),
            icon: Icons.play_arrow_rounded,
            onPressed: () => onContinue(spec.id),
          ),
        ],
      ),
    );
  }
}

/// The hero when there is nothing to resume — the same offer the home tab
/// makes, so this tab never bottoms out on "choose something".
class _NfTodaysPlanCard extends StatelessWidget {
  const _NfTodaysPlanCard({
    required this.libraryIsEmpty,
    required this.onStart,
  });

  /// The learner has no words yet, so framing the plan as "reviews" would be a
  /// promise about content that does not exist.
  final bool libraryIsEmpty;

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return NfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const _NfIconTile(
                icon: Icons.wb_sunny_outlined,
                size: _kHeroIconTile,
              ),
              const SizedBox(width: NfSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      // TODO(i18n): needs a key
                      "Today's plan",
                      style: NfTokens.body(
                        size: NfFont.s125,
                        weight: NfTokens.bodyEmphasisWeight,
                        color: t.inkMuted,
                      ),
                    ),
                    const SizedBox(height: NfSpace.s4),
                    Text(
                      libraryIsEmpty
                          // TODO(i18n): needs a key
                          ? 'Learn your first words'
                          // TODO(i18n): needs a key
                          : 'Start your daily session',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NfTokens.display(size: NfFont.s20, color: t.ink),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: NfSpace.s10),
          Text(
            libraryIsEmpty
                // TODO(i18n): needs a key
                ? 'Your library is empty — today\'s words are the place to start.'
                // TODO(i18n): needs a key
                : "Today's words and everything due for review, in one go.",
            style: NfTokens.body(size: NfFont.s135, color: t.inkMuted),
          ),
          const SizedBox(height: NfSpace.s14),
          NfPrimaryButton(
            label: context.tr('common.start'),
            icon: Icons.play_arrow_rounded,
            onPressed: onStart,
          ),
        ],
      ),
    );
  }
}

/// Two columns of mode tiles.
///
/// Built from rows rather than a [GridView] so a tile grows with its own text:
/// a fixed `childAspectRatio` overflows as soon as a translation runs long or
/// the learner turns up the system text size. [IntrinsicHeight] then squares up
/// the pair so the row still reads as a grid.
class _NfModeGrid extends StatelessWidget {
  const _NfModeGrid({required this.specs, required this.onOpenMode});

  final List<_NfModeSpec> specs;
  final ValueChanged<String> onOpenMode;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];

    for (int i = 0; i < specs.length; i += 2) {
      final _NfModeSpec left = specs[i];
      final _NfModeSpec? right = i + 1 < specs.length ? specs[i + 1] : null;

      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: _NfModeTile(spec: left, onTap: onOpenMode)),
              const SizedBox(width: NfSpace.s12),
              Expanded(
                child: right == null
                    // Keeps a lone last tile at half width instead of letting
                    // it stretch across the row.
                    ? const SizedBox.shrink()
                    : _NfModeTile(spec: right, onTap: onOpenMode),
              ),
            ],
          ),
        ),
      );

      if (i + 2 < specs.length) {
        rows.add(const SizedBox(height: NfSpace.s12));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

class _NfModeTile extends StatelessWidget {
  const _NfModeTile({required this.spec, required this.onTap});

  final _NfModeSpec spec;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final bool quiet = spec.isGame;

    return NfCard(
      padding: const EdgeInsets.all(NfSpace.s14),
      backgroundColor: quiet ? t.raised : null,
      onTap: () => onTap(spec.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _NfIconTile(icon: spec.icon, size: _kTileIconTile, quiet: quiet),
          const SizedBox(height: NfSpace.s12),
          Text(
            spec.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NfTokens.display(size: NfFont.s16, color: t.ink),
          ),
          const SizedBox(height: NfSpace.s4),
          Text(
            spec.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: NfTokens.body(
              size: NfFont.s125,
              color: quiet ? t.inkFaint : t.inkMuted,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded icon tile. Core modes get the brand tint; games get a plain surface
/// on the raised card, which is what makes them read as quieter without
/// inventing a colour.
class _NfIconTile extends StatelessWidget {
  const _NfIconTile({
    required this.icon,
    required this.size,
    this.quiet = false,
  });

  final IconData icon;
  final double size;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: quiet ? t.surface : t.primarySoft,
        borderRadius: NfRadius.iconTileAll,
        border: quiet ? Border.fromBorderSide(t.side) : null,
      ),
      child: Icon(
        icon,
        size: size * _kIconRatio,
        color: quiet ? t.inkMuted : t.primaryText,
      ),
    );
  }
}

/// Icon tile sizes. Not in the token set — the spec fixes radii and strokes but
/// not icon-tile dimensions — so they live here, next to their only users.
const double _kHeroIconTile = 46;
const double _kTileIconTile = 42;

/// Glyph-to-tile ratio, tuned so the icon reads at both sizes.
const double _kIconRatio = 0.5;
