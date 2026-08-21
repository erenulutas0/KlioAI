import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/models/exam_models.dart';

/// The XP award for finishing an exam is idempotent by transaction id, so the id has to
/// distinguish one exam from another. Only `category` does: `exam` is fixed at the single
/// call site and `mode` is a string literal in the prompt.
void main() {
  ExamMeta metaFor(String category) => ExamMeta.fromJson({
        'exam': 'YDS',
        'mode': 'category',
        'category': category,
        'time_limit_minutes': 30,
        'total_questions': 20,
      });

  String idFor(ExamMeta meta) =>
      'exam_${meta.exam}_${meta.mode}_${meta.category ?? 'none'}_2026-08-22';

  test('category survives parsing', () {
    expect(metaFor('grammar').category, equals('grammar'));
  });

  test('three exams in one day produce three different transaction ids', () {
    // They used to collapse to one, so grammar then vocabulary then reading earned 20 XP
    // instead of 60 - the later awards returned zero and the result screen looked identical.
    final ids = ['grammar', 'vocabulary', 'reading'].map((c) => idFor(metaFor(c))).toSet();

    expect(ids.length, equals(3));
  });

  test('the same exam twice in one day still earns once', () {
    expect(idFor(metaFor('grammar')), equals(idFor(metaFor('grammar'))));
  });

  test('a payload with no category still yields a stable id', () {
    final meta = ExamMeta.fromJson({
      'exam': 'YDS',
      'mode': 'category',
      'time_limit_minutes': 30,
      'total_questions': 20,
    });

    expect(meta.category, isNull);
    expect(idFor(meta), contains('_none_'));
  });
}
