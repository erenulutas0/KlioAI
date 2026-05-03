import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;
import 'dart:async';

import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
// Add Word model
import '../widgets/animated_background.dart';
import '../services/user_data_service.dart';
import '../services/social_service.dart';
import '../widgets/info_dialog.dart';
import 'profile_page.dart';
import '../providers/app_state_provider.dart';
import '../models/word.dart';
import '../widgets/daily_word_card.dart';
import '../widgets/word_of_the_day_modal.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';
import 'support_tickets_page.dart';
import '../services/first_session_activation_service.dart';

class HomePage extends StatefulWidget {
  final Function(String) onNavigate;
  final bool enableBackgroundTasks;

  const HomePage({
    super.key,
    required this.onNavigate,
    this.enableBackgroundTasks = true,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  // AutomaticKeepAliveClientMixin sayesinde widget "canlı" kalır
  @override
  bool get wantKeepAlive => true;

  // Çevrimiçi kullanıcılar - gerçek sistem olmadığı için boş başlar
  List<Map<String, dynamic>> onlineUsers = [];

  // Animation Controllers
  late AnimationController _glowAnimation1;
  late AnimationController _glowAnimation2;
  late AnimationController _statsAnimation;
  late AnimationController _circularProgressAnimation;
  late AnimationController _horizontalProgressAnimation;
  late AnimationController _percentageAnimation;
  late AnimationController _pulseAnimation;

  // Heartbeat timer for online status
  Timer? _heartbeatTimer;
  final SocialService _socialService = SocialService();
  final FirstSessionActivationService _activationService =
      FirstSessionActivationService();
  String? _activationSelectedLevel;
  bool _activationPracticeCompleted = false;
  bool _activationDismissed = false;

  AppThemeConfig _currentTheme({bool listen = true}) {
    try {
      final provider = Provider.of<ThemeProvider?>(context, listen: listen);
      return provider?.currentTheme ?? VocabThemes.defaultTheme;
    } catch (_) {
      return VocabThemes.defaultTheme;
    }
  }

  Color _mix(Color from, Color to, double amount) {
    return Color.lerp(from, to, amount) ?? from;
  }

  @override
  void initState() {
    super.initState();
    if (widget.enableBackgroundTasks) {
      _handleLostData();
      _loadOnlineUsers();
      _startHeartbeat();
    }
    _loadActivationState();

    // Glow animations
    _glowAnimation1 = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _glowAnimation2 = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) _glowAnimation2.repeat(reverse: true);
    });

    // Stats animation
    _statsAnimation = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();

    // Circular progress
    _circularProgressAnimation = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..forward();

    // Horizontal progress
    _horizontalProgressAnimation = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..forward();

