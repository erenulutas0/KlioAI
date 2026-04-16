import 'package:equatable/equatable.dart';

class WordSet extends Equatable {
  final String centerWord;
  final List<String> relatedWords;
  final String difficulty;
  final Map<String, List<String>> relatedWordAliases;
  final Map<String, List<String>> turkishTranslations;

  const WordSet({
    required this.centerWord,
    required this.relatedWords,
    required this.difficulty,
    this.relatedWordAliases = const {},
    this.turkishTranslations = const {},
  });

  @override
  List<Object?> get props => [
        centerWord,
        relatedWords,
        difficulty,
        relatedWordAliases,
        turkishTranslations,
      ];
}
