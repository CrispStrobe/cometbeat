// g2p_phonemizer.dart — public API for the pure-Dart, web/wasm-safe
// grapheme-to-phoneme phonemizer (English + German) that produces Kokoro-82M
// phoneme token ids.
//
// This is the missing web piece for running the neural Kokoro TTS voice in the
// browser: `onnx_runtime_dart` already runs Kokoro-82M at 0.995 parity, but the
// native text→phonemes step is C via dart:ffi (libcrispasr), which has no web
// path. This library reimplements the built-in G2P and the Kokoro tokenizer
// entirely in pure Dart — no dart:io, no dart:ffi, no Flutter, no network — so
// it runs unchanged on web/wasm.
//
// LICENSE / DATA PROVENANCE (all clean for an MIT product):
//   - LTS rules + ARPAbet→IPA mapping: ported (rules, not source) from our own
//     MIT repo CrispASR (`src/core/g2p_en.h`, `g2p_de.h`, `phonemizer.cpp`).
//   - Kokoro vocab + pad-wrap contract: `kokoro.cpp`; vocab per the Apache-2.0
//     model card `onnx-community/Kokoro-82M-v1.0-ONNX` / `hexgrad/Kokoro-82M`.
//   - Bundled English dict: CMUdict (PUBLIC DOMAIN) → IPA via our own mapping.
//   - Bundled German dict: OLaPh (MIT).
//   - espeak-ng dicts (GPLv3 grey) and open-dict-data (CC-BY-SA) are NOT
//     bundled; used only as a test oracle for accuracy measurement.
// Kokoro expects espeak/misaki-style IPA, so we emit that IPA CONVENTION — an
// interop/factual requirement, independent of the data-source licensing.
//
// Word resolution per token: injected dict → bundled dict → hand lexicon → LTS.
//
//   phonemizeToIpa(text, {lang, dict, useBundledDict}) → IPA string
//   kokoroTokens(text, {lang, dict, useBundledDict})   → pad-wrapped token ids

import 'package:comet_beat/core/audio/tts/g2p/g2p_de.dart';
import 'package:comet_beat/core/audio/tts/g2p/g2p_en.dart';
import 'package:comet_beat/core/audio/tts/g2p/kokoro_vocab.dart';
import 'package:comet_beat/core/audio/tts/g2p/pron_dict.dart';

/// Convert [text] to an IPA phoneme string.
///
/// [lang] selects the rules: any code containing `de` → German, else English.
/// [dict] is an optional caller-supplied pronunciation dictionary (e.g. a fuller
/// dict downloaded + cached at runtime — see [kEnDictDownloadUrl]) consulted
/// first. [useBundledDict] (default true) consults the shipped high-frequency
/// dict (CMUdict/OLaPh-derived) next. Both fall back to the hand lexicon + LTS.
String phonemizeToIpa(
  String text, {
  String lang = 'en',
  PronunciationDictionary? dict,
  bool useBundledDict = true,
}) {
  if (_isGerman(lang)) {
    final bundled = useBundledDict ? bundledDeDict() : null;
    return textToIpaDe(text, lookup: _resolver(dict, bundled));
  }
  final bundled = useBundledDict ? bundledEnDict() : null;
  return textToIpaEn(text, lookup: _resolver(dict, bundled));
}

/// Convert [text] to Kokoro-82M input token ids.
///
/// Pipeline: text → IPA ([phonemizeToIpa]) → per-code-point vocab lookup
/// (unknown code points dropped, matching the reference tokenizer) → StyleTTS2
/// pad-wrap `[0, ...ids, 0]`, ready for the Kokoro `input_ids` tensor.
List<int> kokoroTokens(
  String text, {
  String lang = 'en',
  PronunciationDictionary? dict,
  bool useBundledDict = true,
}) {
  final ipa = phonemizeToIpa(
    text,
    lang: lang,
    dict: dict,
    useBundledDict: useBundledDict,
  );
  return wrapWithPad(ipaToTokenIds(ipa));
}

/// Convert an already-computed IPA string directly to pad-wrapped Kokoro token
/// ids (skips G2P).
List<int> kokoroTokensFromIpa(String ipa) => wrapWithPad(ipaToTokenIds(ipa));

String? Function(String)? _resolver(
  PronunciationDictionary? injected,
  PronunciationDictionary? bundled,
) {
  if (injected == null && bundled == null) return null;
  return (String word) => injected?.lookup(word) ?? bundled?.lookup(word);
}

// Mirrors the reference `lang.find("de")` dispatch: any lang code mentioning
// "de" routes to German; everything else is English.
bool _isGerman(String lang) => lang.toLowerCase().contains('de');
