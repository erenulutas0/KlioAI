import 'package:flutter/material.dart';
import '../widgets/animated_background.dart';
import '../widgets/modern_card.dart';
import '../widgets/modern_background.dart';
import '../services/social_service.dart';
import 'chat_detail_page.dart';

class UserProfilePage extends StatefulWidget {
  final int userId;
  final String? initialName;
  final String? initialAvatar;

  const UserProfilePage({
    super.key,
    required this.userId,
    this.initialName,
    this.initialAvatar,
  });

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final SocialService _socialService = SocialService();
  
  Map<String, dynamic>? profile;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await _socialService.getUserProfile(widget.userId);
      if (mounted) {
        setState(() {
          profile = data;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = e.toString();
          isLoading = false;
        });
      }
    }
  }

  Future<void> _removeFriend() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1e1b4b),
        title: const Text('Arkadaşlıktan Çıkar', style: TextStyle(color: Colors.white)),
        content: Text(
          '${profile?['displayName'] ?? 'Bu kişiyi'} arkadaşlıktan çıkarmak istediğinize emin misiniz?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Çıkar', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _socialService.removeFriend(widget.userId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Arkadaşlıktan çıkarıldı'), backgroundColor: Colors.orange),
          );
          _loadProfile(); // Refresh
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _sendFriendRequest() async {
    if (profile == null || profile!['email'] == null) return;
    
    try {
      await _socialService.sendFriendRequest(profile!['email']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Arkadaşlık isteği gönderildi!'), backgroundColor: Colors.green),
        );
        _loadProfile(); // Refresh
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      const SizedBox(width: 8),
                      Text(
                        widget.initialName ?? 'Profil',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // Content
                Expanded(
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : errorMessage != null
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                                  const SizedBox(height: 16),
                                  Text(errorMessage!, style: const TextStyle(color: Colors.white70)),
                                ],
                              ),
                            )
                          : _buildProfileContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileContent() {
    if (profile == null) return const SizedBox();

    final displayName = profile!['displayName'] ?? 'Kullanıcı';
    final userTag = profile!['userTag'] ?? '';
    final email = profile!['email'] ?? '';
    final createdAt = profile!['createdAt'] ?? '';
    final isOnline = profile!['online'] == true;
    final isFriend = profile!['isFriend'] == true;
    final friendshipStatus = profile!['friendshipStatus'] ?? 'NONE';
    final isCurrentUser = profile!['isCurrentUser'] == true;
    final level = profile!['level'] ?? 1;
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Profile Card
          ModernCard(
            padding: const EdgeInsets.all(24),
            borderRadius: BorderRadius.circular(24),
            variant: BackgroundVariant.primary,
            child: Column(
              children: [
                // Avatar
                Stack(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: isOnline
                              ? [const Color(0xFF22d3ee), const Color(0xFF3b82f6)]
                              : [Colors.grey.shade600, Colors.grey.shade800],
                        ),
                      ),
                      child: Center(
                        child: Text(
                          initial,
                          style: const TextStyle(fontSize: 48, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: isOnline ? Colors.green : Colors.grey.shade500,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF1e1b4b), width: 3),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Name and Tag
                Text(
                  displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  userTag,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 8),

                // Online Status
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isOnline ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isOnline ? 'Çevrimiçi' : 'Çevrimdışı',
                      style: TextStyle(
                        color: isOnline ? Colors.green.shade300 : Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                const Divider(color: Colors.white10),
                const SizedBox(height: 16),

                // Stats Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem(Icons.star, 'Seviye', level.toString()),
                    _buildStatItem(Icons.calendar_today, 'Katılım', _formatDate(createdAt)),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Action Buttons
          if (!isCurrentUser) ...[
            // Friend Status Actions
            ModernCard(
              padding: const EdgeInsets.all(16),
              borderRadius: BorderRadius.circular(16),
              variant: BackgroundVariant.secondary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isFriend) ...[
                    // Already friends - show message and remove buttons
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatDetailPage(
                              userId: widget.userId,
                              name: displayName,
                              avatar: initial,
                              status: isOnline ? 'Çevrimiçi' : 'Çevrimdışı',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.message, color: Colors.white),
                      label: const Text('Mesaj Gönder', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22d3ee),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _removeFriend,
                      icon: const Icon(Icons.person_remove, color: Colors.redAccent),
                      label: const Text('Arkadaşlıktan Çıkar', style: TextStyle(color: Colors.redAccent)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ] else if (friendshipStatus == 'PENDING') ...[
                    // Request pending
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.hourglass_empty, color: Colors.orange),
                          SizedBox(width: 8),
                          Text(
                            'Arkadaşlık isteği bekliyor',
                            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // Not friends - show add button
                    ElevatedButton.icon(
                      onPressed: _sendFriendRequest,
                      icon: const Icon(Icons.person_add, color: Colors.white),
                      label: const Text('Arkadaş Ekle', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22d3ee),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Email Info (for friends only)
          if (isFriend || isCurrentUser)
            ModernCard(
              padding: const EdgeInsets.all(16),
              borderRadius: BorderRadius.circular(16),
              variant: BackgroundVariant.secondary,
              child: Row(
                children: [
                  const Icon(Icons.email, color: Colors.white54),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      email,
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF22d3ee), size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  String _formatDate(String dateString) {
    if (dateString.isEmpty) return '-';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString.split('T')[0];
    }
  }
}

