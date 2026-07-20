// Piano transcription (Kong regression model): a fast decode-parity test against
// the package's own RegressionPostProcessor, plus a model-gated end-to-end +
// runtime-parity check against onnxruntime. The e2e tests skip when the ~99 MB
// ONNX isn't cached (set COMET_PIANO_DIR).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/piano.dart';
import 'package:comet_beat/core/audio/transcription/piano_model_store.dart';
import 'package:comet_beat/core/audio/transcription/route.dart'
    show NeuralTranscriber;
import 'package:flutter_test/flutter_test.dart';

const String _dir = 'test/transcription';
const int _sr = 16000;

Float64List readBin64(String path) {
  final bd = ByteData.sublistView(File(path).readAsBytesSync());
  final count = bd.getInt32(0, Endian.little);
  final out = Float64List(count);
  for (var i = 0; i < count; i++) {
    out[i] = bd.getFloat32(4 + i * 4, Endian.little);
  }
  return out;
}

Float32List readBin32(String path) {
  final bd = ByteData.sublistView(File(path).readAsBytesSync());
  final count = bd.getInt32(0, Endian.little);
  final out = Float32List(count);
  for (var i = 0; i < count; i++) {
    out[i] = bd.getFloat32(4 + i * 4, Endian.little);
  }
  return out;
}

/// The exact deterministic synthetic input the reference oracle used.
Float64List synthInput(int n) {
  final x = Float64List(n);
  for (final (start, f0, dur) in [(0, 261.63, 1.2), (_sr, 329.63, 1.0)]) {
    for (var i = 0; i < n; i++) {
      final tt = (i - start) / _sr;
      if (tt >= 0 && tt < dur) {
        final env = math.exp(-3.0 * tt);
        var s = 0.0;
        for (var h = 1; h < 5; h++) {
          s += (1.0 / h) * math.sin(2 * math.pi * f0 * h * tt);
        }
        x[i] += 0.5 * env * s;
      }
    }
  }
  return x;
}

void main() {
  group('Piano decode (RegressionPostProcessor, no model)', () {
    test('matches the Kong reference on a crafted output_dict', () {
      final heads = (
        onset: readBin64('$_dir/piano_decode_onset.bin'),
        offset: readBin64('$_dir/piano_decode_offset.bin'),
        frame: readBin64('$_dir/piano_decode_frame.bin'),
        velocity: readBin64('$_dir/piano_decode_velocity.bin'),
        frames: 256,
      );
      final events = decodePianoHeads(heads);

      final ref = (jsonDecode(
        File('$_dir/piano_decode_events.json').readAsStringSync(),
      ) as Map<String, dynamic>)['events'] as List;

      expect(events.length, ref.length, reason: 'event count');
      for (var i = 0; i < ref.length; i++) {
        final r = ref[i] as Map<String, dynamic>;
        expect(events[i].midi, r['midi'], reason: 'midi[$i]');
        expect(events[i].onMs, closeTo((r['onMs'] as num).toDouble(), 0.5));
        expect(events[i].offMs, closeTo((r['offMs'] as num).toDouble(), 0.5));
        expect(pianoMidiVelocity(events[i]), r['vel'], reason: 'vel[$i]');
      }
    });
  });

  group('Piano deframe (multi-segment stitch, no model)', () {
    for (final n in [2, 3]) {
      test('$n segments stitch like Kong deframe', () {
        const segFrames = 101, classes = 88;
        final flat = readBin32('$_dir/piano_deframe_in_$n.bin');
        // Split into n segments (each [segFrames×88]); repeat into all 4 heads.
        final perSeg = <List<Float32List>>[];
        for (var s = 0; s < n; s++) {
          final seg = Float32List.sublistView(
            flat,
            s * segFrames * classes,
            (s + 1) * segFrames * classes,
          );
          perSeg.add([seg, seg, seg, seg]);
        }
        final heads = pianoDeframeSegments(perSeg);
        final ref = readBin32('$_dir/piano_deframe_out_$n.bin');
        expect(heads.frames * classes, ref.length, reason: 'deframed length');
        for (final head in [heads.onset, heads.offset, heads.frame]) {
          for (var i = 0; i < ref.length; i++) {
            expect(head[i], ref[i], reason: 'deframe[$i]');
          }
        }
      });
    }
  });

  group('Piano end-to-end (model-gated)', () {
    test(
      'runtime parity + events match onnxruntime',
      () async {
        OnnxPianoModel? bundle;
        try {
          bundle = await PianoModelStore().load();
        } catch (_) {
          // ignore: avoid_print
          print('SKIP: piano model unavailable.');
          return;
        }
        final audio = synthInput((_sr * 2.5).toInt());
        final events = await pianoTranscribe(audio, model: bundle.model);

        // 1) Runtime parity: the first segment's first 100 frames vs onnxruntime.
        final heads = pianoHeadsForTest(audio, bundle.model);
        for (final name in ['reg_onset', 'reg_offset', 'frame', 'velocity']) {
          final ref = readBin32('$_dir/piano_e2e_${name}_crop.bin');
          final got = heads[name]!;
          var dot = 0.0, ng = 0.0, nr = 0.0;
          for (var i = 0; i < ref.length; i++) {
            dot += got[i] * ref[i];
            ng += got[i] * got[i];
            nr += ref[i] * ref[i];
          }
          final cos = dot / (math.sqrt(ng) * math.sqrt(nr) + 1e-30);
          expect(cos, greaterThan(0.9999), reason: '$name runtime cos=$cos');
        }

        // 2) End-to-end events vs the Python pipeline.
        final ref = (jsonDecode(
          File('$_dir/piano_e2e_events.json').readAsStringSync(),
        ) as Map<String, dynamic>)['events'] as List;
        expect(events.length, ref.length, reason: 'e2e event count');
        for (var i = 0; i < ref.length; i++) {
          final r = ref[i] as Map<String, dynamic>;
          expect(events[i].midi, r['midi'], reason: 'e2e midi[$i]');
          expect(events[i].onMs, closeTo((r['onMs'] as num).toDouble(), 15.0));
          expect(pianoMidiVelocity(events[i]), closeTo(r['vel'] as num, 2));
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'concurrent transcriber (parallel-isolate segments) == reference',
      () async {
        final NeuralTranscriber transcribe;
        try {
          transcribe = await PianoModelStore().transcriber(concurrent: true);
        } catch (_) {
          // ignore: avoid_print
          print('SKIP: piano model unavailable.');
          return;
        }
        final audio = synthInput((_sr * 2.5).toInt());
        final events = await transcribe(audio, _sr);
        final ref = (jsonDecode(
          File('$_dir/piano_e2e_events.json').readAsStringSync(),
        ) as Map<String, dynamic>)['events'] as List;
        expect(events.length, ref.length, reason: 'concurrent event count');
        for (var i = 0; i < ref.length; i++) {
          final r = ref[i] as Map<String, dynamic>;
          expect(events[i].midi, r['midi'], reason: 'concurrent midi[$i]');
          expect(events[i].onMs, closeTo((r['onMs'] as num).toDouble(), 15.0));
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
