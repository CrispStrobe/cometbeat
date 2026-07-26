// bin/tts_render.dart — BUILD-TIME neural-narration pre-renderer.
//
// Renders fixed text to a WAV with the pure-Dart Piper VITS core (CC0 voices),
// so the app can bundle the audio as an asset and play it INSTANTLY on web —
// with zero client-side inference. This exists because runtime client-side
// neural TTS on the web is impractical: Dart is single-threaded there
// (`onnx_runtime_dart.runAsync` throws on web), so a 10–20 s synthesis would
// freeze the browser tab. Pre-rendering offline sidesteps that entirely.
//
// Usage:
//   dart run bin/tts_render.dart --text "Willkommen" --lang de --out hi.wav
//   dart run bin/tts_render.dart --text "Hello there" --lang en   # → tts_out.wav
//
// Native only (downloads/caches the voice via PiperVoiceStore). Clean-room:
// Piper is MIT, the voices are CC0, onnx_runtime_dart + the g2p are ours.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show wavBytes;
import 'package:comet_beat/core/audio/tts/piper/piper_phonemes.dart';
import 'package:comet_beat/core/audio/tts/piper/piper_synth.dart';
import 'package:comet_beat/core/audio/tts/piper/piper_voice_store.dart';
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

String _arg(List<String> a, String flag, String fallback) {
  final i = a.indexOf(flag);
  return (i >= 0 && i + 1 < a.length) ? a[i + 1] : fallback;
}

Future<int> main(List<String> args) async {
  final text = _arg(args, '--text', '');
  final lang = _arg(args, '--lang', 'en');
  final out = _arg(args, '--out', 'tts_out.wav');
  if (text.trim().isEmpty) {
    stderr.writeln('usage: dart run bin/tts_render.dart --text "…" '
        '[--lang en|de] [--out file.wav]');
    return 2;
  }
  if (!PiperVoiceStore.voices.containsKey(lang)) {
    stderr.writeln('unknown --lang "$lang" (have: '
        '${PiperVoiceStore.voices.keys.join(", ")})');
    return 2;
  }

  final store = PiperVoiceStore();
  final voice = PiperVoiceStore.voices[lang]!;
  stdout.writeln('voice: ${voice.base} [${voice.license}]  — resolving…');
  final modelFile = await store.ensureModel(lang);
  if (modelFile == null) {
    stderr.writeln('could not download/cache the voice (offline?).');
    return 1;
  }
  final config = store.configFile(lang).readAsStringSync();
  final phonemeIdMap = phonemeIdMapFromJson(config);
  final sampleRate = sampleRateFromJson(config);

  final model = OnnxModel.fromBytes(
    modelFile.readAsBytesSync().buffer.asUint8List(),
  );
  final ids = piperPhonemeIds(text, lang: lang, phonemeIdMap: phonemeIdMap);

  final sw = Stopwatch()..start();
  final pcm = PiperSynth(model, sampleRate: sampleRate).synthesize(ids);
  sw.stop();

  // Float32 [-1,1] → PCM16.
  final samples = Int16List(pcm.length);
  for (var i = 0; i < pcm.length; i++) {
    samples[i] = (pcm[i].clamp(-1.0, 1.0) * 32767).round();
  }
  File(out).writeAsBytesSync(wavBytes(samples, sampleRate: sampleRate));

  var sumSq = 0.0;
  for (final s in pcm) {
    sumSq += s * s;
  }
  final rms = pcm.isEmpty ? 0.0 : math.sqrt(sumSq / pcm.length);
  final seconds = pcm.length / sampleRate;
  stdout.writeln('rendered ${ids.length} phoneme-ids → '
      '${seconds.toStringAsFixed(2)} s @ ${sampleRate}Hz '
      '(RMS ${rms.toStringAsFixed(4)}) in ${sw.elapsedMilliseconds} ms → $out');
  return 0;
}
