// S3 — tuning estimation. A performance a known number of cents off A440 is
// recovered from its F0 track, and feeding the corrected reference back into the
// note-HMM snaps a de-tuned melody onto the right notes. Synthetic sines we
// control; the real mistuned-singer case is the bin/listen.dart --transcribe
// demo that motivated this slice.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/note_hmm.dart';
import 'package:comet_beat/core/audio/transcription/pyin.dart';
import 'package:comet_beat/core/audio/transcription/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

import 'note_metrics.dart';

const _sr = 44100;

// A4-referenced MIDI, then detuned by [offsetCents] (sharp = positive).
double _hz(int midi, double offsetCents) =>
    440 * pow(2, (midi - 69) / 12 + offsetCents / 1200).toDouble();

Float64List _tone(double hz, double seconds) {
  final n = (seconds * _sr).round();
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = 0.5 * sin(2 * pi * hz * i / _sr);
  }
  return out;
}

Float64List _melody(List<int> midis, double offsetCents) {
  final parts = <Float64List>[];
  for (final m in midis) {
    parts.add(_tone(_hz(m, offsetCents), 0.4));
    parts.add(Float64List((0.08 * _sr).round())); // rest
  }
  final total = parts.fold<int>(0, (s, p) => s + p.length);
  final out = Float64List(total);
  var off = 0;
  for (final p in parts) {
    out.setAll(off, p);
    off += p.length;
  }
  return out;
}

void main() {
  test('a perfectly tuned track reports ~0 cents', () {
    final track = pyinF0(_melody(const [60, 62, 64, 65, 67], 0));
    expect(estimateTuningCents(track).abs(), lessThan(6));
  });

  test('a known offset is recovered to within a few cents', () {
    for (final offset in const [-40.0, -20.0, 15.0, 35.0]) {
      final track = pyinF0(_melody(const [60, 62, 64, 67, 69], offset));
      final est = estimateTuningCents(track);
      expect(
        (est - offset).abs(),
        lessThan(8),
        reason: 'offset $offset → estimated $est',
      );
    }
  });

  test('the estimate is CIRCULAR — a −45c take is not confused with +55c', () {
    final track = pyinF0(_melody(const [60, 64, 67], -45));
    final est = estimateTuningCents(track);
    expect(est, lessThan(0)); // stays near −45, does not wrap to +55
    expect((est - -45).abs(), lessThan(8));
  });

  test('correcting the reference fixes a de-tuned transcription', () {
    // 40 cents flat: on the rigid A440 grid the notes smear to wrong neighbours;
    // with the estimated reference they snap back to C D E F G.
    const song = [60, 62, 64, 65, 67];
    final track = pyinF0(_melody(song, -40));
    final ref = tunedReference(track);
    expect((ref - 440 * pow(2, -40 / 1200)).abs(), lessThan(2));

    final tuned = segmentNotes(track, a4: ref);
    // 400 ms note + 80 ms rest ⇒ 480 ms between onsets.
    final expected = notes([
      for (var i = 0; i < song.length; i++)
        (song[i], i * 480.0, i * 480.0 + 400),
    ]);
    // The whole point: with the estimated reference the pitch classes snap back.
    expect(
        [for (final n in tuned) n.midi % 12], song.map((m) => m % 12).toList());
    expect(notePrf(expected, tuned, onsetTolMs: 200, pitchTol: 0).f,
        greaterThanOrEqualTo(0.9));
  });

  test('silence yields a safe zero', () {
    expect(estimateTuningCents(pyinF0(Float64List(_sr))), 0);
    expect(estimateTuningCents(const []), 0);
  });
}
