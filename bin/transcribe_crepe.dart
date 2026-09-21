// bin/transcribe_crepe.dart
//
// CLI demo for W-CREPE: a WAV file → CREPE monophonic F0 → notes, using CREPE
// as the F0Estimator behind the shared note-segmentation chain (auto-tuning →
// note-HMM → octave cleanup). Pure Dart — runs the ONNX model on
// onnx_runtime_dart, no Flutter needed. CREPE is timbre-robust where pYIN
// octave-doubles on real singing.
//
//   dart run bin/transcribe_crepe.dart path/to/audio.wav
//       [--a4 440] [--fmin 50] [--fmax 2006] [--workers N] [--batch 512]
//       [--f0] [--json]
//
//   --f0         dump the raw pitch track (time, Hz, voicing) instead of notes
//   --workers N  run inference on an N-isolate pool (0 = single-threaded)
//   --batch N    frames per inference batch
//
// The execution path is also gated by env — COMET_CREPE_WORKERS /
// COMET_CREPE_POOLCONV / COMET_CREPE_BATCH — so sync vs pooled can be
// A/B-benchmarked without recompiling (flags override env). See CrepeRunConfig.
//
// Convert anything to mono WAV first, e.g.
//   ffmpeg -i in.ogg -ac 1 -ar 44100 -c:a pcm_s16le out.wav
//
// The MIT CREPE-tiny model is downloaded on first run (see CrepeModelStore).
library;

import 'dart:convert';
import 'dart:io';

import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/crepe_model_store.dart';
import 'package:comet_beat/core/audio/transcription/route.dart';
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
    stderr.writeln(
      'usage: dart run bin/transcribe_crepe.dart audio.wav '
      '[--a4 440] [--fmin 50] [--fmax 2006] [--f0] [--json]',
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

  final model = await CrepeModelStore().load();
  final fmin = _optD(args, '--fmin', 50);
  final fmax = _optD(args, '--fmax', 2006);
  // Path (sync vs isolate-pool) gated by env; --workers/--batch override it.
  final envCfg = CrepeRunConfig.fromEnv();
  final cfg = CrepeRunConfig(
    workers: _optI(args, '--workers', envCfg.workers),
    poolConv: envCfg.poolConv,
    batchFrames: _optI(args, '--batch', envCfg.batchFrames),
  );
  stderr.writeln('crepe $cfg');
  final sw = Stopwatch()..start();

  if (args.contains('--f0')) {
    // Raw pitch track.
    final PitchTrack track = await crepeRun(
      mono,
      model: model,
      sampleRate: wav.sampleRate,
      config: cfg,
      fmin: fmin,
      fmax: fmax,
    );
    sw.stop();
    // Machine-readable on stderr in every mode, for the pool A/B harness
    // (tool/pool_workers_ab.dart).
    stderr.writeln('elapsed_ms ${sw.elapsedMilliseconds}');
    if (args.contains('--json')) {
      stdout.writeln(
        jsonEncode([
          for (final f in track)
            {'timeMs': f.timeMs, 'f0Hz': f.f0Hz, 'voicedProb': f.voicedProb},
        ]),
      );
    } else {
      stderr.writeln('${track.length} frames (${sw.elapsedMilliseconds} ms):');
      stdout.writeln('   time(s)     f0(Hz)   voiced');
      for (final f in track) {
        stdout.writeln(
          '${(f.timeMs / 1000).toStringAsFixed(3).padLeft(9)}  '
          '${f.f0Hz.toStringAsFixed(2).padLeft(9)}  '
          '${f.voicedProb.toStringAsFixed(3).padLeft(7)}',
        );
      }
    }
    return;
  }

  // Notes via the shared chain, with CREPE as the F0 source.
  final events = await transcribeMonophonic(
    mono,
    sampleRate: wav.sampleRate,
    a4: _optD(args, '--a4', 440),
    f0: (m, sr) => crepeRun(
      m,
      model: model,
      sampleRate: sr,
      config: cfg,
      fmin: fmin,
      fmax: fmax,
    ),
  );
  sw.stop();
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
      stdout.writeln(
        '${(i + 1).toString().padLeft(3)}  '
        '${_noteName(n.midi).padRight(5)} '
        '${(n.onMs / 1000).toStringAsFixed(3).padLeft(7)}s '
        '${(n.offMs / 1000).toStringAsFixed(3).padLeft(7)}s '
        '${n.confidence.toStringAsFixed(2).padLeft(6)}',
      );
    }
  }
}
