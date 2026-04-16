import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_catalog.dart';
import '../../theme/theme_provider.dart';

class NeuralParticleBackground extends StatefulWidget {
  final int particleCount;

  const NeuralParticleBackground({
    super.key,
    this.particleCount = 40,
  });

  @override
  State<NeuralParticleBackground> createState() =>
      _NeuralParticleBackgroundState();
}

class _NeuralParticleBackgroundState extends State<NeuralParticleBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ParticleSpec> _particles;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();

    _particles = List<_ParticleSpec>.generate(widget.particleCount, (_) {
      return _ParticleSpec(
        xSeed: _random.nextDouble(),
        phase: _random.nextDouble(),
        speed: 0.5 + _random.nextDouble() * 1.1,
        drift: 0.02 + _random.nextDouble() * 0.06,
        size: 2 + _random.nextDouble() * 3,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedTheme = _currentTheme(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;

              return Stack(
                children: _particles.map((particle) {
                  final progress =
                      (_controller.value * particle.speed + particle.phase) %
                          1.0;
                  final y = height - (progress * height * 1.2);
                  final oscillation =
                      sin(progress * 2 * pi + particle.phase) * particle.drift;
                  final x = (particle.xSeed + oscillation) * width;

                  return Positioned(
                    left: x,
                    top: y,
                    child: Container(
                      width: particle.size,
                      height: particle.size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selectedTheme.colors.particleColor
                            .withOpacity(0.18 + progress * 0.25),
                        boxShadow: [
                          BoxShadow(
                            color: selectedTheme.colors.particleGlow
                                .withOpacity(0.20),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          );
        },
      ),
    );
  }

  AppThemeConfig _currentTheme(BuildContext context) {
    try {
      return Provider.of<ThemeProvider?>(context, listen: true)?.currentTheme ??
          VocabThemes.defaultTheme;
    } catch (_) {
      return VocabThemes.defaultTheme;
    }
  }
}

class _ParticleSpec {
  final double xSeed;
  final double phase;
  final double speed;
  final double drift;
  final double size;

  const _ParticleSpec({
    required this.xSeed,
    required this.phase,
    required this.speed,
    required this.drift,
    required this.size,
  });
}
