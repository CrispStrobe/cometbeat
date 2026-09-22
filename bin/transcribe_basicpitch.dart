// bin/transcribe_basicpitch.dart
//
// CLI demo for the Worker 3 polyphonic transcriber: a WAV file → Basic Pitch
// notes, printed as a table (and optionally a hand-labelled note-F score).
// Pure Dart — runs the ONNX model on onnx_runtime_dart, no Flutter needed.
//
//   dart run bin/transcribe_basicpitch.dart path/to/audio.wav
//       [--onset 0.5] [--frame 0.3] [--min-len 11] [--melodia] [--json]
//       [--workers N]
//
// `--workers N` selects the inference path, and is the A/B knob the pooling
// benchmark drives (one arm per process — see docs/BASIC_PITCH_POOL_AB.md):
//   N < 0  (default) — autoPoolWorkers(), i.e. what the app itself does
//   N = 0            — the synchronous, web-safe basicPitchTranscribe
//   N > 0            — parallelize(workers: N, poolConv: true) + runAsync
// The notes are identical on every setting; only the wall clock differs.
//
// Convert anything to the expected format first, e.g.
//   ffmpeg -i in.ogg -ac 1 -ar 44100 -c:a pcm_s16le out.wav
//
// The Apache-2.0 Basic Pitch model is downloaded on first run (see
// BasicPitchModelStore); attribution ships next to it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:comet_beat/core/audio/transcription/basic_pitch.dart';
import 'package:comet_beat/core/audio/transcription/basic_pitch_model_store.dart';
import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/crepe_model_store.dart'
    show autoPoolWorkers;
import 'package:comet_beat/core/audio/wav_io.dart';

const _names = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];
String _noteName(int midi) => '${_names[midi % 12]}${midi ~/ 12 - 1}';

double _optD(List<String> a, String f, double d) {
  final i = a.indexOf(f);
  return i >= 0 && i + 1 < a.length ? double.parse(a[i + 1]) : d;
}

int _optI(List<String> a, String f, int d) {
  final i = a.indexOf(f);
  return i >= 0 && i + 1 < a.length ? int.parse(a[i + 1]) : d;
}

Future<void> main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.isEmpty) {
    stderr.writeln('usage: dart run bin/transcribe_basicpitch.dart audio.wav '
        '[--onset 0.5] [--frame 0.3] [--min-len 11] [--melodia] [--json] '
        '[--workers N]');
    exit(64);
  }
  final path = positional.first;
  if (!File(path).existsSync()) {
    stderr.writeln('no such file: $path');
    exit(66);
  }

  final wav = readWavPcm16(File(path).readAsBytesSync());
  final mono = wavToMonoFloat(wav);
  stderr.writeln('loaded $path — ${wav.sampleRate} Hz, ${wav.channels}ch, '
      '${(mono.length / wav.sampleRate).toStringAsFixed(2)} s');

  final model = await BasicPitchModelStore().load();
  final requested = _optI(args, '--workers', -1);
  final workers = requested < 0 ? autoPoolWorkers() : requested;
  if (workers > 0) {
    await model.parallelize(workers: workers, poolConv: true);
  }
  stderr.writeln(
    workers > 0
        ? 'inference: isolate pool, $workers workers (poolConv)'
        : 'inference: single isolate (synchronous)',
  );

  final sw = Stopwatch()..start();
  final List<NoteEvent> events = workers > 0
      ? await basicPitchTranscribeAsync(
          mono,
          model: model,
          sampleRate: wav.sampleRate,
          onsetThreshold: _optD(args, '--onset', 0.5),
          frameThreshold: _optD(args, '--frame', 0.3),
          minNoteLenFrames: _optI(args, '--min-len', 11),
          melodiaTrick: args.contains('--melodia'),
        )
      : basicPitchTranscribe(
          mono,
          model: model,
          sampleRate: wav.sampleRate,
          onsetThreshold: _optD(args, '--onset', 0.5),
          frameThreshold: _optD(args, '--frame', 0.3),
          minNoteLenFrames: _optI(args, '--min-len', 11),
          melodiaTrick: args.contains('--melodia'),
        );
  sw.stop();
  model.dispose();
  // Machine-readable on stderr in every mode, so the A/B harness can read the
  // timing from the same run it reads the notes from.
  stderr.writeln('elapsed_ms ${sw.elapsedMilliseconds}');

  if (args.contains('--json')) {
    stdout.writeln(
      jsonEncode([
        for (final n in events)
          {
            'midi': n.midi,
            'name': _noteName(n.midi),
            'onMs': n.onMs,
            'offMs': n.offMs,
            'confidence': n.confidence,
          },
      ]),
    );
  } else {
    stdout.writeln('${events.length} notes  (${sw.elapsedMilliseconds} ms):');
    stdout.writeln('  #   note   start      end     conf');
    for (var i = 0; i < events.length; i++) {
      final n = events[i];
      stdout.writeln('${(i + 1).toString().padLeft(3)}  '
          '${_noteName(n.midi).padRight(5)} '
          '${(n.onMs / 1000).toStringAsFixed(3).padLeft(7)}s '
          '${(n.offMs / 1000).toStringAsFixed(3).padLeft(7)}s '
          '${n.confidence.toStringAsFixed(2).padLeft(6)}');
    }
  }
}
