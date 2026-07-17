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

import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/audio/mod/module_doc.dart';
import 'package:klang_universum/core/audio/mod/module_instrument_bridge.dart';
import 'package:klang_universum/core/audio/pitch_analysis.dart';
import 'package:klang_universum/core/audio/tracker_engine.dart';

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
        throwsArgumentError, // parseAnyModule rejects unknown format
      );
    });
  });
}
