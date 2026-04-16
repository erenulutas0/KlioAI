import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/global_matchmaking_sheet.dart';
import '../main.dart';
import '../services/social_service.dart';
import 'friend_list_page.dart';
import 'notifications_page.dart';

// ---------------------------------------------------------------------------
// DATA MODELS
// ---------------------------------------------------------------------------

class Comment {
  final int id;
  final int userId;
  final String userName;
  final String userAvatar;
  final String content;
  final String timestamp;

  Comment({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.content,
    required this.timestamp,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    return Comment(
      id: json['id'],
      userId: user['id'],
      userName: user['displayName'] ?? 'User',
      userAvatar: user['photoUrl'] ?? ((user['displayName'] ?? 'U')[0]), // Fallback to initial
      content: json['content'],
      timestamp: json['createdAt'] ?? '',
    );
  }
}

class Post {
  final int id;
  final int userId;
  final String userName;
  final String userAvatar;
  final String userHandle;
  final String timestamp;
  final String content;
  final String? imageUrl;
  int likes;
  int commentCount;
  List<Comment> comments; // Loaded on demand usually, but keeping list structure
  bool liked;

  Post({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.userHandle,
    required this.timestamp,
    required this.content,
    this.imageUrl,
    required this.likes,
    required this.commentCount,
    this.comments = const [],
    this.liked = false,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    String displayName = user['displayName'] ?? 'User';
    
    // Parse timestamp
    String timeStr = 'Şimdi';
    if (json['createdAt'] != null) {
      try {
        final dt = DateTime.parse(json['createdAt']);
        final diff = DateTime.now().difference(dt);
        if (diff.inMinutes < 60) {
          timeStr = '${diff.inMinutes} dk önce';
        } else if (diff.inHours < 24) {
          timeStr = '${diff.inHours} saat önce';
        } else {
          timeStr = '${diff.inDays} gün önce';
        }
      } catch (_) {}
    }

    return Post(
      id: json['id'],
      userId: user['id'],
      userName: displayName,
      userAvatar: displayName.isNotEmpty ? displayName[0] : 'U', 
      userHandle: '@${displayName.toLowerCase().replaceAll(' ', '')}',
      timestamp: timeStr,
      content: json['content'],
      imageUrl: json['mediaUrl'],
      likes: json['likeCount'] ?? 0,
      commentCount: json['commentCount'] ?? 0,
      liked: json['liked'] ?? false, // Parse liked status from backend
    );
  }
}

// ---------------------------------------------------------------------------
// MAIN PAGE
// ---------------------------------------------------------------------------

class SocialFeedPage extends StatefulWidget {
  const SocialFeedPage({super.key});

  @override
  State<SocialFeedPage> createState() => _SocialFeedPageState();
}

class _SocialFeedPageState extends State<SocialFeedPage> 
    with TickerProviderStateMixin {
  List<Post> posts = [];
  bool showCreatePost = false;
  TextEditingController newPostController = TextEditingController();
  Set<int> expandedComments = {}; // Changed to int ID
  Map<int, TextEditingController> commentControllers = {};
  late List<AnimationController> _rainControllers;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final SocialService _socialService = SocialService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFeed();
    _initRainAnimations();
  }

  Future<void> _loadFeed() async {
    try {
      final List<dynamic> feedData = await _socialService.getFeed();
      if (mounted) {
        setState(() {
          posts = feedData.map((json) => Post.fromJson(json)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        debugPrint('Feed error: $e');
      }
    }
  }

  @override
  void dispose() {
    newPostController.dispose();
    for (var c in commentControllers.values) {
      c.dispose();
    }
    for (var c in _rainControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _initRainAnimations() {
    _rainControllers = List.generate(40, (i) {
      final duration = 3.0 + Random().nextDouble() * 3;
      final delay = Random().nextDouble() * 5;
      
      final controller = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: (duration * 1000).toInt()),
      );
      
      Future.delayed(Duration(milliseconds: (delay * 1000).toInt()), () {
        if (mounted) controller.repeat();
      });
      
      return controller;
    });
  }

  // ---------------------------------------------------------------------------
  // SAMPLE DATA
  // ---------------------------------------------------------------------------

  // Awards removed


  Future<void> _createPost() async {
    if (newPostController.text.trim().isEmpty) return;
    
    try {
      final newPostJson = await _socialService.createPost(newPostController.text);
      if (mounted) {
        setState(() {
          posts.insert(0, Post.fromJson(newPostJson));
          newPostController.clear();
          showCreatePost = false;
        });
      }
    } catch (e) {
      debugPrint('Create post error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paylaşım yapılamadı')));
    }
  }
  
  Future<void> _addComment(Post post, String text) async {
    if (text.trim().isEmpty) return;
    
    try {
      final newCommentJson = await _socialService.commentPost(post.id, text);
      if (mounted) {
        setState(() {
          post.comments.add(Comment.fromJson(newCommentJson));
          post.commentCount++;
          commentControllers[post.id]?.clear();
        });
      }
    } catch (e) {
      debugPrint('Comment error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Yorum yapılamadı')));
    }
  }

