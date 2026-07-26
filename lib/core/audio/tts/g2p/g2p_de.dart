// g2p_de.dart — German grapheme-to-phoneme (text → IPA), pure Dart.
//
// Port of the *built-in / LTS* path of CrispASR's `core/g2p_de.h` +
// `phonemizer.cpp::phonemize_builtin_de` (MIT). The C++ pipeline is
// dictionary → compound-splitting → LTS rules; only the zero-dependency LTS
// path is portable to web/wasm. This file implements the full rule set:
//   - open-syllable vowel lengthening (a/e/i/o/u/ä/ö/ü);
//   - digraph/trigraph rules (sch/ch/tsch/ei/eu/au/äu/sp/st/ng/...);
//   - Auslautverhärtung (final devoicing b→p, d→t, ɡ→k, v→f, z→s).
// Plus a modest bundled high-frequency exception lexicon ([kDeLexicon]) that
// also supplies primary-stress marks (the LTS rules alone emit none).
//
// Output approximates espeak-ng's German voice. No dart:io/ffi/Flutter.

import 'package:comet_beat/core/audio/tts/g2p/g2p_de_lexicon.dart';

bool _isVowelAscii(String c) => 'aeiouy'.contains(c);

/// Count consonant PHONEME units after byte position [i] (digraphs
/// ch/ng/ck/pf/tz/th/sch counted as one). Operates on UTF-8 bytes to match the
/// reference; here we treat the string as code units and stop at any non-ASCII.
int _countFollowingConsonantUnits(List<int> w, int i) {
  var n = 0;
  var j = i + 1;
  final len = w.length;
  while (j < len) {
    final c = w[j];
    if (c >= 0x80) break;
    final cs = String.fromCharCode(c);
    if (_isVowelAscii(cs)) break;
    if (c < 0x61 || c > 0x7a) break; // not a-z
    final c1 = j + 1 < len ? String.fromCharCode(w[j + 1]) : '';
    if ((cs == 'c' && c1 == 'h') ||
        (cs == 'n' && c1 == 'g') ||
        (cs == 'c' && c1 == 'k') ||
        (cs == 'p' && c1 == 'f') ||
        (cs == 't' && c1 == 'z') ||
        (cs == 't' && c1 == 'h') ||
        (cs == 's' && c1 == 'c')) {
      n++;
      j += 2;
      if (cs == 's' && c1 == 'c' && j < len && w[j] == 0x68) j++; // sch
      continue;
    }
    n++;
    j++;
  }
  return n;
}

bool _isOpenSyllable(List<int> w, int i) {
  final cons = _countFollowingConsonantUnits(w, i);
  if (cons == 0) return true;
  if (cons == 1) {
    var j = i + 1;
    final len = w.length;
    while (j < len &&
        w[j] < 0x80 &&
        !_isVowelAscii(String.fromCharCode(w[j])) &&
        w[j] >= 0x61 &&
        w[j] <= 0x7a) {
      j++;
    }
    if (j < len && w[j] < 0x80 && _isVowelAscii(String.fromCharCode(w[j]))) {
      return true;
    }
    if (j + 1 < len && w[j] == 0xC3) return true; // umlaut vowel next
  }
  return false;
}

/// UTF-8-aware lowercase (handles Ä/Ö/Ü). Returns a byte list so the byte-level
/// rules from the reference translate directly.
List<int> _toLowerDeBytes(String s) {
  final bytes = _utf8Encode(s);
  final out = <int>[];
  for (var i = 0; i < bytes.length; i++) {
    final c = bytes[i];
    if (c >= 0x41 && c <= 0x5a) {
      out.add(c + 32);
      continue;
    }
    if (c == 0xC3 && i + 1 < bytes.length) {
      final c2 = bytes[i + 1];
      if (c2 >= 0x80 && c2 <= 0x9E) {
        out.add(c);
        out.add(c2 + 0x20);
        i++;
        continue;
      }
    }
    out.add(c);
  }
  return out;
}

// Minimal UTF-8 encoder (avoids dart:convert to keep the surface tiny; still
// pure Dart — dart:convert would also be fine on web, but this is trivial).
List<int> _utf8Encode(String s) {
  final out = <int>[];
  for (final r in s.runes) {
    if (r < 0x80) {
      out.add(r);
    } else if (r < 0x800) {
      out.add(0xC0 | (r >> 6));
      out.add(0x80 | (r & 0x3F));
    } else if (r < 0x10000) {
      out.add(0xE0 | (r >> 12));
      out.add(0x80 | ((r >> 6) & 0x3F));
      out.add(0x80 | (r & 0x3F));
    } else {
      out.add(0xF0 | (r >> 18));
      out.add(0x80 | ((r >> 12) & 0x3F));
      out.add(0x80 | ((r >> 6) & 0x3F));
      out.add(0x80 | (r & 0x3F));
    }
  }
  return out;
}

