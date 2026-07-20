// bin/transcribe_crispasr.dart
//
// CLI demo for the CrispASR ggml CREPE F0 path — the NATIVE ("crispasr")
// runtime of the 3-path decision framework. A WAV file → `crispasr --pitch`
// (ggml CREPE, GPU-fast) → notes through the SAME shared note-segmentation
// chain (auto-tuning → note-HMM → octave cleanup) the ONNX/pyin paths use.
//
// This shells out to the `crispasr` binary, so it needs one built + a CREPE
// GGUF (cstr/crepe-GGUF). Configure via flags or env:
//
//   dart run bin/transcribe_crispasr.dart audio.wav \
//       --bin /path/to/crispasr --model /path/to/crepe-full.gguf [--a4 440] \
//       [--f0] [--json]
//
//   env CRISPASR_BIN=/path/to/crispasr CRISPASR_CREPE_GGUF=/path/to/crepe.gguf \
//       dart run bin/transcribe_crispasr.dart audio.wav
//
//   --f0    dump the raw pitch track (time, Hz, voicing) instead of notes
//
// The GUI uses the identical provider (crispasr_pitch.dart) via the engine
// resolver; this CLI is the headless twin. Convert anything to mono WAV first,
// e.g.  ffmpeg -i in.ogg -ac 1 -ar 16000 -c:a pcm_s16le out.wav
library;

import 'dart:convert';
import 'dart:io';

import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_pitch.dart';
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

String? _optS(List<String> a, String f) {
  final i = a.indexOf(f);
  return i >= 0 && i + 1 < a.length ? a[i + 1] : null;
}

Future<void> main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.isEmpty) {
    stderr.writeln(
      'usage: dart run bin/transcribe_crispasr.dart audio.wav '
      '[--bin crispasr] [--model crepe.gguf] [--a4 440] [--f0] [--json]',
    );
    exit(64);
  }
  final path = positional.first;
  if (!File(path).existsSync()) {
    stderr.writeln('no such file: $path');
    exit(66);
  }

  final f0 = crispasrCliCrepeF0(
    binary: _optS(args, '--bin'),
    model: _optS(args, '--model'),
  );
  if (f0 == null) {
    stderr.writeln(
      'crispasr CREPE unavailable — pass --bin <crispasr> --model <crepe.gguf> '
      'or set CRISPASR_BIN / CRISPASR_CREPE_GGUF (both files must exist).',
    );
    exit(69);
  }

  final wav = readWavPcm16(File(path).readAsBytesSync());
  final mono = wavToMonoFloat(wav);
  stderr.writeln(
    'loaded $path — ${wav.sampleRate} Hz, ${wav.channels}ch, '
    '${(mono.length / wav.sampleRate).toStringAsFixed(2)} s',
  );
  final sw = Stopwatch()..start();

  if (args.contains('--f0')) {
    final PitchTrack track = await f0(mono, wav.sampleRate);
    sw.stop();
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

  final events = await transcribeMonophonic(
    mono,
    sampleRate: wav.sampleRate,
    a4: _optD(args, '--a4', 440),
    f0: f0,
  );
  sw.stop();

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
