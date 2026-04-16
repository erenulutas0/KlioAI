import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../widgets/animated_background.dart';
import '../widgets/bottom_nav.dart';
import '../services/user_data_service.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';

import '../widgets/navigation_menu_panel.dart';
import '../main.dart'; // Import MainScreen
import '../screens/profile_page.dart';
import '../screens/chat_list_page.dart';
import '../screens/quick_dictionary_page.dart';
import '../screens/social_feed_page.dart';
import '../widgets/modern_card.dart';
import '../widgets/modern_background.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  final UserDataService _userDataService = UserDataService();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  bool _isLoading = true;
  List<Map<String, dynamic>> _achievements = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStats();
    });
  }

  Future<void> _loadStats() async {
    try {
      // AppState'i yenile
      final appState = context.read<AppStateProvider>();
      await appState.refreshUserData();
      
      // Achievements'ı ayrıca yükle
      final achievements = await _userDataService.getAchievements();
      
      if (mounted) {
        setState(() {
          if (achievements.isNotEmpty) _achievements = achievements;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Stats yükleme hatası: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Provider'ı dinle (Watch)
    final appState = context.watch<AppStateProvider>();
    final userStats = appState.userStats;
    final weeklyActivity = appState.weeklyActivity;
    
    // Eğer weeklyActivity boşsa (henüz yüklenmediyse) mock data oluştur
    final displayWeeklyActivity = weeklyActivity.isNotEmpty 
        ? weeklyActivity 
        : List.generate(7, (index) => {'day': index, 'count': 0});

    return Scaffold(
      key: _scaffoldKey,
      drawer: NavigationMenuPanel(
        activeTab: '', 
        currentPage: 'stats', 
        onTabChange: (id) {
           Navigator.pop(context); 
           if (['home', 'words', 'sentences', 'practice'].contains(id)) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => MainScreen(initialIndex: 
                  id == 'home' ? 0 : 
                  id == 'words' ? 1 : 
                  id == 'sentences' ? 3 : 4
                )),
                (route) => false,
              );
           }
        },
        onNavigate: (id) {
           Navigator.pop(context);
           
           if (id == 'stats') return;
               
               if (id == 'chat') {
                   Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChatListPage()));
               } else if (id == 'feed') {
                   Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SocialFeedPage()));
               } else if (id == 'speaking') {
                   Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const MainScreen(initialIndex: 4)), 
                    (route) => false,
                  );
               } else if (id == 'dictionary') {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuickDictionaryPage()));
               } else if (id == 'repeat') {
                   Navigator.of(context).pushNamed('/review'); 
               } else if (id == 'profile-settings') {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfilePage()));
               }
            },
      ),
      body: Stack(
        children: [
          const AnimatedBackground(isDark: true),
          SafeArea(
            child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF06b6d4)))
              : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'İstatistiklerim',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Top Stats Cards
                    Row(
                      children: [
                        Expanded(
                          child: _buildTopStatCard(
                            icon: Icons.menu_book,
                            value: (userStats['totalWords'] ?? 0).toString(),
                            label: 'Toplam Kelime',
                            color: const Color(0xFF06b6d4),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTopStatCard(
                            icon: Icons.local_fire_department,
                            value: (userStats['streak'] ?? 0).toString(),
                            label: 'Gün Serisi',
                            color: const Color(0xFF06b6d4),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Weekly Progress Chart
                    _buildWeeklyProgressCard(displayWeeklyActivity),
                    
                    const SizedBox(height: 24),
                    
                    // XP Progress Chart
                    _buildXPProgressCard(displayWeeklyActivity),
                    
                    const SizedBox(height: 24),
                    
                    // Achievements
                    _buildAchievements(),
                    
                    const SizedBox(height: 80),
                  ],
                ),
              ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // MVP: GlobalMatchmakingSheet disabled for v1.0
          // const GlobalMatchmakingSheet(),
          BottomNav(
            currentIndex: -1, // No tab selected usually, or maybe 2 if we consider menu? -1 is safer.
            onTap: (index) {
              if (index == 2) {
                 _scaffoldKey.currentState?.openDrawer();
              } else {
                 Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => MainScreen(initialIndex: index)),
                    (route) => false,
                 );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTopStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return ModernCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(20),
      variant: BackgroundVariant.primary,
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 40),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyProgressCard(List<Map<String, dynamic>> weeklyActivity) {
    // Haftalık aktivite verilerinden bar chart data oluştur
    final weeklyData = weeklyActivity.asMap().entries.map((entry) {
      final dayNames = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
      final dayIndex = entry.key;
      final count = entry.value['count'] as int? ?? 0;
      return {
        'day': dayNames[dayIndex],
        'value': count.toDouble(),
      };
    }).toList();

    // Eğer veri yoksa default boş göster
    if (weeklyData.isEmpty) {
      return ModernCard(
        padding: const EdgeInsets.all(20),
        borderRadius: BorderRadius.circular(20),
        variant: BackgroundVariant.primary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.calendar_today, color: Color(0xFF06b6d4), size: 20),
                SizedBox(width: 8),
                Text(
                  'Haftalık İlerleme',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'Henüz veri yok',
                style: TextStyle(color: Colors.white.withOpacity(0.5)),
              ),
            ),
          ],
        ),
      );
    }

    final maxY = weeklyData.map((d) => d['value'] as double).reduce((a, b) => a > b ? a : b);
    final chartMaxY = maxY > 0 ? (maxY + 2).ceilToDouble() : 10.0;

    return ModernCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(20),
      variant: BackgroundVariant.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.calendar_today, color: Color(0xFF06b6d4), size: 20),
              SizedBox(width: 8),
              Text(
                'Haftalık İlerleme',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: chartMaxY,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() >= 0 && value.toInt() < weeklyData.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              weeklyData[value.toInt()]['day'] as String,
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.white.withOpacity(0.1),
                      strokeWidth: 1,
                    );
                  },
                ),
                borderData: FlBorderData(show: false),
                barGroups: weeklyData.asMap().entries.map((entry) {
                  return BarChartGroupData(
                    x: entry.key,
                    barRods: [
                      BarChartRodData(
                        toY: entry.value['value'] as double,
                        color: const Color(0xFF06b6d4),
                        width: 16,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildXPProgressCard(List<Map<String, dynamic>> weeklyActivity) {
    // Haftalık XP verilerini hesapla
    final xpData = weeklyActivity.asMap().entries.map((entry) {
      final count = entry.value['count'] as int? ?? 0;
      return FlSpot(entry.key.toDouble(), (count * 10).toDouble());
    }).toList();

    // Eğer veri yoksa veya tüm değerler 0 ise
    final hasData = xpData.isNotEmpty && xpData.any((spot) => spot.y > 0);

    if (!hasData) {
      return ModernCard(
        padding: const EdgeInsets.all(20),
        borderRadius: BorderRadius.circular(20),
        variant: BackgroundVariant.primary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.stars, color: Color(0xFF06b6d4), size: 20),
                SizedBox(width: 8),
                Text(
                  'XP Gelişimi',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'Henüz XP kazanılmadı',
                style: TextStyle(color: Colors.white.withOpacity(0.5)),
              ),
            ),
          ],
        ),
      );
    }

    final maxY = xpData.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final chartMaxY = maxY > 0 ? (maxY * 1.2).ceilToDouble() : 100.0;

    return ModernCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(20),
      variant: BackgroundVariant.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.stars, color: Color(0xFF06b6d4), size: 20),
              SizedBox(width: 8),
              Text(
                'XP Gelişimi',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.white.withOpacity(0.1),
                      strokeWidth: 1,
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        const days = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
                        if (value.toInt() >= 0 && value.toInt() < days.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              days[value.toInt()],
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: 6,
                minY: 0,
                maxY: chartMaxY,
                lineBarsData: [
                  LineChartBarData(
                    spots: xpData,
                    isCurved: true,
                    color: const Color(0xFF06b6d4),
                    barWidth: 3,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 4,
                          color: const Color(0xFF06b6d4),
                          strokeWidth: 2,
                          strokeColor: Colors.white,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF06b6d4).withOpacity(0.2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievements() {
    return ModernCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(20),
      variant: BackgroundVariant.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.emoji_events, color: Color(0xFF06b6d4), size: 20),
              SizedBox(width: 8),
              Text(
                'Başarılar',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.75,
            ),
            itemCount: _achievements.length,
            itemBuilder: (context, index) {
              final achievement = _achievements[index];
              final unlocked = achievement['unlocked'] as bool? ?? false;
              
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: unlocked 
                      ? const Color(0xFF3b82f6).withOpacity(0.3)
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: unlocked 
                        ? const Color(0xFF3b82f6)
                        : Colors.white.withOpacity(0.1),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      achievement['icon'] as String? ?? '🎯',
                      style: TextStyle(
                        fontSize: 40,
                        color: unlocked ? null : Colors.white.withOpacity(0.3),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      achievement['title'] as String? ?? '',
                      style: TextStyle(
                        color: unlocked ? Colors.white : Colors.white.withOpacity(0.5),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      achievement['desc'] as String? ?? '',
                      style: TextStyle(
                        color: unlocked ? Colors.white70 : Colors.white.withOpacity(0.3),
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

