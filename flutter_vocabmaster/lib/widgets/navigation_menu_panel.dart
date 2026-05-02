import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';

class MenuItemData {
  final String id;
  final String labelKey;
  final IconData icon;

  MenuItemData({
    required this.id,
    required this.labelKey,
    required this.icon,
  });
}

class NavigationMenuPanel extends StatefulWidget {
  final String activeTab;
  final String currentPage;
  final Function(String) onTabChange;
  final Function(String) onNavigate;

  const NavigationMenuPanel({
    required this.activeTab,
    required this.currentPage,
    required this.onTabChange,
    required this.onNavigate,
    super.key,
  });

  @override
  State<NavigationMenuPanel> createState() => _NavigationMenuPanelState();
}

class _NavigationMenuPanelState extends State<NavigationMenuPanel>
    with TickerProviderStateMixin {
  late List<AnimationController> _orbControllers;
  late List<AnimationController> _rainControllers;
  late List<AnimationController> _sparkleControllers;

  AppThemeConfig _currentTheme({required bool listen}) {
    try {
      return Provider.of<ThemeProvider?>(context, listen: listen)
              ?.currentTheme ??
          VocabThemes.defaultTheme;
    } catch (_) {
      return VocabThemes.defaultTheme;
    }
  }

  Color _mix(Color a, Color b, double t) {
    return Color.lerp(a, b, t) ?? a;
  }

  final List<MenuItemData> mainPages = [
    MenuItemData(
        id: 'profile-settings', labelKey: 'nav.profile', icon: Icons.person),
    MenuItemData(id: 'home', labelKey: 'nav.home', icon: Icons.home),
    MenuItemData(id: 'words', labelKey: 'nav.words', icon: Icons.book),
    MenuItemData(
        id: 'sentences', labelKey: 'nav.sentences', icon: Icons.description),
    MenuItemData(id: 'practice', labelKey: 'nav.practice', icon: Icons.school),
    // MVP: Social features disabled for v1.0
    // MenuItemData(id: 'chat', labelKey: 'nav.chat', icon: Icons.chat_bubble),
    // MenuItemData(id: 'feed', labelKey: 'nav.feed', icon: Icons.rss_feed),
    // MenuItemData(id: 'notifications', labelKey: 'nav.notifications', icon: Icons.notifications),
    MenuItemData(id: 'stats', labelKey: 'nav.stats', icon: Icons.bar_chart),
  ];

  final List<MenuItemData> specialPages = [
    MenuItemData(
        id: 'speaking',
        labelKey: 'nav.speaking',
        icon: Icons.chat_bubble_outline),
    MenuItemData(id: 'repeat', labelKey: 'nav.repeat', icon: Icons.replay),
    MenuItemData(
        id: 'dictionary', labelKey: 'nav.dictionary', icon: Icons.book),
    MenuItemData(
        id: 'xp-history', labelKey: 'nav.xpHistory', icon: Icons.history),
    MenuItemData(
        id: 'settings', labelKey: 'nav.settings', icon: Icons.settings),
    MenuItemData(
        id: 'language', labelKey: 'language.label', icon: Icons.language),
  ];

  @override
  void initState() {
    super.initState();
    _initAnimationControllers();
  }

  void _initAnimationControllers() {
    // Orb controllers
    _orbControllers = List.generate(3, (i) {
      final controller = AnimationController(
        vsync: this,
        duration: Duration(seconds: 10 + i * 2),
      );
      controller.repeat();
      return controller;
    });

    // Rain controllers
    _rainControllers = List.generate(20, (i) {
      final duration = 2.0 + Random().nextDouble() * 2;
      final delay = Random().nextDouble() * 3;

      final controller = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: (duration * 1000).toInt()),
      );

      Future.delayed(Duration(milliseconds: (delay * 1000).toInt()), () {
        if (mounted) controller.repeat();
      });

      return controller;
    });

    // Sparkle controllers
    _sparkleControllers = List.generate(10, (i) {
      final duration = 2.0 + Random().nextDouble() * 2;
      final delay = Random().nextDouble() * 3;

      final controller = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: (duration * 1000).toInt()),
      );

      Future.delayed(Duration(milliseconds: (delay * 1000).toInt()), () {
        if (mounted) controller.repeat();
      });

      return controller;
    });
  }

  @override
  void dispose() {
    for (var controller in _orbControllers) {
      controller.dispose();
    }
    for (var controller in _rainControllers) {
      controller.dispose();
    }
    for (var controller in _sparkleControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _handleNavigation(String pageId) {
    // Determine if it's a tab change or navigation
    // Based on user logic:
    // Tabs: home (0), words (1), sentences (3), practice (4)
    // Navigations: profile-settings, chat, stats, speaking, repeat, dictionary

    // We pass the ID back to the parent to handle
    if (['home', 'words', 'sentences', 'practice'].contains(pageId)) {
      widget.onTabChange(pageId);
    } else {
      widget.onNavigate(pageId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _currentTheme(listen: true);
    final mainStart = _mix(theme.colors.accent, theme.colors.primary, 0.25);
    final mainEnd = theme.colors.primary;
    final specialStart = _mix(theme.colors.primary, theme.colors.accent, 0.45);
    final specialEnd = theme.colors.accent;

    return Drawer(
      // Wrapped in Drawer to work with Scaffold.drawer
      backgroundColor: Colors.transparent,
      elevation: 0,
      width: 320, // As per prompt container width
      child: Container(
        width: 320,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colors.background.withOpacity(0.98),
              _mix(theme.colors.background, theme.colors.primaryDark, 0.55)
                  .withOpacity(0.98),
              theme.colors.background.withOpacity(0.98),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Layer 2: Animated effects
            _buildAnimatedEffects(),

            // Layer 3: Content
            Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    children: [
                      // Main Pages
                      _buildSectionHeader(
                        context.tr('nav.mainPages'),
                        mainStart,
                        mainEnd,
                      ),
                      const SizedBox(height: 6),
                      ...mainPages.map((page) => _buildMenuItemWrapper(page)),

                      const SizedBox(height: 24),

                      // Special Pages
                      _buildSectionHeader(
                        context.tr('nav.specialPages'),
                        specialStart,
                        specialEnd,
                      ),
                      const SizedBox(height: 6),
                      ...specialPages
                          .map((page) => _buildMenuItemWrapper(page)),
                    ],
                  ),
                ),
                _buildFooter(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItemWrapper(MenuItemData page) {
    final theme = _currentTheme(listen: true);
    // Determine if active
    bool isActive = false;
    if (['home', 'words', 'sentences', 'practice'].contains(page.id)) {
      isActive = widget.activeTab == page.id;
    } else {
      isActive = widget.currentPage == page.id;
    }

    // Colors based on section
    final bool isSpecial = specialPages.contains(page);

    return _buildMenuItem(
      item: page,
      isActive: isActive,
      onTap: () => _handleNavigation(page.id),
      activeStartColor: isSpecial
          ? _mix(theme.colors.primary, theme.colors.accent, 0.45)
          : _mix(theme.colors.accent, theme.colors.primary, 0.20),
      activeEndColor: isSpecial ? theme.colors.accent : theme.colors.primary,
      iconColor: isSpecial
          ? _mix(theme.colors.accent, Colors.white, 0.18)
          : _mix(theme.colors.primary, Colors.white, 0.18),
      shadowColor: isSpecial
          ? theme.colors.accentGlow.withOpacity(0.45)
          : theme.colors.accentGlow.withOpacity(0.35),
    );
  }

  Widget _buildAnimatedEffects() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            ...List.generate(3, (i) => _buildGlowingOrb(i)),
            ...List.generate(20, (i) => _buildRainDrop(i)),
            ...List.generate(10, (i) => _buildSparkle(i)),
          ],
        ),
      ),
    );
  }

  Widget _buildGlowingOrb(int index) {
    final theme = _currentTheme(listen: true);
    return AnimatedBuilder(
      animation: _orbControllers[index],
      builder: (context, child) {
        final value = _orbControllers[index].value;
        final scale = 1.0 + 0.3 * sin(value * 2 * pi);
        final opacity = 0.3 + 0.3 * sin(value * 2 * pi);
        final offsetX = 20 * sin(value * 2 * pi);
        final offsetY = -30 * cos(value * 2 * pi);

        return Positioned(
          left: index * 30.0 * 3.2 + offsetX,
          top: index * 40.0 * 6 + offsetY,
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: 256,
                height: 256,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      index % 2 == 0
                          ? theme.colors.orbColor1.withOpacity(0.18)
                          : theme.colors.orbColor2.withOpacity(0.18),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.7],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRainDrop(int index) {
    final theme = _currentTheme(listen: true);
    final size = 2.0 + Random().nextDouble() * 3;
    final initialX = Random().nextDouble() * 320;

    return AnimatedBuilder(
      animation: _rainControllers[index],
      builder: (context, child) {
        final value = _rainControllers[index].value;
        final yPos = -20 + (800 * value);
        final opacity = value < 0.2
            ? value / 0.2
            : value > 0.8
                ? (1 - value) / 0.2
                : 1.0;

        return Positioned(
          left: initialX,
          top: yPos,
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: size,
              height: size * 3,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.colors.particleColor.withOpacity(0.52),
                    theme.colors.particleColor.withOpacity(0.22),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
                borderRadius: BorderRadius.circular(size),
                boxShadow: [
                  BoxShadow(
                    color: theme.colors.particleGlow.withOpacity(0.45),
                    blurRadius: 8,
                    spreadRadius: 0,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSparkle(int index) {
    final theme = _currentTheme(listen: true);
    final left = Random().nextDouble() * 320;
    final top = Random().nextDouble() * 800;

    return AnimatedBuilder(
      animation: _sparkleControllers[index],
      builder: (context, child) {
        final value = _sparkleControllers[index].value;
        final scale = value < 0.5 ? value * 3 : (1 - value) * 3;
        final opacity = value < 0.5 ? value * 2 : (1 - value) * 2;

        return Positioned(
          left: left,
          top: top,
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colors.accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: theme.colors.accentGlow.withOpacity(0.55),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    final theme = _currentTheme(listen: true);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 56, 18, 20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        border: Border(
          bottom: BorderSide(
            color: theme.colors.glassBorder.withOpacity(0.75),
            width: 1,
          ),
        ),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colors.accent.withOpacity(0.28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colors.accentGlow.withOpacity(0.45),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(
                    'assets/images/mainLogo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.auto_awesome_rounded,
                      color: theme.colors.accent,
                      size: 26,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon:
                    const Icon(Icons.close, color: Color(0xB3FFFFFF), size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color startColor, Color endColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [startColor, endColor],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: startColor.withOpacity(0.8),
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required MenuItemData item,
    required bool isActive,
    required VoidCallback onTap,
    required Color activeStartColor,
    required Color activeEndColor,
    required Color iconColor,
    required Color shadowColor,
  }) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 300),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(-20 * (1 - value), 0),
          child: Opacity(
            opacity: value,
            // Wrapping Material to ensure ink splash works over container
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(12),
                  splashColor: activeStartColor.withOpacity(0.2),
                  highlightColor: activeStartColor.withOpacity(0.1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: isActive
                          ? LinearGradient(
                              colors: [activeStartColor, activeEndColor],
                            )
                          : null,
                      color: isActive ? null : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: shadowColor,
                                blurRadius: 16,
                                spreadRadius: 0,
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          item.icon,
                          size: 20,
                          color: isActive ? Colors.white : iconColor,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            context.tr(item.labelKey),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: isActive
                                  ? Colors.white
                                  : const Color(0xCCFFFFFF),
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                        if (isActive) _buildPulsingDot(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: const SizedBox.shrink(), // Not used, builder is used
    );
  }

  Widget _buildPulsingDot() {
    return TweenAnimationBuilder<double>(
      duration: const Duration(seconds: 2),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeInOut,
      onEnd: () {
        if (mounted) setState(() {});
      },
      builder: (context, value, child) {
        final scale = 1.0 + 0.2 * sin(value * 2 * pi);
        final opacity = 0.7 + 0.3 * sin(value * 2 * pi);

        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x80FFFFFF),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    final theme = _currentTheme(listen: true);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colors.accent.withOpacity(0.12),
            theme.colors.primary.withOpacity(0.12),
          ],
        ),
        border: Border(
          top: BorderSide(
            color: theme.colors.glassBorder.withOpacity(0.75),
            width: 1,
          ),
        ),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Column(
            children: [
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [
                    _mix(theme.colors.accent, Colors.white, 0.22),
                    theme.colors.primary,
                  ],
                ).createShader(bounds),
                child: Text(
                  context.tr('nav.version'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('nav.copyright2026'),
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
