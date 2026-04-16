import 'dart:math';
import 'package:flutter/material.dart';

class MatchingAnimation extends StatefulWidget {
  final int waitingTimeSeconds;
  final VoidCallback? onCancel;
  
  const MatchingAnimation({
    super.key,
    this.waitingTimeSeconds = 0,
    this.onCancel,
  });

  @override
  State<MatchingAnimation> createState() => _MatchingAnimationState();
}

class _MatchingAnimationState extends State<MatchingAnimation> with TickerProviderStateMixin {
  late AnimationController _radarController;
  late AnimationController _starController;
  late AnimationController _avatarController;

  final List<Offset> _starPositions = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();

    // Radar Animation
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // Star Animation (Pulse)
    _starController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Avatar Scroll Animation
    _avatarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // Generate random star positions
    for (int i = 0; i < 15; i++) {
      _starPositions.add(Offset(
        _random.nextDouble(),
        _random.nextDouble(),
      ));
    }
  }

  @override
  void dispose() {
    _radarController.dispose();
    _starController.dispose();
    _avatarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200, // Height of the animation area
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a).withOpacity(0.5), // Deep dark blue bg
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Layer 3: Stars (Background)
            CustomPaint(
              painter: StarPainter(
                animation: _starController,
                starPositions: _starPositions,
              ),
              child: Container(),
            ),

            // Layer 1: Radar (Middle)
            ...List.generate(4, (index) {
              return AnimatedBuilder(
                animation: _radarController,
                builder: (context, child) {
                  double value = (_radarController.value + (index * 0.25)) % 1.0;
                  double scale = value * 1.5; // Expand outwards
                  double opacity = (1.0 - value).clamp(0.0, 1.0) * 0.5;

                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF06b6d4).withOpacity(opacity),
                          width: 2,
                        ),
                      ),
                    ),
                  );
                },
              );
            }),

            // Center Pulse Point
            Container(
               width: 8,
               height: 8,
               decoration: BoxDecoration(
                 color: const Color(0xFF06b6d4),
                 shape: BoxShape.circle,
                 boxShadow: [
                   BoxShadow(
                     color: const Color(0xFF06b6d4).withOpacity(0.8),
                     blurRadius: 10,
                     spreadRadius: 2,
                   )
                 ]
               ),
            ),



            // "Eşleşiyor..." Button/Text (Bottom Center)
            Positioned(
              bottom: 30,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Bekleme süresi göstergesi
                  if (widget.waitingTimeSeconds > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${widget.waitingTimeSeconds} saniye',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  
                  // Eşleşiyor durumu
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0ea5e9).withOpacity(0.2), // Glassy Blue
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF0ea5e9).withOpacity(0.5),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0ea5e9).withOpacity(0.2),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF06b6d4)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Eşleşiyor...',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // İptal butonu
                  if (widget.onCancel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: GestureDetector(
                        onTap: widget.onCancel,
                        child: Text(
                          'İptal',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StarPainter extends CustomPainter {
  final Animation<double> animation;
  final List<Offset> starPositions;

  StarPainter({required this.animation, required this.starPositions})
      : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF06b6d4)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = const Color(0xFF06b6d4).withOpacity(0.2)
      ..strokeWidth = 1.0;

    // Draw lines between nearby stars
    for (int i = 0; i < starPositions.length; i++) {
        for (int j = i + 1; j < starPositions.length; j++) {
            Offset p1 = Offset(starPositions[i].dx * size.width, starPositions[i].dy * size.height);
            Offset p2 = Offset(starPositions[j].dx * size.width, starPositions[j].dy * size.height);
            
            if ((p1 - p2).distance < 60) {
                 canvas.drawLine(p1, p2, linePaint);
            }
        }
    }

    // Draw stars
    for (var pos in starPositions) {
      double dx = pos.dx * size.width;
      double dy = pos.dy * size.height;
      
      // Pulse size
      double radius = 1.5 + (sin(animation.value * pi * 2) * 0.5); 
      
      // Glow
      canvas.drawCircle(
        Offset(dx, dy),
        radius * 2,
        Paint()..color = const Color(0xFF06b6d4).withOpacity(0.3),
      );

      canvas.drawCircle(Offset(dx, dy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(StarPainter oldDelegate) => true;
}

