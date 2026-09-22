// test/transcription/basic_pitch_test.dart
//
// Worker 3 (Basic Pitch, polyphonic) tests. Two tiers:
//  • UNIT — the note decoder on a hand-built posteriorgram (no model, fully
//    deterministic): the core lockable behaviour.
//  • LIVE — the whole pipeline through the ONNX model on a synthetic C-major
//    triad; gated skip-if-absent so CI without the model (or offline) stays
//    green. Scored with the shared note_metrics ruler.
//
// Real-recording validation is a documented CLI demo (see bin/transcribe.dart
// and the commit message), not bundled — CI has no network and we don't ship
// audio.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/audio/transcription/basic_pitch.dart';
import 'package:comet_beat/core/audio/transcription/basic_pitch_model_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'note_metrics.dart';

const _nBins = 88;

/// Peak-normalise to ±0.9 (a loaded WAV is already in ±1; the additive synth is
/// not — Basic Pitch expects audio in that range).
Float64List _normalize(Float64List x) {
  var peak = 0.0;
  for (final v in x) {
    if (v.abs() > peak) peak = v.abs();
  }
  if (peak == 0) return x;
  final out = Float64List(x.length);
  for (var i = 0; i < x.length; i++) {
    out[i] = x[i] / peak * 0.9;
  }
  return out;
}

/// Build a `(frames, onsets)` posteriorgram of [nFrames] × 88 with a note at
/// each `(midi, startFrame, lenFrames)`: an onset spike at `startFrame` and
/// sustained frame energy over its length.
(List<Float64List>, List<Float64List>) _grid(
  int nFrames,
  List<(int midi, int start, int len)> spec,
) {
  final frames = [for (var t = 0; t < nFrames; t++) Float64List(_nBins)];
  final onsets = [for (var t = 0; t < nFrames; t++) Float64List(_nBins)];
  for (final (midi, start, len) in spec) {
    final b = midi - 21; // MIDI_OFFSET
    onsets[start][b] = 0.9; // a strict local max ≥ onset threshold
    for (var t = start; t < start + len && t < nFrames; t++) {
      frames[t][b] = 0.8;
    }
  }
  return (frames, onsets);
}

