import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/word.dart';
import '../providers/app_state_provider.dart';
import '../services/analytics_service.dart';
import '../services/local_reminder_service.dart';
import 'nf_frontend_preference.dart';
import 'screens/nf_dictionary_page.dart';
import 'screens/nf_grammar_page.dart';
import 'screens/nf_notifications_page.dart';
import 'screens/nf_practice_page.dart';
import 'screens/nf_profile_page.dart';
import 'screens/nf_pronunciation_page.dart';
import 'screens/nf_reading_practice_page.dart';
import 'screens/nf_session_page.dart';
import 'screens/nf_settings_page.dart';
import 'screens/nf_subscription_page.dart';
import 'screens/nf_today_page.dart';
import 'screens/nf_translation_practice_page.dart';
import 'screens/nf_tutor_page.dart';
import 'screens/nf_word_detail_page.dart';
import 'screens/nf_word_galaxy_page.dart';
import 'screens/nf_words_page.dart';
import 'screens/nf_writing_practice_page.dart';
import 'theme/nf_theme.dart';
import 'theme/nf_theme_scope.dart';
import 'theme/nf_tokens.dart';

/// Height of the tab bar's content, from the spec. The safe-area inset sits
/// below this, not inside it.
const double _navBarHeight = 70;

/// Nav icons match the foundation's ambient icon size.
const double _navIconSize = 22;

/// The active tab's icon sits in a pill of this height — the same
/// `primarySoft` fill `NfChipVariant.selected` uses, so "selected" looks the
/// same everywhere in this frontend.
const double _navPillHeight = 32;

/// A nav label never needs to grow past this; the bar is a fixed 70px and a
/// clipped label helps nobody. The icon above it keeps the system scale.
const double _navLabelMaxScale = 1.4;

/// The new frontend's root: five tabs over the same app.
///
/// This is a peer of `MainScreen`, not a replacement — both ship in one build
/// and `NfFrontendPreference` decides which one `main.dart` mounts. Everything
/// below it reads the same providers and services the current screens read; the
/// shell only owns navigation.
///
/// Destinations that have no new-frontend screen yet push the existing screen
/// from `lib/screens/`. A familiar screen with the old paint on it is a far
/// better answer than a dead end, and it keeps the preview honest about what is
/// actually finished.
class NfShell extends StatefulWidget {
  const NfShell({super.key, this.initialIndex = todayTab});

  static const int todayTab = 0;
  static const int practiceTab = 1;
  static const int tutorTab = 2;
  static const int wordsTab = 3;
  static const int profileTab = 4;
  static const int tabCount = 5;

  /// Which tab to open on. Values outside the range are clamped rather than
  /// asserted — this arrives from notification payloads and from other screens.
  final int initialIndex;

  /// Maps a `MainScreen` tab index onto the nearest new tab.
  ///
  /// Half a dozen existing screens push `MainScreen(initialIndex: n)` with the
  /// old layout in mind (0 home, 1 words, 2 menu, 3 sentences, 4 practice).
  /// Those call sites are not being touched, so the translation lives here.
  /// Sentences have no tab of their own in this frontend; Words is their
  /// nearest kin, since that is where a learner manages their own material.
  static int tabForLegacyIndex(int legacyIndex) {
    switch (legacyIndex) {
      case 1:
      case 3:
        return wordsTab;
      case 4:
        return practiceTab;
      case 0:
      case 2:
      default:
        return todayTab;
    }
  }

  @override
  State<NfShell> createState() => _NfShellState();
}

class _NfShellState extends State<NfShell> {
  late int _index = _clampTab(widget.initialIndex);

