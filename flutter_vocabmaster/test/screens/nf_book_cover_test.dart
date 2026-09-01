import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/frontend_newest/screens/nf_books_page.dart';
import 'package:vocabmaster/models/book.dart';

/// Five of the six books on the shelf have a real cover bundled; the sixth is
/// drawn. Three things have to stay true for that to keep working.
///
/// The list of which books have artwork is written in Dart, not discovered at
/// runtime. That is deliberate -- a missing asset throws during layout and the
/// recovery is a frame late, so the shelf would flash a broken tile before it
/// settled -- and it is exactly the kind of list that drifts from the files
/// beside it. So the first test reads the directory.
///
/// The drawn cover is not a fallback nobody sees. Heart of Darkness uses it
/// today, because what Gutenberg serves for that book is a generated
/// placeholder with their name across it. If the drawn path ever stops being
/// exercised, the shelf has quietly gained a sixth asset that may not be one
/// we are entitled to.
void main() {
  const List<String> shelf = <String>[
    'peter-rabbit',
    'aesops-fables',
    'happy-prince',
    'sherlock-adventures',
    'jekyll-and-hyde',
    'heart-of-darkness',
  ];

  BookShelfEntry entry(String slug, String title, String author) =>
      BookShelfEntry(
        slug: slug,
        title: title,
        author: author,
        level: 'B1',
        sentenceCount: 100,
        lastSentenceIndex: 0,
        started: false,
      );

  test('every slug claiming artwork has a file, and vice versa', () {
    final Directory dir = Directory('assets/covers');
    expect(dir.existsSync(), isTrue,
        reason: 'run this from the flutter_vocabmaster directory');

    final Set<String> onDisk = dir
        .listSync()
        .whereType<File>()
        .map((File f) => f.uri.pathSegments.last)
        .where((String name) => name.endsWith('.jpg'))
        .map((String name) => name.substring(0, name.length - 4))
        .toSet();

    expect(BookCover.withArtwork, onDisk,
        reason: 'the list in BookCover and the files in assets/covers have '
            'drifted apart. In the list but not on disk means a shelf tile '
            'throws; on disk but not in the list means a file is shipped and '
            'never drawn.');
  });

  test('the drawn cover is still reachable', () {
    final Iterable<String> drawn =
        shelf.where((String s) => !BookCover.withArtwork.contains(s));
    expect(drawn, isNotEmpty,
        reason: 'every book now has artwork, so nothing exercises the drawn '
            'cover. If a cover was added for Heart of Darkness, check it is '
            'not the Project Gutenberg placeholder.');
  });

  test('each book on the shelf gets its own board colour', () {
    final Set<Color> colours = <Color>{
      for (int i = 0; i < shelf.length; i++) BookCover.colourOf(i),
    };
    expect(colours.length, shelf.length,
        reason: 'only ${colours.length} colours across ${shelf.length} books, '
            'so two drawn covers would look identical');
  });

  test('the palette has room for the shelf to grow', () {
    // Where it wraps is where two boards start sharing a colour. Knowing the
    // number is the point: it says how many books can be added before someone
    // has to widen the palette, rather than leaving it to be discovered.
    int size = 1;
    while (size < 64 && BookCover.colourOf(size) != BookCover.colourOf(0)) {
      size++;
    }
    expect(size, greaterThanOrEqualTo(shelf.length + 2),
        reason: 'the palette wraps at $size and the shelf already holds '
            '${shelf.length}, so the next book or two collides');
  });

  test('a negative index still picks a colour', () {
    // Nothing passes one today, and it is one modulo away from an exception
    // inside a list builder, which is a poor way to lose a shelf.
    expect(() => BookCover.colourOf(-1), returnsNormally);
  });

  testWidgets('a book without artwork is drawn with its title and author',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BookCover(
          shelfIndex: 5,
          book: entry('heart-of-darkness', 'Heart of Darkness',
              'Joseph Conrad'),
        ),
      ),
    ));

    expect(find.text('Heart of Darkness'), findsOneWidget);
    expect(find.text('Joseph Conrad'), findsOneWidget);
    expect(find.byType(Image), findsNothing,
        reason: 'this book has no bundled cover, so nothing should be loading '
            'one');
  });

  testWidgets('a book with artwork draws the image, not the title',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BookCover(
          shelfIndex: 0,
          book: entry('peter-rabbit', 'The Tale of Peter Rabbit',
              'Beatrix Potter'),
        ),
      ),
    ));

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('The Tale of Peter Rabbit'), findsNothing,
        reason: 'the cover carries the title already; printing it over the '
            'artwork would be setting it twice');
  });
}
