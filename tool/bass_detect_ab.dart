// tool/bass_detect_ab.dart
//
// Measures the harmonic-sum bass finder (BB-H1).
//
//   dart run tool/bass_detect_ab.dart
//
// The claim being tested is that we can name the LOWEST sounding note, which a
// chromagram structurally cannot do — it folds away the octave, so `C` and `C/E`
// are the same twelve numbers and `C6` and `Am7` are the same four pitch classes.
//
// It is measured rather than asserted because the physics are against the naive
// approach: at 44.1 kHz a 4096-point FFT has 10.77 Hz bins and a semitone at C3
// spans 7.8 Hz, so below ~G3 the transform cannot separate adjacent semitones at
// all. The finder therefore scores candidates by harmonic summation instead.
// Whether that actually works is an empirical question.

// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/chroma_analysis.dart';
import 'package:comet_beat/core/audio/synth.dart' show renderSegments;

int _windowSize = 4096;
double _freq(int midi) => 440.0 * math.pow(2.0, (midi - 69) / 12.0);

Float64List _window(List<int> midis) {
  final samples = renderSegments([(freqs: midis.map(_freq).toList(), ms: 600)]);
  final start = (samples.length - _windowSize) ~/ 2;
  final out = Float64List(_windowSize);
  for (var i = 0; i < _windowSize; i++) {
    out[i] = samples[start + i] / 32768.0;
  }
  return out;
}

const _names = [
  'C',
  'C#',
  'D',
  'Eb',
  'E',
  'F',
  'F#',
  'G',
  'Ab',
  'A',
  'Bb',
  'B',
];

void main(List<String> args) {
  // The decisive experiment: does a longer window make bass detection possible
  // at all? 4096 samples cannot resolve a semitone below F#3, so any per-semitone
  // decision under that is noise no matter how it is scored.
  for (final w in [4096, 8192, 16384]) {
    _windowSize = w;
    stdout.writeln('\n########## window $w '
        '(${(1000 * w / 44100).toStringAsFixed(0)} ms, '
        '${(44100 / w).toStringAsFixed(2)} Hz bins) ##########');
    _run();
  }
}

void _run() {
  final d = ChordDetector();

  // Root position: the bass IS the root, across the whole bass register.
  var hit = 0, miss = 0, unknown = 0;
  final missesByRegister = <String, int>{};
  for (var midi = 36; midi <= 60; midi++) {
    for (final iv in const [
      [0, 4, 7],
      [0, 3, 7],
      [0, 4, 7, 10],
      [0, 3, 7, 10],
    ]) {
      final notes = [for (final i in iv) midi + i];
      final got = d.analyze(_window(notes)).bassPc;
      final want = midi % 12;
      if (got == null) {
        unknown++;
      } else if (got == want) {
        hit++;
      } else {
        miss++;
        final oct = midi < 48 ? 'below C3' : 'C3 and up';
        missesByRegister[oct] = (missesByRegister[oct] ?? 0) + 1;
      }
    }
  }
  final total = hit + miss + unknown;
  stdout.writeln('=== root position, bass = root (midi 36..60) ===');
  stdout.writeln('  correct ${(100 * hit / total).toStringAsFixed(1)}%  '
      'wrong ${(100 * miss / total).toStringAsFixed(1)}%  '
      'unknown ${(100 * unknown / total).toStringAsFixed(1)}%  (n=$total)');
  if (missesByRegister.isNotEmpty) {
    stdout.writeln('  wrong by register: $missesByRegister');
  }

  // Inversions: the bass is NOT the root. This is the case chroma cannot see.
  stdout.writeln('\n=== inversions — the case a chromagram is blind to ===');
  var invHit = 0, invTotal = 0;
  for (var root = 48; root < 60; root++) {
    for (final iv in const [
      [0, 4, 7],
      [0, 3, 7],
      [0, 4, 7, 10],
    ]) {
      for (var rot = 1; rot < iv.length; rot++) {
        final notes = <int>[
          for (var k = rot; k < iv.length; k++) root + iv[k],
          for (var k = 0; k < rot; k++) root + iv[k] + 12,
        ]..sort();
        final want = notes.first % 12;
        final got = d.analyze(_window(notes)).bassPc;
        invTotal++;
        if (got == want) invHit++;
      }
    }
  }
  stdout.writeln('  bass correct on inversions: '
      '${(100 * invHit / invTotal).toStringAsFixed(1)}%  (n=$invTotal)');

  // The headline collision: same four pitch classes, different bass.
  stdout
      .writeln('\n=== the C6 / Am7 collision (identical pitch-class sets) ===');
  for (final (label, notes) in [
    ('C6  (C in the bass)  C3 E3 G3 A3', [48, 52, 55, 57]),
    ('Am7 (A in the bass)  A2 C3 E3 G3', [45, 48, 52, 55]),
    ('Cm6 (C in the bass)  C3 Eb3 G3 A3', [48, 51, 55, 57]),
    ('Am7b5 (A in the bass) A2 C3 Eb3 G3', [45, 48, 51, 55]),
  ]) {
    final r = d.analyze(_window(notes));
    final bass = r.bassPc == null ? '?' : _names[r.bassPc!];
    final named = r.hasChord ? r.candidates.first.toString() : 'none';
    stdout.writeln('  ${label.padRight(34)} bass=${bass.padRight(3)} '
        'chroma says: $named');
  }
}