    // Percentage
    _percentageAnimation = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _percentageAnimation.forward();
    });

    // Pulse
    _pulseAnimation = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);
  }

  Future<void> _loadActivationState() async {
    final results = await Future.wait<Object?>([
      _activationService.getSelectedLevel(),
      _activationService.isPracticeCompleted(),
      _activationService.isDismissed(),
    ]);
    if (!mounted) return;
    setState(() {
      _activationSelectedLevel = results[0] as String?;
      _activationPracticeCompleted = results[1] as bool? ?? false;
      _activationDismissed = results[2] as bool? ?? false;
    });
  }

  Future<void> _selectActivationLevel(String level) async {
    await _activationService.setSelectedLevel(level);
    if (!mounted) return;
    setState(() => _activationSelectedLevel = level);
  }

  Future<void> _dismissActivationCard() async {
    await _activationService.dismiss();
    if (!mounted) return;
    setState(() => _activationDismissed = true);
  }

  Future<void> _refreshActivationPracticeCompletion() async {
    if (_activationPracticeCompleted) return;
    final completed = await _activationService.isPracticeCompleted();
    if (!mounted || !completed) return;
    setState(() => _activationPracticeCompleted = true);
  }

  void _startHeartbeat() {
    // İlk heartbeat'i hemen gönder
    _socialService.sendHeartbeat();

    // Her 2 dakikada bir heartbeat gönder
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _socialService.sendHeartbeat();
    });
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _glowAnimation1.dispose();
    _glowAnimation2.dispose();
    _statsAnimation.dispose();
    _circularProgressAnimation.dispose();
    _horizontalProgressAnimation.dispose();
    _percentageAnimation.dispose();
    _pulseAnimation.dispose();
    super.dispose();
  }

  /// Level için minimum XP değerini döndürür
  int _getLevelMinXP(int level) {
    if (level <= 1) return 0;
    if (level == 2) return 100;
    if (level == 3) return 250;
    if (level == 4) return 500;
    if (level == 5) return 1000;
    if (level == 6) return 2000;
    if (level == 7) return 3500;
    if (level == 8) return 5500;
    if (level == 9) return 8000;
    if (level == 10) return 11000;
    // 10. seviyeden sonra her 5000 XP
    return 15000 + ((level - 11) * 5000);
  }

  Future<void> _loadOnlineUsers() async {
    try {
      final users = await UserDataService().getOnlineUsers();
      if (mounted) {
        setState(() => onlineUsers = users);
      }
    } catch (_) {}
  }

  Future<void> _handleLostData() async {
    if (Platform.isAndroid) {
      final picker = ImagePicker();
      final LostDataResponse response = await picker.retrieveLostData();
      if (response.isEmpty) return;
      if (response.file != null) {
        final path = response.file!.path;
        final prefs = await SharedPreferences.getInstance();

        await prefs.setString('profile_image_path', path);
        await prefs.setString('profile_image_type', 'gallery');

        // Provider'ı güncelle
        if (mounted) {
          context.read<AppStateProvider>().updateProfileImage(
                type: 'gallery',
                path: path,
              );
        }
      }
    }
  }

  // Pull-to-refresh için
  Future<void> _refreshData() async {
    final provider = context.read<AppStateProvider>();
    await Future.wait([
      provider.refreshUserData(),
      provider.refreshDailyWords(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin için gerekli

    return Consumer<AppStateProvider>(
      builder: (context, appState, child) {
        if (!_activationPracticeCompleted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _refreshActivationPracticeCompletion();
          });
        }
        final selectedTheme = _currentTheme(listen: true);
        final user = appState.userStats;
        final userName = appState.userName;
        final calendar = appState.weeklyActivity.isNotEmpty
            ? appState.weeklyActivity
            : [
                {'day': 'Mon', 'learned': false, 'count': 0},
                {'day': 'Tue', 'learned': false, 'count': 0},
                {'day': 'Wed', 'learned': false, 'count': 0},
                {'day': 'Thu', 'learned': false, 'count': 0},
                {'day': 'Fri', 'learned': false, 'count': 0},
                {'day': 'Sat', 'learned': false, 'count': 0},
                {'day': 'Sun', 'learned': false, 'count': 0},
              ];
        final dailyWords = appState.dailyWords;
        final isLoadingDailyWords = appState.isLoadingDailyWords;
        final profileImageType = appState.profileImageType;
        final profileImagePath = appState.profileImagePath;
        final avatarSeed = appState.avatarSeed;

        return Scaffold(
          body: Stack(
            children: [
              AnimatedBackground(
                isDark: true,
                enableAnimations: widget.enableBackgroundTasks,
              ),
              SafeArea(
                child: RefreshIndicator(
                  onRefresh: _refreshData,
                  color: selectedTheme.colors.accent,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      children: [
                        // Top Section
                        _buildTopSection(user, userName, profileImageType,
                            profileImagePath, avatarSeed),
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: [
                              _buildFirstSessionActivation(appState),
                              if (!_shouldHideActivationCard())
                                const SizedBox(height: 24),
                              // Stats Cards
                              _buildStatsCards(user),
                              const SizedBox(height: 24),
                              // Daily Words Section
                              _buildDailyWordsSection(
                                  dailyWords, isLoadingDailyWords, appState),
                              const SizedBox(height: 24),
                              // Daily Goal
                              _buildDailyGoal(user),
                              const SizedBox(height: 24),
                              // Weekly Calendar
                              _buildWeeklyCalendar(calendar),
                              const SizedBox(height: 24),
                              // Quick Actions
                              _buildQuickActions(),
                              // MVP: Social features disabled for v1.0
                              // const SizedBox(height: 24),
                              // Social Feed Preview
                              // const SocialFeedPreview(),
                              // const SizedBox(height: 24),
                              // Online Users
                              // _buildOnlineUsers(),
                              const SizedBox(height: 24),
                              // Recently Learned
                              _buildRecentlyLearned(),
                              const SizedBox(height: 80),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 18,
                bottom: 24,
                child: _buildSupportBubble(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopSection(Map<String, dynamic> user, String userName,
      String? profileImageType, String? profileImagePath, String avatarSeed) {
    final selectedTheme = _currentTheme();
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: selectedTheme.colors.accentGlow.withOpacity(0.18),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _mix(selectedTheme.colors.background,
                          selectedTheme.colors.accent, 0.18)
                      .withOpacity(0.78),
                  _mix(selectedTheme.colors.background,
                          selectedTheme.colors.primary, 0.16)
                      .withOpacity(0.74),
                  selectedTheme.colors.background.withOpacity(0.62),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
              border: Border.all(
                color: selectedTheme.colors.glassBorder.withOpacity(0.72),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile Picture and Level
                Column(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const ProfilePage()),
                        );
                        if (!mounted) return;
                        // Profil sayfasından dönünce verileri yenile
                        context.read<AppStateProvider>().refreshUserData();
                      },
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selectedTheme.colors.accent,
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: _buildProfileImageWidget(profileImageType,
                              profileImagePath, avatarSeed, userName),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${context.tr('common.level')} ${user['level']}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                // User Info & XP Progress
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: ShaderMask(
                              shaderCallback: (bounds) => selectedTheme
                                  .colors.buttonGradient
                                  .createShader(bounds),
                              child: Text(
                                '${context.tr('home.welcome')}, $userName',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              InfoDialog.show(
                                context,
                                title: context.tr('home.info.title'),
                                steps: [
                                  context.tr('home.info.step1'),
                                  context.tr('home.info.step2'),
                                  context.tr('home.info.step3'),
                                  context.tr('home.info.step4'),
                                  context.tr('home.info.step5'),
                                ],
                              );
                            },
                            icon: const Icon(Icons.info_outline,
                                color: Colors.white, size: 20),
                          ),
                          // MVP: Notification icon disabled for v1.0
                          // IconButton(
                          //   visualDensity: VisualDensity.compact,
                          //   onPressed: () {
                          //     Navigator.push(
                          //       context,
                          //       MaterialPageRoute(
                          //         builder: (_) => const NotificationsPage(),
                          //       ),
                          //     );
                          //   },
                          //   icon: const Icon(Icons.notifications_outlined,
                          //       color: Colors.white, size: 20),
                          // ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  context.tr('home.xpProgress'),
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 11,
                                  ),
                                ),
                                Flexible(
                                  child: Builder(
                                    builder: (context) {
                                      // Level-based XP hesaplama
                                      final totalXP = user['xp'] ?? 0;
                                      final level = user['level'] ?? 1;

                                      // Mevcut leveldeki ilerleme
                                      final currentLevelXP =
                                          _getLevelMinXP(level);
                                      final nextLevelXP =
                                          _getLevelMinXP(level + 1);
                                      final xpInCurrentLevel =
                                          totalXP - currentLevelXP;
                                      final xpNeededForLevel =
                                          nextLevelXP - currentLevelXP;

                                      return Text(
                                        '$xpInCurrentLevel / $xpNeededForLevel',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Builder(
                                builder: (context) {
                                  final totalXP = user['xp'] ?? 0;
                                  final level = user['level'] ?? 1;
                                  final currentLevelXP = _getLevelMinXP(level);
                                  final nextLevelXP = _getLevelMinXP(level + 1);
                                  final xpInCurrentLevel =
                                      totalXP - currentLevelXP;
                                  final xpNeededForLevel =
                                      nextLevelXP - currentLevelXP;
                                  final progress = xpNeededForLevel > 0
                                      ? (xpInCurrentLevel / xpNeededForLevel)
                                          .clamp(0.0, 1.0)
                                      : 0.0;

                                  return LinearProgressIndicator(
                                    value: progress,
                                    backgroundColor:
                                        Colors.white.withOpacity(0.2),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      selectedTheme.colors.accent,
                                    ),
                                    minHeight: 8,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${context.tr('home.nextLevelIn')} ${user['xpToNextLevel'] ?? 0} XP',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSupportBubble() {
    final selectedTheme = _currentTheme();
    return SafeArea(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => SupportTicketsPage.showModal(context),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: selectedTheme.colors.buttonGradient,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selectedTheme.colors.glassBorder.withOpacity(0.76),
              ),
              boxShadow: [
                BoxShadow(
                  color: selectedTheme.colors.accentGlow.withOpacity(0.30),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileImageWidget(String? profileImageType,
      String? profileImagePath, String avatarSeed, String userName) {
    final selectedTheme = _currentTheme();
    if (profileImageType == null) {
      return Container(
        color: Colors.grey[800],
        child: Center(
          child: CircularProgressIndicator(
            color: selectedTheme.colors.accent,
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (profileImageType == 'gallery' && profileImagePath != null) {
      return Image.file(
        File(profileImagePath),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _buildInitialsWidget(userName),
      );
    } else if (profileImageType == 'initials') {
      return _buildInitialsWidget(userName);
    } else {
      // Default avatar
      return Image.network(
        'https://api.dicebear.com/7.x/avataaars/png?seed=$avatarSeed',
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              color: selectedTheme.colors.accent,
              strokeWidth: 2,
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) =>
            _buildInitialsWidget(userName),
      );
    }
  }

  Widget _buildInitialsWidget(String userName) {
    final selectedTheme = _currentTheme();
    final initials = userName.isNotEmpty ? userName[0].toUpperCase() : '?';
    return Container(
      color: selectedTheme.colors.primary,
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  bool _shouldHideActivationCard() {
    return _activationDismissed;
  }

  String _activationText(String tr, String en) {
    return Localizations.localeOf(context).languageCode == 'tr' ? tr : en;
  }

  Widget _buildFirstSessionActivation(AppStateProvider appState) {
    if (_shouldHideActivationCard()) {
      return const SizedBox.shrink();
    }

    final selectedTheme = _currentTheme();
    final wordCount = appState.allWords.length;
    final sentenceCount = appState.allSentences.length;
    final hasLevel = (_activationSelectedLevel ?? '').isNotEmpty;
    final hasWords = wordCount >= 3;
    final hasSentence = sentenceCount > 0;
    final hasPractice = _activationPracticeCompleted;
    final completedCount = [
      hasLevel,
      hasWords,
      hasSentence,
      hasPractice,
    ].where((item) => item).length;
    final isComplete = completedCount == 4;

    String buttonLabel;
    VoidCallback buttonAction;
    if (!hasWords) {
      buttonLabel = _activationText('3 kelime ekle', 'Add 3 words');
      buttonAction = () => widget.onNavigate('words');
    } else if (!hasSentence) {
      buttonLabel = _activationText('İlk cümleyi ekle', 'Add first sentence');
      buttonAction = () => widget.onNavigate('sentences');
    } else if (!hasPractice) {
      buttonLabel = _activationText('İlk tekrarı yap', 'Do first review');
      buttonAction = () => widget.onNavigate('repeat');
    } else {
      buttonLabel = _activationText('Pratiğe devam et', 'Continue practice');
      buttonAction = () => widget.onNavigate('practice_speaking');
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _mix(selectedTheme.colors.background, selectedTheme.colors.accent,
                    0.16)
                .withOpacity(0.82),
            _mix(selectedTheme.colors.background, selectedTheme.colors.primary,
                    0.12)
                .withOpacity(0.76),
          ],
        ),
        border: Border.all(
          color: selectedTheme.colors.glassBorder.withOpacity(0.72),
        ),
        boxShadow: [
          BoxShadow(
            color: selectedTheme.colors.accentGlow.withOpacity(0.14),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: selectedTheme.colors.buttonGradient,
                ),
                child: const Icon(Icons.route_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _activationText(
                        'Bugünkü tek hedef',
                        'Today\'s one target',
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _activationText(
                        'İlk öğrenme döngünü tamamla: seviye, kelime, cümle, tekrar.',
                        'Complete your first learning loop: level, words, sentence, review.',
                      ),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.72),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (isComplete)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _dismissActivationCard,
                  icon: Icon(
                    Icons.close_rounded,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: completedCount / 4,
              minHeight: 8,
              backgroundColor: Colors.white.withOpacity(0.10),
              valueColor:
                  AlwaysStoppedAnimation<Color>(selectedTheme.colors.accent),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _activationText(
              '$completedCount / 4 adım tamamlandı',
              '$completedCount / 4 steps complete',
            ),
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            runSpacing: 10,
            spacing: 10,
            children: [
              _buildActivationStep(
                done: hasLevel,
                title: _activationSelectedLevel ??
                    _activationText('Seviye seç', 'Pick level'),
                subtitle: _activationText('A1-B2 arası', 'A1-B2'),
              ),
              _buildActivationStep(
                done: hasWords,
                title: _activationText('3 kelime', '3 words'),
                subtitle: '$wordCount / 3',
              ),
              _buildActivationStep(
                done: hasSentence,
                title: _activationText('1 cümle', '1 sentence'),
                subtitle: '$sentenceCount',
              ),
              _buildActivationStep(
                done: hasPractice,
                title: _activationText('1 tekrar', '1 review'),
                subtitle: hasPractice
                    ? _activationText('Tamam', 'Done')
                    : _activationText('Bekliyor', 'Pending'),
              ),
            ],
          ),
          if (!hasLevel) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['A1', 'A2', 'B1', 'B2']
                  .map(
                    (level) => _buildActivationLevelChip(level, selectedTheme),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: buttonAction,
              icon: Icon(isComplete
                  ? Icons.check_circle_rounded
                  : Icons.arrow_forward_rounded),
              label: Text(buttonLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: selectedTheme.colors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivationStep({
    required bool done,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: 154,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(done ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withOpacity(done ? 0.24 : 0.10),
        ),
      ),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            color: done ? Colors.white : Colors.white.withOpacity(0.48),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.62),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivationLevelChip(String level, AppThemeConfig selectedTheme) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _selectActivationLevel(level),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selectedTheme.colors.accent.withOpacity(0.16),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selectedTheme.colors.accent.withOpacity(0.42),
          ),
        ),
        child: Text(
          level,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildStatsCards(Map<String, dynamic> user) {
    final selectedTheme = _currentTheme();
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.emoji_events,
            value: user['totalWords'].toString(),
            label: '${context.tr('home.total')}\n${context.tr('nav.words')}',
            gradient: LinearGradient(
              colors: [
                selectedTheme.colors.accent.withOpacity(0.95),
                selectedTheme.colors.primary.withOpacity(0.95),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.whatshot,
            value: user['streak'].toString(),
            label: '${context.tr('home.days')}\n${context.tr('home.streak')}',
            gradient: LinearGradient(
              colors: [
                selectedTheme.colors.primaryLight.withOpacity(0.95),
                selectedTheme.colors.primaryDark.withOpacity(0.95),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.star,
            value: user['weeklyXP'].toString(),
            label: '${context.tr('home.thisWeek')}\nXP',
            gradient: LinearGradient(
              colors: [
                selectedTheme.colors.primaryDark.withOpacity(0.95),
                selectedTheme.colors.accent.withOpacity(0.95),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Gradient gradient,
  }) {
    return Container(
      height: 150, // Sabit yükseklik ile eşit boy
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.spaceEvenly, // Dikeyde eşit dağılım
        children: [
          Icon(icon, color: Colors.white, size: 28),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              height: 1.2,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildDailyGoal(Map<String, dynamic> user) {
    final selectedTheme = _currentTheme();
    final dailyGoal = user['dailyGoal'] ?? 5;
    final learnedToday = user['learnedToday'] ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            selectedTheme.colors.accent.withOpacity(0.16),
            selectedTheme.colors.primary.withOpacity(0.14),
            selectedTheme.colors.primaryDark.withOpacity(0.14),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selectedTheme.colors.glassBorder.withOpacity(0.72),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: selectedTheme.colors.accentGlow.withOpacity(0.34),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Stack(
            children: [
              // Animated Glow Background
              Positioned(
                top: 0,
                right: 0,
                child: AnimatedBuilder(
                  animation: _glowAnimation1,
                  builder: (context, child) {
                    return ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                      child: Container(
                        width: 128,
                        height: 128,
                        decoration: BoxDecoration(
                          color: selectedTheme.colors.accent
                              .withOpacity(_glowAnimation1.value * 0.4),
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  },
                ),
              ),

              Positioned(
                bottom: 0,
                left: 0,
                child: AnimatedBuilder(
                  animation: _glowAnimation2,
                  builder: (context, child) {
                    return ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: selectedTheme.colors.primary
                              .withOpacity(_glowAnimation2.value * 0.4),
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: selectedTheme.colors.buttonGradient,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: selectedTheme.colors.accentGlow
                                    .withOpacity(0.48),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.track_changes,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.tr('home.dailyGoal.title'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                context.tr('home.dailyGoal.subtitle'),
                                style: TextStyle(
                                  color: selectedTheme.colors.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Stats Grid
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0x0DFFFFFF), // white/5
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selectedTheme.colors.glassBorder
                                    .withOpacity(0.55),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: selectedTheme.colors.accent,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: selectedTheme
                                                .colors.accentGlow
                                                .withOpacity(0.52),
                                            blurRadius: 8,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      context.tr('home.today'),
                                      style: TextStyle(
                                        color:
                                            selectedTheme.colors.textSecondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ScaleTransition(
                                  scale: Tween<double>(begin: 0.0, end: 1.0)
                                      .animate(CurvedAnimation(
                                          parent: _statsAnimation,
                                          curve: Curves.elasticOut)),
                                  child: Text(
                                    '$learnedToday',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  context.tr('nav.words').toLowerCase(),
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0x0DFFFFFF),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selectedTheme.colors.glassBorder
                                    .withOpacity(0.46),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.auto_awesome,
                                      color: selectedTheme.colors.textSecondary,
                                      size: 12,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      context.tr('home.dailyGoal.target'),
                                      style: TextStyle(
                                        color:
                                            selectedTheme.colors.textSecondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '$dailyGoal',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  context.tr('nav.words').toLowerCase(),
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Circular Progress
                    Center(
                      child: SizedBox(
                        width: 128,
                        height: 128,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            AnimatedBuilder(
                              animation: _circularProgressAnimation,
                              builder: (context, child) {
                                return CustomPaint(
                                  size: const Size(128, 128),
                                  painter: CircularProgressPainter(
                                    progress: _circularProgressAnimation.value *
                                        (dailyGoal > 0
                                            ? learnedToday / dailyGoal
                                            : 0),
                                    gradientColors: [
                                      selectedTheme.colors.accent,
                                      selectedTheme.colors.primary,
                                      selectedTheme.colors.primaryLight,
                                    ],
                                  ),
                                );
                              },
                            ),
                            ScaleTransition(
                              scale: Tween<double>(begin: 0.0, end: 1.0)
                                  .animate(CurvedAnimation(
                                      parent: _percentageAnimation,
                                      curve: Curves.elasticOut)),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${dailyGoal > 0 ? ((learnedToday / dailyGoal) * 100).round() : 0}%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    context.tr('home.dailyGoal.completed'),
                                    style: TextStyle(
                                      color: selectedTheme.colors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Horizontal Progress Bar
                    Column(
                      children: [
                        Container(
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0x1AFFFFFF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: AnimatedBuilder(
                              animation: _horizontalProgressAnimation,
                              builder: (context, child) {
                                return FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor:
                                      _horizontalProgressAnimation.value *
                                          (dailyGoal > 0
                                              ? (learnedToday / dailyGoal)
                                                  .clamp(0.0, 1.0)
                                              : 0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          selectedTheme.colors.accent,
                                          selectedTheme.colors.primary,
                                          selectedTheme.colors.primaryLight,
                                        ],
                                      ),
                                    ),
                                    child: Stack(
                                      children: [
                                        // Pulse overlay
                                        AnimatedBuilder(
                                          animation: _pulseAnimation,
                                          builder: (context, child) {
                                            return Container(
                                              color: Colors.white.withOpacity(
                                                _pulseAnimation.value * 0.2,
                                              ),
                                            );
                                          },
                                        ),
                                        // White dot at end
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: Container(
                                            margin:
                                                const EdgeInsets.only(right: 2),
                                            width: 8,
                                            height: 8,
                                            decoration: const BoxDecoration(
                                              color: Colors.white,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Color(0x80FFFFFF),
                                                  blurRadius: 8,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '0',
                              style: TextStyle(
                                color: selectedTheme.colors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              context.tr('home.keepGoing'),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              '$dailyGoal',
                              style: TextStyle(
                                color: selectedTheme.colors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeeklyCalendar(List<Map<String, dynamic>> calendar) {
    final selectedTheme = _currentTheme();
    // Calculate stats
    int totalWords = calendar
        .where((d) => d['learned'] == true)
        .fold<int>(0, (sum, d) => sum + (d['count'] as int));
    int activeDays = calendar.where((d) => d['learned'] == true).length;

    // Get streak directly from Provider since we are inside State
    final streak = Provider.of<AppStateProvider>(context, listen: false)
            .userStats['streak'] ??
        0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            selectedTheme.colors.primary.withOpacity(0.14),
            selectedTheme.colors.accent.withOpacity(0.14),
            selectedTheme.colors.primaryDark.withOpacity(0.14),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selectedTheme.colors.glassBorder.withOpacity(0.72),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: selectedTheme.colors.accentGlow.withOpacity(0.34),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Stack(
            children: [
              // Floating Particles matches prompt
              ...List.generate(6, (i) {
                return FloatingParticle(
                  left: math.Random().nextDouble() * 300,
                  top: math.Random().nextDouble() *
                      200, // Adjusted height for card
                  index: i,
                );
              }),

              // Content
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Header with Streak Badge
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: selectedTheme.colors.buttonGradient,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: selectedTheme.colors.accentGlow
                                    .withOpacity(0.50),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.calendar_month,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.tr('home.weeklyActivity'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                context.tr('home.keepStreak'),
                                style: TextStyle(
                                  color: selectedTheme.colors.textSecondary,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFF97316),
                                Color(0xFFEF4444),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x80F97316),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.local_fire_department,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$streak ${context.tr('home.days')}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // 7 Day Grid
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        crossAxisSpacing:
                            8, // Reduced spacing for 7 items to fit
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.55, // Adjusted to prevent overflow
                      ),
                      itemCount: calendar.length,
                      itemBuilder: (context, index) {
                        final day = calendar[index];
                        return _DayCard(
                          day: day,
                          index: index,
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    // Weekly Summary
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0x0DFFFFFF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color:
                              selectedTheme.colors.glassBorder.withOpacity(0.6),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.emoji_events,
                            color: selectedTheme.colors.accent,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            context.tr('home.thisWeek'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                context.tr('home.total'),
                                style: TextStyle(
                                  color: selectedTheme.colors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$totalWords',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                context.tr('home.days'),
                                style: TextStyle(
                                  color: selectedTheme.colors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$activeDays/7',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _normalizeSynonyms(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is String) {
      return value
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

  String _normalizeDifficultyValue(dynamic value) {
    final raw = (value ?? 'medium').toString().toLowerCase().trim();
    switch (raw) {
      case 'easy':
      case 'kolay':
        return 'easy';
      case 'hard':
      case 'zor':
        return 'hard';
      default:
        return 'medium';
    }
  }

  Map<String, dynamic> _normalizeDailyWord(Map<String, dynamic> rawWord) {
    final word = (rawWord['word'] ?? rawWord['englishWord'] ?? '').toString();
    final translation =
        (rawWord['translation'] ?? rawWord['turkishMeaning'] ?? '').toString();
    final definition =
        (rawWord['definition'] ?? rawWord['englishDefinition'] ?? '')
            .toString();
    final exampleSentence =
        (rawWord['exampleSentence'] ?? rawWord['sentence'] ?? '').toString();
    final exampleTranslation = (rawWord['exampleTranslation'] ??
            rawWord['sentenceTranslation'] ??
            rawWord['translation'] ??
            rawWord['turkishMeaning'] ??
            '')
        .toString();
    final partOfSpeech =
        (rawWord['partOfSpeech'] ?? rawWord['type'] ?? 'Unknown').toString();
    final pronunciation = (rawWord['pronunciation'] ?? '').toString();

    return {
      ...rawWord,
      'word': word,
      'translation': translation,
      'definition': definition,
      'exampleSentence': exampleSentence,
      'exampleTranslation': exampleTranslation,
      'partOfSpeech': partOfSpeech,
      'pronunciation': pronunciation,
      'difficulty': _normalizeDifficultyValue(rawWord['difficulty']),
      'synonyms': _normalizeSynonyms(rawWord['synonyms']),
    };
  }

  void _showHomeMessage(String message, {bool success = true}) {
    if (!mounted) return;
    final selectedTheme = _currentTheme(listen: false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            success ? selectedTheme.colors.primary : Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _addDailyWordToLibrary(
    Map<String, dynamic> normalizedWord, {
    required bool withSentence,
  }) async {
    final appState = context.read<AppStateProvider>();
    final missingWordMessage = context.tr('home.snack.missingWord');
    final alreadyAddedMessage = context.tr('home.snack.alreadyAdded');
    final addFailedMessage = context.tr('home.snack.addFailed');
    final successMessage = withSentence
        ? context.tr('home.snack.wordSentenceAdded')
        : context.tr('home.snack.wordAdded');

    final wordText = (normalizedWord['word'] ?? '').toString().trim();
    final translationText =
        (normalizedWord['translation'] ?? '').toString().trim();
    final sentenceText =
        (normalizedWord['exampleSentence'] ?? '').toString().trim();
    final sentenceTranslation =
        (normalizedWord['exampleTranslation'] ?? '').toString().trim();

    if (wordText.isEmpty) {
      _showHomeMessage(missingWordMessage, success: false);
      return;
    }

    Word? existingWord = appState.findWordByEnglish(wordText);
    final sentenceAlreadyAdded = existingWord != null &&
        sentenceText.isNotEmpty &&
        appState.hasSentenceForWord(existingWord, sentenceText);

    if (existingWord != null && (!withSentence || sentenceAlreadyAdded)) {
      _showHomeMessage(alreadyAddedMessage);
      return;
    }

    Word? targetWord = existingWord;
    if (targetWord == null) {
      targetWord = await appState.addWord(
        english: wordText,
        turkish: translationText.isEmpty ? '⭐ $wordText' : '⭐ $translationText',
        addedDate: DateTime.now(),
        difficulty: _normalizeDifficultyValue(normalizedWord['difficulty']),
        source: 'daily_word',
      );
      if (targetWord == null) {
        _showHomeMessage(addFailedMessage, success: false);
        return;
      }
    }

    if (withSentence && sentenceText.isNotEmpty) {
      final hasSentence = appState.hasSentenceForWord(targetWord, sentenceText);
      if (!hasSentence) {
        await appState.addSentenceToWord(
          wordId: targetWord.id,
          sentence: sentenceText,
          translation: sentenceTranslation,
          difficulty: 'medium',
        );
      }
    }

    _showHomeMessage(successMessage);
  }

  Future<void> _showDailyWordActions(
    Map<String, dynamic> normalizedWord,
  ) async {
    final appState = context.read<AppStateProvider>();
    final wordText = (normalizedWord['word'] ?? '').toString();
    final sentenceText = (normalizedWord['exampleSentence'] ?? '').toString();
    final existingWord = appState.findWordByEnglish(wordText);
    final wordAdded = existingWord != null;
    final sentenceAdded = existingWord != null &&
        sentenceText.isNotEmpty &&
        appState.hasSentenceForWord(existingWord, sentenceText);
    final canAddSentence = sentenceText.trim().isNotEmpty;
    final selectedTheme = _currentTheme(listen: false);

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1F2E),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(
              color: selectedTheme.colors.glassBorder.withOpacity(0.7),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  Text(
                    wordText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    onTap: wordAdded
                        ? null
                        : () => Navigator.of(sheetContext).pop('word'),
                    leading: Icon(
                      wordAdded ? Icons.check_circle : Icons.add_circle_outline,
                      color: wordAdded ? Colors.greenAccent : Colors.white,
                    ),
                    title: Text(
                      context.tr('home.sheet.addWord'),
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      wordAdded
                          ? context.tr('home.sheet.wordAlreadyAdded')
                          : context.tr('home.sheet.addWordSubtitle'),
                      style: TextStyle(color: Colors.white.withOpacity(0.65)),
                    ),
                  ),
                  ListTile(
                    onTap: (!canAddSentence || sentenceAdded)
                        ? null
                        : () => Navigator.of(sheetContext).pop('word+sentence'),
                    leading: Icon(
                      sentenceAdded
                          ? Icons.check_circle
                          : Icons.playlist_add_rounded,
                      color: sentenceAdded ? Colors.greenAccent : Colors.white,
                    ),
                    title: Text(
                      context.tr('home.sheet.addWordWithSentence'),
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      !canAddSentence
                          ? context.tr('home.sheet.noExampleSentence')
                          : sentenceAdded
                              ? context
                                  .tr('home.sheet.wordAndSentenceAlreadyAdded')
                              : context
                                  .tr('home.sheet.addWordWithSentenceSubtitle'),
                      style: TextStyle(color: Colors.white.withOpacity(0.65)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    if (action == 'word') {
      await _addDailyWordToLibrary(normalizedWord, withSentence: false);
    } else if (action == 'word+sentence') {
      await _addDailyWordToLibrary(normalizedWord, withSentence: true);
    }
  }

  Future<void> _openDailyWordModal(Map<String, dynamic> normalizedWord) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return WordOfTheDayModal(
          wordData: normalizedWord,
          onClose: () => Navigator.of(dialogContext).pop(),
        );
      },
    );
  }

  List<Map<String, dynamic>> _fallbackDailyWords() {
    final todayKey = DateTime.now().toIso8601String().split('T')[0];
    final seed = todayKey.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
    final pool = <Map<String, dynamic>>[
      {
        'word': 'resilient',
        'translation': 'dayanikli',
        'definition': 'Able to recover quickly after difficulty.',
        'exampleSentence': 'A resilient plan can survive unexpected changes.',
        'exampleTranslation':
            'Dayanikli bir plan beklenmeyen degisikliklere dayanabilir.',
        'partOfSpeech': 'adjective',
        'difficulty': 'medium',
        'synonyms': ['flexible', 'strong'],
      },
      {
        'word': 'clarify',
        'translation': 'acikliga kavusturmak',
        'definition': 'To make an idea easier to understand.',
        'exampleSentence': 'Can you clarify the main goal of the project?',
        'exampleTranslation':
            'Projenin ana hedefini acikliga kavusturabilir misin?',
        'partOfSpeech': 'verb',
        'difficulty': 'easy',
        'synonyms': ['explain', 'simplify'],
      },
      {
        'word': 'insight',
        'translation': 'kavrayis',
        'definition': 'A clear understanding of a situation or idea.',
        'exampleSentence': 'The chart gave us useful insight into user habits.',
        'exampleTranslation':
            'Grafik bize kullanici aliskanliklari hakkinda faydali kavrayis sagladi.',
        'partOfSpeech': 'noun',
        'difficulty': 'medium',
        'synonyms': ['understanding', 'awareness'],
      },
      {
        'word': 'adapt',
        'translation': 'uyum saglamak',
        'definition': 'To change so something works better in a new situation.',
        'exampleSentence': 'Teams adapt faster when feedback is clear.',
        'exampleTranslation':
            'Geri bildirim net oldugunda ekipler daha hizli uyum saglar.',
        'partOfSpeech': 'verb',
        'difficulty': 'easy',
        'synonyms': ['adjust', 'modify'],
      },
      {
        'word': 'consistent',
        'translation': 'tutarli',
        'definition': 'Happening in the same reliable way over time.',
        'exampleSentence':
            'Consistent practice makes new words easier to remember.',
        'exampleTranslation':
            'Tutarli pratik yeni kelimeleri hatirlamayi kolaylastirir.',
        'partOfSpeech': 'adjective',
        'difficulty': 'easy',
        'synonyms': ['steady', 'regular'],
      },
    ];

    return List.generate(5, (index) {
      return Map<String, dynamic>.from(pool[(seed + index) % pool.length]);
    });
  }

  Widget _buildDailyWordsSection(List<Map<String, dynamic>> dailyWords,
      bool isLoadingDailyWords, AppStateProvider appState) {
    final selectedTheme = _currentTheme();
    if (isLoadingDailyWords) {
      return SizedBox(
        height: 180,
        child: Center(
          child: CircularProgressIndicator(color: selectedTheme.colors.accent),
        ),
      );
    }

    var normalizedWords = dailyWords
        .map(_normalizeDailyWord)
        .where((word) => (word['word'] ?? '').toString().trim().isNotEmpty)
        .take(5)
        .toList();

    if (normalizedWords.isEmpty) {
      normalizedWords = _fallbackDailyWords()
          .map(_normalizeDailyWord)
          .where((word) => (word['word'] ?? '').toString().trim().isNotEmpty)
          .take(5)
          .toList();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selectedTheme.colors.glassBorder.withOpacity(0.7),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book_rounded, color: selectedTheme.colors.accent),
              const SizedBox(width: 8),
              Text(
                context.tr('home.dailyWords.title'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${normalizedWords.length}',
                style: TextStyle(
                  color: selectedTheme.colors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 180,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: normalizedWords.length,
              itemBuilder: (context, index) {
                final wordData = normalizedWords[index];
                final wordText = (wordData['word'] ?? '').toString();
                final sentenceText =
                    (wordData['exampleSentence'] ?? '').toString();
                final existingWord = appState.findWordByEnglish(wordText);
                final isWordAdded = existingWord != null;
                final isSentenceAdded = existingWord != null &&
                    sentenceText.isNotEmpty &&
                    appState.hasSentenceForWord(existingWord, sentenceText);

                return DailyWordCard(
                  wordData: wordData,
                  index: index,
                  isWordAdded: isWordAdded,
                  isSentenceAdded: isSentenceAdded,
                  onTap: () => _openDailyWordModal(wordData),
                  onQuickAdd: () => _showDailyWordActions(wordData),
                  onAddSentence: () =>
                      _addDailyWordToLibrary(wordData, withSentence: true),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final actions = <Map<String, dynamic>>[
      {
        'icon': Icons.menu_book_rounded,
        'title': context.tr('home.quick.words.title'),
        'subtitle': context.tr('home.quick.words.subtitle'),
        'route': 'words',
      },
      {
        'icon': Icons.format_quote_rounded,
        'title': context.tr('home.quick.sentences.title'),
        'subtitle': context.tr('home.quick.sentences.subtitle'),
        'route': 'sentences',
      },
      {
        'icon': Icons.search_rounded,
        'title': context.tr('home.quick.dictionary.title'),
        'subtitle': context.tr('home.quick.dictionary.subtitle'),
        'route': 'dictionary',
      },
      {
        'icon': Icons.language_rounded,
        'title': context.tr('home.quick.language.title'),
        'subtitle': context.tr('home.quick.language.subtitle'),
        'route': 'language',
      },
      {
        'icon': Icons.refresh_rounded,
        'title': context.tr('home.quick.review.title'),
        'subtitle': context.tr('home.quick.review.subtitle'),
        'route': 'repeat',
      },
      {
        'icon': Icons.support_agent_rounded,
        'title': Localizations.localeOf(context).languageCode == 'tr'
            ? 'Destek'
            : 'Support',
        'subtitle': Localizations.localeOf(context).languageCode == 'tr'
            ? 'Ticketlarini gor ve yeni talep ac'
            : 'Open and review your tickets',
        'route': 'support',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('home.quickAccess.title'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final action in actions)
                  SizedBox(
                    width: cardWidth,
                    child: _buildQuickActionCard(
                      icon: action['icon'] as IconData,
                      title: action['title'] as String,
                      subtitle: action['subtitle'] as String,
                      route: action['route'] as String,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String route,
  }) {
    final selectedTheme = _currentTheme();
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => widget.onNavigate(route),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [
              selectedTheme.colors.primary.withOpacity(0.22),
              selectedTheme.colors.accent.withOpacity(0.20),
            ],
          ),
          border: Border.all(
            color: selectedTheme.colors.glassBorder.withOpacity(0.7),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: selectedTheme.colors.accent, size: 20),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: selectedTheme.colors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentlyLearned() {
    final selectedTheme = _currentTheme();
    final words = context.watch<AppStateProvider>().allWords;
    final recentWords = List<Word>.from(words)
      ..sort((a, b) => b.learnedDate.compareTo(a.learnedDate));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selectedTheme.colors.glassBorder.withOpacity(0.7),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('home.recent.title'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (recentWords.isEmpty)
            Text(
              context.tr('home.recent.empty'),
              style: TextStyle(
                color: selectedTheme.colors.textSecondary,
                fontSize: 13,
              ),
            )
          else
            Column(
              children: [
                for (final word in recentWords.take(5)) ...[
                  _buildRecentWordRow(word),
                  const SizedBox(height: 10),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildRecentWordRow(Word word) {
    final selectedTheme = _currentTheme();
    final difficulty = word.difficulty.toLowerCase();
    final chipColor = _difficultyColor(difficulty);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: chipColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                word.englishWord,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                word.turkishMeaning,
                style: TextStyle(
                  color: selectedTheme.colors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Text(
          _difficultyLabel(difficulty),
          style: TextStyle(
            color: chipColor,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Color _difficultyColor(String difficulty) {
    switch (difficulty) {
      case 'easy':
      case 'kolay':
        return Colors.greenAccent;
      case 'medium':
      case 'orta':
        return Colors.amberAccent;
      case 'hard':
      case 'zor':
        return Colors.redAccent;
      default:
        return Colors.lightBlueAccent;
    }
  }

  String _difficultyLabel(String difficulty) {
    switch (difficulty) {
      case 'easy':
      case 'kolay':
        return context.tr('home.difficulty.easy');
      case 'medium':
      case 'orta':
        return context.tr('home.difficulty.medium');
      case 'hard':
      case 'zor':
        return context.tr('home.difficulty.hard');
      default:
        return difficulty.isEmpty
            ? context.tr('home.difficulty.default')
            : difficulty;
    }
  }
}

// -----------------------------------------------------------------------------
// HELPER CLASSES - Ultra Modern UI
// -----------------------------------------------------------------------------

class CircularProgressPainter extends CustomPainter {
  final double progress;
  final List<Color> gradientColors;

  CircularProgressPainter(
      {required this.progress, required this.gradientColors});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 8) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Background circle
    final backgroundPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, backgroundPaint);

    // Gradient shader
    final gradient = SweepGradient(
      colors: gradientColors,
      startAngle: -math.pi / 2,
      endAngle: 3 * math.pi / 2,
    );

    // Progress arc
    final progressPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class FloatingParticle extends StatefulWidget {
  final double left;
  final double top;
  final int index;

  const FloatingParticle({
    super.key,
    required this.left,
    required this.top,
    required this.index,
  });

  @override
  State<FloatingParticle> createState() => _FloatingParticleState();
}

class _FloatingParticleState extends State<FloatingParticle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 50),
    ]).animate(CurvedAnimation(
      parent: _controller,
      curve: Interval(
        widget.index * 0.15,
        1.0,
        curve: Curves.easeInOut,
      ),
    ));

    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 50),
    ]).animate(CurvedAnimation(
      parent: _controller,
      curve: Interval(
        widget.index * 0.15,
        1.0,
        curve: Curves.easeInOut,
      ),
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ThemeProvider? themeProvider;
    try {
      themeProvider = Provider.of<ThemeProvider?>(context, listen: true);
    } catch (_) {
      themeProvider = null;
    }
    final selectedTheme =
        themeProvider?.currentTheme ?? VocabThemes.defaultTheme;

    return Positioned(
      left: widget.left,
      top: widget.top,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Opacity(
              opacity: _opacityAnimation.value,
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: selectedTheme.colors.particleColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DayCard extends StatefulWidget {
  final Map<String, dynamic> day;
  final int index;

  const _DayCard({required this.day, required this.index});

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(
          0.0,
          1.0,
          curve: Curves.easeOut,
        ),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(
          0.5,
          1.0,
          curve: Curves.elasticOut,
        ),
      ),
    );

    // Staggered delay
    Future.delayed(Duration(milliseconds: widget.index * 100), () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ThemeProvider? themeProvider;
    try {
      themeProvider = Provider.of<ThemeProvider?>(context, listen: true);
    } catch (_) {
      themeProvider = null;
    }
    final selectedTheme =
        themeProvider?.currentTheme ?? VocabThemes.defaultTheme;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: GestureDetector(
          onTap: () {},
          child: Container(
            decoration: BoxDecoration(
              gradient: (widget.day['learned'] == true)
                  ? LinearGradient(
                      colors: [
                        selectedTheme.colors.accent,
                        selectedTheme.colors.primary,
                      ],
                    )
                  : null,
              color: (widget.day['learned'] == true)
                  ? null
                  : const Color(0x1AFFFFFF),
              borderRadius: BorderRadius.circular(16),
              border: (widget.day['learned'] == true)
                  ? null
                  : Border.all(
                      color: selectedTheme.colors.glassBorder.withOpacity(0.42),
                      width: 1,
                    ),
              boxShadow: (widget.day['learned'] == true)
                  ? [
                      BoxShadow(
                        color:
                            selectedTheme.colors.accentGlow.withOpacity(0.52),
                        blurRadius: 16,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.day['day'],
                  style: TextStyle(
                    color: (widget.day['learned'] == true)
                        ? Colors.white
                        : selectedTheme.colors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                if (widget.day['learned'] == true)
                  ScaleTransition(
                    scale: _scaleAnimation,
                    child: Column(
                      children: [
                        Text(
                          '${widget.day['count']}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Icon(
                          Icons.star,
                          color: Colors.white.withOpacity(0.8),
                          size: 12,
                        ),
                      ],
                    ),
                  )
                else
                  const Text(
                    '·',
                    style: TextStyle(
                      color: Color(0x4DFFFFFF),
                      fontSize: 24,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
