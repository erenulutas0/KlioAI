import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/app_tour_service.dart';
import '../providers/app_state_provider.dart';
import '../main.dart';
import '../frontend_newest/screens/nf_landing_page.dart';
import '../frontend_newest/screens/nf_onboarding_page.dart';
import '../frontend_newest/theme/nf_tokens.dart';

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
        // Same branch, same `pushReplacement`, new destinations: the tour and
        // the sign-in screen both come from the new frontend now.
        //
        // Neither page is wrapped in `NfThemeScope` here. Unlike the pages
        // `NfShell._pushNf` opens, these two run before any shell exists and so
        // install the scope themselves — wrapping again would only build a
        // second palette over an identical one.
        //
        // `nextPageBuilder` is what keeps the tour from falling back to the
        // legacy `LoginPage` when it finishes.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => shouldShowTour
                ? NfOnboardingPage(
                    nextPageBuilder: (_) => const NfLandingPage(),
                  )
                : const NfLandingPage(),
          ),
        );
      }
    }
  }

  /// The splash paints in the new frontend's brand violet, taken from the light
  /// palette rather than resolved from the device: this screen takes over from
  /// the Android launch drawable, whose `@color/splash_background` is that one
  /// value in both light and dark, and any difference between the two shows up
  /// as a flash of colour on every cold start.
  static const NfTokens _tokens = NfTokens.light;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // White mark on violet, so the system icons have to be light too.
      value: SystemUiOverlayStyle(
        statusBarColor: NfTokens.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: _tokens.primary,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _tokens.primary,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // Same flat mark and same size as the native splash, so the
              // handover is invisible: the K does not move, resize or change
              // colour when Flutter takes the first frame. It is also the mark
              // `NfLandingPage` opens with, so the next screen keeps it too.
              const Image(
                image: AssetImage('assets/images/flat_k_white.png'),
                width: 128,
                height: 128,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: _tokens.primaryInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
