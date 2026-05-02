import 'package:flutter/material.dart';
import 'dart:async';
import 'login_page.dart'; // Import LoginPage
import '../widgets/modern_card.dart';
import '../widgets/modern_background.dart';
import '../l10n/app_localizations.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with TickerProviderStateMixin {
  // Animation Controllers
  late AnimationController _logoController;
  late AnimationController _orb1Controller;
  late AnimationController _orb2Controller;
  late AnimationController _orb3Controller;
  late List<AnimationController> _sparkleControllers;
  late List<AnimationController> _statsAnimations;

  // PageView
  late PageController _pageController;
  int _currentFeature = 0;
  Timer? _featureTimer;

  // Animations
  late Animation<double> _logoScaleAnimation;
  late Animation<double> _logoRotationAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize controllers
    _logoController = AnimationController(
        duration: const Duration(milliseconds: 1200), vsync: this);

    _logoScaleAnimation = CurvedAnimation(
      parent: _logoController,
      curve: Curves.elasticOut,
    );

    _logoRotationAnimation = Tween<double>(
      begin: -3.14,
      end: 0.0,
    ).animate(_logoController);

    _orb1Controller =
        AnimationController(duration: const Duration(seconds: 8), vsync: this)
          ..repeat(reverse: true);
    _orb2Controller =
        AnimationController(duration: const Duration(seconds: 10), vsync: this)
          ..repeat(reverse: true);
    _orb3Controller =
        AnimationController(duration: const Duration(seconds: 12), vsync: this)
          ..repeat(reverse: true);

    _sparkleControllers = List.generate(
        4,
        (i) => AnimationController(
            duration: const Duration(seconds: 2), vsync: this)
          ..repeat());
    _statsAnimations = List.generate(
        4,
        (i) => AnimationController(
            duration: const Duration(milliseconds: 500), vsync: this));

    _pageController = PageController(); // Initialize PageController

    // Start animations
    _logoController.forward();
    _startStaggeredAnimations();
    _startFeatureRotation();
  }

  void _startStaggeredAnimations() {
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _statsAnimations[0].forward();
    });
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _statsAnimations[1].forward();
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _statsAnimations[2].forward();
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _statsAnimations[3].forward();
    });
  }

  void _startFeatureRotation() {
    _featureTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) return;
      if (_currentFeature < 4) {
        _currentFeature++;
      } else {
        _currentFeature = 0;
      }
      if (_pageController.hasClients) {
        _pageController.animateToPage(_currentFeature,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut);
      }
    });
  }

  @override
  void dispose() {
    _featureTimer?.cancel();
    _logoController.dispose();
    _orb1Controller.dispose();
    _orb2Controller.dispose();
    _orb3Controller.dispose();
    for (var c in _sparkleControllers) {
      c.dispose();
    }
    for (var c in _statsAnimations) {
      c.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF020617),
                  Color(0xFF172554),
                  Color(0xFF020617)
                ],
              ),
            ),
          ),

          // Orb 1, 2, 3
          _buildAnimatedOrb(_orb1Controller, top: 80, left: -80),
          _buildAnimatedOrb(_orb2Controller, top: 160, right: -80, delay: 1),
          _buildAnimatedOrb(_orb3Controller,
              bottom: -80, centerX: true, delay: 2),

          // Main content
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const SizedBox(height: 48),
                    _buildLogo(),
                    const SizedBox(height: 32),
                    _buildTitle(),
                    const SizedBox(height: 16),
                    _buildSubtitle(),
                    const SizedBox(height: 32),
                    _buildStatsGrid(),
                    const SizedBox(height: 48),
                    _buildFeatureShowcase(),
                    const SizedBox(height: 24),
                    _buildNavigationDots(),
                    const SizedBox(height: 32),
                    _buildCTAButton(),
                    const SizedBox(height: 32),
                    _buildTrustIndicators(),
                    const SizedBox(height: 48),
                    _buildFooter(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Widget builders...
  Widget _buildAnimatedOrb(AnimationController controller,
      {double? top,
      double? bottom,
      double? left,
      double? right,
      bool centerX = false,
      int delay = 0}) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: centerX ? null : left,
      right: right,
      // For centerX, we need to wrap in Center or Align, but Positioned doesn't support center directly horizontally without left/right
      // We'll use MediaQuery to center
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final scale = 1.0 + (0.2 * controller.value);
          final opacity = 0.3 + (0.2 * controller.value);
          final orbWidget = Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: 384,
                height: 384,
                decoration: BoxDecoration(
                  color: const Color(0xFF06B6D4).withOpacity(0.2),
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF06B6D4).withOpacity(0.2),
                      Colors.transparent
                    ],
                  ),
                ),
              ),
            ),
          );

          if (centerX) {
            return SizedBox(
              width: MediaQuery.of(context).size.width,
              child: Center(child: orbWidget),
            );
          }
          return orbWidget;
        },
      ),
    );
  }

  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: _logoController,
      builder: (context, child) {
        return Transform.scale(
          scale: _logoScaleAnimation.value,
          child: Transform.rotate(
            angle: _logoRotationAnimation.value,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF22D3EE), Color(0xFF3B82F6)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF22D3EE).withOpacity(0.5),
                        blurRadius: 40,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.book, size: 48, color: Colors.white),
                ),
                // Sparkles
                ...List.generate(4, (i) => _buildSparkle(i)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSparkle(int i) {
    return AnimatedBuilder(
      animation: _sparkleControllers[i],
      builder: (context, child) {
        final progress = _sparkleControllers[i].value;
        // Calculate position relative to center (0,0 is center of Stack)
        // Container is 96x96. Top-left is -48,-48
        final offsetX = ((i - 1.5) * 30.0) + ((i - 1.5) * 15.0 * progress);
        final offsetY = -60 + (-40.0 * progress);

        return Transform.translate(
          offset: Offset(offsetX, offsetY),
          child: Opacity(
            opacity: 1 - progress,
            child: Container(
              width: 8 * (1 - progress),
              height: 8 * (1 - progress),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.white, blurRadius: 5)],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTitle() {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [
          Color(0xFF22D3EE),
          Color(0xFF3B82F6),
          Color(0xFFA855F7),
        ],
      ).createShader(bounds),
      child: const Text(
        'KlioAI',
        style: TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: -1,
        ),
      ),
    );
  }

  Widget _buildSubtitle() {
    return Text(
      context.tr('landing.subtitle'),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 16,
        color: const Color(0xFFE0F2FE).withOpacity(0.8),
        height: 1.5,
      ),
    );
  }

  Widget _buildStatsGrid() {
    final stats = [
      {
        'value': '6+',
        'label': context.tr('landing.stat.aiModels'),
        'icon': Icons.psychology
      },
      {
        'value': '5K+',
        'label': context.tr('landing.stat.activeUsers'),
        'icon': Icons.people
      },
      {
        'value': '10+',
        'label': context.tr('landing.stat.features'),
        'icon': Icons.star
      },
      {
        'value': '99%',
        'label': context.tr('landing.stat.satisfaction'),
        'icon': Icons.favorite
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio:
            1.1, // Decreased from 1.5 to provide more vertical space
      ),
      itemCount: 4,
      itemBuilder: (context, index) {
        return ScaleTransition(
          scale: _statsAnimations[index],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF22D3EE).withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(stats[index]['icon'] as IconData,
                    color: const Color(0xFF22D3EE), size: 24),
                const SizedBox(height: 8),
                Text(
                  stats[index]['value'] as String,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  stats[index]['label'] as String,
                  style: TextStyle(
                    fontSize: 12,
                    color: const Color(0xFF67E8F9).withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeatureShowcase() {
    final features = [
      {
        'icon': Icons.psychology,
        'title': context.tr('landing.feature.speaking.title'),
        'subtitle': context.tr('landing.feature.speaking.subtitle'),
        'description': context.tr('landing.feature.speaking.description'),
        'stats': context.tr('landing.feature.speaking.stats'),
        'highlights': [
          context.tr('landing.feature.speaking.h1'),
          context.tr('landing.feature.speaking.h2'),
          context.tr('landing.feature.speaking.h3'),
        ],
        'gradient': [const Color(0xFF22D3EE), const Color(0xFF3B82F6)],
      },
      {
        'icon': Icons.edit,
        'title': context.tr('landing.feature.writing.title'),
        'subtitle': context.tr('landing.feature.writing.subtitle'),
        'description': context.tr('landing.feature.writing.description'),
        'stats': context.tr('landing.feature.writing.stats'),
        'highlights': [
          context.tr('landing.feature.writing.h1'),
          context.tr('landing.feature.writing.h2'),
          context.tr('landing.feature.writing.h3'),
        ],
        'gradient': [const Color(0xFF3B82F6), const Color(0xFFA855F7)],
      },
      {
        'icon': Icons.people,
        'title': context.tr('landing.feature.social.title'),
        'subtitle': context.tr('landing.feature.social.subtitle'),
        'description': context.tr('landing.feature.social.description'),
        'stats': context.tr('landing.feature.social.stats'),
        'highlights': [
          context.tr('landing.feature.social.h1'),
          context.tr('landing.feature.social.h2'),
          context.tr('landing.feature.social.h3'),
        ],
        'gradient': [const Color(0xFFA855F7), const Color(0xFFEC4899)],
      },
      {
        'icon': Icons.track_changes,
        'title': context.tr('landing.feature.progress.title'),
        'subtitle': context.tr('landing.feature.progress.subtitle'),
        'description': context.tr('landing.feature.progress.description'),
        'stats': context.tr('landing.feature.progress.stats'),
        'highlights': [
          context.tr('landing.feature.progress.h1'),
          context.tr('landing.feature.progress.h2'),
          context.tr('landing.feature.progress.h3'),
        ],
        'gradient': [const Color(0xFFEC4899), const Color(0xFFEF4444)],
      },
      {
        'icon': Icons.mic,
        'title': context.tr('landing.feature.speechPractice.title'),
        'subtitle': context.tr('landing.feature.speechPractice.subtitle'),
        'description': context.tr('landing.feature.speechPractice.description'),
        'stats': context.tr('landing.feature.speechPractice.stats'),
        'highlights': [
          context.tr('landing.feature.speechPractice.h1'),
          context.tr('landing.feature.speechPractice.h2'),
          context.tr('landing.feature.speechPractice.h3'),
        ],
        'gradient': [const Color(0xFFEF4444), const Color(0xFFF97316)],
      },
    ];

    return SizedBox(
      height: 480, // Increased height for better fit
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          if (mounted) {
            setState(() {
              _currentFeature = index;
            });
          }
        },
        itemCount: features.length,
        itemBuilder: (context, index) {
          final feature = features[index];
          final gradient = feature['gradient'] as List<Color>;
          final highlights = feature['highlights'] as List<String>;

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    gradient[0].withOpacity(0.1),
                    gradient[1].withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
                boxShadow: [
                  BoxShadow(
                    color: gradient[0].withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ]),
            child: Stack(
              children: [
                // Top line
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: gradient),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon & Badge
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                                gradient: LinearGradient(colors: gradient),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 10,
                                      offset: Offset(0, 5))
                                ]),
                            child: Icon(
                              feature['icon'] as IconData,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF06B6D4).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF22D3EE).withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              feature['stats'] as String,
                              style: const TextStyle(
                                color: Color(0xFF67E8F9),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Title
                      Text(
                        feature['title'] as String,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        feature['subtitle'] as String,
                        style: TextStyle(
                          fontSize: 12,
                          color: const Color(0xFF67E8F9).withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Description
                      Text(
                        feature['description'] as String,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.8),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Highlights
                      ...highlights.map((highlight) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle,
                                  color: gradient[0], size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  highlight,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: const Color(0xFFE0F2FE)
                                        .withOpacity(0.9),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildNavigationDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        return GestureDetector(
          onTap: () {
            _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: _currentFeature == index ? 32 : 8,
            height: 8,
            decoration: BoxDecoration(
              gradient: _currentFeature == index
                  ? const LinearGradient(
                      colors: [Color(0xFF22D3EE), Color(0xFF3B82F6)])
                  : null,
              color: _currentFeature == index
                  ? null
                  : Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCTAButton() {
    return GestureDetector(
      onTap: () {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const LoginPage()),
          );
        }
      },
      child: ModernCard(
        variant: BackgroundVariant.accent,
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.symmetric(vertical: 20),
        showGlow: true,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Text(
              context.tr('landing.cta'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward, color: Colors.white, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildTrustIndicators() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildTrustIndicator(Icons.shield, context.tr('landing.trust.secure')),
        const SizedBox(width: 24),
        _buildTrustIndicator(Icons.flash_on, context.tr('landing.trust.fast')),
        const SizedBox(width: 24),
        _buildTrustIndicator(Icons.public, context.tr('landing.trust.global')),
      ],
    );
  }

  Widget _buildTrustIndicator(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF67E8F9).withOpacity(0.6), size: 16),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: const Color(0xFF67E8F9).withOpacity(0.6),
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        color: Colors.black.withOpacity(0.2),
      ),
      child: Column(
        children: [
          Text(
            context.tr('landing.footer.copy'),
            style: TextStyle(
              color: const Color(0xFF67E8F9).withOpacity(0.6),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            context.tr('landing.footer.subtitle'),
            style: TextStyle(
              color: const Color(0xFF67E8F9).withOpacity(0.4),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
