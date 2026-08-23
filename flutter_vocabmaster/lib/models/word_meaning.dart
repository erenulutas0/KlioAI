/// One sense of a word.
///
/// A word used to carry a single comma-joined translation string. It now carries a list
/// of meanings, each of which a sentence can be attached to. The joined string still
/// exists on [Word.turkishMeaning] as a denormalised copy for the shipped client.
class WordMeaning {
  final int id;
  final String translation;
  final String? definition;
  final int position;

  const WordMeaning({
    required this.id,
    required this.translation,
    this.definition,
    this.position = 0,
  });

  factory WordMeaning.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value, {int fallback = 0}) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? fallback;
    }

    return WordMeaning(
      id: parseInt(json['id']),
      translation: json['translation']?.toString() ?? '',
      definition: json['definition']?.toString(),
      position: parseInt(json['position']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'translation': translation,
      'definition': definition,
      'position': position,
    };
  }
}
