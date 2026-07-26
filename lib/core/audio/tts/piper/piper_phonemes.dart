// piper_phonemes.dart — text → Piper VITS phoneme-id sequence, pure Dart.
//
// Reuses OUR g2p (`../g2p/g2p_phonemizer.dart`): it already emits espeak-
// convention IPA, which is exactly what Piper's voices were phonemized with, so
// the same IPA feeds Piper's `phoneme_id_map` directly.
//
// Pure Dart — `dart:convert` only (web-safe); no dart:io/ffi/Flutter.
//
// CLEAN-ROOM / LICENSE: the id-sequence FORMAT (BOS `^`, pad `_` after every
// phoneme, EOS `$`) is Piper's convention (rhasspy/piper, MIT); the g2p is ours.

import 'dart:convert';

import 'package:comet_beat/core/audio/tts/g2p/g2p_phonemizer.dart';

/// Piper's special symbols (present in every voice's `phoneme_id_map`).
const String kPiperPad = '_'; // interspersed after each phoneme
const String kPiperBos = '^'; // beginning of sentence
const String kPiperEos = r'$'; // end of sentence

/// Parse a voice's `.onnx.json` and return its `phoneme_id_map` as
/// `phoneme → id`. The file stores each value as a one-element `List<int>`; we
/// keep the first id (Piper voices map each phoneme to a single id).
Map<String, int> phonemeIdMapFromJson(String jsonStr) {
  final root = jsonDecode(jsonStr);
  if (root is! Map || root['phoneme_id_map'] is! Map) {
    throw const FormatException('no phoneme_id_map in voice config json');
  }
  final raw = root['phoneme_id_map'] as Map;
  final out = <String, int>{};
  raw.forEach((k, v) {
    if (k is String && v is List && v.isNotEmpty && v.first is int) {
      out[k] = v.first as int;
    }
  });
  return out;
}

/// The voice's output sample rate (`audio.sample_rate`) from its `.onnx.json`,
/// or [fallback] if absent.
int sampleRateFromJson(String jsonStr, {int fallback = 22050}) {
  final root = jsonDecode(jsonStr);
  if (root is Map && root['audio'] is Map) {
    final sr = (root['audio'] as Map)['sample_rate'];
    if (sr is int) return sr;
    if (sr is num) return sr.toInt();
  }
  return fallback;
}

/// Convert [text] to a Piper phoneme-id sequence for a voice whose
/// [phonemeIdMap] came from [phonemeIdMapFromJson].
///
/// Pipeline: `phonemizeToIpa(text, lang)` (our g2p) → IPA string → segment into
/// code points (Piper voices use a single-code-point id map, so tie bars /
/// combining marks that aren't keys are simply dropped) → build Piper's id
/// sequence:
///
///     [ BOS,  id(p1), PAD,  id(p2), PAD,  …,  id(pn), PAD,  EOS ]
///
/// i.e. a leading `^`, then every mapped phoneme followed by the `_` pad, then a
/// trailing `$` — exactly Piper's `phonemize → ids` convention. Phonemes (code
/// points) absent from [phonemeIdMap] are skipped.
List<int> piperPhonemeIds(
  String text, {
  required String lang,
  required Map<String, int> phonemeIdMap,
}) {
  final ipa = phonemizeToIpa(text, lang: lang);
  final bos = phonemeIdMap[kPiperBos];
  final eos = phonemeIdMap[kPiperEos];
  final pad = phonemeIdMap[kPiperPad];
  final ids = <int>[];
  if (bos != null) ids.add(bos);
  for (final rune in ipa.runes) {
    final id = phonemeIdMap[String.fromCharCode(rune)];
    if (id == null) continue; // drop phonemes not in this voice's map
    ids.add(id);
    if (pad != null) ids.add(pad);
  }
  if (eos != null) ids.add(eos);
  return ids;
}
