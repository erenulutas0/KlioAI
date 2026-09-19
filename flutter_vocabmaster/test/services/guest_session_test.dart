import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/services/auth_service.dart';

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
