import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';

class AnimatedBackground extends StatefulWidget {
  final bool isDark;
  final bool enableAnimations;

  const AnimatedBackground({
    super.key,
    this.isDark = true,
    this.enableAnimations = true,
  });

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _ParticleSeed {
  final double x;
  final double y;
  final double size;
  final double driftX;
  final double driftY;
  final double angle;

  const _ParticleSeed({
    required this.x,
    required this.y,
    required this.size,
    required this.driftX,
    required this.driftY,
    required this.angle,
  });
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with TickerProviderStateMixin {
  final List<Timer> _startTimers = [];
  final Random _random = Random();

  List<AnimationController> _particleControllers = [];
  List<AnimationController> _orbControllers = [];
  AnimationController? _coreBurstController;
  List<_ParticleSeed> _particles = [];
  AppThemeConfig _theme = VocabThemes.defaultTheme;
  bool _isConfigured = false;

  @override
  void initState() {
    super.initState();
    _configureAnimations();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final themeProvider = _getThemeProvider(listen: true);
    final nextTheme = themeProvider?.currentTheme ?? VocabThemes.defaultTheme;
    if (nextTheme.id != _theme.id) {
      _theme = nextTheme;
      _configureAnimations();
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enableAnimations != widget.enableAnimations) {
      _configureAnimations();
    }
  }

  ThemeProvider? _getThemeProvider({required bool listen}) {
    try {
      return Provider.of<ThemeProvider?>(context, listen: listen);
    } catch (_) {
      return null;
    }
  }

  void _configureAnimations() {
    _disposeControllers();
    _cancelStartTimers();
    _particles = [];

    if (!widget.enableAnimations) {
      if (mounted) {
        setState(() {
          _isConfigured = true;
        });
      } else {
        _isConfigured = true;
      }
      return;
    }

    final count = _theme.animations.particleCount.clamp(10, 45).toInt();
    _particles = List<_ParticleSeed>.generate(count, (index) {
      return _ParticleSeed(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        size: 1.8 + _random.nextDouble() * 3.6,
        driftX: (_random.nextDouble() - 0.5) * 80,
        driftY: (_random.nextDouble() - 0.5) * 80,
        angle: _random.nextDouble() * pi * 2,
      );
    });

    _particleControllers = List<AnimationController>.generate(count, (index) {
      final controller = AnimationController(
        duration: Duration(milliseconds: _particleDurationMs()),
        vsync: this,
      );

      final delayMs = (_random.nextDouble() * 2500).toInt();
      final timer = Timer(Duration(milliseconds: delayMs), () {
        if (mounted) {
          controller.repeat();
        }
      });
      _startTimers.add(timer);
      return controller;
    });

    _orbControllers = List<AnimationController>.generate(3, (index) {
      final controller = AnimationController(
        duration: Duration(milliseconds: 7000 + index * 1800),
        vsync: this,
      )..repeat(reverse: true);
      return controller;
    });

    _coreBurstController = AnimationController(
      duration: Duration(milliseconds: _burstDurationMs()),
      vsync: this,
    )..repeat();

    if (mounted) {
      setState(() {
        _isConfigured = true;
      });
    } else {
      _isConfigured = true;
    }
  }

  int _particleDurationMs() {
    final style = _theme.animations.particleStyle;
    switch (style) {
      case ThemeParticleStyle.rain:
        return 1800 + _random.nextInt(1800);
      case ThemeParticleStyle.neural:
        return 12000 + _random.nextInt(9000);
      case ThemeParticleStyle.float:
        return 9000 + _random.nextInt(7000);
      case ThemeParticleStyle.pulse:
        return 2600 + _random.nextInt(2600);
      case ThemeParticleStyle.energy:
        return 1800 + _random.nextInt(1700);
    }
  }

  int _burstDurationMs() {
    switch (_theme.animations.particleStyle) {
      case ThemeParticleStyle.energy:
        return 1800;
      case ThemeParticleStyle.neural:
        return 2400;
      case ThemeParticleStyle.float:
        return 2800;
      case ThemeParticleStyle.pulse:
        return 2600;
      case ThemeParticleStyle.rain:
        return 2200;
    }
  }

  double _glowFactor() {
    switch (_theme.animations.glowIntensity) {
      case 'low':
        return 0.85;
      case 'high':
        return 1.35;
      default:
        return 1.0;
    }
  }

  double _darknessFactor() {
    return widget.isDark ? 1.0 : 0.75;
  }

  @override
  void dispose() {
    _cancelStartTimers();
    _disposeControllers();
    super.dispose();
  }

  void _cancelStartTimers() {
    for (final timer in _startTimers) {
      timer.cancel();
    }
    _startTimers.clear();
  }

  void _disposeControllers() {
    for (final controller in _particleControllers) {
      controller.dispose();
    }
    for (final controller in _orbControllers) {
      controller.dispose();
    }
    _coreBurstController?.dispose();
    _coreBurstController = null;
    _particleControllers = [];
    _orbControllers = [];
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = _getThemeProvider(listen: true);
    final selectedTheme =
        themeProvider?.currentTheme ?? VocabThemes.defaultTheme;
    if (selectedTheme.id != _theme.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _theme = selectedTheme;
        _configureAnimations();
      });
    }

    final size = MediaQuery.of(context).size;
    final transitionMs = selectedTheme.animations.transitionDurationMs;

    return IgnorePointer(
      child: AnimatedContainer(
        duration: Duration(milliseconds: transitionMs),
        curve: Curves.easeInOut,
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          gradient: selectedTheme.colors.backgroundGradient,
        ),
        child: widget.enableAnimations && _isConfigured
            ? Stack(
                children: [
                  ..._buildCoreBurst(size),
                  ..._buildParticles(size),
                  ..._buildOrbs(size),
                ],
              )
            : null,
      ),
    );
  }

  List<Widget> _buildParticles(Size size) {
    switch (_theme.animations.particleStyle) {
      case ThemeParticleStyle.rain:
        return _buildRainParticles(size);
      case ThemeParticleStyle.neural:
        return _buildNeuralParticles(size);
      case ThemeParticleStyle.float:
        return _buildFloatParticles(size);
      case ThemeParticleStyle.pulse:
        return _buildPulseParticles(size);
      case ThemeParticleStyle.energy:
        return _buildEnergyParticles(size);
    }
  }

  List<Widget> _buildRainParticles(Size size) {
    final glow = _glowFactor() * _darknessFactor();
    return List<Widget>.generate(_particles.length, (index) {
      final controller = _particleControllers[index];
      final particle = _particles[index];

      return AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final progress = controller.value;
          final opacity = progress < 0.1
              ? progress * 10
              : (progress > 0.9 ? (1 - progress) * 10 : 1.0);
          final xPos = particle.x * size.width;
          final yPos = -22 + progress * (size.height + 80);

          return Positioned(
            left: xPos,
            top: yPos,
            child: Opacity(
              opacity: opacity * 0.7,
              child: Container(
                width: particle.size,
                height: particle.size * 3.1,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(particle.size),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _theme.colors.particleColor,
                      _theme.colors.particleColor.withOpacity(0.25),
                      Colors.transparent,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _theme.colors.particleGlow.withOpacity(0.5 * glow),
                      blurRadius: 8 * glow,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    });
  }

  List<Widget> _buildNeuralParticles(Size size) {
    final glow = _glowFactor() * _darknessFactor();
    return List<Widget>.generate(_particles.length, (index) {
      final controller = _particleControllers[index];
      final particle = _particles[index];

      return AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final progress = controller.value;
          final xPos = particle.x * size.width;
          final yPos = size.height - progress * (size.height + 120);
          final wave = sin(progress * pi * 2);
          final scale = 0.8 + wave.abs() * 0.45;
          final opacity = (0.15 + (1 - (progress - 0.45).abs() * 1.6))
              .clamp(0.0, 1.0)
              .toDouble();

          return Positioned(
            left: xPos,
            top: yPos,
            child: Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: opacity * 0.9,
                child: Container(
                  width: particle.size * 1.6,
                  height: particle.size * 1.6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _theme.colors.particleColor,
                    boxShadow: [
                      BoxShadow(
                        color:
                            _theme.colors.particleGlow.withOpacity(0.55 * glow),
                        blurRadius: 12 * glow,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
  }

  List<Widget> _buildFloatParticles(Size size) {
    final glow = _glowFactor() * _darknessFactor();
    return List<Widget>.generate(_particles.length, (index) {
      final controller = _particleControllers[index];
      final particle = _particles[index];

      return AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final progress = controller.value;
          final xDrift =
              sin(progress * 2 * pi + particle.angle) * particle.driftX;
          final yDrift =
              cos(progress * 2 * pi + particle.angle) * particle.driftY;
          final xPos = (particle.x * size.width + xDrift)
              .clamp(-40.0, size.width + 40)
              .toDouble();
          final yPos = (particle.y * size.height + yDrift)
              .clamp(-40.0, size.height + 40)
              .toDouble();
          final pulse = 0.65 + 0.35 * sin(progress * pi * 2).abs();

          return Positioned(
            left: xPos,
            top: yPos,
            child: Opacity(
              opacity: 0.35 + 0.35 * pulse,
              child: Container(
                width: particle.size * 2.2,
                height: particle.size * 2.2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _theme.colors.particleColor,
                  boxShadow: [
                    BoxShadow(
                      color:
                          _theme.colors.particleGlow.withOpacity(0.45 * glow),
                      blurRadius: 10 * glow,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    });
  }

  List<Widget> _buildPulseParticles(Size size) {
    final glow = _glowFactor() * _darknessFactor();
    return List<Widget>.generate(_particles.length, (index) {
      final controller = _particleControllers[index];
      final particle = _particles[index];
      final xPos = particle.x * size.width;
      final yPos = particle.y * size.height;

      return AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final progress = controller.value;
          final scale = 0.7 + 0.8 * sin(progress * pi).abs();
          final opacity = 0.2 + 0.45 * sin(progress * pi).abs();
          final radius = particle.size * 4.2 * scale;

          return Positioned(
            left: xPos - radius / 2,
            top: yPos - radius / 2,
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: radius,
                height: radius,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _theme.colors.particleColor.withOpacity(0.55),
                      _theme.colors.particleColor.withOpacity(0.15),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          _theme.colors.particleGlow.withOpacity(0.35 * glow),
                      blurRadius: 8 * glow,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    });
  }

  List<Widget> _buildEnergyParticles(Size size) {
    final glow = _glowFactor() * _darknessFactor();
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final maxRadius = min(size.width, size.height) * 0.6;

    return List<Widget>.generate(_particles.length, (index) {
      final controller = _particleControllers[index];
      final particle = _particles[index];
      final baseAngle =
          particle.angle + (index / max(1, _particles.length)) * pi * 2;

      return AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final progress = controller.value;
          final radius = progress * maxRadius;
          final angle = baseAngle + sin(progress * pi * 2) * 0.3;
          final xPos = centerX + cos(angle) * radius;
          final yPos = centerY + sin(angle) * radius;
          final opacity = (1.0 - progress).clamp(0.0, 1.0).toDouble();
          final scale = 0.8 + (1.0 - progress) * 0.7;

          return Positioned(
            left: xPos,
            top: yPos,
            child: Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: 0.85 * opacity,
                child: Container(
                  width: particle.size * 2.2,
                  height: particle.size * 2.2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _theme.colors.particleColor,
                    boxShadow: [
                      BoxShadow(
                        color:
                            _theme.colors.particleGlow.withOpacity(0.6 * glow),
                        blurRadius: 12 * glow,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
  }

  List<Widget> _buildOrbs(Size size) {
    if (!_theme.animations.backgroundMotion) {
      return const [];
    }
    if (_orbControllers.isEmpty) {
      return const [];
    }

    return List<Widget>.generate(_orbControllers.length, (index) {
      final controller = _orbControllers[index];
      final baseSize = index == 0
          ? size.width * 0.7
          : (index == 1 ? size.width * 0.56 : size.width * 0.64);
      final anchorX = index == 0
          ? size.width * 0.08
          : (index == 1 ? size.width * 0.72 : size.width * 0.46);
      final anchorY = index == 0
          ? size.height * 0.14
          : (index == 1 ? size.height * 0.62 : size.height * 0.32);
      final orbColor =
          index % 2 == 0 ? _theme.colors.orbColor1 : _theme.colors.orbColor2;

      return AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final progress = controller.value;
          final motionX = sin(progress * pi * 2 + index) * (20 + index * 12);
          final motionY = cos(progress * pi * 2 + index) * (16 + index * 10);
          final scale = 0.9 + sin(progress * pi * 2).abs() * 0.25;
          final opacity =
              (0.45 + sin(progress * pi * 2).abs() * 0.35) * _darknessFactor();

          return Positioned(
            left: anchorX + motionX - (baseSize / 2),
            top: anchorY + motionY - (baseSize / 2),
            child: Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0).toDouble(),
                child: Container(
                  width: baseSize,
                  height: baseSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        orbColor,
                        orbColor.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
  }

  List<Widget> _buildCoreBurst(Size size) {
    final controller = _coreBurstController;
    if (controller == null) {
      return const [];
    }

    final centerX = size.width / 2;
    final centerY = size.height * 0.5;
    final maxRadius = min(size.width, size.height) * 0.42;

    return [
      Positioned.fill(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            final t = controller.value;
            final eased = Curves.easeOut.transform(t);
            final burstRadius = maxRadius * eased;
            final ringOpacity = (1.0 - eased).clamp(0.0, 1.0);
            final coreOpacity = (0.55 - (eased * 0.40)).clamp(0.0, 1.0);

            return Stack(
              children: [
                Positioned(
                  left: centerX - burstRadius,
                  top: centerY - burstRadius,
                  child: Container(
                    width: burstRadius * 2,
                    height: burstRadius * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _theme.colors.accentGlow
                            .withOpacity(0.35 * ringOpacity),
                        width: 2.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _theme.colors.accentGlow
                              .withOpacity(0.22 * ringOpacity),
                          blurRadius: 24,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: centerX - 56,
                  top: centerY - 56,
                  child: Opacity(
                    opacity: coreOpacity,
                    child: Container(
                      width: 112,
                      height: 112,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            _theme.colors.primary.withOpacity(0.65),
                            _theme.colors.accent.withOpacity(0.20),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.58, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ];
  }
}

