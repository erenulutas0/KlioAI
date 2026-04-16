import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../screens/ai_bot_chat_page.dart';
import 'modern_card.dart';
import 'modern_background.dart';

class AnimatedAIChatCard extends StatefulWidget {
  const AnimatedAIChatCard({super.key});

  @override
  State<AnimatedAIChatCard> createState() => _AnimatedAIChatCardState();
}

class _AnimatedAIChatCardState extends State<AnimatedAIChatCard> with TickerProviderStateMixin {
  late AnimationController _avatarAnimationController;
  late Animation<double> _avatarAnimation;

  final List<String> _avatarUrls = [
    'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=100&h=100&fit=crop',  // Sarah
    'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=100&h=100&fit=crop',  // James
    'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=100&h=100&fit=crop',  // Emma
    'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=100&h=100&fit=crop',  // Michael
    'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=100&h=100&fit=crop',  // Olivia
    'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=100&h=100&fit=crop',  // David
  ];

  @override
  void initState() {
    super.initState();
    _avatarAnimationController = AnimationController(
       duration: const Duration(seconds: 20),
       vsync: this,
     )..repeat();
     
     _avatarAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
       CurvedAnimation(
         parent: _avatarAnimationController,
         curve: Curves.linear,
       ),
     );
  }

  @override
  void dispose() {
    _avatarAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ModernCard(showGlow: true, borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          // SLIDING AVATARS BACKGROUND
          Positioned.fill(
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _avatarAnimation,
                builder: (context, child) {
                  const double avatarWidth = 48.0;
                  const double gap = 16.0;
                  final double setWidth = (avatarWidth + gap) * _avatarUrls.length;
                  final double offset = -(_avatarAnimation.value * setWidth);
                  
                  return Transform.translate(
                    offset: Offset(offset, 0),
                    child: SingleChildScrollView( // Overflow Fix: Wrap Row in SingleChildScrollView
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(), // Disable user scrolling
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Repeat 3 times for seamless loop
                          for (var i = 0; i < 3; i++)
                            ..._avatarUrls.map((url) => Padding(
                              padding: const EdgeInsets.only(right: gap),
                              child: Opacity(
                                opacity: 0.2, 
                                child: CircleAvatar(
                                  radius: avatarWidth / 2,
                                  backgroundImage: CachedNetworkImageProvider(url),
                                  backgroundColor: const Color(0x1AFFFFFF),
                                ),
                              ),
                            )),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          
          // CONTENT (ABOVE ANIMATION)
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Title + Online dot
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'Modellerimizle Sohbet Et ',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Container(
                        margin: const EdgeInsets.only(left: 4),
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF4ADE80),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x4D4ADE80),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),
              
              // Subtitle
              const Text(
                'AI asistanlarımızla İngilizce konuş',
                style: TextStyle(
                  color: Color(0xFFBAE6FD),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 24),
              
              // Button (Icon Removed)
              SizedBox(
                width: double.infinity,
                child: ModernCard(
                  variant: BackgroundVariant.accent,
                  showGlow: true,
                  borderRadius: BorderRadius.circular(16),
                  padding: EdgeInsets.zero,
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                         Navigator.push(
                           context,
                           MaterialPageRoute(builder: (context) => const AIBotChatPage()),
                         );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Sohbete Başla',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

