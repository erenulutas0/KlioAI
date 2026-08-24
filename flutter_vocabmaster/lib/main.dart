import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'screens/home_page.dart';
import 'screens/dictionary_page.dart';
import 'screens/words_page.dart';
import 'screens/sentences_page.dart';
import 'screens/menu_page.dart';
import 'screens/practice_page.dart';
import 'screens/stats_page.dart';
import 'screens/quick_dictionary_page.dart';
import 'widgets/bottom_nav.dart';
import 'widgets/navigation_menu_panel.dart';
import 'screens/profile_page.dart';
import 'screens/ai_bot_chat_page.dart';
import 'screens/splash_screen.dart';
import 'screens/xp_history_page.dart';
import 'screens/settings_page.dart';
import 'screens/review_mode_selector_page.dart';
import 'screens/support_tickets_page.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/offline_sync_service.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/analytics_service.dart';
import 'services/crashlytics_service.dart';
import 'services/local_reminder_service.dart';
import 'services/push_token_service.dart';
import 'widgets/theme_side_tab.dart';
import 'widgets/xp_toast_host.dart';
import 'providers/app_state_provider.dart';
import 'providers/language_provider.dart';
import 'providers/learning_language_provider.dart';
import 'l10n/app_localizations.dart';
import 'theme/theme_provider.dart';
import 'frontend_newest/nf_frontend_preference.dart';
import 'frontend_newest/nf_shell.dart';
import 'frontend_newest/screens/nf_landing_page.dart';
import 'frontend_newest/screens/nf_onboarding_page.dart';

bool _firebaseTelemetryEnabled = false;
bool _handlingSessionExpiry = false;

/// Wired to [ApiService.onSessionExpired]: when a protected request can no
/// longer recover its session (dead token + refresh exhausted), clear the
/// local session and bounce the user to a clean entry so they can sign in
/// again — instead of stranding them on a cached screen. Idempotent: many
/// concurrent failing requests may call this at once.
void _handleSessionExpired() {
  if (_handlingSessionExpiry) {
    return;
  }
  _handlingSessionExpiry = true;
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await AuthService().logout();
    } catch (_) {
      // Best-effort: even if the server logout call fails, local tokens are
      // cleared by logout() and we still route to login.
    }
    final navigator = appNavigatorKey.currentState;
    if (navigator != null) {
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SplashScreen()),
        (route) => false,
      );
    }
    _handlingSessionExpiry = false;
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ApiService.onSessionExpired = _handleSessionExpired;
  _firebaseTelemetryEnabled = await _initializeFirebaseTelemetry();
  if (_firebaseTelemetryEnabled) {
    AnalyticsService.logAppOpen(source: 'cold_start');
    WidgetsBinding.instance.addObserver(_AppOpenLifecycleObserver());
  }

  try {
    await dotenv.load(fileName: ".env");
  } catch (_) {
    // Release builds no longer bundle `.env`; runtime config should come
    // from dart-define values and safe defaults.
  }

  // Offline sync service başlat
  final offlineSyncService = OfflineSyncService();
  await offlineSyncService.initialize();
  final authService = AuthService();
  await authService.enforceMandatorySessionResetIfNeeded();
  final currentUserId = await authService.getUserId();
  if (currentUserId != null && currentUserId > 0) {
    await AnalyticsService.setUserId(currentUserId.toString());
    await CrashlyticsService.setUserId(currentUserId.toString());
  }
  if (await authService.isLoggedIn()) {
    await offlineSyncService.initialDataLoad();
  }
  await LocalReminderService().initialize();
  if (_firebaseTelemetryEnabled && await authService.isLoggedIn()) {
    unawaited(PushTokenService().initialize());
  }

  // Global App State Provider oluştur
  final appStateProvider = AppStateProvider();
  final themeProvider = ThemeProvider();
  final languageProvider = LanguageProvider();
  final learningLanguageProvider = LearningLanguageProvider();
  final nfFrontendPreference = NfFrontendPreference();
  await themeProvider.initialize();
  await languageProvider.initialize();
  await learningLanguageProvider.initialize();
  // Awaited with the rest so the first frame already knows which frontend to
  // build; loading it later would flash the one the learner did not pick.
  await nfFrontendPreference.initialize();

  appStateProvider.addListener(() {
    final xp = (appStateProvider.userStats['xp'] as int?) ?? 0;
    themeProvider.updateUserXP(xp);

    final rawSubscriptionEnd =
        appStateProvider.userInfo?['subscriptionEndDate']?.toString().trim();
    bool hasPremiumAccess = false;
    if (rawSubscriptionEnd != null &&
        rawSubscriptionEnd.isNotEmpty &&
        rawSubscriptionEnd.toLowerCase() != 'null') {
      final parsed = DateTime.tryParse(rawSubscriptionEnd);
      if (parsed == null) {
        hasPremiumAccess = true;
      } else {
        final now = parsed.isUtc ? DateTime.now().toUtc() : DateTime.now();
        hasPremiumAccess = parsed.isAfter(now);
      }
    }
    themeProvider.updatePremiumAccess(hasPremiumAccess);
  });

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appStateProvider),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: languageProvider),
        ChangeNotifierProvider.value(value: learningLanguageProvider),
        ChangeNotifierProvider.value(value: nfFrontendPreference),
      ],
      child: const KlioAIApp(),
    ),
  );

  // Uygulama başlatıldıktan sonra veriyi yükle (non-blocking)
  appStateProvider.initialize();
}

