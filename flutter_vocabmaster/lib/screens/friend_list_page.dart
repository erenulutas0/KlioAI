import 'package:flutter/material.dart';
import '../widgets/animated_background.dart';
import '../widgets/modern_card.dart';
import '../widgets/modern_background.dart';
import '../services/social_service.dart';
import 'chat_detail_page.dart';

class FriendListPage extends StatefulWidget {
  const FriendListPage({super.key});

  @override
  State<FriendListPage> createState() => _FriendListPageState();
}

class _FriendListPageState extends State<FriendListPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SocialService _socialService = SocialService();
  final TextEditingController _searchController = TextEditingController();

  List<dynamic> _friends = [];
  List<dynamic> _searchResults = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadFriends();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final users = await _socialService.getFriends();
      
      if (mounted) {
        setState(() {
          _friends = users.map((user) {
             String name = user['displayName'] ?? 'User';
             String initials = name.isNotEmpty ? name[0].toUpperCase() : 'U';
             if (name.contains(' ') && name.split(' ').length > 1) {
               initials += name.split(' ')[1][0].toUpperCase();
             }
             
             return {
               'id': user['id'],
               'name': name,
               'username': user['userTag'] ?? '@user',
               'avatar': initials,
             };
          }).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading friends: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          // Clean mock data
          _friends = [];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Arkadaşlar yüklenemedi')),
        );
      }
    }
  }

  Future<void> _searchUsers(String query) async {
    // Search is now filtering the "All Users" list which we're treating as "Friends" for MVP
    if (query.isEmpty) {
      if (mounted) setState(() => _searchResults = []);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Since _friends now contains ALL users from backend (as per previous request),
    // we can filter that list. Ideally, this should call a search API.
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (mounted) {
      setState(() {
        _searchResults = _friends.where((u) {
          final name = u['name'].toString().toLowerCase();
          final username = u['username'].toString().toLowerCase();
          final q = query.toLowerCase();
          return name.contains(q) || username.contains(q);
        }).toList();
        _isLoading = false;
      });
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
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Arkadaşlar',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // Tabs
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
                      ),
                    ),
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    tabs: const [
                      Tab(text: 'Arkadaşlarım'),
                      Tab(text: 'Arkadaş Ekle'),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),

                // Content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildFriendsList(),
                      _buildAddFriendSection(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendsList() {
    if (_isLoading && _friends.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF22D3EE)));
    }

    if (_friends.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 16),
            Text(
              'Henüz arkadaşın yok',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _friends.length,
      itemBuilder: (context, index) {
        final friend = _friends[index];
        return ModernCard(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          borderRadius: BorderRadius.circular(16),
          variant: BackgroundVariant.primary,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF06B6D4),
              child: Text(friend['avatar'], style: const TextStyle(color: Colors.white)),
            ),
            title: Text(friend['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text(friend['username'], style: const TextStyle(color: Colors.white70)),
            trailing: IconButton(
              icon: const Icon(Icons.message, color: Color(0xFF22D3EE)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatDetailPage(
                      userId: friend['id'],
                      name: friend['name'],
                      avatar: friend['avatar'],
                      status: 'Çevrimiçi', // Default status for now
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildAddFriendSection() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Kullanıcı adı veya isim ara...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF22D3EE)),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward, color: Color(0xFF22D3EE)),
                onPressed: () => _searchUsers(_searchController.text),
              ),
            ),
            onSubmitted: _searchUsers,
          ),
        ),
        
        Expanded(
          child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF22D3EE)))
            : _searchResults.isEmpty
              ? Center(
                  child: Text(
                    'Arama sonucu yok',
                    style: TextStyle(color: Colors.white.withOpacity(0.5)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final user = _searchResults[index];
                    return ModernCard(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      borderRadius: BorderRadius.circular(16),
                      variant: BackgroundVariant.secondary,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF3B82F6),
                          child: Text(user['avatar'], style: const TextStyle(color: Colors.white)),
                        ),
                        title: Text(user['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text(user['username'], style: const TextStyle(color: Colors.white70)),
                        trailing: IconButton(
                          icon: const Icon(Icons.message, color: Color(0xFF22D3EE)),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ChatDetailPage(
                                  userId: user['id'],
                                  name: user['name'],
                                  avatar: user['avatar'],
                                  status: 'Çevrimiçi',
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

