import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/app_tour_service.dart';
import '../providers/app_state_provider.dart';
import '../main.dart';
import 'landing_page.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // Holds the mark on screen long enough to be read rather than flashed.
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final authService = AuthService();
    final isLoggedIn = await authService.isLoggedIn();

    if (isLoggedIn) {
      // Loaded here so the first frame of the app already has a user.
      final user = await authService.getUser();
      if (user != null && mounted) {
        Provider.of<AppStateProvider>(context, listen: false).setUser(user);
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      }
    } else {
      final shouldShowTour = !await AppTourService().isCompleted();
      if (!mounted) return;
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                shouldShowTour ? const OnboardingScreen() : const LandingPage(),
          ),
        );
      }
    }
  }

  /// Brand violet — the same value as `@color/splash_background` in
  /// `android/app/src/main/res/values/colors.xml`. This screen takes over from
  /// the Android launch drawable, so any difference between the two shows up as
  /// a flash of colour on every cold start.
  static const Color _brandViolet = Color(0xFF6C4EF5);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: _brandViolet,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // Same flat mark and same size as the native splash, so the
            // handover is invisible: the K does not move, resize or change
            // colour when Flutter takes the first frame.
            Image(
              image: AssetImage('assets/images/flat_k_white.png'),
              width: 128,
              height: 128,
              fit: BoxFit.contain,
            ),
            SizedBox(height: 40),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