class _AppOpenLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AnalyticsService.logAppOpen(source: 'resume');
    }
  }
}

Future<bool> _initializeFirebaseTelemetry() async {
  try {
    await Firebase.initializeApp();
    CrashlyticsService.setEnabled(true);
    FlutterError.onError = CrashlyticsService.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(CrashlyticsService.recordError(error, stack, fatal: true));
      return true;
    };
    AnalyticsService.setEnabled(true);
    return true;
  } catch (e) {
    AnalyticsService.setEnabled(false);
    CrashlyticsService.setEnabled(false);
    debugPrint('Firebase telemetry disabled: $e');
    return false;
  }
}

class KlioAIApp extends StatelessWidget {
  const KlioAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    final selectedTheme = context.watch<ThemeProvider>().currentTheme;
    final selectedLocale = context.watch<LanguageProvider>().locale;

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      navigatorObservers:
          _firebaseTelemetryEnabled ? [AnalyticsService.navigatorObserver] : [],
      title: context.tr('app.name'),
      debugShowCheckedModeBanner: false,
      locale: selectedLocale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: selectedTheme.colors.primary,
        colorScheme: ColorScheme.dark(
          primary: selectedTheme.colors.primary,
          secondary: selectedTheme.colors.accent,
          surface: selectedTheme.colors.background,
        ),
        scaffoldBackgroundColor: Colors.transparent,
        fontFamily: 'Inter',
      ),
      builder: (context, child) => ThemeSideTab(
        child: XpToastHost(
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: const AppEntryGate(),
    );
  }
}

/// What the app shows first: the first-run flow, or the splash.
///
/// The condition is unchanged — no app language has ever been chosen means this
/// is a first run — but it no longer opens `LanguageSelectionPage`. Picking the
/// language is the first step of [NfOnboardingPage] now, which then carries
/// straight on into the tour and the learning profile instead of handing back
/// to the splash in between.
class AppEntryGate extends StatefulWidget {
  const AppEntryGate({super.key});

  @override
  State<AppEntryGate> createState() => _AppEntryGateState();
}

class _AppEntryGateState extends State<AppEntryGate> {
  /// Latched the first time the answer is known, and deliberately not re-read.
  ///
  /// Choosing a language flips `hasExplicitSelection`, and this widget is
  /// listening: re-deciding on that rebuild would tear the flow down half way
  /// through and drop the learner on the splash. `LanguageSelectionPage` could
  /// not hit that, because it navigated away the moment it saved.
  bool? _isFirstRun;

