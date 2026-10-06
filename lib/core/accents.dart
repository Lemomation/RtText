import 'package:flutter/material.dart';

/// A selectable accent preset: a stable [id] used for persistence plus the
/// seed [color] the Material 3 scheme is derived from.
@immutable
class Accent {
  const Accent({required this.id, required this.label, required this.color});

  final String id;
  final String label;
  final Color color;
}

/// The accent used until the user picks another one.
const kDefaultAccentId = 'teal';

/// The curated accent presets. Teal leads so it stays the default.
const List<Accent> accents = [
  Accent(id: 'teal', label: 'Teal', color: Color(0xFF2DD4BF)),
  Accent(id: 'violet', label: 'Violet', color: Color(0xFFA78BFA)),
  Accent(id: 'rose', label: 'Rose', color: Color(0xFFFB7185)),
  Accent(id: 'amber', label: 'Amber', color: Color(0xFFFBBF24)),
  Accent(id: 'blue', label: 'Blue', color: Color(0xFF60A5FA)),
  Accent(id: 'green', label: 'Green', color: Color(0xFF34D399)),
];

/// Looks a preset up by [id], falling back to the default when unknown.
Accent accentById(String id) => accents.firstWhere(
      (accent) => accent.id == id,
      orElse: () => accents.first,
    );
