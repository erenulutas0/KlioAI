import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vocabmaster/screens/neural_game_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('NeuralGamePage supports menu -> play -> menu flow',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NeuralGamePage(),
      ),
    );

    expect(find.text('Neural Word Network'), findsOneWidget);
    expect(find.text('Oyunu Baslat'), findsOneWidget);

    await tester.ensureVisible(find.text('Oyunu Baslat'));
    await tester.tap(find.text('Oyunu Baslat'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Type a related word'), findsOneWidget);
    expect(find.text('Menu'), findsOneWidget);

    await tester.tap(find.text('Menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Neural Word Network'), findsOneWidget);
  });
}
