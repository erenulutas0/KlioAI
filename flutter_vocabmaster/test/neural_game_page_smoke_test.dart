import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vocabmaster/screens/neural_game_page.dart';
import 'package:vocabmaster/widgets/neural/neural_word_node.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('NeuralGamePage supports menu -> play -> menu flow',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        supportedLocales: [Locale('en'), Locale('tr')],
        home: NeuralGamePage(),
      ),
    );

    expect(find.text('Neural Network'), findsOneWidget);
    expect(find.text('Start Game'), findsOneWidget);

    await tester.ensureVisible(find.text('Start Game'));
    await tester.tap(find.text('Start Game'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Type a related word'), findsOneWidget);
    expect(find.text('Menu'), findsOneWidget);

    await tester.tap(find.text('Menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Neural Network'), findsOneWidget);
  });

  testWidgets('Neural word nodes stay inside compact phone viewport',
      (tester) async {
    await _pumpGameAndCreateNodes(tester, const Size(320, 568));
    _expectWordNodesInsideViewport(tester, const Size(320, 568));
  });

  testWidgets('Neural word nodes stay inside tall phone viewport',
      (tester) async {
    await _pumpGameAndCreateNodes(tester, const Size(430, 932));
    _expectWordNodesInsideViewport(tester, const Size(430, 932));
  });
}

Future<void> _pumpGameAndCreateNodes(WidgetTester tester, Size viewport) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    const MaterialApp(
      locale: Locale('en'),
      supportedLocales: [Locale('en'), Locale('tr')],
      home: NeuralGamePage(),
    ),
  );

  await tester.ensureVisible(find.text('Start Game'));
  await tester.tap(find.text('Start Game'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));

  for (var i = 0; i < 6; i++) {
    final suggestion = find.byType(ActionChip).first;
    expect(suggestion, findsOneWidget);
    await tester.tap(suggestion);
    await tester.pump(const Duration(milliseconds: 120));
  }

  await tester.pump(const Duration(milliseconds: 1500));
}

void _expectWordNodesInsideViewport(WidgetTester tester, Size viewport) {
  final nodes = find.byType(NeuralWordNode);
  expect(nodes, findsWidgets);

  for (final element in nodes.evaluate()) {
    final rect = tester.getRect(find.byElementPredicate((candidate) {
      return identical(candidate, element);
    }));

    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(viewport.width));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(viewport.height));
  }
}
