import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

class NeuralWordNodeModel extends Equatable {
  final String id;
  final String word;
  final String? subtitle;
  final Offset position;

  const NeuralWordNodeModel({
    required this.id,
    required this.word,
    this.subtitle,
    required this.position,
  });

  @override
  List<Object?> get props => [id, word, subtitle, position];
}
