import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/global_state.dart';
import '../services/matchmaking_service.dart';

class GlobalMatchingIndicator extends StatefulWidget {
  const GlobalMatchingIndicator({super.key});

  @override
  State<GlobalMatchingIndicator> createState() => _GlobalMatchingIndicatorState();
}

class _GlobalMatchingIndicatorState extends State<GlobalMatchingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MatchmakingService>(
      builder: (context, matchmaking, child) {
        return Container(
          height: 70, // Fixed height
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF1e3a8a).withOpacity(0.9), // Dark Blue
            border: const Border(
              top: BorderSide(color: Colors.white24, width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              // Animated Radar Icon
              CustomPaint(
                painter: RadarPainter(_controller),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF0ea5e9), // Cyan center
                  ),
                  child: const Icon(Icons.wifi_tethering, color: Colors.white, size: 24),
                ),
              ),
              
              const SizedBox(width: 16),
              
              // Text with waiting time
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Eşleşme aranıyor...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (matchmaking.waitingTimeSeconds > 0)
                      Text(
                        '${matchmaking.waitingTimeSeconds} saniye',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              
              // Close Button
              GestureDetector(
                onTap: () {
                  // Cancel matching - MatchmakingService üzerinden
                  matchmaking.leaveQueue();
                  GlobalState.isMatching.value = false;
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


class RadarPainter extends CustomPainter {
  final Animation<double> animation;

  RadarPainter(this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0ea5e9).withOpacity(0.0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final center = Offset(size.width / 2, size.height / 2);
    
    // Draw 3 ripples
    for (int i = 0; i < 3; i++) {
      double value = (animation.value + i * 0.33) % 1.0;
      double radius = 20 + (value * 20); // Expand from 20 to 40 radius
      double opacity = (1.0 - value).clamp(0.0, 1.0);
      
      paint.color = const Color(0xFF0ea5e9).withOpacity(opacity * 0.5);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(RadarPainter oldDelegate) => true;
}

