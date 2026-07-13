// Unit tests for the shared SATB voicing — especially the widened multi-key
// path, which the game widget tests (run at 0 stars = C major, 2 voices) don't
// reach. Guarantees: right number of parts, strictly ascending (no voice
// crossing), and Soprano/Alto on treble with Tenor/Bass on bass.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/features/games/note_reading/satb_voicing.dart';
import 'package:partitura/partitura.dart' show Clef;

void main() {
  final random = Random(1234); // seeded for determinism

  test('2-voice: Soprano above Alto, both on the treble staff', () {
    for (var i = 0; i < 200; i++) {
      final parts = voiceRandomChord(random, satb: false, wide: true);
      expect(
        parts.map((p) => p.voice).toList(),
        [SatbVoice.soprano, SatbVoice.alto],
      );
      final s = parts[0].pitch.midiNumber;
      final a = parts[1].pitch.midiNumber;
      expect(s, greaterThan(a), reason: 'Soprano must sit above Alto');
      expect(SatbVoice.soprano.clef, Clef.treble);
      expect(SatbVoice.alto.clef, Clef.treble);
    }
  });

  test('SATB wide: four voices strictly descending S>A>T>B, no crossing', () {
    for (var i = 0; i < 400; i++) {
      final parts = voiceRandomChord(random, satb: true, wide: true);
      expect(parts.length, 4);
      final midis = parts.map((p) => p.pitch.midiNumber).toList();
      // Parts are S, A, T, B in order — each strictly below the previous.
      for (var v = 1; v < midis.length; v++) {
        expect(
          midis[v],
          lessThan(midis[v - 1]),
          reason: 'voice ${v + 1} must be below voice $v (no crossing)',
        );
      }
      // Tenor & Bass render on the bass staff; Soprano & Alto on treble.
      expect(SatbVoice.tenor.clef, Clef.bass);
      expect(SatbVoice.bass.clef, Clef.bass);
    }
  });

  test('every voice carries a distinct highlight id', () {
    expect(
      SatbVoice.values.map((v) => v.id).toSet().length,
      SatbVoice.values.length,
    );
  });
}
