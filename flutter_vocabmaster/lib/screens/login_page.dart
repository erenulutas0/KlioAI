import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../utils/app_colors.dart';
import '../utils/login_spacing.dart';
import '../widgets/raindrop.dart';
import '../widgets/floating_orb.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../services/analytics_service.dart';
import '../services/locale_text_service.dart';
import '../l10n/app_localizations.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback? onLoginSuccess;

  const LoginPage({super.key, this.onLoginSuccess});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowController;
  late final Animation<double> _glowAnimation;
  bool _isSigningIn = false;

  String _text(String tr, String en) => LocaleTextService.pick(tr, en);

  @override
  void initState() {
    super.initState();
    _glowController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.6).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleLogin() async {
    if (_isSigningIn) return;
    setState(() => _isSigningIn = true);

    final auth = AuthService();
    final result = await auth.googleLogin();

    if (!mounted) return;
    setState(() => _isSigningIn = false);

    if (result['success'] == true) {
      await AnalyticsService.logLoginCompleted(
        method: 'google',
        userId: _extractUserId(result),
      );

      if (!mounted) return;
      final user = result['user'];
      if (user is Map<String, dynamic>) {
        context.read<AppStateProvider>().setUser(user);
      } else if (user is Map) {
        context
            .read<AppStateProvider>()
            .setUser(Map<String, dynamic>.from(user));
      }

      if (widget.onLoginSuccess != null) {
        widget.onLoginSuccess!();
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      }
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result['message'] ?? context.tr('login.error.google')),
        backgroundColor: Colors.red,
      ),
    );
  }

  String? _extractUserId(Map<String, dynamic> result) {
    final user = result['user'];
    if (user is Map) {
      final id = user['id'] ?? user['userId'];
      if (id != null) return id.toString();
    }
    final id = result['userId'] ?? result['id'];
    return id?.toString();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: AppColors.backgroundGradient,
            ),
          ),
          ...List.generate(4, (_) => const FloatingOrb()),
          ...List.generate(
            28,
            (_) => RaindropWidget(
              screenWidth: size.width,
              screenHeight: size.height,
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: LoginSpacing.mainPaddingH,
                  vertical: LoginSpacing.mainPaddingV,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildLogoSection(),
                      const SizedBox(height: 28),
                      _buildGoogleCard(),
                      const SizedBox(height: 18),
                      _buildTrustLine(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _glowAnimation,
          builder: (context, child) {
            return Container(
              width: 80,
              height: 80,
              alignment: Alignment.center,
              child: Container(
                width: LoginSpacing.logoSize,
                height: LoginSpacing.logoSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.cyan400.withValues(alpha: 0.3),
                      AppColors.blue500.withValues(alpha: 0.3),
                    ],
                  ),
                  border: Border.all(
                    color: AppColors.cyan500.withValues(alpha: 0.3),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.cyan500
                          .withValues(alpha: _glowAnimation.value),
                      blurRadius: 30 * _glowAnimation.value + 10,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  size: LoginSpacing.logoIconSize,
                  color: AppColors.cyan400,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: LoginSpacing.logoMarginBottom),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [AppColors.cyan400, AppColors.blue400, AppColors.cyan400],
          ).createShader(bounds),
          child: const Text(
            'KlioAI',
            style: TextStyle(
              fontSize: LoginSpacing.titleFontSize,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: LoginSpacing.titleMarginBottom),
        Text(
          context.tr('login.subtitle'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: const Color(0xFF67E8F9).withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }

  Widget _buildGoogleCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppColors.slate900.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(18),
            border:
                Border.all(color: AppColors.cyan500.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                context.tr('login.social.google'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _text(
                  'Tek hesapla kelimelerin, aboneligin ve gunluk AI kotan senkron kalir.',
                  'Keep your words, subscription, and daily AI quota synced with one account.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.slate400,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _isSigningIn ? null : _handleGoogleLogin,
                  icon: _isSigningIn
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.g_mobiledata, size: 30),
                  label: Text(
                    _isSigningIn
                        ? _text(
                            'Google hesabi kontrol ediliyor',
                            'Checking Google account',
                          )
                        : context.tr('login.social.google'),
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: Colors.white70,
                    disabledForegroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrustLine() {
    return Text(
      _text(
        'KlioAI sadece Google Sign-In kullanir. Sifre saklamaz.',
        'KlioAI uses Google Sign-In only and never stores passwords.',
      ),
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: AppColors.slate400,
        fontSize: LoginSpacing.infoFontSize,
        height: 1.35,
      ),
    );
  }
}
