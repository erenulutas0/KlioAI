import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

class DailyPracticeProgressService {
  DailyPracticeProgressService({AuthService? authService})
      : _authService = authService ?? AuthService();

  static const List<String> cefrLevels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

  final AuthService _authService;

  Future<Map<String, bool>> getCompletedLevels(String type) async {
    final result = <String, bool>{};
    for (final level in cefrLevels) {
      result[level] = await isCompleted(type: type, level: level);
    }
    return result;
  }

  Future<bool> isCompleted({
    required String type,
    required String level,
  }) async {
    final payload = await _readPayload(type: type, level: level);
    return payload['completed'] == true;
  }

  Future<void> saveReadingResult({
    required String level,
    required int score,
    required int totalQuestions,
    required Map<int, String?> selectedAnswers,
    required Map<int, bool?> checkedAnswers,
  }) async {
    final selected = <String, String>{};
    for (final entry in selectedAnswers.entries) {
      final value = entry.value;
      if (value != null && value.isNotEmpty) {
        selected[entry.key.toString()] = value;
      }
    }

    final checked = <String, bool>{};
    for (final entry in checkedAnswers.entries) {
      final value = entry.value;
      if (value != null) {
        checked[entry.key.toString()] = value;
      }
    }

    await _writePayload(
      type: 'reading',
      level: level,
      payload: {
        'completed': true,
        'score': score,
        'totalQuestions': totalQuestions,
        'selectedAnswers': selected,
        'checkedAnswers': checked,
        'completedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<ReadingReviewData?> getReadingResult(String level) async {
    final payload = await _readPayload(type: 'reading', level: level);
    if (payload.isEmpty) {
      return null;
    }

    final selectedRaw = payload['selectedAnswers'];
    final checkedRaw = payload['checkedAnswers'];

    final selected = <int, String?>{};
    if (selectedRaw is Map) {
      for (final entry in selectedRaw.entries) {
        final key = int.tryParse(entry.key.toString());
        if (key != null) {
          selected[key] = entry.value?.toString();
        }
      }
    }

    final checked = <int, bool?>{};
    if (checkedRaw is Map) {
      for (final entry in checkedRaw.entries) {
        final key = int.tryParse(entry.key.toString());
        if (key != null) {
          final rawValue = entry.value;
          checked[key] = rawValue == true;
        }
      }
    }

    return ReadingReviewData(
      score: _toInt(payload['score']),
      totalQuestions: _toInt(payload['totalQuestions']),
      selectedAnswers: selected,
      checkedAnswers: checked,
      completedAt: payload['completedAt']?.toString(),
    );
  }

  Future<void> saveWritingResult({
    required String level,
    required String topic,
    required int score,
  }) async {
    await _writePayload(
      type: 'writing',
      level: level,
      payload: {
        'completed': true,
        'topic': topic,
        'score': score,
        'completedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<WritingReviewData?> getWritingResult(String level) async {
    final payload = await _readPayload(type: 'writing', level: level);
    if (payload.isEmpty) {
      return null;
    }
    return WritingReviewData(
      topic: payload['topic']?.toString() ?? '',
      score: _toInt(payload['score']),
      completedAt: payload['completedAt']?.toString(),
    );
  }

  Future<Map<String, dynamic>> _readPayload({
    required String type,
    required String level,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(await _buildKey(type: type, level: level));
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final decoded = json.decode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return {};
    }
    return {};
  }

  Future<void> _writePayload({
    required String type,
    required String level,
    required Map<String, dynamic> payload,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      await _buildKey(type: type, level: level),
      json.encode(payload),
    );
  }

  Future<String> _buildKey({
    required String type,
    required String level,
  }) async {
    final userId = await _authService.getUserId() ?? 0;
    final dayKey = DateTime.now().toUtc().toIso8601String().split('T').first;
    return 'daily_practice:$userId:$dayKey:${type.toLowerCase()}:${level.toUpperCase()}';
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class ReadingReviewData {
  const ReadingReviewData({
    required this.score,
    required this.totalQuestions,
    required this.selectedAnswers,
    required this.checkedAnswers,
    required this.completedAt,
  });

  final int score;
  final int totalQuestions;
  final Map<int, String?> selectedAnswers;
  final Map<int, bool?> checkedAnswers;
  final String? completedAt;
}

class WritingReviewData {
  const WritingReviewData({
    required this.topic,
    required this.score,
    required this.completedAt,
  });

  final String topic;
  final int score;
  final String? completedAt;
}
