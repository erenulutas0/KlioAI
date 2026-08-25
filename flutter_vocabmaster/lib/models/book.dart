/// The reading shelf, as the client sees it.
///
/// Books are public-domain texts imported once on the server and served from
/// the database, so nothing here costs anything to read. The learning happens
/// by tapping a word, not by reading a translation: most of the shelf has no
/// translation at all, deliberately.
library;

import 'package:flutter/foundation.dart';

/// One book on the shelf, with where this reader left off in it.
@immutable
class BookShelfEntry {
  const BookShelfEntry({
    required this.slug,
    required this.title,
    required this.author,
    required this.level,
    required this.sentenceCount,
    required this.lastSentenceIndex,
    required this.started,
  });

  final String slug;
  final String title;
  final String author;

  /// Rough CEFR level (A1…C1), or empty when the server has not judged one.
  final String level;

  final int sentenceCount;

  /// The last sentence this reader finished. Zero for an unopened book *and*
  /// for one opened but not read, which is why [started] exists separately.
  final int lastSentenceIndex;

  /// Whether this reader has ever opened the book.
  final bool started;

  /// How far through, from 0 to 1. Zero-length books read as unstarted rather
  /// than dividing by zero.
  double get fraction =>
      sentenceCount <= 0 ? 0 : (lastSentenceIndex / sentenceCount).clamp(0, 1);

  factory BookShelfEntry.fromJson(Map<String, dynamic> json) => BookShelfEntry(
        slug: (json['slug'] ?? '') as String,
        title: (json['title'] ?? '') as String,
        author: (json['author'] ?? '') as String,
        level: (json['level'] ?? '') as String? ?? '',
        sentenceCount: (json['sentenceCount'] as num?)?.toInt() ?? 0,
        lastSentenceIndex: (json['lastSentenceIndex'] as num?)?.toInt() ?? 0,
        started: json['started'] == true,
      );
}

/// One sentence as the reader shows it.
@immutable
class ReaderSentence {
  const ReaderSentence({
    required this.index,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.text,
    required this.translation,
  });

  final int index;
  final int chapterIndex;

  /// May be empty: not every book names its chapters.
  final String chapterTitle;

  final String text;

  /// Null when this sentence has no translation, which is the normal case.
  ///
  /// Kept nullable rather than defaulted to an empty string so the screen can
  /// tell "there is no translation" from "the translation failed to load".
  final String? translation;

  bool get hasTranslation =>
      translation != null && translation!.trim().isNotEmpty;

  factory ReaderSentence.fromJson(Map<String, dynamic> json) => ReaderSentence(
        index: (json['index'] as num?)?.toInt() ?? 0,
        chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
        chapterTitle: (json['chapterTitle'] as String?) ?? '',
        text: (json['text'] ?? '') as String,
        translation: json['translation'] as String?,
      );
}

/// A window of a book: the sentences asked for, and where they sit in it.
@immutable
class ReaderWindow {
  const ReaderWindow({
    required this.slug,
    required this.title,
    required this.from,
    required this.sentenceCount,
    required this.sentences,
  });

  final String slug;
  final String title;

  /// Index of the first sentence in [sentences].
  final int from;

  /// How many sentences the whole book has, so the reader knows when to stop
  /// asking for more.
  final int sentenceCount;

  final List<ReaderSentence> sentences;

  factory ReaderWindow.fromJson(Map<String, dynamic> json) => ReaderWindow(
        slug: (json['slug'] ?? '') as String,
        title: (json['title'] ?? '') as String,
        from: (json['from'] as num?)?.toInt() ?? 0,
        sentenceCount: (json['sentenceCount'] as num?)?.toInt() ?? 0,
        sentences: ((json['sentences'] as List<dynamic>?) ?? <dynamic>[])
            .map((dynamic e) =>
                ReaderSentence.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}