  static int _clampTab(int index) {
    if (index < 0) {
      return NfShell.todayTab;
    }
    return index >= NfShell.tabCount ? NfShell.todayTab : index;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _logTab(_index);
      unawaited(_consumePendingNotificationNavigation());
    });
  }

  // ---------------------------------------------------------------------------
  // Tabs
  // ---------------------------------------------------------------------------

  void _select(int index) {
    final int next = _clampTab(index);
    if (next == _index) {
      return;
    }
    setState(() => _index = next);
    if (next == NfShell.todayTab) {
      // Same refresh `MainScreen` does when the home tab comes forward: the
      // XP and streak figures on it are stale the moment a session ends.
      unawaited(context.read<AppStateProvider>().refreshXpStatsFromLocal());
    }
    _logTab(next);
  }

  /// Screen names are `nf_` prefixed so the preview's usage can be told apart
  /// from the current frontend's in analytics — which is the whole reason both
  /// are shipping at once.
  void _logTab(int index) {
    AnalyticsService.logScreenView(
      _screenNameForTab(index),
      screenClass: 'NfShell',
    );
  }

  static String _screenNameForTab(int index) {
    switch (index) {
      case NfShell.practiceTab:
        return 'nf_practice';
      case NfShell.tutorTab:
        return 'nf_tutor';
      case NfShell.wordsTab:
        return 'nf_words';
      case NfShell.profileTab:
        return 'nf_profile';
      case NfShell.todayTab:
      default:
        return 'nf_today';
    }
  }

  /// Consumes the payload left behind by a tapped notification.
  ///
  /// This has to happen in whichever shell is mounted: the read clears the
  /// stored payload, so if neither shell consumed it the notification would
  /// fire again on some unrelated later launch.
  ///
  /// Both practice reminders land on Today rather than on the mode library,
  /// because in this frontend Today *is* the daily-practice screen — it opens
  /// with the plan and a button that starts it.
  Future<void> _consumePendingNotificationNavigation() async {
    final String? payload =
        await LocalReminderService.consumePendingNavigationPayload();
    if (!mounted || payload == null) {
      return;
    }

    switch (payload.trim().toLowerCase()) {
      case 'notifications':
      case 'admin_test':
      case 'daily_practice':
      case 'streak_guard':
        _select(NfShell.todayTab);
        break;
      default:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Routing
  // ---------------------------------------------------------------------------

  void _push(Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  /// Pushes a page belonging to this frontend.
  ///
  /// A route is built under the app's [Navigator], which is above this shell,
  /// so it inherits none of the shell's `NfTheme`. Without the scope the page
  /// would resolve its palette from the device brightness and ignore the
  /// learner's in-app choice.
  void _pushNf(Widget page) {
    _push(NfThemeScope(child: page));
  }

  /// The daily plan and the "N due words" row both mean the same thing: a
  /// session over exactly the words the scheduler has raised. `NfSessionPage`
  /// keeps that promise, and falls back to unscheduled words when nothing is
  /// due, so it can never open an empty session.
  void _startReviewSession() {
    _pushNf(const NfSessionPage());
  }

  void _openMode(String modeId) {
    // Speaking practice in the current app *is* the AI voice chat, and this
    // frontend has that as a tab of its own. Sending the learner to the older
    // screen instead would be a downgrade, not a fallback.
    if (modeId == NfPracticeModes.speaking) {
      _select(NfShell.tutorTab);
      return;
    }
    switch (modeId) {
      case NfPracticeModes.translate:
        // The legacy setup step asked which word before showing anything. Here
        // the deck answers that: with words saved, the round is drawn from them
        // — which is what practising *your* vocabulary means. Only an empty
        // deck falls back to typing a word, because there is nothing to draw.
        final bool hasWords = context.read<AppStateProvider>().allWords.isNotEmpty;
        _pushNf(NfTranslationPracticePage(
          subMode: hasWords ? 'random' : 'select',
        ));
      case NfPracticeModes.reading:
        _pushNf(const NfReadingPracticePage());
      case NfPracticeModes.writing:
        _pushNf(const NfWritingPracticePage());
      case NfPracticeModes.grammar:
        _pushNf(const NfGrammarPage());
      case NfPracticeModes.pronunciation:
        _pushNf(const NfPronunciationPage());
      case NfPracticeModes.wordGalaxy:
        _pushNf(const NfWordGalaxyPage());
      default:
        // An unknown id can only come from a stored "continue where you left
        // off" note written by an older build. Dropping the learner on the
        // mode library is the honest answer; opening a legacy screen would
        // undo the transformation this shell exists for.
        _select(NfShell.practiceTab);
    }
  }

  /// A word opens its own screen rather than a sheet: meanings each carry their
  /// own sentences now, which is more than a half-height modal can hold.
  void _openWord(Word word) {
    _pushNf(NfWordDetailPage(word: word));
  }

  /// Notification preferences, in this frontend rather than in `ProfilePage`.
  ///
  /// The legacy screen would have saved writing the switches, but it carries
  /// the legacy `BottomNav`, and inside this shell a tap on that bar runs
  /// `pushAndRemoveUntil(..., (route) => false)` — which disposes the running
  /// `NfShell` and everything its `IndexedStack` is holding. `NfNotificationsPage`
  /// calls the same services, so nothing about the behaviour is reimplemented,
  /// only the chrome.
  void _openNotifications() {
    _pushNf(const NfNotificationsPage());
  }

  /// Settings is the app's settings screen *and* the way out of the preview —
  /// the design switch lives on it. The profile row that opens it is labelled
  /// as settings for that reason; it used to read "Language", which left the
  /// switch back to the classic design unsignposted.
  void _openSettings() {
    _pushNf(NfSettingsPage(
      onOpenNotifications: _openNotifications,
      onManageSubscription: _openSubscription,
    ));
  }

  void _openSubscription() {
    _pushNf(const NfSubscriptionPage());
  }

  /// The dictionary is where a word gets added, and an empty deck is the one
  /// state in which Today offers that instead of a review session.
  void _openDictionary() {
    _pushNf(const NfDictionaryPage());
  }

  /// Resolved at tap time rather than captured at build time, so the flip is
  /// always away from what is actually on screen — including when the device
  /// palette changed under a learner who has never chosen one.
  void _toggleBrightness() {
    final NfFrontendPreference preference =
        context.read<NfFrontendPreference>();
    final Brightness current =
        preference.brightnessFor(MediaQuery.platformBrightnessOf(context));
    unawaited(preference.toggleBrightness(current));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  List<Widget> _pages() {
    return <Widget>[
      NfTodayPage(
        onStartSession: _startReviewSession,
        onOpenTutor: () => _select(NfShell.tutorTab),
        onAddFirstWord: _openDictionary,
      ),
      NfPracticePage(
        onOpenMode: _openMode,
        onStartTodaysPlan: () => _select(NfShell.todayTab),
      ),
      const NfTutorPage(),
      NfWordsPage(
        onOpenWord: _openWord,
        onOpenDictionary: _openDictionary,
        onStartReview: _startReviewSession,
      ),
      NfProfilePage(
        onManageSubscription: _openSubscription,
        onOpenNotifications: _openNotifications,
        onOpenSettings: _openSettings,
        onToggleBrightness: _toggleBrightness,
      ),
    ];
  }

  Brightness? _themedBrightness;
  ThemeData? _materialTheme;

  /// Cached because a `ThemeData` here means rebuilding a dozen Google Fonts
  /// text styles, and this rebuilds on every tab tap.
  ThemeData _themeFor(Brightness brightness) {
    if (_materialTheme == null || _themedBrightness != brightness) {
      _themedBrightness = brightness;
      _materialTheme = NfTheme.materialTheme(brightness);
    }
    return _materialTheme!;
  }

  @override
  Widget build(BuildContext context) {
    final NfFrontendPreference preference =
        context.watch<NfFrontendPreference>();
    final Brightness brightness =
        preference.brightnessFor(MediaQuery.platformBrightnessOf(context));
    final NfTokens tokens = NfTokens.resolve(brightness);
    final bool isDark = brightness == Brightness.dark;

    return NfTheme(
      tokens: tokens,
      // Material still paints the scrollbars, spinners, text selection and
      // dialogs inside these pages; without this they would come through in
      // the current app's dark blue.
      child: Theme(
        data: _themeFor(brightness),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: NfTokens.transparent,
            statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: tokens.surface,
            systemNavigationBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
          ),
          child: Scaffold(
            backgroundColor: tokens.ground,
            // No `extendBody`: the tab bar is opaque and bordered, and content
            // running under it would fight the 2px line that separates them.
            body: IndexedStack(index: _index, children: _pages()),
            bottomNavigationBar: _NfNavBar(index: _index, onSelect: _select),
          ),
        ),
      ),
    );
  }
}

/// The five-tab bar: 70px of content, a 2px top border, labels always on.
class _NfNavBar extends StatelessWidget {
  const _NfNavBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    // TODO(i18n): needs a key — "Today" and "Tutor" have no key yet. The other
    // three reuse `nav.*`, which are already translated everywhere.
    final List<_NfNavItem> items = <_NfNavItem>[
      const _NfNavItem(icon: Icons.today_outlined, label: 'Today'),
      _NfNavItem(
        icon: Icons.school_outlined,
        label: context.tr('nav.practice'),
      ),
      const _NfNavItem(icon: Icons.forum_outlined, label: 'Tutor'),
      _NfNavItem(
        icon: Icons.menu_book_outlined,
        label: context.tr('nav.words'),
      ),
      _NfNavItem(
        icon: Icons.person_outline,
        label: context.tr('nav.profile'),
      ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: t.side),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _navBarHeight,
          child: Row(
            children: <Widget>[
              for (int i = 0; i < items.length; i++)
                Expanded(
                  child: _NfNavButton(
                    item: items[i],
                    selected: i == index,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

@immutable
class _NfNavItem {
  const _NfNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _NfNavButton extends StatelessWidget {
  const _NfNavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NfNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final Color foreground = selected ? t.primaryText : t.inkFaint;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          // Opaque so the whole column — the full 70px, well past the 44px
          // floor — is the target, not just the glyph.
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                height: _navPillHeight,
                padding: const EdgeInsets.symmetric(horizontal: NfSpace.s14),
                decoration: BoxDecoration(
                  color: selected ? t.primarySoft : NfTokens.transparent,
                  borderRadius: NfRadius.pillAll,
                ),
                child: Icon(item.icon, size: _navIconSize, color: foreground),
              ),
              const SizedBox(height: NfSpace.s4),
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: _navLabelMaxScale,
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NfTokens.display(
                    size: NfFont.s115,
                    color: foreground,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
