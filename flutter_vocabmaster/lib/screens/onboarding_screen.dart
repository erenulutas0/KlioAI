import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../widgets/animated_background.dart';
import 'login_page.dart';
import '../l10n/app_localizations.dart';
import '../services/app_tour_service.dart';

class OnboardingScreen extends StatefulWidget {
  final bool fromSettings;

  const OnboardingScreen({
    super.key,
    this.fromSettings = false,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Icon Animation Controllers
  late AnimationController _iconController;
  late Animation<double> _iconScaleAnimation;
  late Animation<double> _iconRotationAnimation;

  @override
  void initState() {
    super.initState();

    // Icon Animations
    _iconController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _iconScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _iconController,
        curve: Curves.elasticOut,
      ),
    );

    _iconRotationAnimation = Tween<double>(begin: -0.5, end: 0.0).animate(
      CurvedAnimation(
        parent: _iconController,
        curve: Curves.easeOut,
      ),
    );

    // Start initial animations
    _iconController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
    });

    // Reset and replay icon animation
    _iconController.reset();
    _iconController.forward();
  }

  Future<void> _finishOnboarding() async {
    await AppTourService().markCompleted();
    if (!mounted) return;

    if (widget.fromSettings) {
      Navigator.of(context).pop();
      return;
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const LoginPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  List<OnboardingData> _pages(BuildContext context) {
    return [
      OnboardingData(
        title: context.tr('landing.feature.speaking.title'),
        description: context.tr('landing.feature.speaking.description'),
        icon: Icons.psychology,
        gradient: [const Color(0xFF06b6d4), const Color(0xFF2563eb)],
        featureTexts: [
          context.tr('landing.feature.speaking.h1'),
          context.tr('landing.feature.speaking.h2'),
          context.tr('landing.feature.speaking.h3'),
        ],
      ),
      OnboardingData(
        title: context.tr('landing.feature.writing.title'),
        description: context.tr('landing.feature.writing.description'),
        icon: Icons.edit,
        gradient: [const Color(0xFF3b82f6), const Color(0xFF8b5cf6)],
        featureTexts: [
          context.tr('landing.feature.writing.h1'),
          context.tr('landing.feature.writing.h2'),
          context.tr('landing.feature.writing.h3'),
        ],
      ),
      OnboardingData(
        title: context.tr('landing.feature.social.title'),
        description: context.tr('landing.feature.social.description'),
        icon: Icons.people,
        gradient: [const Color(0xFF22d3ee), const Color(0xFF3b82f6)],
        featureTexts: [
          context.tr('landing.feature.social.h1'),
          context.tr('landing.feature.social.h2'),
          context.tr('landing.feature.social.h3'),
        ],
      ),
      OnboardingData(
        title: context.tr('landing.feature.progress.title'),
        description: context.tr('landing.feature.progress.description'),
        icon: Icons.track_changes,
        gradient: [const Color(0xFF2563eb), const Color(0xFF06b6d4)],
        featureTexts: [
          context.tr('landing.feature.progress.h1'),
          context.tr('landing.feature.progress.h2'),
          context.tr('landing.feature.progress.h3'),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages(context);

    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: Stack(
        children: [
          // Background (Animated Background)
          const Positioned.fill(
            child: AnimatedBackground(isDark: true),
          ),

          // Background Orbs (Pulse Animation)
          const PulsingOrb(
            size: 200, // Reduced size slightly so it's not overwhelming
            color: Color(0xFF06b6d4),
            alignment: Alignment(-0.8, -0.8), // Top Left
            duration: 4,
          ),
          const PulsingOrb(
            size: 300,
            color: Color(0xFF3b82f6),
            alignment: Alignment(0.8, 0.8), // Bottom Right
            duration: 5,
          ),

          // Skip Button
          if (_currentPage < pages.length - 1)
            Positioned(
              top: 50,
              right: 20,
              child: TextButton(
                onPressed: _finishOnboarding,
                child: Text(
                  context.tr('common.skip'),
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),

          // Main Page View
          PageView.builder(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            itemCount: pages.length,
            itemBuilder: (context, index) {
              return AnimatedBuilder(
                animation: _pageController,
                builder: (context, child) {
                  double value = 1.0;
                  if (_pageController.position.haveDimensions) {
                    value = _pageController.page! - index;
                    value = (1 - (value.abs() * 0.3)).clamp(0.0, 1.0);
                  }

                  // Apply Scale and Opacity based on scroll position
                  return Center(
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height *
                          0.8, // Limit height
                      child: Opacity(
                        opacity: value.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: Curves.easeInOut.transform(value),
                          child: child,
                        ),
                      ),
                    ),
                  );
                },
                child: _buildPageContent(index),
              );
            },
          ),

          // Bottom Controls
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Column(
              children: [
                // Swipe Hint removed
                const SizedBox(height: 20),

                // Pagination Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children:
                      List.generate(pages.length, (index) => _buildDot(index)),
                ),

                const SizedBox(height: 30),

                // Navigation Buttons (Back / Next)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back Button (Animated Fade In)
                    AnimatedOpacity(
                      opacity: _currentPage > 0 ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: IgnorePointer(
                        ignoring: _currentPage == 0,
                        child: OutlinedButton(
                          onPressed: () {
                            _pageController.previousPage(
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeInOut,
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white24),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(context.tr('common.back')),
                        ),
                      ),
                    ),

                    // Next / Start Button
                    ElevatedButton(
                      onPressed: _currentPage == pages.length - 1
                          ? _finishOnboarding
                          : () {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 500),
                                curve: Curves.easeInOut,
                              );
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0ea5e9),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 12),
                        elevation: 8,
                        shadowColor: const Color(0xFF0ea5e9).withOpacity(0.4),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_currentPage == pages.length - 1)
                            const Icon(Icons.auto_awesome, size: 18)
                          else
                            Text(context.tr('common.next')),
                          if (_currentPage == pages.length - 1)
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Text(context.tr('common.start')),
                            )
                          else
                            const Padding(
                              padding: EdgeInsets.only(left: 4.0),
                              child: Icon(Icons.arrow_forward, size: 18),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: _currentPage == index ? 32 : 8,
      height: 8,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        gradient: _currentPage == index
            ? const LinearGradient(
                colors: [Color(0xFF06b6d4), Color(0xFF3b82f6)],
              )
            : null,
        color: _currentPage == index ? null : Colors.white.withOpacity(0.2),
      ),
    );
  }

  Widget _buildPageContent(int index) {
    final data = _pages(context)[index];

    // Key ensures StaggeredFeatures rebuilds and restarts animation on page change
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon Container with Animation
          AnimatedBuilder(
            animation: _iconController,
            builder: (context, child) {
              return Transform.scale(
                scale: _iconScaleAnimation.value,
                child: Transform.rotate(
                  angle: _iconRotationAnimation.value * math.pi,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          gradient: LinearGradient(
                            colors: data.gradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: data.gradient[0].withOpacity(0.4),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Icon(data.icon, size: 60, color: Colors.white),
                      ),
                      // Floating Particles
                      const Positioned.fill(child: FloatingParticles()),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 50),

          Text(
            data.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            data.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: const Color(0xFF67e8f9).withOpacity(0.8),
              height: 1.5,
            ),
          ),

          const SizedBox(height: 50),

          // Features
          // Re-create widget when index changes to restart animations
          StaggeredFeatures(
            key: ValueKey(index),
            features: data.featureTexts,
          ),
        ],
      ),
    );
  }
}

// ------ Helper Models ------

class OnboardingData {
  final String title;
  final String description;
  final IconData icon;
  final List<Color> gradient;
  final List<String> featureTexts;

  OnboardingData({
    required this.title,
    required this.description,
    required this.icon,
    required this.gradient,
    required this.featureTexts,
  });
}

// ------ Custom Animated Widgets ------

class FloatingParticles extends StatefulWidget {
  const FloatingParticles({super.key});

  @override
  State<FloatingParticles> createState() => _FloatingParticlesState();
}

class _FloatingParticlesState extends State<FloatingParticles>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _yAnimations;
  late List<Animation<double>> _opacityAnimations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (i) => AnimationController(
        duration: const Duration(seconds: 2),
        vsync: this,
      ),
    );

    _yAnimations = _controllers.map((controller) {
      return Tween<double>(begin: 0, end: -40).animate(controller);
    }).toList();

    _opacityAnimations = _controllers.map((controller) {
      return Tween<double>(begin: 1, end: 0).animate(controller);
    }).toList();

    // Stagger start
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 400), () {
        if (mounted) _controllers[i].repeat();
      });
    }
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _controllers[i],
          builder: (context, child) {
            return Positioned(
              // Position particles relative to the container (120x120)
              top: 20 + _yAnimations[i].value,
              left: 40 + (i * 20.0), // Spread horizontally
              child: Opacity(
                opacity: _opacityAnimations[i].value,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.white54,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

class StaggeredFeatures extends StatefulWidget {
  final List<String> features;
  const StaggeredFeatures({super.key, required this.features});

  @override
  State<StaggeredFeatures> createState() => _StaggeredFeaturesState();
}

class _StaggeredFeaturesState extends State<StaggeredFeatures>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );

    _animations = List.generate(3, (index) {
      double start = (index * 0.2); // 0.0, 0.2, 0.4
      double end = start + 0.5;
      if (end > 1.0) end = 1.0;

      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(start, end, curve: Curves.elasticOut),
        ),
      );
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(widget.features.length, (i) {
        return Expanded(
          child: AnimatedBuilder(
            animation: _animations[i],
            builder: (context, child) {
              return Transform.scale(
                scale: _animations[i].value,
                child: Opacity(
                  opacity: _animations[i].value.clamp(0.0, 1.0),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding:
                        const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF06b6d4).withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(_getIcon(i), color: const Color(0xFF06b6d4)),
                        const SizedBox(height: 8),
                        Text(
                          widget.features[i],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      }),
    );
  }

  IconData _getIcon(int index) {
    if (index == 0) return Icons.flash_on;
    if (index == 1) return Icons.star;
    return Icons.auto_awesome;
  }
}

class PulsingOrb extends StatefulWidget {
  final double size;
  final Color color;
  final Alignment alignment;
  final int duration;

  const PulsingOrb({
    super.key,
    required this.size,
    required this.color,
    required this.alignment,
    this.duration = 3,
  });

  @override
  State<PulsingOrb> createState() => _PulsingOrbState();
}

class _PulsingOrbState extends State<PulsingOrb>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(seconds: widget.duration),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _opacityAnimation = Tween<double>(begin: 0.1, end: 0.3).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.alignment,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Opacity(
              opacity: _opacityAnimation.value,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      widget.color.withOpacity(0.5),
                      widget.color.withOpacity(0.0),
                    ],
                    stops: const [0.2, 1.0],
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
