import 'package:flutter/material.dart';
import '../widgets/animated_background.dart';
import 'chat_detail_page.dart';
import 'user_profile_page.dart';
import '../widgets/global_matchmaking_sheet.dart';
import '../widgets/modern_card.dart';
import '../widgets/modern_background.dart';
import '../services/chat_service.dart';
import '../services/social_service.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> with SingleTickerProviderStateMixin {
  final ChatService _chatService = ChatService();
  final SocialService _socialService = SocialService();
  
  List<dynamic> conversations = [];
  List<dynamic> allUsers = [];
  bool isLoading = true;
  
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final List<dynamic> loadedConversations = await _chatService.getConversations();
      final List<dynamic> loadedUsers = await _socialService.getFriends();
      if (mounted) {
        setState(() {
          conversations = loadedConversations;
          allUsers = loadedUsers;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Veri yüklenemedi: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
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
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sohbet',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Arkadaşlarınla mesajlaş',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Tab Bar
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: const Color(0xFF22d3ee),
                    ),
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    tabs: [
                      Tab(text: 'Sohbetler (${conversations.length})'),
                      Tab(text: 'Arkadaşlar (${allUsers.length})'),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Tab Bar View
                Expanded(
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            // Sohbetler Tab
                            conversations.isEmpty
                                ? const Center(child: Text('Henüz kimseyle sohbet etmediniz.', style: TextStyle(color: Colors.white54)))
                                : ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    itemCount: conversations.length,
                                    itemBuilder: (context, index) {
                                      final user = conversations[index];
                                      return _buildChatCard(user);
                                    },
                                  ),
                            // Arkadaşlar Tab
                            allUsers.isEmpty
                                ? const Center(child: Text('Henüz arkadaş yok.', style: TextStyle(color: Colors.white54)))
                                : ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    itemCount: allUsers.length,
                                    itemBuilder: (context, index) {
                                      final user = allUsers[index];
                                      return _buildFriendCard(user);
                                    },
                                  ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const GlobalMatchmakingSheet(),
    );
  }

  Widget _buildChatCard(Map<String, dynamic> user) {
    // Default avatar extraction logic (first letter of name or generic icon)
    String displayName = user['displayName'] ?? 'Kullanıcı';
    String initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    bool isOnline = user['online'] == true;
    
    return Opacity(
      opacity: isOnline ? 1.0 : 0.7,
      child: ModernCard(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        borderRadius: BorderRadius.circular(24),
        variant: BackgroundVariant.primary,
        child: Column(
          children: [
            Row(
              children: [
                Stack(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: isOnline
                              ? [const Color(0xFF22d3ee), const Color(0xFF3b82f6)]
                              : [Colors.grey.shade600, Colors.grey.shade800],
                        ),
                      ),
                      child: Center(
                        child: Text(initial, style: const TextStyle(fontSize: 30, color: Colors.white)),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: isOnline ? Colors.green : Colors.grey.shade500,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF1e1b4b), width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          // Timestamp removed since we don't have last message info yet
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Row(
                        children: [
                          Icon(Icons.star, color: Colors.amber, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Seviye ?', // User entity doesn't have level exposed in list yet
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Mock "Last Message" placeholder
                      Text(
                        isOnline ? "Şu an çevrimiçi" : "Son görülme yakın zamanda",
                        style: TextStyle(
                            color: isOnline ? Colors.green.shade300 : Colors.white54, 
                            fontSize: 13,
                            fontStyle: FontStyle.italic
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white10),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ModernCard(
                    height: 44,
                    padding: EdgeInsets.zero,
                    borderRadius: BorderRadius.circular(12),
                    variant: BackgroundVariant.secondary,
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UserProfilePage(
                              userId: user['id'],
                              initialName: displayName,
                              initialAvatar: initial,
                            ),
                          ),
                        ).then((_) => _loadData());
                      },
                      child: const Center(
                        child: Text('Profili Gör', style: TextStyle(color: Colors.white70)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ModernCard(
                    height: 44,
                    padding: EdgeInsets.zero,
                    borderRadius: BorderRadius.circular(12),
                    variant: BackgroundVariant.accent,
                    showGlow: true,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChatDetailPage(
                              userId: user['id'],
                              name: displayName,
                              avatar: initial,
                              status: isOnline ? 'Çevrimiçi' : 'Çevrimdışı',
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: EdgeInsets.zero,
                      ),
                      child: const Center(
                        child: Text('Mesaj Gönder', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendCard(Map<String, dynamic> user) {
    String displayName = user['displayName'] ?? user['name'] ?? 'Kullanıcı';
    String userTag = user['userTag'] ?? '';
    String initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    bool isOnline = user['online'] == true;
    String statusText = isOnline ? 'Çevrimiçi' : 'Çevrimdışı';

    return Opacity(
      opacity: isOnline ? 1.0 : 0.6, // Offline kullanıcılar sönük
      child: ModernCard(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        borderRadius: BorderRadius.circular(16),
        variant: BackgroundVariant.secondary,
        child: Row(
          children: [
            // Avatar with online indicator
            Stack(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: isOnline 
                          ? [const Color(0xFF22d3ee), const Color(0xFF3b82f6)]
                          : [Colors.grey.shade600, Colors.grey.shade800],
                    ),
                  ),
                  child: Center(
                    child: Text(initial, style: const TextStyle(fontSize: 24, color: Colors.white)),
                  ),
                ),
                // Online indicator dot
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: isOnline ? Colors.green : Colors.grey.shade500,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF1e1b4b), width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      color: isOnline ? Colors.white : Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (userTag.isNotEmpty)
                    Text(
                      userTag,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isOnline ? Colors.green : Colors.grey.shade500,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF1e1b4b), width: 2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: isOnline ? Colors.green.shade300 : Colors.grey.shade400,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.message,
                color: isOnline ? const Color(0xFF22d3ee) : Colors.grey.shade500,
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatDetailPage(
                      userId: user['id'],
                      name: displayName,
                      avatar: initial,
                      status: statusText,
                    ),
                  ),
                ).then((_) => _loadData()); // Sohbet sonrası listeyi yenile
              },
            ),
          ],
        ),
      ),
    );
  }
}

