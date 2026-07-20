// Native CrispASR-CLI CREPE F0 estimator. Shells out to `crispasr --pitch -f
// in.wav -m crepe.gguf`, which prints one tab-separated line per frame
// ("time_ms\tf0_hz\tvoiced_prob"), and maps those to the shared PitchTrack.
// dart:io only — reached solely via crispasr_pitch.dart's conditional import.
//
// The binary + GGUF are configured by the passed paths, else the environment
// (CRISPASR_BIN / CRISPASR_CREPE_GGUF). Desktop/dev route (the app ships
// libcrispasr for FFI TTS; the productionised path is an FFI binding once the
// crispasr package exposes crepe_compute_f0). Model: cstr/crepe-GGUF.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show wavBytes;
import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/route.dart'
    show F0Estimator;

String? _bin(String? p) => _resolve(p, 'CRISPASR_BIN');
String? _gguf(String? p) => _resolve(p, 'CRISPASR_CREPE_GGUF');

String? _resolve(String? passed, String env) {
  final v = passed ?? Platform.environment[env];
  if (v == null || v.isEmpty || !File(v).existsSync()) return null;
  return v;
}

/// Whether the crispasr binary + a CREPE GGUF are both configured & present.
bool crispasrCrepeAvailable() => _bin(null) != null && _gguf(null) != null;

/// A CrispASR-CLI CREPE [F0Estimator], or null when the binary/model aren't
/// available. Writes the mono audio to a temp WAV, runs `--pitch`, parses the
/// frames. Returns an empty track on any failure so the caller falls back.
F0Estimator? crispasrCliCrepeF0({
  String? binary,
  String? model,
  String? workDir,
}) {
  final bin = _bin(binary);
  final gguf = _gguf(model);
  if (bin == null || gguf == null) return null;
  return (Float64List mono, int sampleRate) async {
    final dir = Directory(
      workDir ?? Directory.systemTemp.createTempSync('cb_pitch_').path,
    )..createSync(recursive: true);
    try {
      final wav = File('${dir.path}/in.wav');
      final pcm = Int16List(mono.length);
      for (var i = 0; i < mono.length; i++) {
        pcm[i] = (mono[i].clamp(-1.0, 1.0) * 32767).round();
      }
      wav.writeAsBytesSync(wavBytes(pcm, sampleRate: sampleRate));
      final res = await Process.run(bin, [
        '--pitch',
        '-f',
        wav.path,
        '-m',
        gguf,
        '--pitch-format',
        'text',
      ]);
      if (res.exitCode != 0) return const <PitchFrame>[];
      return parsePitchFrames('${res.stdout}');
    } catch (_) {
      return const <PitchFrame>[];
    }
  };
}

/// Parse `crispasr --pitch` text output — one line per frame,
/// "time_ms\tf0_hz\tvoiced_prob" — into a [PitchTrack]. Skips non-data lines.
/// Exposed for testing without the binary.
PitchTrack parsePitchFrames(String stdout) {
  final track = <PitchFrame>[];
  for (final line in const LineSplitter().convert(stdout)) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 3) continue;
    final t = double.tryParse(parts[0]);
    final f = double.tryParse(parts[1]);
    final v = double.tryParse(parts[2]);
    if (t == null || f == null || v == null) continue;
    track.add((timeMs: t, f0Hz: f, voicedProb: v));
  }
  return track;
}