void main() {
  group('note decoder (unit — no model, deterministic)', () {
    test('a 3-note posteriorgram → the 3 correct notes', () {
      // C4/E4/G4 (MIDI 60/64/67), onset at frame 5, ~25 frames long.
      final (frames, onsets) = _grid(50, [
        (60, 5, 25),
        (64, 5, 25),
        (67, 5, 25),
      ]);
      final result = notesFromPosteriorgrams(
        frames,
        onsets,
        inferOnsets: false,
      );
      expect(result.length, 3);
      expect(result.map((n) => n.midi).toList()..sort(), [60, 64, 67]);
      // Frame 5 ≈ 58 ms, frame 30 ≈ 348 ms.
      for (final n in result) {
        expect(n.onMs, closeTo(_frameMs(5), 1));
        expect(n.offMs, greaterThan(n.onMs + 200));
        expect(n.confidence, closeTo(0.8, 0.01));
      }
      final gt = notes([(60, 58, 348), (64, 58, 348), (67, 58, 348)]);
      expect(notePrf(gt, result).f, 1.0);
    });

    test('notes shorter than the minimum are dropped', () {
      final (frames, onsets) = _grid(30, [(60, 5, 6)]); // 6 < min 11
      expect(
        notesFromPosteriorgrams(frames, onsets, inferOnsets: false),
        isEmpty,
      );
    });

    test('empty / too-short input is safe', () {
      expect(notesFromPosteriorgrams(const [], const []), isEmpty);
      expect(
        notesFromPosteriorgrams([Float64List(_nBins)], [Float64List(_nBins)]),
        isEmpty,
      );
    });

    // Differential test against the canonical Python implementation: the same
    // posteriorgram fed to Spotify basic_pitch `output_to_notes_polyphonic`
    // (test/transcription/basic_pitch_ref.json) must yield the SAME notes —
    // exercising the normal-onset, inferred-onset, and melodia-trick paths.
    test('note decoder matches the Python basic_pitch reference exactly', () {
      final ref = jsonDecode(
        File('test/transcription/basic_pitch_ref.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      List<Float64List> grid(String k) => [
            for (final r in ref[k] as List)
              Float64List.fromList(
                [for (final x in r as List) (x as num).toDouble()],
              ),
          ];
      final result = notesFromPosteriorgrams(
        grid('frames'),
        grid('onsets'),
        melodiaTrick: true,
      );
      // Reference notes are (startFrame, endFrame, midi, amp); compare
      // (startFrame, endFrame, midi) — recover frames from the ms mapping.
      int frame(double ms) => (ms * 22050 / 256 / 1000).round();
      final got = [
        for (final n in result) '${frame(n.onMs)},${frame(n.offMs)},${n.midi}',
      ]..sort();
      final want = [
        for (final e in ref['notes'] as List) '${e[0]},${e[1]},${e[2]}',
      ]..sort();
      expect(got, want);
    });
  });

  group('end-to-end (live — needs the ONNX model)', () {
    test(
      'a synthetic C-major triad → C/E/G, note-F ≥ 0.9',
      () async {
        final store = BasicPitchModelStore();
        final file = await store.ensureFile();
        if (file == null) {
          markTestSkipped(
            'Basic Pitch model unavailable (offline) — skipping.',
          );
          return;
        }
        final model = await store.load();
        // 1.5 s C-major triad (C4 E4 G4) — a near-sine flute timbre so the
        // additive harmonics don't spawn octave ghosts; normalised to ±0.9.
        final audio = _normalize(
          renderSegmentsRaw(
            const [
              (freqs: [261.63, 329.63, 392.00], ms: 1500),
            ],
            timbre: timbreFor(Instrument.flute),
          ),
        );
        final result = basicPitchTranscribe(
          audio,
          model: model,
          frameThreshold: 0.4,
          melodiaTrick:
              true, // struck-together notes share one onset; fill them
        );
        final gt = notes([(60, 0, 1500), (64, 0, 1500), (67, 0, 1500)]);
        final prf = notePrf(gt, result, onsetTolMs: 120);
        // ignore: avoid_print
        print('triad: detected ${result.map((n) => n.midi).toList()}  $prf');
        expect(prf.f, greaterThanOrEqualTo(0.9));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    // The isolate GEMM pool splits each Conv/MatMul by output band and
    // concatenates the bands — a pure SCHEDULING change. So the pooled path is
    // not "close enough", it is exactly equal, and anything else is a bug in
    // the partitioning rather than a precision tradeoff worth accepting. This
    // test is the standing guard on that claim; it is what licenses
    // `BasicPitchModelStore.transcriber()` to be the default native path.
    test(
      'pooled transcribe == synchronous transcribe, element for element',
      () async {
        final store = BasicPitchModelStore();
        if (await store.ensureFile() == null) {
          markTestSkipped(
            'Basic Pitch model unavailable (offline) — skipping.',
          );
          return;
        }
        final audio = _normalize(
          renderSegmentsRaw(
            const [
              (freqs: [261.63, 329.63, 392.00], ms: 900),
              (freqs: [293.66, 349.23, 440.00], ms: 900),
            ],
            timbre: timbreFor(Instrument.flute),
          ),
        );

        // Two separate OnnxModel instances, so the pooled arm cannot be
        // accidentally reading state the sync arm left behind.
        final plain = await BasicPitchModelStore().load();
        final sync = basicPitchTranscribe(audio, model: plain);

        final pooledModel = await BasicPitchModelStore().load();
        await pooledModel.parallelize(workers: 2, poolConv: true);
        final pooled =
            await basicPitchTranscribeAsync(audio, model: pooledModel);
        pooledModel.dispose();

        expect(pooled.length, sync.length);
        for (var i = 0; i < sync.length; i++) {
          expect(pooled[i].midi, sync[i].midi, reason: 'note $i midi');
          expect(pooled[i].onMs, sync[i].onMs, reason: 'note $i onMs');
          expect(pooled[i].offMs, sync[i].offMs, reason: 'note $i offMs');
          expect(
            pooled[i].confidence,
            sync[i].confidence,
            reason: 'note $i confidence',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}

double _frameMs(int f) => f * 256 / 22050 * 1000;
