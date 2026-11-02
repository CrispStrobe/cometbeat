import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/practice/practice_mix.dart';
import 'package:comet_beat/core/audio/transcription/beat_grid.dart';
import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/separated_stem.dart';
import 'package:flutter_test/flutter_test.dart';

NoteEvent _n(int midi, double on, double off) => (
      midi: midi,
      onMs: on,
      offMs: off,
      confidence: 1,
      program: gmProgramUnknown,
    );

void main() {
  group('effectiveVolumes', () {
    test('unmuted strips play at their volume, muted ones are silent', () {
      expect(
        effectiveVolumes(const [
          StemControl(name: 'vocals', volume: 0.5),
          StemControl(name: 'drums', muted: true),
          StemControl(name: 'bass'),
        ]),
        [0.5, 0.0, 1.0],
      );
    });

    test('solo wins over mute, and silences every strip not soloed', () {
      expect(
        effectiveVolumes(const [
          StemControl(name: 'vocals', solo: true, muted: true),
          StemControl(name: 'drums'),
          StemControl(name: 'bass', solo: true, volume: 0.25),
        ]),
        [1.0, 0.0, 0.25],
      );
    });

    test('a volume outside 0..1 is clamped', () {
      expect(
        effectiveVolumes(const [StemControl(name: 'x', volume: 3)]),
        [1.0],
      );
    });
  });

  test('minusOne mutes exactly the named stem and clears every solo', () {
    final out = minusOne(
      const [
        StemControl(name: 'vocals', solo: true),
        StemControl(name: 'drums', muted: true),
        StemControl(name: 'bass'),
      ],
      'bass',
    );
    expect(effectiveVolumes(out), [1.0, 1.0, 0.0]);
  });

  group('interleavedWindow', () {
    final stem = SeparatedStem(
      'x',
      Float32List.fromList([1, 2, 3, 4]),
      Float32List.fromList([-1, -2, -3, -4]),
      44100,
    );

    test('interleaves L,R from the start frame', () {
      expect(interleavedWindow(stem, 1, 2), [2, -2, 3, -3]);
    });

    test('is cut short at the end, never padded', () {
      expect(interleavedWindow(stem, 3, 10), [4, -4]);
      expect(interleavedWindow(stem, 9, 10), isEmpty);
    });

    test('a negative start reads from the beginning', () {
      expect(interleavedWindow(stem, -5, 1), [1, -1]);
    });
  });

  group('melodyChart', () {
    test('keeps every note at its absolute song time, at the grid tempo', () {
      final chart = melodyChart(
        [_n(64, 1500, 2000), _n(62, 500, 1000)],
        grid: const BeatGrid(beatMs: [0, 500], downbeatMs: [0], bpm: 120),
      );
      expect(chart.bpm, 120);
      expect(chart.octaveAgnostic, isTrue);
      // Sorted, and start beat × beat length gives back the onset in ms — the
      // invariant that keeps a backing started on beat 0 in step.
      expect(chart.notes.map((n) => n.midi), [62, 64]);
      for (final (i, on) in [500.0, 1500.0].indexed) {
        expect(chart.notes[i].startBeat * chart.beatMs, closeTo(on, 1e-6));
        expect(chart.notes[i].beats * chart.beatMs, closeTo(500, 1e-6));
      }
    });

    test('drops flickers shorter than a singable note', () {
      final chart = melodyChart([
        _n(60, 0, kMinSingNoteMs - 1),
        _n(62, 200, 200 + kMinSingNoteMs),
      ]);
      expect(chart.notes.map((n) => n.midi), [62]);
    });

    test('without a usable tempo it falls back to 100 BPM, times unchanged',
        () {
      for (final grid in [
        null,
        const BeatGrid(beatMs: [], downbeatMs: [], bpm: 0),
        const BeatGrid(beatMs: [], downbeatMs: [], bpm: double.nan),
      ]) {
        final chart = melodyChart([_n(60, 900, 1300)], grid: grid);
        expect(chart.bpm, 100);
        expect(chart.notes.single.startBeat * chart.beatMs, closeTo(900, 1e-6));
      }
    });
  });

  group('BeatGrid', () {
    test('beatsPerBar is the commonest beat count between downbeats', () {
      final beats = [for (var i = 0; i < 13; i++) i * 500.0];
      final grid = BeatGrid(
        beatMs: beats,
        downbeatMs: [0, 1500, 3000, 4500, 6000],
        bpm: 120,
      );
      expect(grid.beatsPerBar, 3);
      expect(grid.firstDownbeatMs, 0);
    });

    test('needs two downbeats, and falls back to the first beat', () {
      const grid = BeatGrid(beatMs: [250, 750], downbeatMs: [], bpm: 120);
      expect(grid.beatsPerBar, isNull);
      expect(grid.firstDownbeatMs, 250);
    });
  });

  test('mixtureConsistent makes the stems sum to the mix exactly', () {
    SeparatedStem st(String n, List<double> l) => SeparatedStem(
          n,
          Float32List.fromList(l),
          Float32List.fromList([for (final v in l) -v]),
          44100,
        );
    final mixL = Float32List.fromList([1, 1, 1]);
    final mixR = Float32List.fromList([-1, -1, -1]);
    final out = mixtureConsistent(
      [
        st('a', [0.5, 0.2, 0]),
        st('b', [0.1, 0.2, 0]),
      ],
      mixL,
      mixR,
    );
    for (var i = 0; i < 3; i++) {
      expect(out[0].left[i] + out[1].left[i], closeTo(1, 1e-6));
      expect(out[0].right[i] + out[1].right[i], closeTo(-1, 1e-6));
    }
    // Equal shares of the residual: the difference between stems survives.
    expect(out[0].left[0] - out[1].left[0], closeTo(0.4, 1e-6));
  });

  group('practice loop', () {
    SeparatedStem ramp(String name, int n) => SeparatedStem(
          name,
          Float32List.fromList([for (var i = 0; i < n; i++) 1.0]),
          Float32List.fromList([for (var i = 0; i < n; i++) -1.0]),
          44100,
        );

    test('loopRegion cuts the span and fades both ends to silence', () {
      final out = loopRegion([ramp('a', 10000)], 1000, 3000, fadeFrames: 100);
      final s = out.single;
      expect(s.frames, 2000);
      expect(s.left.first, 0); // faded in from silence…
      expect(s.left.last, 0); // …and out, so the seam cannot click
      expect(s.left[1000], 1); // untouched in the middle
      expect(s.right[1000], -1);
    });

    test('loopRegion clamps to the stem and never inverts', () {
      expect(loopRegion([ramp('a', 100)], 50, 500).single.frames, 50);
      expect(loopRegion([ramp('a', 100)], 80, 20).single.frames, 0);
    });

    test('snapToBeat moves to the nearest beat, or leaves ms alone', () {
      const grid = BeatGrid(beatMs: [0, 500, 1000], downbeatMs: [0], bpm: 120);
      expect(snapToBeat(740, grid), 500);
      expect(snapToBeat(760, grid), 1000);
      expect(snapToBeat(760, null), 760);
    });

    test('slowStems keeps every stem the same, stretched length', () {
      SeparatedStem tone(String name, double hz) => SeparatedStem(
            name,
            Float32List.fromList([
              for (var i = 0; i < 22050; i++)
                math.sin(2 * math.pi * hz * i / 44100),
            ]),
            Float32List.fromList([
              for (var i = 0; i < 22050; i++)
                math.sin(2 * math.pi * hz * i / 44100),
            ]),
            44100,
          );
      final out = slowStems([tone('bass', 110), tone('other', 440)], 0.5);
      expect(out.map((s) => s.frames).toSet(), {44100}); // twice as long
      expect(out.map((s) => s.name), ['bass', 'other']);
      // Full speed is a no-op, not a needless copy-and-stretch.
      final same = [tone('x', 220)];
      expect(identical(slowStems(same, 1), same), isTrue);
    });
  });
}
