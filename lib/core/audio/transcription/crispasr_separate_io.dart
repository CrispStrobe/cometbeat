// Native CrispASR-CLI source separator. Shells out to `crispasr --separate`
// (ggml HTDemucs / mel-band-roformer, MIT — §248, fully parity + fast), which
// writes `<input>_<stem>.wav` files; those are read back into the stems.dart
// `Stems` the whole-song pipeline consumes. dart:io only — reached solely via
// crispasr_separate.dart's conditional import.
//
// This uses the CrispASR CLI binary (a desktop/dev path — the app already ships
// libcrispasr for FFI TTS, so the productionised route is an FFI binding to
// `crispasr_run_separate` once the Dart package exposes it). Backend/model are
// GGUF, auto-detected from [model]. Returns whatever stems the model produces:
// htdemucs → 4 stems; mel-band-roformer → vocals + instrumental (→ `other`).

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show wavBytes;
import 'package:comet_beat/core/audio/transcription/stems.dart'
    show Separator, Stems;
import 'package:comet_beat/core/audio/wav_io.dart';

/// A [Separator] that runs the CrispASR `--separate` CLI [binary] with a
/// separation [model] GGUF. [workDir] holds the temp mix + stem files (a fresh
/// temp dir by default). Returns empty stems on any failure so the caller falls
/// back to a single-part transcription.
Separator? crispasrCliSeparator({
  required String binary,
  required String model,
  String? workDir,
}) {
  return (Float64List mono, int sampleRate) async {
    if (!File(binary).existsSync() || !File(model).existsSync()) {
      return _empty;
    }
    final dir = Directory(
      workDir ?? Directory.systemTemp.createTempSync('cb_sep_').path,
    )..createSync(recursive: true);
    try {
      final mix = File('${dir.path}/mix.wav');
      mix.writeAsBytesSync(_toWav(mono, sampleRate));
      final res = await Process.run(binary, [
        '--separate',
        '-m',
        model,
        '-f',
        mix.path,
        '--sep-output-dir',
        dir.path,
      ]);
      if (res.exitCode != 0) return _empty;
      return readStemsFromDir(dir.path, 'mix');
    } catch (_) {
      return _empty;
    }
  };
}

const Stems _empty = (vocals: null, bass: null, drums: null, other: null);

/// Read the `<base>_<stem>.wav` files CrispASR wrote in [dir] into [Stems].
/// Missing stems stay null; `instrumental` (roformer's 2-stem output) maps to
/// `other`. Exposed for testing without the CLI.
Stems readStemsFromDir(String dir, String base) {
  Float64List? read(String stem) {
    final f = File('$dir/${base}_$stem.wav');
    if (!f.existsSync()) return null;
    try {
      return wavToMonoFloat(readWavPcm16(f.readAsBytesSync()));
    } catch (_) {
      return null;
    }
  }

  return (
    vocals: read('vocals'),
    bass: read('bass'),
    drums: read('drums'),
    other: read('other') ?? read('instrumental'),
  );
}

Uint8List _toWav(Float64List mono, int sampleRate) {
  final pcm = Int16List(mono.length);
  for (var i = 0; i < mono.length; i++) {
    pcm[i] = (mono[i].clamp(-1.0, 1.0) * 32767).round();
  }
  return wavBytes(pcm, sampleRate: sampleRate);
}