/// Auslautverhärtung — final devoicing applied to the finished IPA string.
String _applyFinalDevoicing(String ipa) {
  if (ipa.isEmpty) return ipa;
  // ɡ (script g) → k
  if (ipa.endsWith('ɡ')) return '${ipa.substring(0, ipa.length - 'ɡ'.length)}k';
  final last = ipa[ipa.length - 1];
  const map = {'b': 'p', 'd': 't', 'z': 's', 'v': 'f'};
  final rep = map[last];
  if (rep != null) return ipa.substring(0, ipa.length - 1) + rep;
  return ipa;
}

/// Rule-based German LTS: word → IPA.
String ltsWordToIpaDe(String word) {
  final ipa = StringBuffer();
  final w = _toLowerDeBytes(word);
  final len = w.length;

  int at(int i, int off) {
    final idx = i + off;
    return (idx >= 0 && idx < len) ? w[idx] : 0;
  }

  var i = 0;
  while (i < len) {
    final c = at(i, 0);
    final c1 = at(i, 1);
    final c2 = at(i, 2);
    final c3 = at(i, 3);
    final cs = String.fromCharCode(c);
    final c1s = String.fromCharCode(c1);
    final c2s = String.fromCharCode(c2);

    // 4-char: tsch → tʃ
    if (cs == 't' && c1s == 's' && c2s == 'c' && c3 == 0x68) {
      ipa.write('tʃ');
      i += 4;
      continue;
    }
    // 3-char.
    if (cs == 's' && c1s == 'c' && c2s == 'h') {
      ipa.write('ʃ');
      i += 3;
      continue;
    }
    if (cs == 'c' && c1s == 'h' && c2s == 's') {
      ipa.write('ks');
      i += 3;
      continue;
    }

    // 2-char consonant clusters.
    if (cs == 'c' && c1s == 'h') {
      final prev = i > 0 ? String.fromCharCode(w[i - 1]) : '';
      ipa.write((prev == 'a' || prev == 'o' || prev == 'u') ? 'x' : 'ç');
      i += 2;
      continue;
    }
    if (cs == 'c' && c1s == 'k') {
      ipa.write('k');
      i += 2;
      continue;
    }
    if (cs == 'p' && c1s == 'h') {
      ipa.write('f');
      i += 2;
      continue;
    }
    if (cs == 'p' && c1s == 'f') {
      ipa.write('pf');
      i += 2;
      continue;
    }
    if (cs == 't' && c1s == 'h') {
      ipa.write('t');
      i += 2;
      continue;
    }
    if (cs == 't' && c1s == 'z') {
      ipa.write('ts');
      i += 2;
      continue;
    }
    if (cs == 'd' && c1s == 't') {
      ipa.write('t');
      i += 2;
      continue;
    }
    if (cs == 'n' && c1s == 'g') {
      ipa.write('ŋ');
      i += 2;
      continue;
    }
    if (cs == 'n' && c1s == 'k') {
      ipa.write('ŋk');
      i += 2;
      continue;
    }
    if (cs == 'q' && c1s == 'u') {
      ipa.write('kv');
      i += 2;
      continue;
    }

    // Vowel digraphs.
    if (cs == 'e' && c1s == 'i') {
      ipa.write('aɪ̯');
      i += 2;
      continue;
    }
    if (cs == 'e' && c1s == 'u') {
      ipa.write('ɔʏ̯');
      i += 2;
      continue;
    }
    if (cs == 'a' && c1s == 'u') {
      ipa.write('aʊ̯');
      i += 2;
      continue;
    }
    if (cs == 'i' && c1s == 'e') {
      ipa.write('iː');
      i += 2;
      continue;
    }
    if (cs == 'e' && c1s == 'e') {
      ipa.write('eː');
      i += 2;
      continue;
    }
    if (cs == 'o' && c1s == 'o') {
      ipa.write('oː');
      i += 2;
      continue;
    }
    if (cs == 'a' && c1s == 'a') {
      ipa.write('ɑː');
      i += 2;
      continue;
    }
    // Lengthening-h digraphs.
    if (cs == 'e' && c1s == 'h') {
      ipa.write('eː');
      i += 2;
      continue;
    }
    if (cs == 'a' && c1s == 'h') {
      ipa.write('ɑː');
      i += 2;
      continue;
    }
    if (cs == 'o' && c1s == 'h') {
      ipa.write('oː');
      i += 2;
      continue;
    }
    if (cs == 'u' && c1s == 'h') {
      ipa.write('uː');
      i += 2;
      continue;
    }
    if (cs == 'i' && c1s == 'h') {
      ipa.write('iː');
      i += 2;
      continue;
    }

    // ä = C3 A4.
    if (c == 0xC3 && c1 == 0xA4) {
      if (at(i, 2) == 0x75) {
        ipa.write('ɔʏ̯');
        i += 3;
        continue;
      } // äu
      if (at(i, 2) == 0x68) {
        ipa.write('ɛː');
        i += 3;
        continue;
      } // äh
      ipa.write(_isOpenSyllable(w, i + 1) ? 'ɛː' : 'ɛ');
      i += 2;
      continue;
    }
    // ö = C3 B6.
    if (c == 0xC3 && c1 == 0xB6) {
      if (at(i, 2) == 0x68) {
        ipa.write('øː');
        i += 3;
        continue;
      }
      ipa.write(_isOpenSyllable(w, i + 1) ? 'øː' : 'œ');
      i += 2;
      continue;
    }
    // ü = C3 BC.
    if (c == 0xC3 && c1 == 0xBC) {
      if (at(i, 2) == 0x68) {
        ipa.write('yː');
        i += 3;
        continue;
      }
      ipa.write(_isOpenSyllable(w, i + 1) ? 'yː' : 'y');
      i += 2;
      continue;
    }
    // ß = C3 9F.
    if (c == 0xC3 && c1 == 0x9F) {
      ipa.write('s');
      i += 2;
      continue;
    }

    // st/sp at word start → ʃt/ʃp.
    if (i == 0 || (i > 0 && (w[i - 1] == 0x20 || w[i - 1] == 0x2d))) {
      if (cs == 's' && c1s == 't') {
        ipa.write('ʃt');
        i += 2;
        continue;
      }
      if (cs == 's' && c1s == 'p') {
        ipa.write('ʃp');
        i += 2;
        continue;
      }
    }
    // ss → s.
    if (cs == 's' && c1s == 's') {
      ipa.write('s');
      i += 2;
      continue;
    }
    // Double consonant → skip one (signals short vowel via open-syllable check).
    if (c == c1 && c >= 0x61 && c <= 0x7a && !_isVowelAscii(cs)) {
      i++;
      continue;
    }

    // Single vowels with open-syllable lengthening.
    if (cs == 'a') {
      ipa.write(_isOpenSyllable(w, i) ? 'ɑː' : 'a');
      i++;
      continue;
    }
    if (cs == 'e') {
      if (i == len - 1) {
        ipa.write('ə');
        i++;
        continue;
      } // final schwa
      if (c1s == 'r' &&
          (i + 2 == len || at(i, 2) == 0x20 || at(i, 2) == 0x2d)) {
        ipa.write('ɜ');
        i += 2;
        continue; // -er → ɜ
      }
      // Unstressed final syllable -en/-el/-em → schwa (morgen, haben, tafel).
      if ((c1s == 'n' || c1s == 'l' || c1s == 'm') &&
          (at(i, 2) == 0 || at(i, 2) == 0x20 || at(i, 2) == 0x2d)) {
        ipa.write('ə');
        i++;
        continue;
      }
      ipa.write(_isOpenSyllable(w, i) ? 'eː' : 'ɛ');
      i++;
      continue;
    }
    if (cs == 'i') {
      ipa.write(_isOpenSyllable(w, i) ? 'iː' : 'ɪ');
      i++;
      continue;
    }
    if (cs == 'o') {
      ipa.write(_isOpenSyllable(w, i) ? 'oː' : 'ɔ');
      i++;
      continue;
    }
    if (cs == 'u') {
      ipa.write(_isOpenSyllable(w, i) ? 'uː' : 'ʊ');
      i++;
      continue;
    }

    // Single consonants.
    const cons = {
      'b': 'b',
      'c': 'k',
      'd': 'd',
      'f': 'f',
      'g': 'ɡ',
      'h': 'h',
      'j': 'j',
      'k': 'k',
      'l': 'l',
      'm': 'm',
      'n': 'n',
      'p': 'p',
      'r': 'ɾ', // espeak-DE tap allophone (coda/onset); vocalised -er → ɜ above
      't': 't',
      'v': 'f',
      'w': 'v',
      'x': 'ks',
      'y': 'y',
      'z': 'ts',
    };
    if (cs == 's') {
      // s before a vowel (incl. umlaut lead byte) → z, else s.
      final voiced = c1s == 'a' ||
          c1s == 'e' ||
          c1s == 'i' ||
          c1s == 'o' ||
          c1s == 'u' ||
          c1 == 0xC3;
      ipa.write(voiced ? 'z' : 's');
      i++;
      continue;
    }
    final cn = cons[cs];
    if (cn != null) {
      ipa.write(cn);
      i++;
      continue;
    }
    i++; // unknown
  }

  return _insertPrimaryStressDe(_applyFinalDevoicing(ipa.toString()));
}

