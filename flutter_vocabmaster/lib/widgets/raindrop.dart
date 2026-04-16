import 'package:flutter/material.dart';
import 'dart:math';
import '../utils/app_colors.dart';

class RaindropWidget extends StatefulWidget {
  final double screenWidth;
  final double screenHeight;

  const RaindropWidget({
    super.key, 
    required this.screenWidth, 
    required this.screenHeight
  });

  @override
  State<RaindropWidget> createState() => _RaindropWidgetState();
}

class _RaindropWidgetState extends State<RaindropWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _yAnimation;
  late Animation<double> _opacityAnimation;
  
  late double _startX;
  late double _width;
  late double _height;
  late Duration _duration;
  late Duration _delay;

  @override
  void initState() {
    super.initState();
    _initializeRandomValues();
    
    _controller = AnimationController(
      vsync: this,
      duration: _duration,
    );

    _yAnimation = Tween<double>(
      begin: -50.0,
      end: widget.screenHeight + 100.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.linear,
    ));

    // Opacity: 0 -> 1 -> 1 -> 0 matches the TweenSequence requested 
    // but doing it simpler with intervals for better performance
    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 80),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 10),
    ]).animate(_controller);

    Future.delayed(_delay, () {
      if (mounted) {
        _controller.repeat();
      }
    });
  }

  void _initializeRandomValues() {
    final random = Random();
    _startX = random.nextDouble() * widget.screenWidth;
    _width = 2.0 + random.nextDouble() * 4.0; // 2-6px
    _height = _width * (10 + random.nextDouble() * 20); // Longer drops look better
    _duration = Duration(milliseconds: 2000 + random.nextInt(2000)); // 2-4s
    _delay = Duration(milliseconds: random.nextInt(3000)); // 0-3s delay
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          left: _startX,
          top: _yAnimation.value,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Container(
              width: _width,
              height: _height,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF06B6D4).withOpacity(0.6), // cyan 60%
                    const Color(0xFF06B6D4).withOpacity(0.3), // cyan 30%
                    Colors.transparent,
                  ],
                ),
                borderRadius: BorderRadius.circular(_width / 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cyan400.withOpacity(0.4),
                    blurRadius: 6,
                    spreadRadius: 1,
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