  // ---------------------------------------------------------------------------
  // WIDGET BUILDERS
  // ---------------------------------------------------------------------------

  Widget _buildRainDrop(int index) {
    final size = 2.0 + Random().nextDouble() * 4;
    // Ensure we have enough controllers or default to 0
    if (index >= _rainControllers.length) return const SizedBox();
    
    final initialX = Random().nextDouble() * MediaQuery.of(context).size.width;
    
    return AnimatedBuilder(
      animation: _rainControllers[index],
      builder: (context, child) {
        final value = _rainControllers[index].value;
        final yPos = -20 + (MediaQuery.of(context).size.height + 100) * value;
        
        double opacity = 1.0;
        if (value < 0.2) {
          opacity = value / 0.2;
        } else if (value > 0.8) {
          opacity = (1 - value) / 0.2;
        }
        
        return Positioned(
          left: initialX,
          top: yPos,
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: size,
              height: size * 3,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x9906B6D4),  // cyan-500 60%
                    Color(0x4D06B6D4),  // cyan-500 30%
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
                borderRadius: BorderRadius.circular(size),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x6606B6D4),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedBackground() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: List.generate(40, (i) => _buildRainDrop(i)),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0x1A06B6D4),  // cyan-500 10%
            Color(0x1A3B82F6),  // blue-500 10%
          ],
        ),
        border: Border(
          bottom: BorderSide(
            color: Color(0x3322D3EE),  // cyan-400 20%
            width: 1,
          ),
        ),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SafeArea(
              bottom: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Menu Button -> Changed to Back Button
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF22D3EE), size: 24),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0x1AFFFFFF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  
                  // Title
                  Row(
                    children: [
                      const Icon(Icons.trending_up, color: Color(0xFF22D3EE), size: 24),
                      const SizedBox(width: 8),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [
                            Color(0xFF22D3EE),  // cyan-400
                            Color(0xFF3B82F6),  // blue-500
                          ],
                        ).createShader(bounds),
                        child: const Text(
                          'Social Feed',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  // Action Buttons
                  Row(
                    children: [
                      // Notifications Button
                      IconButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const NotificationsPage()),
                          );
                        },
                        icon: const Icon(Icons.notifications_outlined, color: Color(0xFF22D3EE), size: 24),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0x1AFFFFFF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Friends Button
                      IconButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const FriendListPage()),
                          );
                        },
                        icon: const Icon(Icons.people_outline, color: Color(0xFF22D3EE), size: 24),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0x1AFFFFFF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(String name, {double size = 48}) {
    // Generate initials
    String initials = '';
    final nameParts = name.trim().split(' ');
    if (nameParts.isNotEmpty) {
      initials = nameParts[0][0].toUpperCase();
      if (nameParts.length > 1) {
        initials += nameParts[1][0].toUpperCase();
      }
    }
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF22D3EE), Color(0xFF3B82F6)], // Cyan to Blue
        ),
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0x8022D3EE),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.4,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildUserHeader(Post post) {
    return Row(
      children: [
        // Avatar
        _buildAvatar(post.userName),
        
        const SizedBox(width: 12),
        
        // User Info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                post.userName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      post.userHandle,
                      style: const TextStyle(
                        color: Color(0xB367E8F9),
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '•',
                    style: TextStyle(color: Color(0xB367E8F9)),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    post.timestamp,
                    style: const TextStyle(
                      color: Color(0xB367E8F9),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        const SizedBox(width: 8),
        
        // Follow Button (Not fully implemented yet)
        ElevatedButton(
          onPressed: () {
            // Placeholder for follow
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF06B6D4), // Cyan if not following
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: Size.zero, 
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide.none,
            ),
          ),
          child: const Text(
            'Takip Et',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        
        const SizedBox(width: 4),
        
        // More Button
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.more_horiz, color: Color(0xB3FFFFFF)),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  Widget _buildPostContent(Post post) {
    return Text(
      post.content,
      style: const TextStyle(
        color: Color(0xE6FFFFFF),  // white 90%
        fontSize: 15,
        height: 1.5,
      ),
    );
  }

  Widget _buildPostImage(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: const Color(0x3322D3EE),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Image.network(
          imageUrl,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
             return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isActive,
    List<Color>? activeGradient,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), // Reduced padding
        decoration: BoxDecoration(
          gradient: isActive && activeGradient != null
            ? LinearGradient(colors: activeGradient)
            : null,
          color: isActive && activeGradient == null 
            ? const Color(0x1AFFFFFF) 
            : null,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isActive && activeGradient != null
            ? [
                BoxShadow(
                  color: activeGradient[0].withOpacity(0.3),
                  blurRadius: 12,
                  spreadRadius: 0,
                ),
              ]
            : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18, // Slightly smaller icon
              color: Colors.white,
            ),
            if (label.isNotEmpty) ...[
               const SizedBox(width: 4),
               Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13, // Slightly smaller font
                  fontWeight: FontWeight.w500,
                ),
               ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCommentItem(Comment comment) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(comment.userName, size: 32),
          
          const SizedBox(width: 12),
          
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x0DFFFFFF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        comment.userName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        comment.timestamp,
                        style: const TextStyle(
                          color: Color(0x80FFFFFF),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    comment.content,
                    style: const TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 14,
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

  Widget _buildCommentsSection(Post post) {
    if (!commentControllers.containsKey(post.id)) {
      commentControllers[post.id] = TextEditingController();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Existing Comments
        ...post.comments.map((comment) => _buildCommentItem(comment)),
        
        if (post.comments.isNotEmpty) const SizedBox(height: 16),
        
        // Add Comment
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildAvatar('Ben', size: 32),
            
            const SizedBox(width: 12),
            
            Expanded(
              child: TextField(
                controller: commentControllers[post.id],
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Yorum ekle...',
                  hintStyle: const TextStyle(color: Color(0x66FFFFFF)),
                  filled: true,
                  fillColor: const Color(0x0DFFFFFF),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0x3322D3EE)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0x3322D3EE)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0x8022D3EE)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (text) => _addComment(post, text),
              ),
            ),
            
            const SizedBox(width: 8),
            
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x4D06B6D4),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: IconButton(
                onPressed: () {
                  final text = commentControllers[post.id]!.text;
                  _addComment(post, text);
                },
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButtons(Post post) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween, // Distribute space evenly
      children: [
        // Like Button
        _buildActionButton(
          icon: post.liked ? Icons.favorite : Icons.favorite_border,
          label: '${post.likes}',
          isActive: post.liked,
          activeGradient: [const Color(0xFFEC4899), const Color(0xFFF43F5E)],  // pink to rose
          onTap: () async {
            // Toggle like - Optimistic UI update
            final wasLiked = post.liked;
            final oldLikes = post.likes;
            
            setState(() {
              post.liked = !wasLiked;
              post.likes = wasLiked ? post.likes - 1 : post.likes + 1;
            });

            try {
              final result = await _socialService.toggleLike(post.id);
              // Sync with backend response
              if (mounted) {
                setState(() {
                  post.liked = result['liked'] ?? !wasLiked;
                  post.likes = result['likeCount'] ?? post.likes;
                });
              }
            } catch (e) {
              // Revert on error
              if (mounted) {
                setState(() {
                  post.liked = wasLiked;
                  post.likes = oldLikes;
                });
              }
              debugPrint('Like toggle error: $e');
            }
          },
        ),
        
        // Comment Button
        _buildActionButton(
          icon: Icons.chat_bubble_outline,
          label: '${post.comments.length}',
          isActive: false,
          onTap: () {
            setState(() {
              if (expandedComments.contains(post.id)) {
                expandedComments.remove(post.id);
              } else {
                expandedComments.add(post.id);
              }
            });
          },
        ),
        
        // Create Space
        const SizedBox(width: 48),
        
        // Share Button
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.share, color: Color(0xB3FFFFFF), size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          style: IconButton.styleFrom(
             tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  Widget _buildPostCard(Post post, int index) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 300),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16), // Slightly reduced padding
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0x661E293B),  // slate-800 40%
              Color(0x661E3A8A),  // blue-900 40%
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0x3322D3EE),  // cyan-400 20%
            width: 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              spreadRadius: 0,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildUserHeader(post),
                const SizedBox(height: 12),
                _buildPostContent(post),
                if (post.imageUrl != null) ...[
                  const SizedBox(height: 16),
                  _buildPostImage(post.imageUrl!),
                ],

                const SizedBox(height: 16),
                const Divider(color: Color(0x1AFFFFFF), height: 1),
                const SizedBox(height: 12),
                _buildActionButtons(post),
                if (expandedComments.contains(post.id)) ...[
                  const SizedBox(height: 16),
                  const Divider(color: Color(0x1AFFFFFF), height: 1),
                  const SizedBox(height: 16),
                  _buildCommentsSection(post),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    return Positioned(
      right: 24,
      bottom: 96,  // Above bottom nav
      child: GestureDetector(
        onTap: () {
          setState(() {
            showCreatePost = true;
          });
        },
        child: Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x8006B6D4),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(
            Icons.auto_awesome,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildCreatePostModal() {
    return Stack(
      children: [
        // Backdrop
        Positioned.fill(
          child: GestureDetector(
            onTap: () {
              setState(() {
                showCreatePost = false;
              });
            },
            child: Container(
              color: const Color(0x99000000),  // black 60%
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
        ),
        
        // Modal
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1E293B),  // slate-800
                  Color(0xFF1E3A8A),  // blue-900
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x4D22D3EE)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 20,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Color(0xFF22D3EE), Color(0xFF3B82F6)],
                          ).createShader(bounds),
                          child: const Text(
                            'Yeni Paylaşım',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              showCreatePost = false;
                            });
                          },
                          icon: const Icon(Icons.close, color: Color(0xB3FFFFFF)),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // User + Input
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildAvatar('Ahmet Yılmaz'),
                        
                        const SizedBox(width: 12),
                        
                        Expanded(
                          child: TextField(
                            controller: newPostController,
                            onChanged: (_) => setState(() {}),
                            maxLines: 5,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'İngilizce öğrenme deneyiminizi paylaşın...',
                              hintStyle: const TextStyle(color: Color(0x66FFFFFF)),
                              filled: true,
                              fillColor: const Color(0x0DFFFFFF),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0x3322D3EE)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0x3322D3EE)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0x8022D3EE)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    const Divider(color: Color(0x1AFFFFFF)),
                    const SizedBox(height: 16),
                    
                    // Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.image, color: Color(0xFF22D3EE)),
                        ),
                        
                        Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x4D06B6D4),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: newPostController.text.trim().isEmpty 
                              ? null 
                              : _createPost,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Paylaş',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          _buildAnimatedBackground(),
          Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _isLoading 
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF22D3EE)))
                  : posts.isEmpty 
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 16, bottom: 100),
                        itemCount: posts.length,
                        itemBuilder: (context, index) => _buildPostCard(posts[index], index),
                      ),
              ),
            ],
          ),
          if (showCreatePost) _buildCreatePostModal(),
        ],
      ),
      floatingActionButton: _buildFloatingActionButton(),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GlobalMatchmakingSheet(),
          BottomNav(
            currentIndex: -1,
            onTap: (index) {
               Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => MainScreen(initialIndex: index)),
                (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.feed_outlined, size: 64, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            'Henüz paylaşım yok',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'İlk paylaşımı sen yaparak topluluğu başlat!',
            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 14),
          ),
        ],
      ),
    );
  }
}

