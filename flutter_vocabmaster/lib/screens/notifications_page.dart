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
  final bool openedFromPush;
  final SocialService? socialService;

  const NotificationsPage({
    super.key,
    this.openedFromPush = false,
    this.socialService,
  });

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late final SocialService _socialService;
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
    _socialService = widget.socialService ?? SocialService();
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
        if (!widget.openedFromPush) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bildirimler yüklenemedi')),
          );
        }
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
                          ? _buildEmptyState(selectedTheme)
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: notifications.length +
                                  (widget.openedFromPush ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (widget.openedFromPush && index == 0) {
                                  return _buildPushReceivedCard(selectedTheme);
                                }
                                final dataIndex =
                                    widget.openedFromPush ? index - 1 : index;
                                return _buildNotificationCard(
                                  notifications[dataIndex],
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

  Widget _buildEmptyState(AppThemeConfig selectedTheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.openedFromPush) ...[
            _buildPushReceivedCard(selectedTheme),
            const SizedBox(height: 20),
          ],
          Text(
            widget.openedFromPush
                ? 'Bu test push başarıyla açıldı. Sosyal bildirim listeniz şu an boş.'
                : 'Henüz bildiriminiz yok.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selectedTheme.colors.textSecondary,
              fontSize: 15,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPushReceivedCard(AppThemeConfig selectedTheme) {
    return ModernCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(16),
      variant: BackgroundVariant.primary,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: selectedTheme.colors.accent.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_active_outlined,
              color: selectedTheme.colors.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Push bildirimi alındı',
                  style: TextStyle(
                    color: selectedTheme.colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Bu ekran sosyal bildirimleri listeler; test pushları burada kalıcı kayıt oluşturmaz.',
                  style: TextStyle(
                    color: selectedTheme.colors.textSecondary,
                    fontSize: 12,
                    height: 1.35,
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
                color: iconColor.withValues(alpha: 0.2),
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
