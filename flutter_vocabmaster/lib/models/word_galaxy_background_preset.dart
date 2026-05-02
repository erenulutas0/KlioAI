import 'package:flutter/material.dart';

enum WordGalaxyBackgroundPreset {
  galaxy,
  blackHole,
  milkyWay,
}

extension WordGalaxyBackgroundPresetX on WordGalaxyBackgroundPreset {
  String get storageValue => switch (this) {
        WordGalaxyBackgroundPreset.galaxy => 'galaxy',
        WordGalaxyBackgroundPreset.blackHole => 'black_hole',
        WordGalaxyBackgroundPreset.milkyWay => 'milky_way',
      };

  String label({required bool isTurkish}) => switch (this) {
        WordGalaxyBackgroundPreset.galaxy => isTurkish ? 'Galaksi' : 'Galaxy',
        WordGalaxyBackgroundPreset.blackHole =>
          isTurkish ? 'Kara Delik' : 'Black Hole',
        WordGalaxyBackgroundPreset.milkyWay =>
          isTurkish ? 'Samanyolu' : 'Milky Way',
      };

  List<Color> get gradientColors => switch (this) {
        WordGalaxyBackgroundPreset.galaxy => const [
            Color(0xFF08131A),
            Color(0xFF10343A),
            Color(0xFF4A1D2F),
          ],
        WordGalaxyBackgroundPreset.blackHole => const [
            Color(0xFF090909),
            Color(0xFF2A140B),
            Color(0xFF4B1016),
          ],
        WordGalaxyBackgroundPreset.milkyWay => const [
            Color(0xFF09141B),
            Color(0xFF1A4037),
            Color(0xFF6C5D2A),
          ],
      };

  Color get accentColor => switch (this) {
        WordGalaxyBackgroundPreset.galaxy => const Color(0xFF67E8F9),
        WordGalaxyBackgroundPreset.blackHole => const Color(0xFFF59E0B),
        WordGalaxyBackgroundPreset.milkyWay => const Color(0xFFA7F3D0),
      };

  Color get highlightColor => switch (this) {
        WordGalaxyBackgroundPreset.galaxy => const Color(0xFFFF7A59),
        WordGalaxyBackgroundPreset.blackHole => const Color(0xFFFB7185),
        WordGalaxyBackgroundPreset.milkyWay => const Color(0xFFFDE68A),
      };

  static WordGalaxyBackgroundPreset fromStorageValue(String? value) {
    for (final preset in WordGalaxyBackgroundPreset.values) {
      if (preset.storageValue == value) {
        return preset;
      }
    }
    return WordGalaxyBackgroundPreset.galaxy;
  }
}