  @override
  Widget build(BuildContext context) {
    final languageProvider = context.watch<LanguageProvider>();
    if (!languageProvider.initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_isFirstRun ??= !languageProvider.hasExplicitSelection) {
      // `nextPageBuilder` is what keeps the end of the flow off the legacy
      // `LoginPage`; without it the page falls back to that as its default.
      return NfOnboardingPage(
        showLanguageStep: true,
        nextPageBuilder: (_) => const NfLandingPage(),
      );
    }
    return const SplashScreen();
  }
}

/// The app's home. Everything else keeps pushing `MainScreen`.
///
/// This used to branch on a preference: the new design was a preview a learner
/// opted into, and [LegacyMainScreen] was what everyone else got. The new
/// design is now the app, so the branch is gone and every entry point — splash,
/// login, a notification tap, the stats shortcuts — lands in [NfShell].
///
/// [LegacyMainScreen] and the screens under `lib/screens/` are deliberately
/// kept in the tree, and deliberately unreachable. Nothing constructs them.
/// They are the fallback if the new design has to be walked back, not dead code
/// to tidy away: deleting them is a decision for after this design has been in
/// front of real learners, not a side effect of shipping it.
class MainScreen extends StatelessWidget {
  final int initialIndex;
  const MainScreen({super.key, this.initialIndex = 0});

  @override
  Widget build(BuildContext context) {
    return NfShell(initialIndex: NfShell.tabForLegacyIndex(initialIndex));
  }
}

/// The previous frontend. No longer reachable — see [MainScreen].
class LegacyMainScreen extends StatefulWidget {
  final int initialIndex;
  const LegacyMainScreen({super.key, this.initialIndex = 0});

  @override
  State<LegacyMainScreen> createState() => _LegacyMainScreenState();
}

