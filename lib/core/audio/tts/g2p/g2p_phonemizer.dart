// g2p_phonemizer.dart — public API for the pure-Dart, web/wasm-safe
// grapheme-to-phoneme phonemizer (English + German) that produces Kokoro-82M
// phoneme token ids.
//
// This is the missing web piece for running the neural Kokoro TTS voice in the
// browser: `onnx_runtime_dart` already runs Kokoro-82M at 0.995 parity, but the
// native text→phonemes step is C via dart:ffi (libcrispasr), which has no web
// path. This library reimplements the built-in (LTS) G2P and the Kokoro
// tokenizer entirely in pure Dart — no dart:io, no dart:ffi, no Flutter, no
// network — so it runs unchanged on web/wasm.
//
// Port provenance: the LTS rules and the ARPAbet→IPA / German rule sets are
// ported (rules, not source) from our own MIT repo CrispASR
// (`src/core/g2p_en.h`, `src/core/g2p_de.h`, `src/phonemizer.cpp`); the token
// vocabulary and pad-wrap contract from `src/kokoro.cpp`.
//
//   phonemizeToIpa(text, lang: 'en'|'de') → IPA string
//   kokoroTokens(text, lang: 'en'|'de')   → pad-wrapped Kokoro token ids

import 'package:comet_beat/core/audio/tts/g2p/g2p_de.dart';
import 'package:comet_beat/core/audio/tts/g2p/g2p_en.dart';
import 'package:comet_beat/core/audio/tts/g2p/kokoro_vocab.dart';

/// Convert [text] to an IPA phoneme string.
///
/// [lang] selects the language rules: any code containing `de` → German,
/// otherwise English (the default). The IPA approximates espeak-ng (what
/// Kokoro-82M was trained on).
String phonemizeToIpa(String text, {String lang = 'en'}) {
  if (_isGerman(lang)) return textToIpaDe(text);
  return textToIpaEn(text);
}

/// Convert [text] to Kokoro-82M input token ids.
///
/// Pipeline: text → IPA ([phonemizeToIpa]) → per-code-point vocab lookup
/// (unknown code points dropped, matching the reference tokenizer) →
/// StyleTTS2 pad-wrap `[0, ...ids, 0]`. The returned list is ready to feed to
/// the Kokoro `input_ids` tensor.
List<int> kokoroTokens(String text, {String lang = 'en'}) {
  final ipa = phonemizeToIpa(text, lang: lang);
  return wrapWithPad(ipaToTokenIds(ipa));
}

/// Convert an already-computed IPA string directly to pad-wrapped Kokoro token
/// ids (skips G2P). Useful when the caller sourced IPA elsewhere.
List<int> kokoroTokensFromIpa(String ipa) => wrapWithPad(ipaToTokenIds(ipa));

// Mirrors the reference `lang.find("de")` dispatch: any lang code mentioning
// "de" routes to German; everything else is English.
bool _isGerman(String lang) => lang.toLowerCase().contains('de');
