import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How often a learner may be asked "how was this?", across every place that asks.
///
/// The question now comes from two places -- the tutor after a conversation, and the sheet
/// after reading, writing or a daily session -- and a learner who does all of those in one
/// evening must not be asked four times. So there is one clock for all of them and one per
/// feature, and a learner who keeps closing the question is taken at their word.
class RatingPromptService {
  RatingPromptService({DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final DateTime Function() _now;

  /// No two questions closer together than this, whatever they are about.
  static const Duration minBetweenAnyTwo = Duration(hours: 20);

  /// The same feature is asked about again only after this long: time enough for the next
  /// conversation to be a different one.
  static const Duration minBetweenSameFeature = Duration(days: 3);

  /// Closing the question this many times without answering means "stop asking".
  static const int dismissalsBeforeSilence = 3;

  static const String lastAnyKey = 'rating_prompt:last_asked_any';
  static const String dismissalsKey = 'rating_prompt:dismissals';
  static const String optedOutKey = 'rating_prompt:opted_out';
  static String lastFeatureKey(String feature) => 'rating_prompt:last_asked:$feature';

  Future<bool> shouldAsk(String feature) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(optedOutKey) ?? false) {
        return false;
      }
      if ((prefs.getInt(dismissalsKey) ?? 0) >= dismissalsBeforeSilence) {
        return false;
      }
      final DateTime now = _now();
      if (_within(prefs.getString(lastAnyKey), minBetweenAnyTwo, now)) {
        return false;
      }
      return !_within(prefs.getString(lastFeatureKey(feature)), minBetweenSameFeature, now);
    } catch (e) {
      // Bookkeeping must never put a question in front of someone by failing open.
      debugPrint('Rating prompt check skipped: $e');
      return false;
    }
  }

  /// Called when the question is shown, not when it is answered: a question scrolled past
  /// has still been asked, and asking it again tomorrow is nagging.
  Future<void> recordAsked(String feature) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String stamp = _now().toIso8601String();
      await prefs.setString(lastAnyKey, stamp);
      await prefs.setString(lastFeatureKey(feature), stamp);
    } catch (e) {
      debugPrint('Rating prompt not recorded: $e');
    }
  }

  Future<void> recordDismissed() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(dismissalsKey, (prefs.getInt(dismissalsKey) ?? 0) + 1);
    } catch (e) {
      debugPrint('Rating dismissal not recorded: $e');
    }
  }

  /// "Don't ask me again", said anywhere, is said everywhere: a learner who asked the reading
  /// sheet to stop would not expect the tutor to start.
  Future<void> recordOptedOut() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(optedOutKey, true);
    } catch (e) {
      debugPrint('Rating opt-out not recorded: $e');
    }
  }

  /// An answer resets the count: somebody who rated once is not someone who wants silence.
  Future<void> recordAnswered() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(dismissalsKey, 0);
    } catch (e) {
      debugPrint('Rating answer not recorded: $e');
    }
  }

  static bool _within(String? stamp, Duration window, DateTime now) {
    if (stamp == null) {
      return false;
    }
    final DateTime? at = DateTime.tryParse(stamp);
    return at != null && now.difference(at) < window;
  }
}

/// A low rating asks what went wrong: the number says something is, the note says what.
bool nfRatingWantsNote(int stars) => stars <= 3;

/// Only a learner who gave five stars is shown the store's rating sheet.
bool nfRatingEarnsStoreReview(int stars) => stars >= 5;

/// "1.4.1+484", or null when the platform cannot say.
Future<String?> nfAppVersion() async {
  try {
    final PackageInfo info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  } catch (_) {
    return null;
  }
}
