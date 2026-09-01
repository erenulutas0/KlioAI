import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/frontend_newest/screens/nf_books_page.dart';
import 'package:vocabmaster/models/book.dart';

/// The shelf's covers are drawn, and both derivations behind them are load
/// bearing in a way that is easy to break quietly.
///
/// The colour came from a hash of the slug in the first version, because a
/// colour that belongs to the book and never moves is the nicer idea. This
/// test killed it: six books drawn from eight colours came out as four
/// colours, and widening the palette until these six separated would have been
/// fitting the design to today's shelf. It is the shelf position now, which
/// cannot collide while there are fewer books than colours.
///
/// The letter must not be "T". Four of the six titles open with "The", and a
/// shelf of four identical letters is not a picture, it is a list with a
/// coloured rectangle in front of it.
void main() {
  // The real shelf, from BookLibrary on the server, in its real order.
  const List<String> shelf = <String>[
    'The Tale of Peter Rabbit',
    "Aesop's Fables",
    'The Happy Prince and Other Tales',
    'The Adventures of Sherlock Holmes',
    'The Strange Case of Dr Jekyll and Mr Hyde',
    'Heart of Darkness',
  ];

  test('the letter skips the article', () {
    expect(BookSpine.initialOf('The Tale of Peter Rabbit'), 'T'); // Tale
    expect(BookSpine.initialOf('The Happy Prince and Other Tales'), 'H');
    expect(BookSpine.initialOf('The Adventures of Sherlock Holmes'), 'A');
    expect(BookSpine.initialOf('A Study in Scarlet'), 'S');
    expect(BookSpine.initialOf("Aesop's Fables"), 'A');

    // Nothing usable must still draw something rather than break a shelf.
    expect(BookSpine.initialOf(''), '?');
    expect(BookSpine.initialOf('   '), '?');
    expect(BookSpine.initialOf('The'), '?');
    expect(BookSpine.initialOf('— 1984 —'), '?');
  });

  test('the six titles do not reduce to one letter', () {
    final Set<String> letters = shelf.map(BookSpine.initialOf).toSet();
    expect(letters.length, greaterThan(3),
        reason: 'the shelf shows ${letters.length} distinct letters across '
            '${shelf.length} books ($letters), which is close to no picture');
  });

  test('every book on this shelf gets its own colour', () {
    final Set<Color> colours = <Color>{
      for (int i = 0; i < shelf.length; i++) BookSpine.colourOf(i),
    };
    expect(colours.length, shelf.length,
        reason: 'only ${colours.length} colours across ${shelf.length} books, '
            'so at least two spines look identical on one screen');
  });

  test('the palette has room for the shelf to grow', () {
    // Where it wraps is where two spines start sharing a colour. Knowing the
    // number is the point: it says how many books can be added before someone
    // has to widen the palette, rather than leaving it to be discovered.
    int size = 1;
    while (size < 64 && BookSpine.colourOf(size) != BookSpine.colourOf(0)) {
      size++;
    }
    expect(size, greaterThanOrEqualTo(shelf.length + 2),
        reason: 'the palette wraps at $size and the shelf already holds '
            '${shelf.length}, so the next book or two collides');
  });

  test('a negative index still draws a colour', () {
    // Nothing passes one today. It is one modulo away from an exception in a
    // list builder, which is a poor way to lose a shelf.
    expect(() => BookSpine.colourOf(-1), returnsNormally);
  });

  testWidgets('a spine draws its letter', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: BookSpine(
          shelfIndex: 2,
          book: BookShelfEntry(
            slug: 'happy-prince',
            title: 'The Happy Prince and Other Tales',
            author: 'Oscar Wilde',
            level: 'B1',
            sentenceCount: 987,
            lastSentenceIndex: 0,
            started: false,
          ),
        ),
      ),
    ));
    expect(find.text('H'), findsOneWidget);
  });
}
