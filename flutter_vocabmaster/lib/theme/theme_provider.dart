import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';
import 'theme_catalog.dart';

class ThemeProvider extends ChangeNotifier {
  // Test/dogfooding phase: keep all themes selectable regardless of XP/subscription.
  static const bool _unlockAllThemesForNow = true;
  static const String _selectedThemeKey = 'selected_theme_id';

  AppThemeConfig _currentTheme = VocabThemes.defaultTheme;
  int _userXP = 0;
  bool _hasPremiumAccess = false;
  bool _isTransitioning = false;
  SharedPreferences? _prefs;

  AppThemeConfig get currentTheme => _currentTheme;
  int get userXP => _userXP;
  bool get hasPremiumAccess => _hasPremiumAccess;
  bool get isTransitioning => _isTransitioning;
  List<AppThemeConfig> get themes => VocabThemes.all;

  Future<void> initialize({
    int initialXP = 0,
    bool initialPremiumAccess = false,
  }) async {
    _prefs = await SharedPreferences.getInstance();
    _userXP = initialXP;
    _hasPremiumAccess = initialPremiumAccess;
    final savedId = _prefs?.getString(_selectedThemeKey);
    final candidate = VocabThemes.byId(savedId);
    if (_isThemeUnlocked(candidate)) {
      _currentTheme = candidate;
    }
    notifyListeners();
  }

  void updateUserXP(int newXP, {bool notify = true}) {
    if (newXP < 0) {
      newXP = 0;
    }
    if (_userXP == newXP) {
      return;
    }
    _userXP = newXP;
    if (!_isThemeUnlocked(_currentTheme)) {
      _currentTheme = VocabThemes.defaultTheme;
    }
    if (notify) {
      notifyListeners();
    }
  }

  void updatePremiumAccess(bool hasPremiumAccess, {bool notify = true}) {
    if (_hasPremiumAccess == hasPremiumAccess) {
      return;
    }
    _hasPremiumAccess = hasPremiumAccess;
    if (!_isThemeUnlocked(_currentTheme)) {
      _currentTheme = VocabThemes.defaultTheme;
    }
    if (notify) {
      notifyListeners();
    }
  }

  bool _isThemeUnlocked(AppThemeConfig theme) {
    if (_unlockAllThemesForNow) {
      return true;
    }
    return !theme.isPremium || _hasPremiumAccess || _userXP >= theme.xpRequired;
  }

  bool canUnlockTheme(AppThemeConfig theme) {
    return _isThemeUnlocked(theme);
  }

  int remainingXPForTheme(AppThemeConfig theme) {
    if (_unlockAllThemesForNow) {
      return 0;
    }
    if (!theme.isPremium || _hasPremiumAccess) {
      return 0;
    }
    final remaining = theme.xpRequired - _userXP;
    return remaining > 0 ? remaining : 0;
  }

  double unlockProgress(AppThemeConfig theme) {
    if (_unlockAllThemesForNow) {
      return 1.0;
    }
    if (!theme.isPremium || _hasPremiumAccess || theme.xpRequired <= 0) {
      return 1.0;
    }
    final value = _userXP / theme.xpRequired;
    if (value < 0.0) {
      return 0.0;
    }
    if (value > 1.0) {
      return 1.0;
    }
    return value;
  }

  Future<bool> setTheme(String themeId) async {
    final nextTheme = VocabThemes.byId(themeId);
    if (!canUnlockTheme(nextTheme)) {
      return false;
    }
    if (_currentTheme.id == nextTheme.id) {
      return true;
    }

    _isTransitioning = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    _currentTheme = nextTheme;
    await _prefs?.setString(_selectedThemeKey, nextTheme.id);
    notifyListeners();

    await Future<void>.delayed(
      Duration(milliseconds: nextTheme.animations.transitionDurationMs),
    );
    _isTransitioning = false;
    notifyListeners();
    return true;
  }
}
