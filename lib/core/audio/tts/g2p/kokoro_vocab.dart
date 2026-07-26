// kokoro_vocab.dart — Kokoro-82M / StyleTTS2 phoneme→token-id vocabulary.
//
// Pure Dart, web/wasm-safe: everything is a `const` in-memory map, no I/O.
//
// The vocabulary is the canonical 178-symbol Kokoro/StyleTTS2 IPA tokenizer
// (pad token "$" = id 0). It is published in the model card
// `hexgrad/Kokoro-82M` (config.json → "vocab") and mirrored by
// `onnx-community/Kokoro-82M-v1.0-ONNX`. Only ~124 of the 178 ids are bound
// to a symbol; the rest are reserved/unused holes in the id space and are
// intentionally absent below. Every symbol is a single Unicode code point,
// so tokenisation is a per-code-point lookup (see [ipaToTokenIds]).
//
// This mirrors the reference C++ tokeniser (CrispASR `kokoro.cpp`,
// `kokoro_phonemes_to_ids`): greedy longest-match over code points, and
// *unknown code points are dropped* (Kokoro's Python reference does the same,
// `filter(lambda i: i is not None, map(vocab.get, phonemes))`) — never emitted
// as pad.

/// Kokoro/StyleTTS2 pad token id (symbol "$"). Sequences are wrapped as
/// `[padId, ...ids, padId]` before the model.
const int kKokoroPadId = 0;

/// Phoneme symbol → Kokoro token id. Const, single-code-point keys.
const Map<String, int> kKokoroTokenToId = {
  r'$': 0, // pad
  ';': 1,
  ':': 2,
  ',': 3,
  '.': 4,
  '!': 5,
  '?': 6,
  '—': 9, // — em dash
  '…': 10, // … ellipsis
  '"': 11,
  '(': 12,
  ')': 13,
  '“': 14, // “
  '”': 15, // ”
  ' ': 16, // space is a real token
  '̃': 17, // ̃ combining tilde
  'ʣ': 18, // ʣ
  'ʥ': 19, // ʥ
  'ʦ': 20, // ʦ
  'ʨ': 21, // ʨ
  'ᵝ': 22, // ᵝ modifier small beta
  'ꭧ': 23, // ꭧ
  'A': 24,
  'I': 25,
  'O': 31,
  'Q': 33,
  'S': 35,
  'T': 36,
  'W': 39,
  'Y': 41,
  'ᵊ': 42, // ᵊ
  'a': 43,
  'b': 44,
  'c': 45,
  'd': 46,
  'e': 47,
  'f': 48,
  'h': 50,
  'i': 51,
  'j': 52,
  'k': 53,
  'l': 54,
  'm': 55,
  'n': 56,
  'o': 57,
  'p': 58,
  'q': 59,
  'r': 60,
  's': 61,
  't': 62,
  'u': 63,
  'v': 64,
  'w': 65,
  'x': 66,
  'y': 67,
  'z': 68,
  'ɑ': 69, // ɑ
  'ɐ': 70, // ɐ
  'ɒ': 71, // ɒ
  'æ': 72, // æ
  'β': 75, // β
  'ɔ': 76, // ɔ
  'ɕ': 77, // ɕ
  'ç': 78, // ç
  'ɖ': 80, // ɖ
  'ð': 81, // ð
  'ʤ': 82, // ʤ
  'ə': 83, // ə
  'ɚ': 85, // ɚ
  'ɛ': 86, // ɛ
  'ɜ': 87, // ɜ
  'ɟ': 90, // ɟ
  'ɡ': 92, // ɡ (script g — espeak's /g/)
  'ɥ': 99, // ɥ
  'ɨ': 101, // ɨ
  'ɪ': 102, // ɪ
  'ʝ': 103, // ʝ
  'ɯ': 110, // ɯ
  'ɰ': 111, // ɰ
  'ŋ': 112, // ŋ
  'ɳ': 113, // ɳ
  'ɲ': 114, // ɲ
  'ɴ': 115, // ɴ
  'ø': 116, // ø
  'ɸ': 118, // ɸ
  'θ': 119, // θ
  'œ': 120, // œ
  'ɹ': 123, // ɹ
  'ɾ': 125, // ɾ
  'ɻ': 126, // ɻ
  'ʁ': 128, // ʁ
  'ɽ': 129, // ɽ
  'ʂ': 130, // ʂ
  'ʃ': 131, // ʃ
  'ʈ': 132, // ʈ
  'ʧ': 133, // ʧ
  'ʊ': 135, // ʊ
  'ʋ': 136, // ʋ
  'ʌ': 138, // ʌ
  'ɣ': 139, // ɣ
  'ɤ': 140, // ɤ
  'χ': 142, // χ
  'ʎ': 143, // ʎ
  'ʒ': 147, // ʒ
  'ʔ': 148, // ʔ
  'ˈ': 156, // ˈ primary stress
  'ˌ': 157, // ˌ secondary stress
  'ː': 158, // ː length
  'ʰ': 162, // ʰ
  'ʲ': 164, // ʲ
  '↓': 169, // ↓
  '→': 171, // →
  '↗': 172, // ↗
  '↘': 173, // ↘
  'ᵻ': 177, // ᵻ barred small-cap i
};

/// Tokenise an IPA phoneme string into Kokoro token ids.
///
/// Per the reference contract every vocab symbol is a single code point, so we
/// iterate code points (runes) and look each up. Code points not in the vocab
/// (e.g. the combining inverted-breve U+032F used in some espeak diphthongs) are
/// **dropped**, exactly like the reference tokeniser. The result is the RAW id
/// sequence — see [wrapWithPad] / [g2p_phonemizer.kokoroTokens] for pad-wrapping.
List<int> ipaToTokenIds(String ipa) {
  final ids = <int>[];
  for (final rune in ipa.runes) {
    final id = kKokoroTokenToId[String.fromCharCode(rune)];
    if (id != null) ids.add(id);
  }
  return ids;
}

/// Wrap a raw id sequence with the StyleTTS2 pad convention:
/// `[padId, ...ids, padId]` (length L+2). Replicates
/// `kokoro_pad_wrap_ids` in the reference C++.
List<int> wrapWithPad(List<int> ids) => [kKokoroPadId, ...ids, kKokoroPadId];