class _LegacyMainScreenState extends State<LegacyMainScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _logTabScreen(_currentIndex);
      unawaited(_consumePendingNotificationNavigation());
    });
  }

  String? _practiceInitialMode;

  void _selectTab(int index, {String? practiceInitialMode}) {
    setState(() {
      _currentIndex = index;
      if (practiceInitialMode != null) {
        _practiceInitialMode = practiceInitialMode;
      }
    });
    if (index == 0) {
      unawaited(context.read<AppStateProvider>().refreshXpStatsFromLocal());
    }
    _logTabScreen(index);
  }

  void _logTabScreen(int index) {
    AnalyticsService.logScreenView(
      _screenNameForIndex(index),
      screenClass: 'MainScreen',
    );
  }

  Future<void> _consumePendingNotificationNavigation() async {
    final payload =
        await LocalReminderService.consumePendingNavigationPayload();
    if (!mounted || payload == null) {
      return;
    }

    final route = payload.trim().toLowerCase();
    // The in-app notification list went with the community feature - every notification it
    // could hold was a friend request, a like, a comment or a message. A push that opens the
    // app should land somewhere with something to do, so these go home rather than to a
    // screen that no longer exists. Nothing sends this payload any more; it is here for a
    // notification that was already in flight, and for admin_test.
    if (route == 'notifications' || route == 'admin_test') {
      _selectTab(0);
      return;
    }

    if (route == 'daily_practice' || route == 'streak_guard') {
      _selectTab(4);
    }
  }

  String _screenNameForIndex(int index) {
    switch (index) {
      case 1:
        return 'words';
      case 2:
        return 'menu';
      case 3:
        return 'sentences';
      case 4:
        return 'practice';
      case 0:
      default:
        return 'home';
    }
  }

  void _onNavigate(String page) {
    switch (page) {
      case 'speaking':
      case 'practice_speaking':
        _selectTab(4, practiceInitialMode: 'speaking');
        break;
      case 'repeat':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ReviewModeSelectorPage()),
        );
        break;
      // Entered from the home "N words due" card: the session must contain
      // exactly those N words, not the whole deck.
      case 'repeat_due':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ReviewModeSelectorPage(dueOnly: true),
          ),
        );
        break;
      case 'dictionary':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DictionaryPage()),
        );
        break;
      case 'words':
        _selectTab(1);
        break;
      case 'sentences':
        _selectTab(3);
        break;
      case 'xp-history':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const XpHistoryPage()),
        );
        break;
      case 'language':
        _showLanguagePickerDialog();
        break;
      case 'settings':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsPage()),
        );
        break;
      case 'support':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SupportTicketsPage()),
        );
        break;
    }
  }


  Future<void> _showLanguagePickerDialog() async {
    final provider = context.read<LanguageProvider>();
    final l10n = context.l10n;
    final current = provider.locale.languageCode;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.t('language.setup.select'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...AppLocalizations.supportedLocales.map((locale) {
                  final code = locale.languageCode;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      current == code
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color:
                          current == code ? Colors.cyanAccent : Colors.white70,
                    ),
                    title: Text(
                      _localizedLanguageLabel(code),
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () async {
                      await provider.selectLanguage(locale);
                      if (!mounted || !sheetContext.mounted) {
                        return;
                      }
                      Navigator.of(sheetContext).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.t('language.changed'))),
                      );
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  String _localizedLanguageLabel(String code) {
    switch (code) {
      case 'tr':
        return context.tr('language.turkish');
      case 'de':
        return context.tr('language.german');
      default:
        return context.tr('language.english');
    }
  }


  // IndexedStack sayfaları "canlı" tutar - rebuild olmaz
  Widget _buildBody() {
    return IndexedStack(
      index: _currentIndex == 2
          ? 0
          : _currentIndex, // Menu index'i atlayarak Ana Sayfa göster
      children: [
        HomePage(onNavigate: _onNavigate), // 0
        const WordsPage(), // 1
        const MenuPage(), // 2 (görünmez, placeholder)
        const SentencesPage(), // 3
        PracticePage(initialMode: _practiceInitialMode), // 4
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      key: _scaffoldKey,
      drawer: NavigationMenuPanel(
        activeTab: _getActiveTab(),
        currentPage: '',
        onTabChange: (id) {
          Navigator.pop(context);

          switch (id) {
            case 'home':
              _selectTab(0);
              break;
            case 'words':
              _selectTab(1);
              break;
            case 'sentences':
              _selectTab(3);
              break;
            case 'practice':
              _selectTab(4);
              break;
          }
        },
        onNavigate: (id) {
          Navigator.pop(context);
          switch (id) {
            case 'speaking':
              _selectTab(4, practiceInitialMode: 'speaking');
              break;
            case 'repeat':
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ReviewModeSelectorPage(),
                ),
              );
              break;
            case 'dictionary':
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const QuickDictionaryPage()),
              );
              break;
            case 'stats':
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StatsPage()),
              );
              break;
            case 'profile-settings':
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
              break;
            case 'chat':
              // Straight to the tutor. This used to open a dialog to choose between
              // chatting with friends and chatting with the AI; with the community feature
              // gone there is one option, and a dialog to pick from one is just a tap.
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AIBotChatPage()),
              );
              break;
            case 'language':
              _showLanguagePickerDialog();
              break;
            case 'settings':
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
              break;
          }
        },
      ),
      body: _buildBody(),
      bottomNavigationBar: BottomNav(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index == 2) {
            _scaffoldKey.currentState?.openDrawer();
          } else {
            _selectTab(index);
          }
        },
      ),
    );
  }

  String _getActiveTab() {
    switch (_currentIndex) {
      case 0:
        return 'home';
      case 1:
        return 'words';
      case 3:
        return 'sentences';
      case 4:
        return 'practice';
      default:
        return '';
    }
  }
}
