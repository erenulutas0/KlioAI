import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/services/auth_service.dart';
import 'package:vocabmaster/services/learning_language_service.dart';

/// The account a learner never asked for.
///
/// The app opens one on first launch so the first conversation can happen before
/// anything is asked of anyone (see NfGuestGate). Everything downstream treats it
/// as an ordinary session, and the only thing that must stay true is that the app
/// knows which kind it is holding: that flag decides whether the sign-in offer is
/// made, whether the paywall lets a purchase start, and whether Google sign-in
/// carries the token that converts this account instead of opening a second one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const Map<String, dynamic> user = <String, dynamic>{
    'id': 42,
    'email': 'guest-abc@guest.klioai.app',
    'displayName': 'Guest',
    'userTag': '#00042',
    'role': 'USER',
  };

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    await AuthService().logout();
  });

  test('a guest session is remembered as one', () async {
    await AuthService().saveSession('access', 'refresh', user, guest: true);

    expect(await AuthService().isGuestSession(), isTrue);
  });

  test('signing in over it stops it being one', () async {
    await AuthService().saveSession('access', 'refresh', user, guest: true);
    await AuthService().saveSession('access2', 'refresh2', user);

    expect(await AuthService().isGuestSession(), isFalse,
        reason: 'the sign-in offer would keep coming back after they took it');
  });

  test('a guest account starts with nothing on the phone', () async {
    // Found on a real reinstall: the first guest account opened onto the
    // previous account's conversations with Amy and its word list. Android had
    // restored the preferences and the database from its own backup while the
    // encrypted store holding the old user id was not restored, so the
    // id-mismatch check above had nothing to compare and cleared nothing.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'nf_tutor_sessions_v1': '[{"id":"1"}]',
      'total_xp_persistent': 1206,
      'current_streak': 5,
      'daily_words_cache': 'yesterday',
    });
    FlutterSecureStorage.setMockInitialValues(<String, String>{});

    await AuthService().saveSession('access', 'refresh', user, guest: true);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('nf_tutor_sessions_v1'), isNull,
        reason: "a brand-new account opened on somebody else's conversations");
    expect(prefs.getInt('total_xp_persistent'), isNull);
    expect(prefs.getInt('current_streak'), isNull);
    expect(prefs.getString('daily_words_cache'), isNull);
  });

  test("a guest does not inherit the last account's answers", () async {
    // Found on the phone, on a Turkish interface: the settings page read "Ana dil:
    // Ingilizce" for a guest account opened minutes earlier, and the tutor explained
    // that learner's mistakes to them in English. The answer belonged to the account
    // before it; nothing cleared it, and the app sends it with every AI request.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'learning_source_language': 'English',
      'learning_english_level': 'C1',
      'learning_goal': 'Exam',
    });
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    LearningLanguageService.setSourceLanguage('English');

    await AuthService().saveSession('access', 'refresh', user, guest: true);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('learning_source_language'), isNull);
    expect(prefs.getString('learning_english_level'), isNull);
    expect(prefs.getString('learning_goal'), isNull);
    expect(LearningLanguageService.currentProfile().containsKey('sourceLanguage'),
        isFalse,
        reason: "a guess is not an answer, and this one was somebody else's");
  });

  test('signing in as somebody else takes the conversations too', () async {
    await AuthService().saveSession('access', 'refresh', user);
    final SharedPreferences seeded = await SharedPreferences.getInstance();
    await seeded.setString('nf_tutor_sessions_v1', '[{"id":"1"}]');

    await AuthService().saveSession('access2', 'refresh2', <String, dynamic>{
      'id': 99,
      'email': 'someone.else@example.com',
      'displayName': 'Someone Else',
      'userTag': '#00099',
      'role': 'USER',
    });

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('nf_tutor_sessions_v1'), isNull);
  });

  test('a session that is not there is not a guest session', () async {
    await AuthService().saveSession('access', 'refresh', user, guest: true);
    await AuthService().logout();

    expect(await AuthService().isGuestSession(), isFalse);
  });

  test('the flag alone is not enough, the tokens have to be there too', () async {
    // What a half-cleared install looks like: the preference survived, the
    // secure storage did not. Reading it as a guest session would offer to save
    // progress for an account the app cannot reach.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'session_is_guest': true,
    });
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    await AuthService().logout();

    expect(await AuthService().isGuestSession(), isFalse);
  });
}
