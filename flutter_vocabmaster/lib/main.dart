import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'screens/home_page.dart';
import 'screens/repeat_page.dart';
import 'screens/dictionary_page.dart';
import 'screens/words_page.dart';
import 'screens/sentences_page.dart';
import 'screens/menu_page.dart';
import 'screens/practice_page.dart';
import 'screens/stats_page.dart';
import 'screens/speaking_page.dart';
import 'screens/review_page.dart';
import 'screens/quick_dictionary_page.dart';
import 'screens/chat_list_page.dart';
import 'widgets/bottom_nav.dart';
import 'widgets/animated_background.dart';
import 'widgets/navigation_menu_panel.dart';
import 'widgets/animated_background.dart';
import 'screens/landing_page.dart';
import 'screens/login_page.dart';
import 'screens/profile_page.dart';
import 'screens/social_feed_page.dart';
import 'screens/ai_bot_chat_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/splash_screen.dart';
import 'screens/notifications_page.dart';
import 'screens/xp_history_page.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/global_state.dart';
import 'services/offline_sync_service.dart';
import 'services/auth_service.dart';
import 'widgets/global_matching_indicator.dart';
import 'widgets/matchmaking_banner.dart';
import 'providers/app_state_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  // Offline sync service başlat
  final offlineSyncService = OfflineSyncService();
  await offlineSyncService.initialize();
  final authService = AuthService();
  if (await authService.isLoggedIn()) {
    await offlineSyncService.initialDataLoad();
  }

  // Global App State Provider oluştur
  final appStateProvider = AppStateProvider();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(
    ChangeNotifierProvider.value(
      value: appStateProvider,
      child: const VocabMasterApp(),
    ),
  );

  // Uygulama başlatıldıktan sonra veriyi yükle (non-blocking)
  appStateProvider.initialize();
}

class VocabMasterApp extends StatelessWidget {
  const VocabMasterApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VocabMaster',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.cyan,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
        fontFamily: 'Inter',
      ),
      // Auth state check via SplashScreen
      home: const SplashScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  final int initialIndex;
  const MainScreen({Key? key, this.initialIndex = 0}) : super(key: key);

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
          _practiceInitialMode = 'Konuşma';
        });
        break;
      case 'repeat':
        // If repeat is requested from home, go to Practice tab (index 4)
        setState(() => _currentIndex = 4);
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
    }
  }

  void _showChatSelectionDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Chat Selection',
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
                      const Padding(
                        padding: EdgeInsets.only(top: 10, bottom: 20),
                        child: Text(
                          'Sohbet Modu Seçin',
                          style: TextStyle(
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
                        title: 'Arkadaşlarla Sohbet',
                        subtitle: 'Online arkadaşlarla konuş',
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
                        title: 'AI ile Sohbet',
                        subtitle: 'Yapay zeka asistanı ile pratik yap',
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
                _practiceInitialMode = 'Konuşma';
              });
              break;
            case 'repeat':
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RepeatPage()),
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
