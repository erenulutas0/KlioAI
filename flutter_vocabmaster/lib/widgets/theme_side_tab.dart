import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class ThemeSideTab extends StatefulWidget {
  final Widget child;

  const ThemeSideTab({
    super.key,
    required this.child,
  });

  @override
  State<ThemeSideTab> createState() => _ThemeSideTabState();
}

class _ThemeSideTabState extends State<ThemeSideTab> {
  bool _isPickerOpen = false;

  Future<void> _openThemePicker() async {
    if (_isPickerOpen) return;
    final navigatorContext = appNavigatorKey.currentContext ?? context;
    final isTurkish = Localizations.localeOf(context).languageCode == 'tr';
    setState(() => _isPickerOpen = true);
    await Future<void>.delayed(Duration.zero);
    if (!mounted || !navigatorContext.mounted) return;

    await showGeneralDialog<void>(
      context: navigatorContext,
      barrierDismissible: true,
      barrierLabel: isTurkish ? 'Tema Sec' : 'Choose Theme',
      barrierColor: Colors.black.withOpacity(0.18),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return const _ThemePickerOverlay();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );

    if (mounted) {
      setState(() => _isPickerOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        _ThemeHandle(
          visible: !_isPickerOpen,
          onTap: _openThemePicker,
        ),
      ],
    );
  }
}

class _ThemeHandle extends StatelessWidget {
  final bool visible;
  final VoidCallback onTap;

  const _ThemeHandle({
    required this.visible,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final selectedTheme = themeProvider.currentTheme;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: visible ? 0 : -8,
      top: MediaQuery.sizeOf(context).height * 0.36,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: visible ? 1 : 0,
        child: SafeArea(
          child: IgnorePointer(
            ignoring: !visible,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(5),
                ),
                child: Container(
                  width: 6,
                  height: 84,
                  decoration: BoxDecoration(
                    gradient: selectedTheme.colors.buttonGradient,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            selectedTheme.colors.accentGlow.withOpacity(0.34),
                        blurRadius: 8,
                        offset: const Offset(2, 0),
                      ),
                    ],
                    border: Border.all(
                      color: Colors.white.withOpacity(0.14),
                      width: 0.4,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemePickerOverlay extends StatelessWidget {
  const _ThemePickerOverlay();

  @override
  Widget build(BuildContext context) {
    final isTurkish = Localizations.localeOf(context).languageCode == 'tr';
    return Consumer<ThemeProvider>(
      builder: (context, provider, _) {
        final current = provider.currentTheme;
        final size = MediaQuery.sizeOf(context);
        final compact = size.height < 720;
        final panelWidth = size.width < 460 ? size.width - 40 : 420.0;

        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: const SizedBox.expand(),
                ),
              ),
              Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    width: panelWidth,
                    padding: EdgeInsets.all(compact ? 14 : 16),
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        current.colors.background,
                        Colors.black,
                        0.12,
                      )!
                          .withOpacity(0.90),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: current.colors.accent.withOpacity(0.34),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: current.colors.accentGlow.withOpacity(0.18),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 30,
                              height: 4,
                              decoration: BoxDecoration(
                                color: current.colors.accent.withOpacity(0.70),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close,
                                  color: Colors.white70),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isTurkish ? 'Tema Sec' : 'Choose Theme',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final theme in provider.themes) ...[
                          _ThemeOptionTile(
                            theme: theme,
                            selected: current.id == theme.id,
                            unlocked: provider.canUnlockTheme(theme),
                            compact: compact,
                            onTap: provider.canUnlockTheme(theme)
                                ? () async {
                                    await provider.setTheme(theme.id);
                                    if (context.mounted) {
                                      Navigator.pop(context);
                                    }
                                  }
                                : null,
                          ),
                          if (theme != provider.themes.last)
                            SizedBox(height: compact ? 6 : 8),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ThemeOptionTile extends StatelessWidget {
  final AppThemeConfig theme;
  final bool selected;
  final bool unlocked;
  final bool compact;
  final VoidCallback? onTap;

  const _ThemeOptionTile({
    required this.theme,
    required this.selected,
    required this.unlocked,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: compact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: selected
              ? theme.colors.accent.withOpacity(0.14)
              : Colors.white.withOpacity(0.045),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? theme.colors.accent.withOpacity(0.62)
                : Colors.white.withOpacity(0.10),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: compact ? 28 : 32,
              height: compact ? 28 : 32,
              decoration: BoxDecoration(
                gradient: theme.colors.buttonGradient,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    theme.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 13 : 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    theme.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: compact ? 10 : 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : unlocked
                      ? Icons.circle_outlined
                      : Icons.lock_rounded,
              color: selected ? theme.colors.accent : Colors.white54,
              size: compact ? 18 : 20,
            ),
          ],
        ),
      ),
    );
  }
}
