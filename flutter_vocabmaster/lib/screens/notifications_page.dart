import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/social_service.dart';
import '../widgets/modern_card.dart';
import '../widgets/modern_background.dart';
import '../widgets/animated_background.dart';
import '../theme/app_theme.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final SocialService _socialService = SocialService();
  List<dynamic> notifications = [];
  bool isLoading = true;

  AppThemeConfig _currentTheme({bool listen = true}) {
    try {
      return Provider.of<ThemeProvider?>(context, listen: listen)
              ?.currentTheme ??
          VocabThemes.defaultTheme;
    } catch (_) {
      return VocabThemes.defaultTheme;
    }
  }

  Color _notificationIconColor(String type, AppThemeConfig theme) {
    switch (type) {
      case 'LIKE':
        return theme.colors.accent;
      case 'COMMENT':
        return theme.colors.primary;
      case 'MESSAGE':
        return theme.colors.primaryLight;
      default:
        return theme.colors.textSecondary;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final data = await _socialService.getNotifications();
      if (mounted) {
        setState(() {
          notifications = data;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bildirimler yüklenemedi')));
      }
    }
  }

  Future<void> _markAsRead(int id) async {
    try {
      await _socialService.markNotificationAsRead(id);
      setState(() {
        final index = notifications.indexWhere((n) => n['id'] == id);
        if (index != -1) {
          notifications[index]['isRead'] = true;
        }
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final selectedTheme = _currentTheme(listen: true);
    return Scaffold(
      body: Stack(
        children: [
          const AnimatedBackground(isDark: true),
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Text(
                        'Bildirimler',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: isLoading
                      ? Center(
                          child: CircularProgressIndicator(
                            color: selectedTheme.colors.accent,
                          ),
                        )
                      : notifications.isEmpty
                          ? Center(
                              child: Text(
                                'Henüz bildiriminiz yok.',
                                style: TextStyle(
                                  color: selectedTheme.colors.textSecondary,
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: notifications.length,
                              itemBuilder: (context, index) {
                                final notification = notifications[index];
                                return _buildNotificationCard(
                                  notification,
                                  selectedTheme,
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(
    Map<String, dynamic> notification,
    AppThemeConfig selectedTheme,
  ) {
    final bool isRead = notification['read'] ?? false; // Backend 'read' boolean
    final String message = notification['message'] ?? '';
    final String type = notification['type'] ?? 'INFO'; // LIKE, COMMENT, etc.

    IconData icon;
    final Color iconColor = _notificationIconColor(type, selectedTheme);

    switch (type) {
      case 'LIKE':
        icon = Icons.favorite;
        break;
      case 'COMMENT':
        icon = Icons.comment;
        break;
      case 'MESSAGE':
        icon = Icons.chat_bubble;
        break;
      default:
        icon = Icons.notifications;
    }

    return GestureDetector(
      onTap: () {
        if (!isRead) {
          _markAsRead(notification['id']);
        }
      },
      child: ModernCard(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        borderRadius: BorderRadius.circular(16),
        variant:
            isRead ? BackgroundVariant.secondary : BackgroundVariant.primary,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: isRead ? Colors.white70 : Colors.white,
                  fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                ),
              ),
            ),
            if (!isRead)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: selectedTheme.colors.accent,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
