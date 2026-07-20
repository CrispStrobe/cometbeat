// test/module_instrument_bridge_test.dart
//
// "Borrow a sample from a module" → a playable SampleInstrument. The strong
// acceptance: synthesize a tonal sample at a known frequency, borrow it, render
// notes through the engine, and run the SAME MPM detector the app uses over the
// output — the borrowed instrument must sound at the sample's pitch and shift by
// an octave between note 60 and note 72. Plus a real-module render + error cases.
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/module_instrument_bridge_test.dart

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/module_instrument_bridge.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [DocSample] holding a pure sine of [freq] Hz sampled at [c5speed], [seconds]
/// long.
DocSample _sineSample(double freq, {int c5speed = 8363, double seconds = 3.0}) {
  final n = (c5speed * seconds).round();
  final pcm = Float64List(n);
  for (var i = 0; i < n; i++) {
    pcm[i] = 0.8 * sin(2 * pi * freq * i / c5speed);
  }
  return DocSample(name: 'sine', c5speed: c5speed, pcm: pcm);
}

/// Renders a single held [note] on [inst] and returns the MPM-detected frequency
/// from a window taken inside the sounding region.
double _detect(SampleInstrument inst, int note) {
  const timing = TrackerTiming(tempoBpm: 60, rows: 4, stepsPerBeat: 1);
  final cells = List<TrackerCell>.generate(
    timing.rows,
    (i) => i == 0 ? TrackerCell(midi: note) : TrackerCell.empty,
  );
  final out = inst.renderChannel(cells, timing);
  final d = PitchDetector();
  const offset = 4000;
  final window = Float64List(d.windowSize);
  for (var i = 0; i < d.windowSize; i++) {
    window[i] = out[offset + i];
  }
  return d.analyze(window).frequency;
}

void main() {
  group('9xx sample offset scales by the c5speed→engine ratio (bug fix)', () {
    // A rising ramp so the read START position is directly observable.
    DocSample rampSample({int c5speed = 8363, int n = 10240}) {
      final pcm = Float64List(n);
      for (var i = 0; i < n; i++) {
        pcm[i] = i / n;
      }
      return DocSample(name: 'ramp', c5speed: c5speed, pcm: pcm);
    }

    test(
        'the offset lands at param×256 of the ORIGINAL sample, not the engine '
        'buffer', () {
      final inst = sampleInstrumentFromDoc('r', rampSample());
      // c5speed 8363 → engine 44100 ⇒ scale ≈ 5.27.
      expect(inst.offsetScale, closeTo(44100 / 8363, 0.01));

      const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
      List<TrackerCell> col(TrackerCell first) => [
            first,
            ...List<TrackerCell>.filled(timing.rows - 1, TrackerCell.empty),
          ];
      // 9x08 → 8×256 = 2048 ORIGINAL samples = 2048/10240 = 20% into the ramp.
      final offset = inst.renderChannel(
        col(const TrackerCell(midi: 60, fxCmd: 0x9, fxParam: 0x08)),
        timing,
      );
      // Just past the declick, the read sits ~0.20 up the ramp. Without the
      // c5speed scaling it would land ~5.27× too shallow (~0.04) and fail.
      expect(offset[500], greaterThan(0.15));
      expect(offset[500], lessThan(0.30));
    });
  });

  group('sampleInstrumentFromDoc — pitch is faithful and shifts by note', () {
    late SampleInstrument inst;
    setUpAll(() {
      inst = sampleInstrumentFromDoc('borrow', _sineSample(220.0));
    });

    test('note 60 plays the sample at its native pitch (~220 Hz)', () {
      expect(_detect(inst, 60), closeTo(220.0, 11.0)); // within ~5%
    });

    test('note 72 is one octave up (~440 Hz)', () {
      final f60 = _detect(inst, 60);
      final f72 = _detect(inst, 72);
      expect(f72, closeTo(440.0, 22.0));
      expect(f72 / f60, closeTo(2.0, 0.1)); // clean octave regardless of tuning
    });
  });

  group('sampleInstrumentFromModule — borrow from a real module', () {
    final bytes = File('test/fixtures/golden.it').readAsBytesSync();

    test('borrowing sample 0 renders non-silent audio', () {
      final inst = sampleInstrumentFromModule('borrow', bytes, 0);
      const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);
      final cells = List<TrackerCell>.generate(
        timing.rows,
        (i) => i == 0 ? const TrackerCell(midi: 60) : TrackerCell.empty,
      );
      final out = inst.renderChannel(cells, timing);
      expect(out.any((s) => s.abs() > 1e-6), isTrue);
    });

    test('borrowableSamples lists the module\'s non-empty samples', () {
      final list = borrowableSamples(bytes);
      expect(list.length, 3); // golden.it has 3 used samples
      expect(list.first.$1, 0); // first is index 0
      expect(list.every((e) => !e.$2.isEmpty), isTrue);
    });

    test('errors: bad index / unrecognized bytes throw', () {
      expect(
        () => sampleInstrumentFromModule('x', bytes, 99),
        throwsArgumentError,
      );
      expect(
        () => sampleInstrumentFromModule('x', Uint8List(16), 0),
        throwsFormatException, // parseAnyModule rejects unknown format
      );
    });
  });

  group('resample clamping', () {
    test('a full-scale sample stays in [-1,1] after resampling', () {
      // A ±1 square-ish wave with sharp transitions makes cubic resampling
      // overshoot (~1.2+). c5speed ≠ engine rate forces a resample.
      final pcm = Float64List.fromList([
        for (var i = 0; i < 256; i++) (i ~/ 4).isEven ? 1.0 : -1.0,
      ]);
      final inst = sampleInstrumentFromDoc(
        's',
        DocSample(pcm: pcm, c5speed: 8000), // ≠ engine rate → forces a resample
      );
      var peak = 0.0;
      for (final v in inst.sample) {
        if (v.abs() > peak) peak = v.abs();
      }
      expect(peak, lessThanOrEqualTo(1.0)); // no overshoot clipping downstream
    });
  });
}
