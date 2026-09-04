import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/models/voice_model.dart';

/// The tutor voices must not wear a real person's face.
///
/// Six Unsplash photographs shipped as Amy, Ryan, Emma, Alan, Jenny and Cori,
/// and six more decorated a practice card. The Unsplash licence covers
/// commercial use of an image and explicitly does not grant model rights;
/// putting a recognisable person forward as a product's persona is the case it
/// excludes. Nobody in those photographs agreed to front an English tutor.
///
/// It was also a third-party request on the tutor screen — every open told
/// images.unsplash.com that a user existed — and a network dependency on a
/// screen that has to work on a bad connection.
///
/// A source-level check because the failure is a URL string, and a URL string
/// is exactly the kind of thing that gets pasted back in.
void main() {
  test('no source file fetches a stock photograph of a person', () {
    final List<String> offenders = <String>[];

    for (final FileSystemEntity entity
        in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final List<String> lines = entity.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i];
        // The doc comment explaining why they went is allowed to name it.
        if (line.trimLeft().startsWith('///') ||
            line.trimLeft().startsWith('//')) {
          continue;
        }
        for (final String host in <String>[
          'images.unsplash.com',
          'images.pexels.com',
          'i.pravatar.cc',
          'randomuser.me',
        ]) {
          if (line.contains(host)) {
            offenders.add('  ${entity.path}:${i + 1}  $host');
          }
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'These fetch a photograph of a real person to stand in for '
            'part of the product:\n${offenders.join('\n')}');
  });

  test('no built-in voice carries an avatar URL', () {
    for (final VoiceModel voice in VoiceModel.availableVoices) {
      expect(voice.avatarUrl, isEmpty,
          reason: '${voice.name} would be drawn from the network');
    }
  });

  test('a stored selection still round-trips', () {
    // The field stays on the model so an old saved choice is readable; it is
    // simply never populated for the built-ins.
    const VoiceModel stored = VoiceModel(
      id: 'amy',
      name: 'Amy',
      gender: 'female',
      accent: 'American',
      locale: 'en_US',
      piperVoice: 'amy',
      sampleText: 'Hi!',
    );

    final VoiceModel back = VoiceModel.fromJsonString(stored.toJsonString());

    expect(back.id, 'amy');
    expect(back.piperVoice, 'amy');
    expect(back.avatarUrl, isEmpty);
  });
}