// IPA vowel nuclei the German LTS can emit (base letters; length/breve marks
// are non-vowel modifiers and skipped).
const Set<String> _deVowels = {
  'a',
  'ɑ',
  'e',
  'ɛ',
  'i',
  'ɪ',
  'o',
  'ɔ',
  'u',
  'ʊ',
  'ø',
  'œ',
  'y',
  'ə',
  'ɜ',
  'ɐ',
  'ʏ',
  'æ',
  'ɨ',
};

/// Insert a primary-stress mark ˈ immediately before the first vowel nucleus —
/// espeak-ng's German default (native words stress the first full syllable).
/// Prefix-shifted stress (be-/ge-/ver-/…) is a known limitation, left to the
/// dictionary tiers.
String _insertPrimaryStressDe(String ipa) {
  if (ipa.contains('ˈ')) return ipa; // already stressed
  final runes = ipa.runes.toList();
  for (var k = 0; k < runes.length; k++) {
    if (_deVowels.contains(String.fromCharCode(runes[k]))) {
      final before = String.fromCharCodes(runes.sublist(0, k));
      final after = String.fromCharCodes(runes.sublist(k));
      return '$beforeˈ$after';
    }
  }
  return ipa;
}

/// Single word → IPA (LTS path only, plus bundled lexicon).
String wordToIpaDe(String word) {
  // Lowercase (UTF-8/umlaut aware) for lexicon lookup.
  final lowerStr = _bytesToString(_toLowerDeBytes(word));
  final lex = kDeLexicon[lowerStr];
  if (lex != null) return lex;
  return ltsWordToIpaDe(word);
}

