import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:ui';

class FloatingOrb extends StatefulWidget {
  const FloatingOrb({super.key});

  @override
  State<FloatingOrb> createState() => _FloatingOrbState();
}

class _FloatingOrbState extends State<FloatingOrb> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _xAnimation;
  late Animation<double> _yAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  
  late double _size;
  late double _initialX;
  late double _initialY;

  @override
  void initState() {
    super.initState();
    final random = Random();
    
    // Random parameters
    _size = 150.0 + random.nextDouble() * 200.0; // 150-350px
    // Start somewhere on screen (rough approximation, layout constraints handled by parent Stack)
    _initialX = random.nextDouble() * 300; 
    _initialY = random.nextDouble() * 600;
    final duration = Duration(seconds: 20 + random.nextInt(10)); // 20-30s

    _controller = AnimationController(
      vsync: this,
      duration: duration,
    );

    _xAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 50.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 50.0, end: 0.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 50),
    ]).animate(_controller);

    _yAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 30.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 30.0, end: -30.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: -30.0, end: 0.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 30),
    ]).animate(_controller);

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2), weight: 33),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 0.9), weight: 33),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 34),
    ]).animate(_controller);
    
    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.3, end: 0.5), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 0.5, end: 0.3), weight: 50),
    ]).animate(_controller);

    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _initialX,
      top: _initialY,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(_xAnimation.value, _yAnimation.value),
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Opacity(
                opacity: _opacityAnimation.value,
                child: Container(
                  width: _size,
                  height: _size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF22D3EE).withOpacity(0.15), // increased slightly for visibility
                        const Color(0xFF3B82F6).withOpacity(0.05),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.4, 1.0],
                    ),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30), // Reduced blur for performance and visibility
                    child: Container(
                      decoration: const BoxDecoration(color: Colors.transparent),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

