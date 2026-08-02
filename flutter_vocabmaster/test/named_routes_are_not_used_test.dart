import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// This app has no route table, so any named-route call is a crash.
///
/// `MaterialApp` in `lib/main.dart` is configured with `home:` alone — no `routes:`, no
/// `onGenerateRoute:`. Every screen is reached by pushing a `MaterialPageRoute` directly.
/// That is a perfectly good way to build a Flutter app, but it means
/// `Navigator.pushNamed('/anything')` cannot ever work: it throws "Could not find a
/// generator for route" the moment it runs.
///
/// One had been sitting in the stats side menu, on the Review entry, next to five siblings
/// that all pushed `MaterialPageRoute` correctly. Nothing catches this — it compiles, the
/// analyzer is happy, and the string looks exactly like working code. It only fails when
/// somebody taps it.
///
/// So the guard is a grep. If a route table is ever added, delete this test; until then, a
/// named-route call is a bug by construction.

void main() {
  test('no named-route navigation, because there is no route table', () {
    final offenders = <String>[];
    final pattern = RegExp(
        r'\b(pushNamed|pushReplacementNamed|popAndPushNamed|pushNamedAndRemoveUntil)\s*\(');

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Skip comments — this file's own fix is documented in one.
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
        if (pattern.hasMatch(line)) {
          offenders.add('${entity.path}:${i + 1}: ${trimmed.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Named routes throw at runtime here — MaterialApp has no routes: or '
          'onGenerateRoute:. Push a MaterialPageRoute instead, or add a route table '
          'and delete this test.\n${offenders.join('\n')}',
    );
  });
}
