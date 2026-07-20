// W-HARMONY end-to-end (model-gated): the full pipeline — audio → Dart CQT →
// BTC ONNX → chord events — on a synthesized, harmonically-rich chord. Skips if
// the model can't be provisioned (offline).
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/harmony.dart';
import 'package:comet_beat/core/audio/transcription/harmony_model_store.dart';
import 'package:comet_beat/core/audio/transcription/model_license.dart';
import 'package:flutter_test/flutter_test.dart';

const _sr = 22050;

// A harmonically-rich note (a few harmonics) — BTC ignores pure sines.
double _note(int midi, double tSec, {int nh = 6}) {
  final f = 440 * pow(2, (midi - 69) / 12.0);
  var s = 0.0;
  for (var k = 1; k <= nh; k++) {
    s += (1.0 / k) * sin(2 * pi * k * f * tSec);
  }
  return s;
}

/// A sustained triad (root octave-doubled bass + [0,4,7]/[0,3,7]) of [seconds].
Float64List _triad(int root, bool major, double seconds) {
  final ints = major ? const [0, 4, 7] : const [0, 3, 7];
  final n = (seconds * _sr).round();
  final y = Float64List(n);
  for (var i = 0; i < n; i++) {
    final t = i / _sr;
    var s = _note(root - 12, t, nh: 3) * 0.7; // bass
    for (final iv in ints) {
      s += _note(root + iv, t);
    }
    y[i] = s / 6;
  }
  var peak = 0.0;
  for (final v in y) {
    if (v.abs() > peak) peak = v.abs();
  }
  if (peak > 0) {
    for (var i = 0; i < y.length; i++) {
      y[i] /= peak;
    }
  }
  return y;
}

Future<HarmonyBundle?> _tryBundle() async {
  // The BTC weights are CC-BY-NC-SA (non-commercial) — the store is gated; the
  // test consents so it can exercise the model.
  acceptModelLicense(HarmonyModelStore.licenseSpdx);
  try {
    return await HarmonyModelStore().load(); // downloads on first run
  } catch (_) {
    return null;
  }
}

void main() {
  test(
    'a sustained C major triad is recognised as C',
    () async {
      final bundle = await _tryBundle();
      if (bundle == null) {
        // ignore: avoid_print
        print('SKIP: BTC model unavailable (offline) — skipping.');
        return;
      }
      // 12 s → >108 frames (a full BTC segment).
      final audio = _triad(48, true, 12); // C3-rooted C major
      final chords = estimateChords(
        audio,
        model: bundle.model,
        cqt: bundle.cqt,
        sampleRate: _sr,
        keepNoChord: true,
      );
      final det = chords.map((c) => '${c.label}@${c.onMs.round()}').toList();
      // ignore: avoid_print
      print('detected: $det');
      expect(chords, isNotEmpty);

      // Total time per label; the dominant non-N chord should be C.
      final byLabel = <String, double>{};
      for (final c in chords) {
        byLabel[c.label] = (byLabel[c.label] ?? 0) + (c.offMs - c.onMs);
      }
      final ranked = byLabel.entries.where((e) => e.key != 'N').toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      // ignore: avoid_print
      print('by-label ms: $byLabel');
      expect(ranked, isNotEmpty, reason: 'no non-N chord detected');
      expect(ranked.first.key, 'C', reason: 'dominant chord should be C');
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
