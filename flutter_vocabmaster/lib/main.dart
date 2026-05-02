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
import 'screens/chat_list_page.dart';
import 'widgets/bottom_nav.dart';
import 'widgets/navigation_menu_panel.dart';
import 'screens/profile_page.dart';
import 'screens/social_feed_page.dart';
import 'screens/ai_bot_chat_page.dart';
import 'screens/splash_screen.dart';
import 'screens/notifications_page.dart';
import 'screens/xp_history_page.dart';
import 'screens/language_selection_page.dart';
import 'screens/settings_page.dart';
import 'screens/review_mode_selector_page.dart';
import 'screens/support_tickets_page.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/global_state.dart';
import 'services/offline_sync_service.dart';
import 'services/auth_service.dart';
import 'widgets/matchmaking_banner.dart';
import 'widgets/theme_side_tab.dart';
import 'providers/app_state_provider.dart';
import 'providers/language_provider.dart';
import 'l10n/app_localizations.dart';
import 'theme/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  if (await authService.isLoggedIn()) {
    await offlineSyncService.initialDataLoad();
  }

  // Global App State Provider oluştur
  final appStateProvider = AppStateProvider();
  final themeProvider = ThemeProvider();
  final languageProvider = LanguageProvider();
  await themeProvider.initialize();
  await languageProvider.initialize();

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
      ],
      child: const KlioAIApp(),
    ),
  );

  // Uygulama başlatıldıktan sonra veriyi yükle (non-blocking)
  appStateProvider.initialize();
}

class KlioAIApp extends StatelessWidget {
  const KlioAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    final selectedTheme = context.watch<ThemeProvider>().currentTheme;
    final selectedLocale = context.watch<LanguageProvider>().locale;

    return MaterialApp(
      navigatorKey: appNavigatorKey,
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
        child: child ?? const SizedBox.shrink(),
      ),
      home: const AppEntryGate(),
    );
  }
}

class AppEntryGate extends StatelessWidget {
  const AppEntryGate({super.key});

  @override
  Widget build(BuildContext context) {
    final languageProvider = context.watch<LanguageProvider>();
    if (!languageProvider.initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!languageProvider.hasExplicitSelection) {
      return const LanguageSelectionPage();
    }
    return const SplashScreen();
  }
}

class MainScreen extends StatefulWidget {
  final int initialIndex;
  const MainScreen({super.key, this.initialIndex = 0});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  String? _practiceInitialMode;

  void _onNavigate(String page) {
    switch (page) {
      case 'speaking':
      case 'practice_speaking':
        setState(() {
          _currentIndex = 4;
          _practiceInitialMode = 'speaking';
        });
        break;
      case 'repeat':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ReviewModeSelectorPage()),
        );
        break;
      case 'dictionary':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DictionaryPage()),
        );
        break;
      case 'words':
        setState(() => _currentIndex = 1);
        break;
      case 'sentences':
        setState(() => _currentIndex = 3);
        break;
      case 'notifications':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NotificationsPage()),
        );
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

  void _showChatSelectionDialog() {
    final l10n = context.l10n;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: l10n.t('nav.selectChatMode'),
      barrierColor: Colors.black.withOpacity(0.8),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return Align(
          alignment: Alignment.center,
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A)
                    .withOpacity(0.9), // Darker, glass-like
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFF22D3EE)
                      .withOpacity(0.5), // Neon blue border
                  width: 1.5,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x4D06B6D4), // Neon blue glow
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 20),
                        child: Text(
                          l10n.t('nav.selectChatMode'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(color: Color(0xFF22D3EE), blurRadius: 10),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildChatOption(
                        title: l10n.t('chat.friends.title'),
                        subtitle: l10n.t('chat.friends.subtitle'),
                        icon: Icons.people_outline,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
                        ),
                        onTap: () {
                          Navigator.pop(context); // Close dialog
                          Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const ChatListPage()),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildChatOption(
                        title: l10n.t('chat.ai.title'),
                        subtitle: l10n.t('chat.ai.subtitle'),
                        icon: Icons.psychology_outlined,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFA855F7), Color(0xFFEC4899)],
                        ),
                        onTap: () {
                          Navigator.pop(context); // Close dialog
                          Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const AIBotChatPage()),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                  Positioned(
                    top: -10,
                    right: -10,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return Transform.scale(
          scale:
              CurvedAnimation(parent: anim1, curve: Curves.easeOutBack).value,
          child: Opacity(
            opacity: anim1.value,
            child: child,
          ),
        );
      },
    );
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
      case 'ar':
        return context.tr('language.arabic');
      case 'zh':
        return context.tr('language.chinese');
      default:
        return context.tr('language.english');
    }
  }

  Widget _buildChatOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withOpacity(0.5),
            ),
          ],
        ),
      ),
    );
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
              setState(() => _currentIndex = 0);
              break;
            case 'words':
              setState(() => _currentIndex = 1);
              break;
            case 'sentences':
              setState(() => _currentIndex = 3);
              break;
            case 'practice':
              setState(() => _currentIndex = 4);
              break;
          }
        },
        onNavigate: (id) {
          Navigator.pop(context);
          switch (id) {
            case 'speaking':
              setState(() {
                _currentIndex = 4;
                _practiceInitialMode = 'speaking';
              });
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
              _showChatSelectionDialog();
              break;
            case 'feed':
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SocialFeedPage()),
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
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: GlobalState.isMatching,
        builder: (context, isMatching, child) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isMatching)
                MatchmakingBanner(
                  onCancel: () {
                    GlobalState.matchmakingService.leaveQueue();
                    GlobalState.isMatching.value = false;
                  },
                ),
              BottomNav(
                currentIndex: _currentIndex,
                onTap: (index) {
                  if (index == 2) {
                    _scaffoldKey.currentState?.openDrawer();
                  } else {
                    setState(() {
                      _currentIndex = index;
                    });
                  }
                },
              ),
            ],
          );
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