String _bytesToString(List<int> bytes) {
  // Minimal UTF-8 decode (pure Dart).
  final buf = StringBuffer();
  var i = 0;
  while (i < bytes.length) {
    final b = bytes[i];
    if (b < 0x80) {
      buf.writeCharCode(b);
      i++;
    } else if (b & 0xE0 == 0xC0 && i + 1 < bytes.length) {
      buf.writeCharCode(((b & 0x1F) << 6) | (bytes[i + 1] & 0x3F));
      i += 2;
    } else if (b & 0xF0 == 0xE0 && i + 2 < bytes.length) {
      final cp = ((b & 0x0F) << 12) |
          ((bytes[i + 1] & 0x3F) << 6) |
          (bytes[i + 2] & 0x3F);
      buf.writeCharCode(cp);
      i += 3;
    } else if (i + 3 < bytes.length) {
      final cp = ((b & 0x07) << 18) |
          ((bytes[i + 1] & 0x3F) << 12) |
          ((bytes[i + 2] & 0x3F) << 6) |
          (bytes[i + 3] & 0x3F);
      buf.writeCharCode(cp);
      i += 4;
    } else {
      i++;
    }
  }
  return buf.toString();
}

const String _punctDe = ',.!?;:-';

List<String> _tokenize(String text) {
  final tokens = <String>[];
  final cur = StringBuffer();
  for (final ch in text.split('')) {
    if (ch == ' ' || ch == '\n' || _punctDe.contains(ch)) {
      if (cur.isNotEmpty) {
        tokens.add(cur.toString());
        cur.clear();
      }
      if (ch != ' ' && ch != '\n') tokens.add(ch);
    } else {
      cur.write(ch);
    }
  }
  if (cur.isNotEmpty) tokens.add(cur.toString());
  return tokens;
}

/// Full text → IPA string.
///
/// [lookup] is an optional dictionary tier consulted per word BEFORE the
/// lexicon/LTS fallback ([wordToIpaDe]); returning null defers to the rules.
String textToIpaDe(String text, {String? Function(String word)? lookup}) {
  final words = _tokenize(text);
  final ipa = StringBuffer();
  for (final w in words) {
    if (w.length == 1 && _punctDe.contains(w)) continue;
    if (ipa.isNotEmpty) ipa.write(' ');
    ipa.write(lookup?.call(w) ?? wordToIpaDe(w));
  }
  return ipa.toString();
}
