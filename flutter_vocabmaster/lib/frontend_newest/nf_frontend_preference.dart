import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which of the two frontends is on screen, and — while the new one is — which
/// palette it draws itself in.
///
/// Both frontends ship in the same build, so the switch has to survive a
/// restart. That is all this class is: two values in [SharedPreferences],
/// following the same shape as `ThemeProvider` and `LanguageProvider` — an
/// awaited [initialize] before `runApp`, then setters that update memory,
/// notify, and persist afterwards.
///
/// Nothing here defaults anybody into the preview. [useNewFrontend] starts
/// false and only a deliberate tap in Settings changes it.
class NfFrontendPreference extends ChangeNotifier {
  /// `nf_` prefixed so these cannot collide with anything the current frontend
  /// already stores.
  static const String _enabledKey = 'nf_frontend_enabled';

  /// Absent means "no explicit choice yet" — see [darkOverride].
  static const String _darkKey = 'nf_frontend_dark';

  bool _useNewFrontend = false;
  bool? _darkOverride;
  bool _initialized = false;

  /// True when the new frontend should be shown instead of `MainScreen`.
  bool get useNewFrontend => _useNewFrontend;

  /// The learner's explicit palette choice, or null while they have not made
  /// one. Null is not the same as "light": it means follow the device, which is
  /// the only setting that cannot surprise a first-time viewer.
  bool? get darkOverride => _darkOverride;

  /// True once [initialize] has run. Callers may read the getters before then;
  /// they will simply see the defaults.
  bool get initialized => _initialized;

  /// The palette to draw in, given what the device is currently asking for.
  Brightness brightnessFor(Brightness platformBrightness) {
    final bool? override = _darkOverride;
    if (override == null) {
      return platformBrightness;
    }
    return override ? Brightness.dark : Brightness.light;
  }

  /// Reads both values. Safe to call more than once.
  Future<void> initialize() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _useNewFrontend = prefs.getBool(_enabledKey) ?? false;
      _darkOverride = prefs.getBool(_darkKey);
    } catch (error) {
      // An unreadable store must not stop the app from starting; the defaults
      // are the current frontend and the device palette, which is where an
      // untouched install sits anyway.
      debugPrint('NfFrontendPreference.initialize failed: $error');
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> setUseNewFrontend(bool value) async {
    if (_useNewFrontend == value) {
      return;
    }
    _useNewFrontend = value;
    notifyListeners();
    await _writeBool(_enabledKey, value);
  }

  Future<void> toggleFrontend() => setUseNewFrontend(!_useNewFrontend);

  /// Records an explicit palette choice. Passing null hands the decision back
  /// to the device.
  Future<void> setDarkOverride(bool? value) async {
    if (_darkOverride == value) {
      return;
    }
    _darkOverride = value;
    notifyListeners();
    await _writeNullableBool(_darkKey, value);
  }

  /// Flips away from whatever is on screen right now.
  ///
  /// Takes the current brightness rather than reading [darkOverride] because
  /// the first tap has to move away from the *device* palette, not from an
  /// assumed default the learner never saw.
  Future<void> toggleBrightness(Brightness current) =>
      setDarkOverride(current != Brightness.dark);

  Future<void> _writeBool(String key, bool value) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (error) {
      // The switch already flipped on screen; losing the note costs one tap
      // after the next restart, never a crash.
      debugPrint('NfFrontendPreference could not persist $key: $error');
    }
  }

  Future<void> _writeNullableBool(String key, bool? value) async {
    if (value == null) {
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.remove(key);
      } catch (error) {
        debugPrint('NfFrontendPreference could not clear $key: $error');
      }
      return;
    }
    await _writeBool(key, value);
  }
}
