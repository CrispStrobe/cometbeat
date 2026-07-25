// test/midi_pitch_test.dart
//
// B1 — one `pitchFromMidi`. It used to be copy-pasted into five files: the
// canonical `shared/midi_pitch.dart`, `mod/module_notation.dart` and
// `tracker_notation.dart` (pitch-class table), and `tab_document.dart` and
// `groove_notation.dart` (natural-below-plus-sharp). The copies agreed, but
// nothing enforced that — a spelling fix in one mode would silently not reach
// the others.
//
// These tests pin the spelling contract AND assert that every ex-copy's import
// site still resolves to the same function, so the four re-exports cannot drift
// back apart.

import 'package:comet_beat/core/audio/mod/module_notation.dart' as module;
import 'package:comet_beat/features/games/composition/groove_notation.dart'
    as groove;
import 'package:comet_beat/features/games/composition/tab_document.dart' as tab;
import 'package:comet_beat/features/games/composition/tracker_notation.dart'
    as tracker;
import 'package:comet_beat/shared/midi_pitch.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pitchFromMidi spelling', () {
    test('C4 is 60 — the anchor every mode assumes', () {
      final c4 = pitchFromMidi(60);
      expect(c4.step, Step.c);
      expect(c4.alter, 0);
      expect(c4.octave, 4);
    });

    test('the twelve pitch classes of octave 4 spell as sharps', () {
      const expected = <(Step, int)>[
        (Step.c, 0),
        (Step.c, 1),
        (Step.d, 0),
        (Step.d, 1),
        (Step.e, 0),
        (Step.f, 0),
        (Step.f, 1),
        (Step.g, 0),
        (Step.g, 1),
        (Step.a, 0),
        (Step.a, 1),
        (Step.b, 0),
      ];
      for (var pc = 0; pc < 12; pc++) {
        final p = pitchFromMidi(60 + pc);
        final (step, alter) = expected[pc];
        expect(p.step, step, reason: 'pitch class $pc step');
        expect(p.alter, alter, reason: 'pitch class $pc alter');
        expect(p.octave, 4, reason: 'pitch class $pc octave');
      }
    });

    test('round-trips through Pitch.midiNumber across the whole MIDI range',
        () {
      for (var midi = 0; midi < 128; midi++) {
        expect(
          pitchFromMidi(midi).midiNumber,
          midi,
          reason: 'midi $midi did not round-trip',
        );
      }
    });

    test('octave boundaries land where the MIDI standard puts them', () {
      expect(pitchFromMidi(0).octave, -1); // C-1
      expect(pitchFromMidi(0).step, Step.c);
      expect(pitchFromMidi(12).octave, 0);
      expect(pitchFromMidi(59).octave, 3); // B3, just under middle C
      expect(pitchFromMidi(59).step, Step.b);
      expect(pitchFromMidi(127).octave, 9); // G9
      expect(pitchFromMidi(127).step, Step.g);
    });
  });

  group('the four ex-copies now resolve to the one implementation', () {
    // Each of these libraries used to define its own `pitchFromMidi` and now
    // re-exports the shared one. Comparing the tear-offs proves it is literally
    // the same function, not a re-implementation that happens to agree today.
    test('function identity', () {
      expect(module.pitchFromMidi, same(pitchFromMidi));
      expect(tracker.pitchFromMidi, same(pitchFromMidi));
      expect(tab.pitchFromMidi, same(pitchFromMidi));
      expect(groove.pitchFromMidi, same(pitchFromMidi));
    });

    test('and agree on every MIDI number', () {
      for (var midi = 0; midi < 128; midi++) {
        final want = pitchFromMidi(midi);
        for (final got in [
          module.pitchFromMidi(midi),
          tracker.pitchFromMidi(midi),
          tab.pitchFromMidi(midi),
          groove.pitchFromMidi(midi),
        ]) {
          expect(got.step, want.step, reason: 'midi $midi');
          expect(got.alter, want.alter, reason: 'midi $midi');
          expect(got.octave, want.octave, reason: 'midi $midi');
        }
      }
    });
  });
}
