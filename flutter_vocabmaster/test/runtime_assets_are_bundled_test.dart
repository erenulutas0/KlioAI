import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every asset the app loads at runtime has to be declared under `flutter:
/// assets:` in `pubspec.yaml`, or it is simply not in the APK.
///
/// This exists because a file can be present on disk, referenced correctly in
/// Dart, and still be missing from the bundle. `flutter analyze` passes,
/// `flutter build` passes, and the failure only appears as a broken image on a
/// real device. It happened with `flat_k_white.png`: the file was added as an
/// input to `flutter_launcher_icons`, which reads it at build time, and then
/// the splash screen drew it at runtime from a bundle it was never added to.
void main() {
  test('every asset referenced from lib/ is declared in pubspec.yaml', () {
    final Set<String> declared = _declaredAssets();
    final Map<String, String> referenced = _referencedAssets();

    final List<String> undeclared = <String>[];
    final List<String> missingOnDisk = <String>[];

    referenced.forEach((String path, String sourceFile) {
      if (!_isDeclared(path, declared)) {
        undeclared.add('$path (referenced from $sourceFile)');
      }
      if (!File(path).existsSync()) {
        missingOnDisk.add('$path (referenced from $sourceFile)');
      }
    });

    expect(
      undeclared,
      isEmpty,
      reason: 'These assets are loaded at runtime but are not listed under '
          '"flutter: assets:" in pubspec.yaml, so they will not be in the '
          'build and will fail on device:\n  ${undeclared.join('\n  ')}',
    );
    expect(
      missingOnDisk,
      isEmpty,
      reason: 'These asset paths do not exist:\n  '
          '${missingOnDisk.join('\n  ')}',
    );
  });

  test('the scanner actually finds references', () {
    // Without this the suite would pass just as happily if the regex stopped
    // matching, which is the one failure mode a guard like this cannot report
    // on its own.
    expect(_referencedAssets(), isNotEmpty);
  });
}

/// Paths listed under `flutter: assets:`. Entries ending in `/` are directory
/// declarations, which cover every file directly inside them.
Set<String> _declaredAssets() {
  final List<String> lines = File('pubspec.yaml').readAsLinesSync();
  final Set<String> declared = <String>{};

  bool inAssets = false;
  for (final String line in lines) {
    final String trimmed = line.trim();
    if (trimmed.startsWith('#') || trimmed.isEmpty) {
      continue;
    }
    if (trimmed == 'assets:') {
      inAssets = true;
      continue;
    }
    if (!inAssets) {
      continue;
    }
    if (trimmed.startsWith('- ')) {
      declared.add(trimmed.substring(2).trim());
      continue;
    }
    // Any other key at this indentation ends the list.
    inAssets = false;
  }
  return declared;
}

bool _isDeclared(String path, Set<String> declared) {
  if (declared.contains(path)) {
    return true;
  }
  final int lastSlash = path.lastIndexOf('/');
  if (lastSlash < 0) {
    return false;
  }
  return declared.contains(path.substring(0, lastSlash + 1));
}

/// Asset paths passed to `Image.asset` / `AssetImage` anywhere under `lib/`,
/// mapped to the file that references them.
Map<String, String> _referencedAssets() {
  final RegExp pattern = RegExp(
    r'''(?:Image\.asset|AssetImage)\(\s*(['"])([^'"]+)\1''',
  );
  final Map<String, String> found = <String, String>{};

  for (final FileSystemEntity entity
      in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    for (final RegExpMatch match
        in pattern.allMatches(entity.readAsStringSync())) {
      final String path = match.group(2)!;
      if (path.startsWith('assets/')) {
        found.putIfAbsent(path, () => entity.path.replaceAll(r'\', '/'));
      }
    }
  }
  return found;
}
