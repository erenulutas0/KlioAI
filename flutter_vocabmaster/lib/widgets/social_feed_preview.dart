import 'package:flutter/material.dart';
import '../constants/social_feed_colors.dart';
import '../screens/social_feed_page.dart';
import 'modern_card.dart';
import 'modern_background.dart';
import '../services/feed_service.dart';

class SocialFeedPreview extends StatefulWidget {
  const SocialFeedPreview({super.key});

  @override
  State<SocialFeedPreview> createState() => _SocialFeedPreviewState();
}

class _SocialFeedPreviewState extends State<SocialFeedPreview> {
  List<UserActivity> _activities = [];
  bool _isLoading = true;
  final FeedService _feedService = FeedService();

  @override
  void initState() {
    super.initState();
    _loadPreviewFeed();
  }

  Future<void> _loadPreviewFeed() async {
    try {
      final data = await _feedService.getFeed(limit: 2);
      if (mounted) {
        setState(() {
          _activities = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ModernCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(24),
      borderRadius: BorderRadius.circular(24),
      variant: BackgroundVariant.primary,
      showGlow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 24),
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: SocialFeedColors.avatarCyan))
          else if (_activities.isEmpty)
            const Center(
              child: Text(
                'Henüz paylaşım yok. İlk adımı sen at!',
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
            )
          else
            ..._activities.map((a) => Column(
              children: [
                _buildPost(
                  context,
                  name: 'User ${a.userId}',
                  time: _formatTimestamp(a.createdAt),
                  content: a.description,
                  likes: 0,
                  comments: 0,
                  avatarColor: SocialFeedColors.avatarCyan,
                  avatarLetter: 'U',
                ),
                if (a != _activities.last) const SizedBox(height: 20),
              ],
            )),
          const SizedBox(height: 24),
          _buildCTAButton(context),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} saat önce';
    return '${diff.inDays} gn önce';
  }

  Widget _buildHeader(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          children: [
            Icon(
              Icons.trending_up_rounded,
              color: SocialFeedColors.avatarCyan,
              size: 28,
            ),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Social Feed',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Toplulukla paylaş!',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPost(BuildContext context, {
    required String name,
    required String time,
    required String content,
    required int likes,
    required int comments,
    required Color avatarColor,
    required String avatarLetter,
  }) {
    return InkWell(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => const SocialFeedPage()));
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: avatarColor.withOpacity(0.2),
                    border: Border.all(
                      color: avatarColor,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      avatarLetter,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        time,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStat(Icons.thumb_up_outlined, likes),
                const SizedBox(width: 20),
                _buildStat(Icons.chat_bubble_outline, comments),
                const Spacer(),
                const Icon(
                  Icons.bookmark_border,
                  color: Colors.white60,
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(IconData icon, int count) {
    return Row(
      children: [
        Icon(
          icon,
          color: Colors.white60,
          size: 22,
        ),
        const SizedBox(width: 8),
        Text(
          count.toString(),
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildCTAButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => const SocialFeedPage()));
      },
      child: ModernCard(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        borderRadius: BorderRadius.circular(16),
        variant: BackgroundVariant.secondary,
        showBorder: false,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.trending_up,
              color: Colors.white,
              size: 20,
            ),
            SizedBox(width: 10),
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
    );
  }
}

