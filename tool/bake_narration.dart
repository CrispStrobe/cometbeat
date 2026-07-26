// tool/bake_narration.dart — offline pre-render of the app's FIXED narration
// strings into bundled WAV assets + a manifest, so the neural voice plays
// instantly on web with zero client inference (runtime synthesis there would
// freeze the single-threaded browser isolate; see bin/tts_render.dart).
//
// Input: a JSON array of {"text": "...", "lang": "en"|"de"} — the strings to
// bake (which strings + the size budget is a product decision; this tool just
// renders whatever list it's given).
//
// Usage:
//   dart run tool/bake_narration.dart strings.json        # → assets/narration/
//   dart run tool/bake_narration.dart strings.json out_dir
//
// Output: <out>/narration/<lang>_<key-hash>.wav + <out>/narration/manifest.json
// mapping narrationKey(text,lang) → "narration/<lang>_<hash>.wav" (flat, so one
// non-recursive Flutter asset dir bundles it all).
//
// Native (dart:io). Clean-room: Piper MIT, voices CC0, onnx_runtime_dart+g2p
// ours. This tool + the assets it makes are the shipped artefacts.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show wavBytes;
import 'package:comet_beat/core/audio/tts/narration_key.dart';
import 'package:comet_beat/core/audio/tts/piper/piper_phonemes.dart';
import 'package:comet_beat/core/audio/tts/piper/piper_synth.dart';
import 'package:comet_beat/core/audio/tts/piper/piper_voice_store.dart';
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// A short, stable, filesystem-safe filename for a key. This runs on the VM
/// only (bake time), so a 64-bit hash is fine — the runtime NEVER recomputes
/// it (it reads the path from the manifest).
String _fileHash(String key) {
  var h = 0xcbf29ce484222325; // FNV-1a 64-bit
  for (final c in key.codeUnits) {
    h ^= c;
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  // Mask the sign bit so the hex filename is never `-`-prefixed.
  return (h & 0x7FFFFFFFFFFFFFFF).toRadixString(16).padLeft(16, '0');
}

Future<int> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/bake_narration.dart '
        'strings.json [out_dir]');
    return 2;
  }
  final input = File(args[0]);
  if (!input.existsSync()) {
    stderr.writeln('input not found: ${args[0]}');
    return 2;
  }
  final outRoot = args.length > 1 ? args[1] : 'assets';
  final items = (jsonDecode(input.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  final store = PiperVoiceStore();
  // Load each language's model + config once.
  final models = <String, ({OnnxModel model, Map<String, int> map, int sr})>{};
  Future<bool> ensureLang(String lang) async {
    if (models.containsKey(lang)) return true;
    if (!PiperVoiceStore.voices.containsKey(lang)) {
      stderr.writeln('  skip: no CC0 voice for lang "$lang"');
      return false;
    }
    final mf = await store.ensureModel(lang);
    if (mf == null) {
      stderr.writeln('  skip: could not fetch the "$lang" voice (offline?)');
      return false;
    }
    final cfg = store.configFile(lang).readAsStringSync();
    models[lang] = (
      model: OnnxModel.fromBytes(mf.readAsBytesSync().buffer.asUint8List()),
      map: phonemeIdMapFromJson(cfg),
      sr: sampleRateFromJson(cfg),
    );
    return true;
  }

  final manifest = <String, String>{};
  var baked = 0;
  for (final item in items) {
    final text = (item['text'] as String?)?.trim() ?? '';
    final lang = narrationLang((item['lang'] as String?) ?? 'en');
    if (text.isEmpty) continue;
    if (!await ensureLang(lang)) continue;

    final m = models[lang]!;
    final ids = piperPhonemeIds(text, lang: lang, phonemeIdMap: m.map);
    final pcm = PiperSynth(m.model, sampleRate: m.sr).synthesize(ids);
    final samples = Int16List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      samples[i] = (pcm[i].clamp(-1.0, 1.0) * 32767).round();
    }

    final key = narrationKey(text, lang);
    // Flat layout (lang in the filename) so a single non-recursive Flutter
    // asset dir (`assets/narration/`) bundles every baked clip + the manifest.
    final rel = 'narration/${lang}_${_fileHash(key)}.wav';
    final file = File('$outRoot/$rel');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(wavBytes(samples, sampleRate: m.sr));
    manifest[key] = rel;
    baked++;
    stdout.writeln(
        '  baked [$lang] "${text.length > 40 ? "${text.substring(0, 40)}…" : text}" '
        '→ $rel (${(pcm.length / m.sr).toStringAsFixed(2)} s)');
  }

  final manifestFile = File('$outRoot/narration/manifest.json');
  manifestFile.parent.createSync(recursive: true);
  manifestFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(manifest),
  );
  stdout.writeln('baked $baked/${items.length} → '
      '$outRoot/narration/ (manifest: ${manifest.length} entries)');
  return 0;
}
