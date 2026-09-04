import 'package:flutter/material.dart';

import '../screens/ai_bot_chat_page.dart';
import 'modern_background.dart';
import 'modern_card.dart';

class AnimatedAIChatCard extends StatefulWidget {
  const AnimatedAIChatCard({super.key});

  @override
  State<AnimatedAIChatCard> createState() => _AnimatedAIChatCardState();
}

class _AnimatedAIChatCardState extends State<AnimatedAIChatCard>
    with TickerProviderStateMixin {
  late AnimationController _avatarAnimationController;
  late Animation<double> _avatarAnimation;

  /// Six discs that drift behind the card, at a fifth of full opacity.
  ///
  /// These were photographs of six real people, fetched from Unsplash. The
  /// licence covers using the image commercially; it does not grant model
  /// rights, and nobody in those photographs agreed to decorate an English
  /// tutor. At 0.2 opacity behind a gradient they were barely faces anyway --
  /// plain colour reads the same and asks nothing of the network.
  final List<Color> _avatarTints = const [
    Color(0xFF6C4EF5),
    Color(0xFF3A24A0),
    Color(0xFF0EA5E9),
    Color(0xFF06B6D4),
    Color(0xFF8B5CF6),
    Color(0xFF2563EB),
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
    final isTurkish = Localizations.localeOf(context).languageCode == 'tr';

    return ModernCard(
      showGlow: true,
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _avatarAnimation,
                builder: (context, child) {
                  const double avatarWidth = 48.0;
                  const double gap = 16.0;
                  final double setWidth =
                      (avatarWidth + gap) * _avatarTints.length;
                  final double offset = -(_avatarAnimation.value * setWidth);

                  return Transform.translate(
                    offset: Offset(offset, 0),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < 3; i++)
                            ..._avatarTints.map(
                              (tint) => Padding(
                                padding: const EdgeInsets.only(right: gap),
                                child: Opacity(
                                  opacity: 0.2,
                                  child: CircleAvatar(
                                    radius: avatarWidth / 2,
                                    backgroundColor: tint,
                                  ),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: isTurkish
                          ? 'Modellerimizle Sohbet Et '
                          : 'Chat with Our Models ',
                      style: const TextStyle(
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
              Text(
                isTurkish
                    ? 'AI asistanlarimizla Ingilizce konus'
                    : 'Practice English with our AI assistants',
                style: const TextStyle(
                  color: Color(0xFFBAE6FD),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
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
                          MaterialPageRoute(
                            builder: (context) => const AIBotChatPage(),
                          ),
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
                      child: Text(
                        isTurkish ? 'Sohbete Basla' : 'Start Chat',
                        style: const TextStyle(
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
