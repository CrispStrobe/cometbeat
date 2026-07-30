// bin/transcribe_chords.dart
//
// CLI demo for W-HARMONY: a WAV file → BTC neural chord recognition → a timed
// chord chart. Pure Dart — runs the BTC ONNX on onnx_runtime_dart, no Flutter.
//
//   dart run bin/transcribe_chords.dart path/to/audio.wav [--keep-n] [--json]
//
//   --keep-n   include 'N' (no-chord) spans in the output
//
// Convert anything to mono WAV first, e.g.
//   ffmpeg -i in.ogg -ac 1 -ar 44100 -c:a pcm_s16le out.wav
//
// The BTC model + CQT asset download on first run (see HarmonyModelStore).
// ⚠️ The BTC *code* is MIT but these *weights* are CC-BY-NC-SA-4.0 —
// NON-COMMERCIAL, and the store gates on that. This comment used to call it
// "the MIT BTC model", which is wrong and contradicts the store.
library;

import 'dart:convert';
import 'dart:io';

import 'package:comet_beat/core/audio/transcription/harmony.dart';
import 'package:comet_beat/core/audio/transcription/harmony_model_store.dart';
import 'package:comet_beat/core/audio/wav_io.dart';

Future<void> main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.isEmpty) {
    stderr.writeln(
      'usage: dart run bin/transcribe_chords.dart audio.wav '
      '[--keep-n] [--json]',
    );
    exit(64);
  }
  final path = positional.first;
  if (!File(path).existsSync()) {
    stderr.writeln('no such file: $path');
    exit(66);
  }

  final wav = readWavPcm16(File(path).readAsBytesSync());
  final mono = wavToMonoFloat(wav);
  stderr.writeln(
    'loaded $path — ${wav.sampleRate} Hz, ${wav.channels}ch, '
    '${(mono.length / wav.sampleRate).toStringAsFixed(2)} s',
  );

  final bundle = await HarmonyModelStore().load();
  final sw = Stopwatch()..start();
  final chords = estimateChords(
    mono,
    model: bundle.model,
    cqt: bundle.cqt,
    sampleRate: wav.sampleRate,
    keepNoChord: args.contains('--keep-n'),
  );
  sw.stop();

  if (args.contains('--json')) {
    stdout.writeln(
      jsonEncode([
        for (final c in chords)
          {
            'label': c.label,
            'rootPc': c.rootPc,
            'quality': c.quality,
            'onMs': c.onMs,
            'offMs': c.offMs,
          },
      ]),
    );
  } else {
    stdout.writeln('${chords.length} chords  (${sw.elapsedMilliseconds} ms):');
    stdout.writeln('   start      end     chord');
    for (final c in chords) {
      stdout.writeln(
        '${(c.onMs / 1000).toStringAsFixed(2).padLeft(7)}s '
        '${(c.offMs / 1000).toStringAsFixed(2).padLeft(7)}s   '
        '${c.label}',
      );
    }
  }
}
