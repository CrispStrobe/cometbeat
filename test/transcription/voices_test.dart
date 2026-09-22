// W-NOTATION voice/staff separation. separateVoices splits a melody-over-bass
// into two independent voices (and keeps a block chord as one); toGrandStaff puts
// the high notes on a treble staff and the low ones on an aligned bass staff.

import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/voices.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter_test/flutter_test.dart';

NoteEvent _n(int midi, double on, double off) =>
    (midi: midi, onMs: on, offMs: off, confidence: 1, program: -1);

const _grid = (
  bpm: 120.0,
  beatMs: [0.0, 500.0, 1000.0, 1500.0, 2000.0],
  onsetMs: <double>[],
);

List<int> _midisOf(Score s) => [
      for (final m in s.measures)
        for (final e in m.elements)
          if (e is NoteElement)
            for (final p in e.pitches) p.midiNumber,
    ];

void main() {
  group('separateVoices', () {
    test('a monophonic line stays one voice', () {
      final v = separateVoices([
        _n(60, 0, 500),
        _n(62, 500, 1000),
        _n(64, 1000, 1500),
      ]);
      expect(v, hasLength(1));
      expect(v.first, hasLength(3));
    });

    test('a melody over a held bass splits into two voices, top first', () {
      // Bass C3 held the whole bar; melody E-F-G above it.
      final v = separateVoices([
        _n(48, 0, 2000), // bass, sustained
        _n(64, 0, 500),
        _n(65, 500, 1000),
        _n(67, 1000, 1500),
      ]);
      expect(v, hasLength(2));
      // Voice 1 (top) is the melody; voice 2 (bottom) is the bass.
      expect(v[0].map((n) => n.midi), [64, 65, 67]);
      expect(v[1].map((n) => n.midi), [48]);
    });

    test('a struck triad stays ONE voice (a chord, not three voices)', () {
      final v = separateVoices([
        _n(60, 0, 500),
        _n(64, 0, 500),
        _n(67, 0, 500),
      ]);
      expect(v, hasLength(1));
      expect(v.first.map((n) => n.midi).toSet(), {60, 64, 67});
    });

    test('empty input → no voices', () {
      expect(separateVoices(const []), isEmpty);
    });
  });

  group('toGrandStaff', () {
    test('splits high vs low notes onto treble + bass staves', () {
      final notes = [
        _n(72, 0, 500), // C5 → treble
        _n(48, 0, 500), // C3 → bass
        _n(76, 500, 1000), // E5 → treble
        _n(43, 500, 1000), // G2 → bass
      ];
      final gs = toGrandStaff(notes, _grid);

      expect(gs.upper.clef, Clef.treble);
      expect(gs.lower.clef, Clef.bass);
      expect(_midisOf(gs.upper).every((m) => m >= 60), isTrue);
      expect(_midisOf(gs.lower).every((m) => m < 60), isTrue);
      expect(_midisOf(gs.upper), containsAll([72, 76]));
      expect(_midisOf(gs.lower), containsAll([48, 43]));
    });

    test('both staves are padded to the same number of bars', () {
      // Only a treble note; the bass staff must still exist and match length.
      final gs = toGrandStaff([_n(72, 0, 2000)], _grid);
      expect(gs.lower.measures, isNotEmpty);
      expect(gs.upper.measures.length, gs.lower.measures.length);
    });

    test('renders valid grand-staff MusicXML', () {
      final gs = toGrandStaff([_n(72, 0, 1000), _n(48, 0, 1000)], _grid);
      final xml = grandStaffToMusicXml(gs);
      expect(xml, contains('<score-partwise'));
    });
  });
}
