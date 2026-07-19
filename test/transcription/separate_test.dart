// W-SEP adapter shell. The pure DSP — overlap-add reconstruction (the seamless
// segment join), per-segment normalisation, and wiring the resulting stems
// through transcribeStems into a multi-part score — is tested WITHOUT the model.
// A model-gated block runs real HTDemucs inference once the ONNX lands.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/separate.dart';
import 'package:comet_beat/core/audio/transcription/separate_model_store.dart';
import 'package:comet_beat/core/audio/transcription/stems.dart';
import 'package:flutter_test/flutter_test.dart';

Float64List _sine(int n, double hz, {int sr = 44100}) {
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = math.sin(2 * math.pi * hz * i / sr);
  }
  return out;
}

// Split [sig] into overlapping segments starting every [hop] for [seg] samples.
(List<Float64List>, List<int>) _chop(Float64List sig, int seg, int hop) {
  final segs = <Float64List>[];
  final starts = <int>[];
  for (var s = 0; s < sig.length; s += hop) {
    final len = math.min(seg, sig.length - s);
    segs.add(Float64List.sublistView(sig, s, s + len));
    starts.add(s);
    if (s + len >= sig.length) break;
  }
  return (segs, starts);
}

void main() {
  group('overlapAdd (seamless segment join)', () {
    test('overlapping identity segments reconstruct the original signal', () {
      final sig = _sine(4000, 220);
      final (segs, starts) = _chop(sig, 1000, 750); // 25% overlap
      final out = overlapAdd(segs, starts, sig.length);
      var maxErr = 0.0;
      for (var i = 0; i < sig.length; i++) {
        maxErr = math.max(maxErr, (out[i] - sig[i]).abs());
      }
      expect(maxErr, lessThan(1e-9), reason: 'triangular OLA is exact for id');
    });

    test('a single full-length segment passes through unchanged', () {
      final sig = _sine(2048, 440);
      final out = overlapAdd([sig], const [0], sig.length);
      for (var i = 0; i < sig.length; i++) {
        expect(out[i], closeTo(sig[i], 1e-9));
      }
    });
  });

  group('normalizeSegment', () {
    test('normalises to ~zero-mean/unit-std and round-trips', () {
      final audio = Float64List(1024);
      for (var i = 0; i < 1024; i++) {
        audio[i] = 5 + 3 * math.sin(2 * math.pi * 7 * i / 1024);
      }
      final n = normalizeSegment(audio, 0, 1024);
      var mean = 0.0;
      for (final v in n.data) {
        mean += v;
      }
      mean /= 1024;
      expect(mean.abs(), lessThan(1e-4));
      // Re-applying std/mean recovers the original.
      for (var i = 0; i < 1024; i++) {
        expect(n.data[i] * n.std + n.mean, closeTo(audio[i], 1e-6));
      }
    });
  });

  test('the separator wires into transcribeStems → a multi-part score',
      () async {
    // Stand in for HTDemucs: split the mix into a high "vocal" + a low "bass"
    // line. Proves separate → stems → assembly end-to-end (no ONNX needed).
    Future<Stems> fakeSeparator(Float64List mono, int sr) async => (
          vocals: _sine(sr, 660), // ~E5
          bass: _sine(sr, 82), // ~E2
          drums: null,
          other: null,
        );
    final r = await transcribeSong(
      Float64List(44100),
      separator: fakeSeparator,
    );
    expect(r.partNames, containsAll(['Vocals', 'Bass']));
    expect(r.score, isNotNull);
  });

  // Completed once the worker publishes the ONNX (skip-if-absent, no-op in CI).
  test('model-gated: HTDemucs splits a mix into four stems', () async {
    final store = DemucsModelStore();
    if (!store.isPresent()) {
      return; // no model yet — the pure DSP above is the lock.
    }
    final model = await store.load();
    final mix = _sine(44100, 220);
    final stems = await demucsSeparate(mix, model: model);
    expect(stems.drums, isNotNull);
    expect(stems.vocals, isNotNull);
    expect(stems.drums!.length, mix.length);
  });
}
