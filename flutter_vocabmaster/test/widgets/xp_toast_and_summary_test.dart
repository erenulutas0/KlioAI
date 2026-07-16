import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/providers/app_state_provider.dart';
import 'package:vocabmaster/services/xp_manager.dart';
import 'package:vocabmaster/widgets/session_summary_sheet.dart';
import 'package:vocabmaster/widgets/xp_toast_host.dart';
import '../test_helper.dart';

void main() {
  setUpAll(() {
    setupTestEnv();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    XPManager.resetIdempotency();
  });

  Widget wrap(Widget child, AppStateProvider appState) {
    return ChangeNotifierProvider<AppStateProvider>.value(
      value: appState,
      child: MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: child,
      ),
    );
  }

  testWidgets('XpToastHost shows +XP chip when an XP gain event fires',
      (tester) async {
    final appState = AppStateProvider();
    await tester.pumpWidget(
      wrap(
        XpToastHost(child: const Scaffold(body: SizedBox.expand())),
        appState,
      ),
    );
    // AppLocalizations.delegate.load bir async Future döndürüyor; ağaç ancak
    // bir sonraki pump'ta gerçekten kurulur.
    await tester.pump();

    // No gain yet: chip exists but fully transparent (animates in/out).
    AnimatedOpacity opacity =
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(opacity.opacity, 0.0);

    // XPManager gerçek I/O yapar (sqflite/prefs); widget testinin fake-async
    // bölgesinde doğrudan await etmek deadlock/timeout üretir - runAsync
    // gerçek async bölgesinde çalıştırır.
    await tester.runAsync(() async {
      await appState.addXPForAction(XPActionTypes.reviewComplete,
          source: 'toast-test');
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.textContaining('XP'), findsOneWidget);
    opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(opacity.opacity, 1.0);

    // Auto-hides after its display window. Gizleme Timer'ı runAsync'in gerçek
    // async bölgesinde kurulduğu için fake-time pump'larıyla TETİKLENMEZ -
    // gerçek zamanda bekleyip sonra frame bastırıyoruz.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1700)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    opacity = tester.widget<AnimatedOpacity>(
      find.byType(AnimatedOpacity),
    );
    expect(opacity.opacity, 0.0);
  });

  testWidgets('SessionSummarySheet renders stats and closes on CTA',
      (tester) async {
    final appState = AppStateProvider();
    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                key: const ValueKey('open-sheet'),
                onPressed: () => SessionSummarySheet.show(
                  context,
                  xpEarned: 35,
                  itemsCompleted: 7,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        appState,
      ),
    );
    // Localizations yüklenmeden ağaç boş kalır (async delegate.load).
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('open-sheet')));
    await tester.pumpAndSettle();

    expect(find.text('Session complete!'), findsOneWidget);
    expect(find.text('+35'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);

    await tester.tap(find.text('Keep going'));
    await tester.pumpAndSettle();
    expect(find.text('Session complete!'), findsNothing);
  });
}
