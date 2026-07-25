// Loop Mixer 3.0 §B — key & scale (engine layer). Every pitched stem, the
// engraving, and the jam math transpose rigidly by the root; minor pentatonic
// borrows the relative-major set (+3), so any combo stays consonant. Pure,
// headless: a real detector reads the transposed synthesis, plus cell-level +
// token roundtrip checks.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/streaming_analyzer.dart';
import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:flutter_test/flutter_test.dart';

// The five sounding pitch-classes for a given transpose over C major pentatonic.
Set<int> _pent(int t) => {
      for (final p in const [0, 2, 4, 7, 9]) (p + t) % 12,
    };

int _detectMidi(Float64List mono) {
  final frames = StreamingAudioAnalyzer(detector: PitchDetector())
      .addSamples(mono)
      .where((f) => f.pitch.hasPitch)
      .toList();
  expect(frames, isNotEmpty, reason: 'nothing voiced to detect');
  return frames[frames.length ~/ 2].pitch.nearestMidi; // steady middle
}

void main() {
  const timing = LoopTiming(tempoBpm: 100);

  group('synthesis truly transposes (a real detector reads it)', () {
    test('renderCells shifts a sustained note by the transpose', () {
      final at0 = _detectMidi(
        renderCells(
          [
            const PatternCell(midis: [60], steps: 16),
          ],
          Instrument.flute,
          timing,
        ),
      );
      final at5 = _detectMidi(
        renderCells(
          [
            const PatternCell(midis: [60], steps: 16),
          ],
          Instrument.flute,
          timing,
          transpose: 5,
        ),
      );
      expect(at0, 60); // C4
      expect(at5, 65); // F4 — moved up a fourth in the actual audio
    });
  });

  group('engine wiring: key/scale change the rendered groove', () {
    LoopEngine melodyEngine() => LoopEngine()
      ..applySpec(
        const GrooveSpec(enabled: {'melody'}),
      );

    test('changing the key re-renders different audio', () {
      final c = melodyEngine();
      final cWav = c.renderLoop();
      c.key = 5;
      final fWav = c.renderLoop();
      expect(cWav, isNotEmpty);
      expect(fWav, isNotEmpty);
      expect(fWav, isNot(equals(cWav))); // the transposition is audible
    });

    test(
        'transposition is RIGID for every pitched track × key × scale '
        '(this is what preserves consonance)', () {
      // A note shifts by exactly pitchTranspose vs the untransposed base — so
      // whatever was consonant at C stays consonant, transposed.
      final base = LoopEngine()
        ..applySpec(
          const GrooveSpec(
            enabled: {'melody', 'chords', 'bass', 'sparkle'},
          ),
        );
      for (final scale in GrooveScale.values) {
        for (var k = 0; k < 12; k++) {
          final e = LoopEngine()
            ..applySpec(
              GrooveSpec(
                enabled: const {'melody', 'chords', 'bass', 'sparkle'},
                key: k,
                scale: scale,
              ),
            );
          final t = e.pitchTranspose;
          for (final id in ['melody', 'chords', 'bass', 'sparkle']) {
            final b = base.engravedCellsFor(id);
            final got = e.engravedCellsFor(id);
            if (b == null) continue;
            expect(got, isNotNull);
            for (var i = 0; i < b.length; i++) {
              final want = b[i].midis?.map((m) => m + t).toList();
              expect(
                got![i].midis,
                want,
                reason: '$id cell $i not rigid for key=$k scale=$scale',
              );
            }
          }
        }
      }
    });

    test('engravedCellsFor transposes; cellsFor stays authored-C', () {
      final e = LoopEngine()..applySpec(const GrooveSpec(enabled: {'melody'}));
      final raw = e.cellsFor('melody')!;
      e.key = 3;
      // cellsFor is unchanged (render transposes at synthesis)...
      expect(e.cellsFor('melody')!.first.midis, raw.first.midis);
      // ...engravedCellsFor reflects the +3 shift.
      final eng = e.engravedCellsFor('melody')!;
      expect(eng.first.midis, raw.first.midis!.map((m) => m + 3).toList());
    });

    test('minor pentatonic uses the relative-major set (+3)', () {
      final e = LoopEngine()
        ..applySpec(
          const GrooveSpec(scale: GrooveScale.minorPentatonic),
        );
      expect(e.pitchTranspose, 3); // C minor pent == Eb major pent
      // C minor pentatonic pitch-classes: C Eb F G Bb = {0,3,5,7,10}.
      expect(_pent(e.pitchTranspose), {0, 3, 5, 7, 10});
    });
  });

  group('jam fit follows the key/scale', () {
    test('scale + chord tones shift with the root', () {
      final major = LoopEngine()
        ..applySpec(const GrooveSpec(key: 2)); // D major
      // D (62) is now the tonic scale/chord tone; C (60) is outside D-pent.
      expect(major.jamFit(62, bar: 0), JamFit.chordTone);
      expect(major.jamFit(60, bar: 0), JamFit.outside);

      final minor = LoopEngine()
        ..applySpec(
          const GrooveSpec(scale: GrooveScale.minorPentatonic),
        ); // C minor
      // Eb (63) is in C minor pentatonic; E natural (64) is not.
      expect(minor.jamFit(63, bar: 0), isNot(JamFit.outside));
      expect(minor.jamFit(64, bar: 0), JamFit.outside);
    });
  });

  group('share token stays backward compatible', () {
    test('default key/scale are omitted so old KU1. tokens are unchanged', () {
      final json = const GrooveSpec(enabled: {'melody'}).toJson();
      expect(json.containsKey('k'), isFalse);
      expect(json.containsKey('sc'), isFalse);
    });

    test('key + scale roundtrip through json', () {
      const spec = GrooveSpec(
        enabled: {'melody', 'bass'},
        key: 7,
        scale: GrooveScale.minorPentatonic,
      );
      final back = GrooveSpec.fromJson(spec.toJson());
      expect(back.key, 7);
      expect(back.scale, GrooveScale.minorPentatonic);
    });

    test('a pre-key token (no k/sc) decodes to C major', () {
      final back = GrooveSpec.fromJson({
        'e': ['melody'],
        't': 100,
      });
      expect(back.key, 0);
      expect(back.scale, GrooveScale.majorPentatonic);
    });

    test('a hostile out-of-range key is wrapped into 0..11', () {
      expect(GrooveSpec.fromJson({'k': 26}).key, 2); // 26 % 12
      expect(GrooveSpec.fromJson({'k': -1}).key, 11);
    });
  });
}
