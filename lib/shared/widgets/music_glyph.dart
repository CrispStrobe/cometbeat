// lib/shared/widgets/music_glyph.dart
//
// Renders a single SMuFL glyph using the Bravura font that ships with the
// partitura package. For single symbols (a quarter note, a rest) this is all
// we need; staff-based rendering comes from partitura's StaffView.

import 'package:flutter/material.dart';

/// Common SMuFL codepoints for individual notes and rests (stable across
/// SMuFL-compliant fonts; "individual notes" range U+E1D0ff, rests U+E4E0ff).
abstract final class Smufl {
  static const wholeNote = '\uE1D2';
  static const halfNote = '\uE1D3'; // stem up
  static const quarterNote = '\uE1D5'; // stem up
  static const eighthNote = '\uE1D7'; // stem up
  static const sixteenthNote = '\uE1D9'; // stem up
  static const wholeRest = '\uE4E3';
  static const halfRest = '\uE4E4';
  static const quarterRest = '\uE4E5';
  static const eighthRest = '\uE4E6';
  static const sixteenthRest = '\uE4E7';
}

class MusicGlyph extends StatelessWidget {
  final String glyph;
  final double size;
  final Color? color;

  const MusicGlyph(this.glyph, {super.key, this.size = 64, this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      glyph,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: 'Bravura',
        package: 'partitura',
        fontSize: size,
        height: 1,
        color: color ?? Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}
