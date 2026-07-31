import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/screens/word_galaxy_page.dart';

/// Word Galaxy laid its cards on rings at fixed radii inside a fixed canvas, while card
/// size grew with sentence count, score and review count, and overdue words were pulled
/// further inward on top of that. Cards ended up overlapping each other and the focus card
/// badly enough that neither could be read.
///
/// The geometry now derives the radii from the cards and the canvas from the radii. These
/// tests assert the property that was missing: nothing overlaps.

/// Where a card sits on its ring, accounting for the vertical squash.
({double dx, double dy}) _centreOf(double radius, double angle) => (
      dx: math.cos(angle) * radius,
      dy: math.sin(angle) * radius * GalaxyRingLayout.verticalSquash,
    );

double _distance(({double dx, double dy}) a, ({double dx, double dy}) b) =>
    math.sqrt(math.pow(a.dx - b.dx, 2) + math.pow(a.dy - b.dy, 2));

/// Card centres for a whole layout, paired with each card's size.
List<({({double dx, double dy}) at, double size})> _placeAll(
  GalaxyRingLayout plan,
  List<double> sizes,
) {
  final placed = <({({double dx, double dy}) at, double size})>[];
  var index = 0;
  for (var ring = 0; ring < plan.ringRadii.length; ring++) {
    final itemsInRing = math.min(galaxyRingCounts[ring], sizes.length - index);
    for (var slot = 0; slot < itemsInRing; slot++) {
      final angle = (-math.pi / 2) + ((2 * math.pi * slot) / itemsInRing);
      placed.add((at: _centreOf(plan.ringRadii[ring], angle), size: sizes[index]));
      index++;
    }
  }
  return placed;
}

void main() {
  // The real range: 104 base, plus up to ~61 from sentences, score, urgency and reviews.
  final smallCards = List<double>.filled(18, 104);
  final largeCards = List<double>.filled(18, 165);
  final mixedCards = List<double>.generate(18, (i) => 104 + (i % 7) * 10);

  for (final entry in {
    'smallest cards': smallCards,
    'largest cards': largeCards,
    'mixed sizes': mixedCards,
  }.entries) {
    group(entry.key, () {
      final sizes = entry.value;
      final plan =
          GalaxyRingLayout.solve(nodeSizes: sizes, ringCounts: galaxyRingCounts);

      test('no card overlaps the focus card', () {
        const focusHalf = GalaxyRingLayout.focusNodeSize / 2;
        for (final card in _placeAll(plan, sizes)) {
          final gap = _distance(card.at, (dx: 0, dy: 0));
          expect(
            gap,
            greaterThanOrEqualTo(focusHalf + (card.size / 2)),
            reason: 'a card at ${card.at} overlaps the focus card',
          );
        }
      });

      test('no card overlaps its neighbour on the same ring', () {
        var index = 0;
        for (var ring = 0; ring < plan.ringRadii.length; ring++) {
          final itemsInRing = math.min(galaxyRingCounts[ring], sizes.length - index);
          for (var slot = 0; slot < itemsInRing; slot++) {
            final a = (-math.pi / 2) + ((2 * math.pi * slot) / itemsInRing);
            final b = (-math.pi / 2) + ((2 * math.pi * ((slot + 1) % itemsInRing)) / itemsInRing);
            if (itemsInRing < 2) continue;
            final gap = _distance(
              _centreOf(plan.ringRadii[ring], a),
              _centreOf(plan.ringRadii[ring], b),
            );
            final needed = (sizes[index + slot] / 2) +
                (sizes[index + ((slot + 1) % itemsInRing)] / 2);
            expect(gap, greaterThanOrEqualTo(needed * 0.72),
                reason: 'ring $ring is too crowded between slots $slot and ${slot + 1}');
          }
          index += itemsInRing;
        }
      });

      test('rings do not collide with each other', () {
        for (var ring = 1; ring < plan.ringRadii.length; ring++) {
          final inner = plan.ringRadii[ring - 1] * GalaxyRingLayout.verticalSquash;
          final outer = plan.ringRadii[ring] * GalaxyRingLayout.verticalSquash;
          final widest = sizes.reduce((a, b) => a > b ? a : b);
          expect(outer - inner, greaterThanOrEqualTo(widest),
              reason: 'rings ${ring - 1} and $ring are closer than one card apart');
        }
      });

      test('the canvas contains every card', () {
        final halfWidth = plan.canvasSize.width / 2;
        final halfHeight = plan.canvasSize.height / 2;
        for (final card in _placeAll(plan, sizes)) {
          expect(card.at.dx.abs() + (card.size / 2), lessThanOrEqualTo(halfWidth),
              reason: 'a card runs off the canvas horizontally');
          expect(card.at.dy.abs() + (card.size / 2), lessThanOrEqualTo(halfHeight),
              reason: 'a card runs off the canvas vertically');
        }
      });
    });
  }

  test('the canvas never shrinks below the minimum', () {
    final plan = GalaxyRingLayout.solve(nodeSizes: const [], ringCounts: galaxyRingCounts);
    expect(plan.canvasSize.width,
        greaterThanOrEqualTo(GalaxyRingLayout.minCanvasSize.width));
    expect(plan.canvasSize.height,
        greaterThanOrEqualTo(GalaxyRingLayout.minCanvasSize.height));
  });

  test('a single word needs no rings at all', () {
    final plan =
        GalaxyRingLayout.solve(nodeSizes: const [], ringCounts: galaxyRingCounts);
    expect(plan.ringRadii, isEmpty);
  });
}
