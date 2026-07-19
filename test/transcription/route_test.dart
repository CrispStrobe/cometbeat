// N1 — the auto-router. The probe must separate "monophonic & tonal" (→ the
// pure-Dart chain) from "polyphonic / inharmonic / percussive" (→ neural), and
// transcribeAuto must honour that, fall back to monophonic when no neural engine
// is injected (the web contract), and respect a forced override.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/route.dart';
import 'package:flutter_test/flutter_test.dart';

const _sr = 44100;
double _hz(int midi) => 440 * pow(2, (midi - 69) / 12).toDouble();

// A sum of pitches. Pass one midi for a monophonic tone, several for a chord.
// [rich] adds harmonics so a single note looks like a real instrument, not a
// bare sine (its overtones are still integer multiples → high harmonicity).
Float64List _tone(List<int> midis, {double seconds = 1.2, bool rich = false}) {
  final n = (seconds * _sr).round();
  final out = Float64List(n);
  for (final m in midis) {
    final f = _hz(m);
    final partials = rich ? 5 : 1;
    for (var h = 1; h <= partials; h++) {
      final amp = 0.4 / h / midis.length;
      for (var i = 0; i < n; i++) {
        out[i] += amp * sin(2 * pi * f * h * i / _sr);
      }
    }
  }
  return out;
}

Float64List _noise({double seconds = 1.2}) {
  final n = (seconds * _sr).round();
  final out = Float64List(n);
  var seed = 12345;
  for (var i = 0; i < n; i++) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    out[i] = (seed / 0x7fffffff) * 2 - 1;
  }
  return out;
}

void main() {
  test('a monophonic tone probes as harmonic → prefer monophonic', () {
    final p = probeInput(_tone([69], rich: true));
    expect(p.harmonicity, greaterThan(0.55));
    expect(p.preferNeural, isFalse);
  });

  test('a bare sine is also clearly monophonic', () {
    expect(probeInput(_tone([60])).preferNeural, isFalse);
  });

  test('a chord (triad) probes as non-harmonic → prefer neural', () {
    // C-E-G: E and G fall between C's harmonics, so harmonicity drops.
    final p = probeInput(_tone([60, 64, 67], rich: true));
    expect(p.harmonicity, lessThan(0.55));
    expect(p.preferNeural, isTrue);
  });

  test('broadband noise (percussive) prefers neural', () {
    expect(probeInput(_noise()).preferNeural, isTrue);
  });

  test('transcribeAuto falls back to monophonic when no neural is injected',
      () async {
    // Even a chord routes to the monophonic chain if there is no neural engine —
    // the web / no-model contract. It still returns notes, never throws.
    final r = await transcribeAuto(_tone([60, 64, 67], rich: true));
    expect(r.engine, TranscriptionEngine.monophonic);
    expect(
      r.probe.preferNeural,
      isTrue,
    ); // it WANTED neural, but none available
  });

  test('transcribeAuto uses the neural engine when the probe prefers it',
      () async {
    var called = false;
    Future<List<NoteEvent>> fakeNeural(Float64List mono, int sr) async {
      called = true;
      return [(midi: 60, onMs: 0, offMs: 500, confidence: 1)];
    }

    final r = await transcribeAuto(
      _tone([60, 64, 67], rich: true),
      neural: fakeNeural,
    );
    expect(called, isTrue);
    expect(r.engine, TranscriptionEngine.neural);
    expect(r.notes.single.midi, 60);
  });

  test('a monophonic input does NOT call the neural engine even if available',
      () async {
    var called = false;
    Future<List<NoteEvent>> fakeNeural(Float64List mono, int sr) async {
      called = true;
      return const [];
    }

    final r = await transcribeAuto(_tone([67], rich: true), neural: fakeNeural);
    expect(called, isFalse);
    expect(r.engine, TranscriptionEngine.monophonic);
  });

  test('forceEngine overrides the probe', () async {
    var called = false;
    Future<List<NoteEvent>> fakeNeural(Float64List mono, int sr) async {
      called = true;
      return const [];
    }

    // Force neural on a monophonic tone.
    final r = await transcribeAuto(
      _tone([67], rich: true),
      neural: fakeNeural,
      forceEngine: TranscriptionEngine.neural,
    );
    expect(called, isTrue);
    expect(r.engine, TranscriptionEngine.neural);
  });
}
