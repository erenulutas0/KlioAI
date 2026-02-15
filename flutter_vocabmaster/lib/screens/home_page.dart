import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;
import 'dart:async';

import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../models/word.dart'; // Add Word model
import '../widgets/animated_background.dart';
import '../services/user_data_service.dart';
import '../services/auth_service.dart';
import '../services/social_service.dart';
import '../widgets/info_dialog.dart';
import 'chat_list_page.dart';
import 'chat_detail_page.dart';
import 'profile_page.dart';
import 'social_feed_page.dart';
import '../widgets/social_feed_preview.dart';
import '../services/groq_service.dart';
import '../widgets/word_of_the_day_modal.dart';
import '../widgets/daily_word_card.dart';
import 'speaking_page.dart';
import 'review_page.dart';
import 'repeat_page.dart';
import '../providers/app_state_provider.dart';
import '../widgets/modern_card.dart';
import '../widgets/modern_background.dart';
import 'notifications_page.dart';

class HomePage extends StatefulWidget {
  final Function(String) onNavigate;
  final bool enableBackgroundTasks;

  const HomePage({
    Key? key,
    required this.onNavigate,
    this.enableBackgroundTasks = true,
  }) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
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

  @override
  void initState() {
    super.initState();
    if (widget.enableBackgroundTasks) {
      _handleLostData();
      _loadOnlineUsers();
      _startHeartbeat();
    }

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
                  color: const Color(0xFF22D3EE),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      children: [
                        // Top Section
                        _buildTopSection(user, userName, profileImageType, profileImagePath, avatarSeed),
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: [
                              // Stats Cards
                              _buildStatsCards(user),
                              const SizedBox(height: 24),
                              // Daily Words Section
                              _buildDailyWordsSection(dailyWords, isLoadingDailyWords),
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
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopSection(Map<String, dynamic> user, String userName, String? profileImageType, String? profileImagePath, String avatarSeed) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          const BoxShadow(
            color: Color(0x4D06B6D4),
            blurRadius: 20,
            offset: Offset(0, 4),
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
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0x4D06B6D4),
                  Color(0x4D3B82F6),
                  Color(0x4D8B5CF6),
                ],
                stops: [0.0, 0.5, 1.0],
              ),
              border: Border.all(
                color: const Color(0x4D22D3EE),
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
                        // Profil sayfasından dönünce verileri yenile
                        context.read<AppStateProvider>().refreshUserData();
                      },
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF22D3EE),
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
                          child: _buildProfileImageWidget(profileImageType, profileImagePath, avatarSeed, userName),
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
                            'Seviye ${user['level']}',
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
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [
                                  Color(0xFF22D3EE),
                                  Color(0xFF3B82F6),
                                ],
                              ).createShader(bounds),
                              child: Text(
                                'Welcome, $userName',
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
                                title: 'VocabMaster\'a Hoş Geldiniz',
                                steps: [
                                  'Her gün en az 5 yeni kelime öğrenerek günlük hedefinizi tamamlayın.',
                                  'Seriyi kırmayın! Ardışık günlerde çalışarak streak kazanmaya devam edin.',
                                  'Kazandığınız deneyim puanlarıyla (XP) seviye atlayın ve yeni özelliklerin kilidini açın.',
                                  'Öğrendiğiniz kelimeleri pratik, okuma ve konuşma aktiviteleriyle pekiştirin.',
                                  'İstatistikler ekranından haftalık ve aylık performansınızı detaylı analiz edin.',
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
                                      'XP İlerlemesi',
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
                                      final xpToNext = user['xpToNextLevel'] ?? 100;
                                      
                                      // Mevcut leveldeki ilerleme
                                      final currentLevelXP = _getLevelMinXP(level);
                                      final nextLevelXP = _getLevelMinXP(level + 1);
                                      final xpInCurrentLevel = totalXP - currentLevelXP;
                                      final xpNeededForLevel = nextLevelXP - currentLevelXP;
                                      
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
                                  final xpInCurrentLevel = totalXP - currentLevelXP;
                                  final xpNeededForLevel = nextLevelXP - currentLevelXP;
                                  final progress = xpNeededForLevel > 0 ? (xpInCurrentLevel / xpNeededForLevel).clamp(0.0, 1.0) : 0.0;
                                  
                                  return LinearProgressIndicator(
                                    value: progress,
                                    backgroundColor: Colors.white.withOpacity(0.2),
                                    valueColor: const AlwaysStoppedAnimation<Color>(
                                        Color(0xFF06b6d4)),
                                    minHeight: 8,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Sonraki seviyeye ${user['xpToNextLevel'] ?? 0} XP kaldı',
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

  Widget _buildProfileImageWidget(String? profileImageType, String? profileImagePath, String avatarSeed, String userName) {
    if (profileImageType == null) {
      return Container(
        color: Colors.grey[800],
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF0ea5e9), strokeWidth: 2),
        ),
      );
    }
    
    if (profileImageType == 'gallery' && profileImagePath != null) {
      return Image.file(
        File(profileImagePath),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildInitialsWidget(userName),
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
          return const Center(child: CircularProgressIndicator(color: Color(0xFF0ea5e9), strokeWidth: 2));
        },
        errorBuilder: (context, error, stackTrace) => _buildInitialsWidget(userName),
      );
    }
  }

  Widget _buildInitialsWidget(String userName) {
    final initials = userName.isNotEmpty ? userName[0].toUpperCase() : '?';
    return Container(
      color: const Color(0xFF0ea5e9),
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

  Widget _buildStatsCards(Map<String, dynamic> user) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.emoji_events,
            value: user['totalWords'].toString(),
            label: 'Toplam\nKelime',
            gradient: const LinearGradient(
              colors: [Color(0xFF06b6d4), Color(0xFF3b82f6)],
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
            label: 'Gün\nSerisi',
            gradient: const LinearGradient(
              colors: [Color(0xFF22d3ee), Color(0xFF3b82f6)],
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
            label: 'Bu Hafta\nXP',
            gradient: const LinearGradient(
              colors: [Color(0xFF3b82f6), Color(0xFF06b6d4)],
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
        mainAxisAlignment: MainAxisAlignment.spaceEvenly, // Dikeyde eşit dağılım
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
    final dailyGoal = user['dailyGoal'] ?? 5;
    final learnedToday = user['learnedToday'] ?? 0;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0x1A06B6D4), // cyan-500/10
            Color(0x1A3B82F6), // blue-500/10
            Color(0x1A8B5CF6), // purple-500/10
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0x4D22D3EE), // cyan-400/30
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4006B6D4), // cyan-500/25
            blurRadius: 24,
            offset: Offset(0, 8),
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
                          color: const Color(0xFF22D3EE).withOpacity(_glowAnimation1.value * 0.4),
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
                          color: const Color(0xFF3B82F6).withOpacity(_glowAnimation2.value * 0.4),
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
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF22D3EE),
                                Color(0xFF3B82F6),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x8006B6D4), // cyan-500/50
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
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Günlük Hedef',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Başarıya bir adım daha yakınsın!',
                                style: TextStyle(
                                  color: Color(0xFFBAE6FD), // cyan-200
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
                                color: const Color(0x3322D3EE), // cyan-400/20
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
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF22D3EE), // cyan-400
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Color(0x8022D3EE),
                                            blurRadius: 8,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Bugün',
                                      style: TextStyle(
                                        color: Color(0xFF7DD3FC), // cyan-300
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ScaleTransition(
                                  scale: Tween<double>(begin: 0.0, end: 1.0).animate(
                                    CurvedAnimation(parent: _statsAnimation, curve: Curves.elasticOut)
                                  ),
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
                                  'kelime',
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
                                color: const Color(0x3360A5FA), // blue-400/20
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.auto_awesome,
                                      color: Color(0xFF93C5FD), // blue-300
                                      size: 12,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Hedef',
                                      style: TextStyle(
                                        color: Color(0xFF93C5FD),
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
                                  'kelime',
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
                                      (dailyGoal > 0 ? learnedToday / dailyGoal : 0),
                                    gradientColors: const [
                                      Color(0xFF22D3EE),
                                      Color(0xFF3B82F6),
                                      Color(0xFF8B5CF6),
                                    ],
                                  ),
                                );
                              },
                            ),
                            ScaleTransition(
                              scale: Tween<double>(begin: 0.0, end: 1.0).animate(
                                CurvedAnimation(parent: _percentageAnimation, curve: Curves.elasticOut)
                              ),
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
                                  const Text(
                                    'tamamlandı',
                                    style: TextStyle(
                                      color: Color(0xFFBAE6FD),
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
                                  widthFactor: _horizontalProgressAnimation.value * 
                                    (dailyGoal > 0 ? (learnedToday / dailyGoal).clamp(0.0, 1.0) : 0),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Color(0xFF22D3EE),
                                          Color(0xFF3B82F6),
                                          Color(0xFF8B5CF6),
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
                                            margin: const EdgeInsets.only(right: 2),
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
                            const Text(
                              '0',
                              style: TextStyle(
                                color: Color(0xFF7DD3FC),
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              'Devam et!',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              '$dailyGoal',
                              style: const TextStyle(
                                color: Color(0xFFC4B5FD),
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
    // Calculate stats
    int totalWords = calendar.where((d) => d['learned'] == true).fold<int>(0, (sum, d) => sum + (d['count'] as int));
    int activeDays = calendar.where((d) => d['learned'] == true).length;
    
    // Get streak directly from Provider since we are inside State
    final streak = Provider.of<AppStateProvider>(context, listen: false).userStats['streak'] ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0x1A3B82F6), // blue-500/10
            Color(0x1A06B6D4), // cyan-500/10
            Color(0x1A14B8A6), // teal-500/10
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0x4D22D3EE), // cyan-400/30
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4006B6D4),
            blurRadius: 24,
            offset: Offset(0, 8),
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
                  top: math.Random().nextDouble() * 200, // Adjusted height for card
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
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF60A5FA),
                                Color(0xFF06B6D4),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x803B82F6),
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
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Haftalık Aktivite',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Seriyi devam ettir!',
                                style: TextStyle(
                                  color: Color(0xFFBAE6FD),
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                                '$streak gün',
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
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        crossAxisSpacing: 8, // Reduced spacing for 7 items to fit
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
                          color: const Color(0x3322D3EE),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.emoji_events,
                            color: Color(0xFF22D3EE),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Bu hafta',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'Toplam',
                                style: TextStyle(
                                  color: Color(0xFF7DD3FC),
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
                              const Text(
                                'Günler',
                                style: TextStyle(
                                  color: Color(0xFF93C5FD),
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

  Widget _buildSocialFeedPreview() {
    // Mock Data for Preview
    final previewPosts = [
      {
        'user': 'Sarah Johnson',
        'avatar': 'https://api.dicebear.com/7.x/avataaars/png?seed=Sarah',
        'time': '2 saat önce',
        'content': 'Just completed my 30-day streak! 🔥 Learned 150+ words this month. Consistency is key! #VocabMaster',
        'likes': 124,
        'comments': 15,
      },
      {
        'user': 'Emma Williams',
        'avatar': 'https://api.dicebear.com/7.x/avataaars/png?seed=Emma',
        'time': '5 saat önce',
        'content': "Pro tip: Watch your favorite Netflix shows in English with English subtitles. I've learned so many phrasal verbs this way!",
        'likes': 87,
        'comments': 8,
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A), // Dark blue base
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF22D3EE).withOpacity(0.3),
        ),
        boxShadow: [
           BoxShadow(
            color: const Color(0xFF22D3EE).withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Gradient Background
          Positioned.fill(
             child: Container(
               decoration: BoxDecoration(
                 borderRadius: BorderRadius.circular(24),
                 gradient: LinearGradient(
                   begin: Alignment.topLeft,
                   end: Alignment.bottomRight,
                   colors: [
                     const Color(0xFF22D3EE).withOpacity(0.05), // Cyan
                     const Color(0xFF14B8A6).withOpacity(0.05), // Teal
                   ],
                 ),
               ),
             ),
          ),
          
          // Glow Orbs (Simplified)
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF22D3EE).withOpacity(0.1), 
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF22D3EE).withOpacity(0.2),
                    blurRadius: 50,
                    spreadRadius: 20,
                  )
                ]
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.trending_up, color: Color(0xFF22D3EE), size: 24), // Cyan icon
                        const SizedBox(width: 8),
                        const Text(
                          'Social Feed',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SocialFeedPage())),
                      child: Row(
                        children: const [
                           Text('Tümü', style: TextStyle(color: Color(0xFF22D3EE), fontSize: 14)),
                           Icon(Icons.chevron_right, color: Color(0xFF22D3EE), size: 16),
                        ]
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 4),
                const Text(
                  'Toplulukla paylaş ve başkalarının deneyimlerinden öğren! 🌟',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                
                const SizedBox(height: 20),
                
                // Posts
                ...previewPosts.map((post) => _buildPreviewPostCard(post)).toList(),
                
                const SizedBox(height: 12),
                
                // CTA Button
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SocialFeedPage())),
                  child: ModernCard(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    borderRadius: BorderRadius.circular(16),
                    variant: BackgroundVariant.secondary,
                    showBorder: false,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.trending_up, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Tüm Paylaşımları Gör',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
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

  Widget _buildPreviewPostCard(Map<String, dynamic> post) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05), // Glassmorphism
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              // Avatar
               Container(
                 width: 40,
                 height: 40,
                 decoration: BoxDecoration(
                   shape: BoxShape.circle,
                   gradient: const LinearGradient(colors: [Color(0xFF22D3EE), Color(0xFF3B82F6)]),
                   border: Border.all(color: Colors.transparent, width: 2),
                 ),
                 child: Container(
                   decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF0F172A)),
                   child: ClipOval(
                      child: Image.network(post['avatar'], fit: BoxFit.cover,
                         errorBuilder: (c,e,s) => Center(child: Text(post['user'][0], style: const TextStyle(color: Colors.white))),
                      ),
                   ),
                 ),
               ),
               const SizedBox(width: 12),
               Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Text(post['user'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                   Text(post['time'], style: const TextStyle(color: Colors.white54, fontSize: 12)),
                 ],
               ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Content
          Text(
            post['content'],
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          
          const SizedBox(height: 12),
          
          // Interactions
          Row(
            children: [
              // Like
              Row(children: [
                const Icon(Icons.thumb_up, color: Color(0xFF22D3EE), size: 16),
                const SizedBox(width: 4),
                Text('${post['likes']}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ]),
              const SizedBox(width: 16),
              // Comment
              Row(children: [
                const Icon(Icons.message, color: Colors.white54, size: 16),
                const SizedBox(width: 4),
                Text('${post['comments']}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ]),
              const Spacer(),
              const Icon(Icons.bookmark_border, color: Colors.white54, size: 18),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return ModernCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(20),
      variant: BackgroundVariant.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
             mainAxisAlignment: MainAxisAlignment.spaceBetween,
             children: [
                const Text(
                  'Hızlı Erişim',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Tümünü Gör',
                  style: TextStyle(
                    color: Colors.cyan.withOpacity(0.8),
                    fontSize: 12,
                  ),
                ),
             ]
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildQuickActionButton(
                  icon: Icons.mic,
                  label: 'Konuşma',
                  width: 100,
                  onTap: () {
                    widget.onNavigate('practice_speaking');
                  },
                ),
                const SizedBox(width: 12),
                _buildQuickActionButton(
                  icon: Icons.repeat,
                  label: 'Tekrar',
                  width: 100,

                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const RepeatPage()),
                    );
                  },
                ),
                const SizedBox(width: 12),
                _buildQuickActionButton(
                  icon: Icons.menu_book,
                  label: 'Sözlük',
                  width: 100,
                  onTap: () => widget.onNavigate('dictionary'),
                ),
                // MVP: Sohbet disabled for v1.0
                // const SizedBox(width: 12),
                // _buildQuickActionButton(
                //    icon: Icons.chat_bubble_outline,
                //    label: 'Sohbet',
                //    width: 100,
                //    onTap: () {
                //      Navigator.push(
                //        context,
                //        MaterialPageRoute(builder: (context) => const ChatListPage()),
                //      );
                //    },
                // ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    double width = 100,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: 100, // Fixed height for consistency
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0x3306B6D4), Color(0x333B82F6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: const Color(0x4D22D3EE), width: 1),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
             BoxShadow(
              color: Color(0x3306B6D4),
              blurRadius: 12,
              spreadRadius: 2,
              offset: Offset(0, 4),
            )
          ],
        ),
        child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 28),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
        ),
      ),
    );
  }

  Widget _buildOnlineUsers() {
    return ModernCard(
      padding: const EdgeInsets.all(24),
      borderRadius: BorderRadius.circular(16),
      variant: BackgroundVariant.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.people, color: Color(0xFF22d3ee), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Biriyle Konuş',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (onlineUsers.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${onlineUsers.length} Çevrimiçi',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            onlineUsers.isEmpty 
              ? 'Şu anda çevrimiçi kullanıcı yok. Yeni arkadaşlar ekleyerek pratik yapabilirsiniz!'
              : 'Diğer kullanıcılarla İngilizce pratiği yapın ve arkadaşlar edinin!',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChatListPage()),
              );
            },
            child: ModernCard(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              borderRadius: BorderRadius.circular(16),
              variant: BackgroundVariant.secondary,
              showBorder: false,
              child: const Center(
                child: Text('Eşleş', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              ),
            ),
          ),
          const SizedBox(height: 24),
          ...onlineUsers.map((user) {
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF475569).withOpacity(0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.08),
                  width: 1,
                ),
              ),
              clipBehavior: Clip.hardEdge,
              child: Row(
                children: [
                  // SABİT: Avatar - 38px
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Color(0xFF22d3ee), Color(0xFF3b82f6)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              user['avatar'],
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                        ),
                        Positioned(
                          right: -1,
                          bottom: -1,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF475569),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // ESNEK: Kullanıcı Bilgisi
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            user['name'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star,
                                color: Colors.amber,
                                size: 12,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'Seviye ${user['level']}',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontSize: 11,
                                    height: 1.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // SABİT: Butonlar - Padding reduced
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () {},
                        child: Container(
                          height: 28,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF64748b),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'Ara',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1,
                            ),
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ChatDetailPage(
                                userId: user['id'] ?? 0, // Fallback for mock data
                                name: user['name'],
                                avatar: user['avatar'],
                                status: user['status'],
                              ),
                            ),
                          );
                        },
                        child: Container(
                          height: 28,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF06b6d4), Color(0xFF0ea5e9)],
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'Mesaj Gönder',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              height: 1,
                            ),
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildRecentlyLearned() {
    return ModernCard(
      padding: const EdgeInsets.all(24),
      borderRadius: BorderRadius.circular(16),
      variant: BackgroundVariant.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Son Öğrenilenler',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.5)),
            ],
          ),
          const SizedBox(height: 16),
          // Dynamic List from Provider
          Builder(
            builder: (context) {
              final provider = Provider.of<AppStateProvider>(context);
              List<Word> recentWords = provider.allWords;
              
              if (recentWords.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'Henüz kelime öğrenilmedi.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 14,
                      ),
                    ),
                  ),
                );
              }

              return Column(
                children: recentWords.take(5).map((word) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildLearnedWordItem(word),
                )).toList(),
              );
            }
          ),
        ],
      ),
    );
  }

  Widget _buildLearnedWordItem(Word wordObj) {
    final bool hasStar = wordObj.turkishMeaning.contains('★') || wordObj.turkishMeaning.contains('⭐');
    final String displayMeaning = wordObj.turkishMeaning.replaceAll('★', '').replaceAll('⭐', '').trim();

    return GestureDetector(
      onTap: () {
        // Kelime detaylarını ve cümleleri göster
        showDialog(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ModernCard(
                  variant: BackgroundVariant.primary,
                  borderRadius: BorderRadius.circular(24),
                  showGlow: true,
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            if (hasStar) ...[
                              const Icon(Icons.star, color: Color(0xFFFACC15), size: 24),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                wordObj.englishWord,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.pop(context),
                        icon: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    displayMeaning,
                    style: const TextStyle(
                      color: Color(0xFF00B4D8), // Cyan-500 equivalent
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFF10B981).withOpacity(0.5),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          wordObj.difficulty,
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (wordObj.sentences.isNotEmpty) ...[
                    const Text(
                      'Örnek Cümleler',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 110,
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        physics: const BouncingScrollPhysics(),
                        itemCount: wordObj.sentences.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final sentence = wordObj.sentences[index];
                          // Replicating Son Öğrenilenler item style (Secondary Variant)
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              // Approximate Secondary Gradient from ModernColors
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xE60F172A), // slate-900/90
                                  Color(0xD931297D), // indigo-950/85
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0x3322D3EE), // cyan-400/20 (Border color from ModernColors)
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  sentence.sentence,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontStyle: FontStyle.italic,
                                    height: 1.4,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                   sentence.translation,
                                   style: TextStyle(
                                     color: Colors.white.withOpacity(0.6),
                                     fontSize: 13,
                                     height: 1.4,
                                   ),
                                   maxLines: 1,
                                   overflow: TextOverflow.ellipsis,
                                 ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ] else
                     Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Henüz örnek cümle bulunmuyor.',
                        style: TextStyle(color: Colors.white.withOpacity(0.5)),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: ModernCard(
                      width: double.infinity,
                      variant: BackgroundVariant.accent,
                      borderRadius: BorderRadius.circular(14),
                      padding: const EdgeInsets.symmetric(vertical: 16), // Match previous padding
                      showGlow: true,
                      showBorder: false,
                      child: const Center(
                        child: Text(
                          'Tamam',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
          ),
        );
      },
      child: ModernCard(
        padding: const EdgeInsets.all(16),
        borderRadius: BorderRadius.circular(16),
        variant: BackgroundVariant.secondary, // Slightly different shade for items
        showBorder: false, // Less visual clutter for items
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0ea5e9).withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.check_circle_outline, color: Color(0xFF0ea5e9), size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Row(
                    children: [
                      if (hasStar) ...[
                         const Icon(Icons.star, color: Color(0xFFFACC15), size: 16),
                         const SizedBox(width: 4),
                      ],
                      Text(
                        wordObj.englishWord,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    displayMeaning,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3)),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyWordsSection(List<Map<String, dynamic>> dailyWords, bool isLoadingDailyWords) {
    if (isLoadingDailyWords) {
      return Container(
        height: 180,
        child: const Center(child: CircularProgressIndicator(color: Color(0xFF0ea5e9))),
      );
    }

    if (dailyWords.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0f172a).withOpacity(0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x4DFACC15)),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Color(0xFFFACC15), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Günün Kelimeleri',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Şu an yüklenemedi. İnternetinizi kontrol edin veya tekrar deneyin.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.65),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                context.read<AppStateProvider>().refreshDailyWords();
              },
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFDE047),
              ),
              child: const Text('Yenile'),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfilePage()),
                );
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
              ),
              child: const Text('Ayarlar'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          children: [
            const Icon(Icons.auto_awesome, color: Color(0xFFFACC15), size: 20), // Yellow-400
            const SizedBox(width: 8),
            const Text(
              'Günün Kelimeleri',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFEAB308).withOpacity(0.2), // Yellow-500/20
                    const Color(0xFFF97316).withOpacity(0.2), // Orange-500/20
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x4DFACC15)), // Yellow-400/30
              ),
              child: const Text(
                '5 Kelime', 
                style: TextStyle(color: Color(0xFFFDE047), fontSize: 12, fontWeight: FontWeight.bold) // Yellow-300
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Horizontal Scroll Cards
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          clipBehavior: Clip.none,
          padding: const EdgeInsets.symmetric(horizontal: 4), // Small offset for visual balance
          child: Row(
            children: dailyWords.asMap().entries.map((entry) {
              final index = entry.key;
              final word = entry.value;
              final appState = context.read<AppStateProvider>();
              final existingWord = appState.findWordByEnglish((word['word'] ?? '').toString());
              final wordAdded = existingWord != null;
              final sentenceAdded = wordAdded &&
                  appState.hasSentenceForWord(existingWord!, (word['exampleSentence'] ?? '').toString());
              return DailyWordCard(
                wordData: word,
                index: index,
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => WordOfTheDayModal(
                      wordData: word,
                      onClose: () => Navigator.pop(ctx),
                    ),
                  );
                },
                isWordAdded: wordAdded,
                isSentenceAdded: sentenceAdded,
                onQuickAdd: wordAdded ? null : () => _showQuickAddOptions(word, wordAdded: wordAdded, sentenceAdded: sentenceAdded),
                onAddSentence: (!wordAdded || sentenceAdded)
                    ? null
                    : () => _addWordToLibrary(word, withSentence: true),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  void _showQuickAddOptions(Map<String, dynamic> wordData, {required bool wordAdded, required bool sentenceAdded}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        if (wordAdded && sentenceAdded) {
          return Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wordData['word'] ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Color(0xFF10B981)),
                      SizedBox(width: 8),
                      Text('Kelime ve cümle zaten eklendi', style: TextStyle(color: Color(0xFF10B981))),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                wordData['word'] ?? '',
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Kelimeyi nasıl eklemek istersiniz?',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 24),
              
              if (wordAdded && !sentenceAdded) ...[
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.playlist_add, color: Colors.green),
                  ),
                  title: const Text('Cümlesini Ekle', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Kelime zaten ekli, sadece cümle eklenecek', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    _addWordToLibrary(wordData, withSentence: true);
                  },
                ),
              ] else ...[
                // Add Only Word
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.blue.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.add, color: Colors.blue),
                  ),
                  title: const Text('Sadece Kelimeyi Ekle', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Kelime listesine eklenir', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    _addWordToLibrary(wordData, withSentence: false);
                  },
                ),
                const SizedBox(height: 12),
                
                // Add With Sentence
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.playlist_add, color: Colors.green),
                  ),
                  title: const Text('Kelimeyi Cümlesiyle Ekle', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Hem kelime hem de örnek cümle eklenir', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    _addWordToLibrary(wordData, withSentence: true);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _addWordToLibrary(Map<String, dynamic> wordData, {required bool withSentence}) async {
    try {
      final appState = context.read<AppStateProvider>();
      final addedDate = DateTime.now();
      final wordText = (wordData['word'] ?? '').toString();
      final sentenceText = (wordData['exampleSentence'] ?? '').toString();
      final translationText = (wordData['exampleTranslation'] ?? '').toString();
      final existingWord = appState.findWordByEnglish(wordText);
      final wordAlreadyAdded = existingWord != null;
      final sentenceAlreadyAdded = wordAlreadyAdded &&
          appState.hasSentenceForWord(existingWord!, sentenceText);
      
      Word? word = existingWord;
      if (!wordAlreadyAdded) {
        // AppStateProvider üzerinden kelime ekle - otomatik XP ve stats güncellenir
        // source: 'daily_word' ile Günün Kelimesi XP'si verilir (+10 XP)
        word = await appState.addWord(
          english: wordText,
          turkish: "⭐ ${wordData['translation']}",
          addedDate: addedDate,
          difficulty: (wordData['difficulty'] as String? ?? 'Medium').toLowerCase(),
          source: 'daily_word', // Günün Kelimesi XP türü
        );
      }

      if (withSentence && word != null && !sentenceAlreadyAdded) {
        // AppStateProvider üzerinden cümle ekle - otomatik XP güncellenir (+5 XP)
        await appState.addSentenceToWord(
          wordId: word.id,
          sentence: sentenceText,
          translation: translationText,
          difficulty: 'medium',
        );
      }

      if (mounted) {
        String message;
        if (wordAlreadyAdded && sentenceAlreadyAdded) {
          message = 'Kelime ve cümle zaten eklendi.';
        } else if (wordAlreadyAdded && withSentence) {
          message = 'Kelime ekli, cümle eklendi! +5 XP';
        } else if (wordAlreadyAdded) {
          message = 'Kelime zaten ekli.';
        } else {
          message = withSentence ? 'Kelime ve cümle eklendi! +15 XP' : 'Kelime eklendi! +10 XP';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata oluştu: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  Color _getDifficultyColor(String? difficulty) {
    switch ((difficulty ?? '').toLowerCase()) {
      case 'easy': return Colors.greenAccent;
      case 'medium': return Colors.amberAccent;
      case 'hard': return Colors.redAccent;
      default: return Colors.blueAccent;
    }
  }
}

// -----------------------------------------------------------------------------
// HELPER CLASSES - Ultra Modern UI
// -----------------------------------------------------------------------------

class CircularProgressPainter extends CustomPainter {
  final double progress;
  final List<Color> gradientColors;
  
  CircularProgressPainter({required this.progress, required this.gradientColors});
  
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
    Key? key,
    required this.left,
    required this.top,
    required this.index,
  }) : super(key: key);
  
  @override
  _FloatingParticleState createState() => _FloatingParticleState();
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
                decoration: const BoxDecoration(
                  color: Color(0xFF22D3EE),
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
  _DayCardState createState() => _DayCardState();
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
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: GestureDetector(
          onTap: () {},
          child: Container(
            decoration: BoxDecoration(
              gradient: (widget.day['learned'] == true)
                  ? const LinearGradient(
                      colors: [
                        Color(0xFF22D3EE),
                        Color(0xFF3B82F6),
                      ],
                    )
                  : null,
              color: (widget.day['learned'] == true) ? null : const Color(0x1AFFFFFF),
              borderRadius: BorderRadius.circular(16),
              border: (widget.day['learned'] == true)
                  ? null
                  : Border.all(
                      color: const Color(0x33FFFFFF),
                      width: 1,
                    ),
              boxShadow: (widget.day['learned'] == true)
                  ? const [
                      BoxShadow(
                        color: Color(0x8006B6D4),
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
                        : const Color(0xFF7DD3FC),
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
