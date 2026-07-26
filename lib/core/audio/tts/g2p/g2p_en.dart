// g2p_en.dart — English grapheme-to-phoneme (text → IPA), pure Dart.
//
// Port of the *built-in / LTS* path of CrispASR's `core/g2p_en.h` +
// `phonemizer.cpp::phonemize_builtin_en` (MIT). The C++ has a three-tier
// pipeline (CMUdict → neural GRU → LTS rules); only the zero-dependency LTS
// path is portable to web/wasm, so this file implements:
//
//   1. a small espeak override table (truly irregular function words), plus a
//      modest bundled high-frequency exception lexicon (see [kEnLexicon]);
//   2. rule-based letter-to-sound (LTS) producing ARPAbet, then a
//      context-sensitive ARPAbet→IPA conversion tuned to approximate espeak-ng
//      (T-flapping, linking-ɹ, stress-dependent vowel reduction).
//
// The output IPA approximates espeak-ng (what Kokoro was trained on); it is not
// a byte-exact reproduction — an exact match to espeak needs a full pronouncing
// dictionary. No dart:io / dart:ffi / Flutter imports.

import 'package:comet_beat/core/audio/tts/g2p/g2p_en_lexicon.dart';

// ── ARPAbet → IPA base table (39-phoneme CMU set) ───────────────────────────
const Map<String, String> _arpabetToIpa = {
  // Vowels — tuned to match espeak-ng output.
  'AA': 'ɑː', 'AE': 'æ', 'AH': 'ʌ', 'AO': 'ɔː', 'AW': 'aʊ', 'AX': 'ə',
  'AY': 'aɪ', 'EH': 'ɛ', 'ER': 'ɚ', 'EY': 'eɪ', 'IH': 'ɪ', 'IX': 'ɨ',
  'IY': 'iː', 'OW': 'oʊ', 'OY': 'ɔɪ', 'UH': 'ʊ', 'UW': 'uː', 'UX': 'ʉ',
  // Consonants.
  'B': 'b', 'CH': 'tʃ', 'D': 'd', 'DH': 'ð', 'DX': 'ɾ', 'EL': 'l̩',
  'EM': 'm̩', 'EN': 'n̩', 'F': 'f', 'G': 'ɡ', 'HH': 'h', 'JH': 'dʒ',
  'K': 'k', 'L': 'l', 'M': 'm', 'N': 'n', 'NG': 'ŋ', 'NX': 'ɾ̃',
  'P': 'p', 'Q': 'ʔ', 'R': 'ɹ', 'S': 's', 'SH': 'ʃ', 'T': 't',
  'TH': 'θ', 'V': 'v', 'W': 'w', 'WH': 'ʍ', 'Y': 'j', 'Z': 'z', 'ZH': 'ʒ',
};

const Set<String> _arpaVowels = {
  'AA',
  'AE',
  'AH',
  'AO',
  'AW',
  'AY',
  'EH',
  'ER',
  'EY',
  'IH',
  'IY',
  'OW',
  'OY',
  'UH',
  'UW',
  'AX',
  'IX',
  'UX',
};

/// Split an ARPAbet symbol like "AH0" into (base, stress). Stress = -1 for
/// consonants (no trailing digit).
List<Object> _splitArpa(String arpa) {
  var base = arpa;
  var stress = -1;
  if (base.isNotEmpty) {
    final last = base.codeUnitAt(base.length - 1);
    if (last >= 0x30 && last <= 0x32) {
      stress = last - 0x30;
      base = base.substring(0, base.length - 1);
    }
  }
  return [base.toUpperCase(), stress];
}

/// Per-phoneme ARPAbet→IPA with stress-dependent vowel quality (matches
/// espeak-ng reductions). Prepends ˈ/ˌ for primary/secondary stress.
String _arpaToIpa(String arpa) {
  final parts = _splitArpa(arpa);
  final base = parts[0] as String;
  final stress = parts[1] as int;

  var ipa = '';
  if (stress == 1) {
    ipa = 'ˈ';
  } else if (stress == 2) {
    ipa = 'ˌ';
  }

  // Context-free reductions.
  if (base == 'AH' && stress == 0) return '$ipaə';
  if (base == 'IH' && stress == 0) return '$ipaɪ';
  if (base == 'IY' && stress == 0) return '${ipa}i';
  if (base == 'UW' && stress == 0) return '$ipaʊ';
  if (base == 'ER' && stress >= 1) return '$ipaɜː';
  if (base == 'ER') return '$ipaɚ';

  final s = _arpabetToIpa[base];
  if (s == null) return '';
  return ipa + s;
}

// ── LTS: word (lowercased) → ARPAbet phonemes (with stress digits) ──────────
List<String> _ltsPredict(String word) {
  final out = <String>[];
  final w = word.toLowerCase();
  final len = w.length;
  var firstVowel = true;

  void emit(String ph, int stress) {
    out.add(stress > 0 ? '$ph$stress' : ph);
  }

  int codeAt(int idx) => (idx >= 0 && idx < len) ? w.codeUnitAt(idx) : 0;

  var i = 0;
  while (i < len) {
    final c = String.fromCharCode(codeAt(i));
    final c1 = i + 1 < len ? String.fromCharCode(codeAt(i + 1)) : '';
    final c2 = i + 2 < len ? String.fromCharCode(codeAt(i + 2)) : '';

    // Trigraphs.
    if (c == 't' && c1 == 'c' && c2 == 'h') {
      emit('CH', 0);
      i += 3;
      continue;
    }
    if (c == 'i' && c1 == 'g' && c2 == 'h') {
      emit('AY', firstVowel ? 1 : 0);
      firstVowel = false;
      i += 3;
      continue;
    }
    if (c == 't' && c1 == 'i' && c2 == 'o') {
      emit('SH', 0);
      emit('AH', 0);
      i += 3;
      continue;
    }

    // Consonant digraphs.
    if (c == 't' && c1 == 'h') {
      emit('TH', 0);
      i += 2;
      continue;
    }
    if (c == 's' && c1 == 'h') {
      emit('SH', 0);
      i += 2;
      continue;
    }
    if (c == 'c' && c1 == 'h') {
      emit('CH', 0);
      i += 2;
      continue;
    }
    if (c == 'p' && c1 == 'h') {
      emit('F', 0);
      i += 2;
      continue;
    }
    if (c == 'w' && c1 == 'h') {
      emit('W', 0);
      i += 2;
      continue;
    }
    if (c == 'n' && c1 == 'g') {
      emit('NG', 0);
      i += 2;
      continue;
    }
    if (c == 'c' && c1 == 'k') {
      emit('K', 0);
      i += 2;
      continue;
    }
    if (c == 'g' && c1 == 'h') {
      i += 2;
      continue; // silent gh
    }
    if (c == 'k' && c1 == 'n') {
      emit('N', 0);
      i += 2;
      continue;
    }
    if (c == 'w' && c1 == 'r') {
      emit('R', 0);
      i += 2;
      continue;
    }

    // "a" before "ll" → ɔː (all, call, small, ball, fall, tall, wall).
    // Reliable except a few (shall) — the dictionary tiers correct those.
    if (c == 'a' && c1 == 'l' && c2 == 'l') {
      emit('AO', firstVowel ? 1 : 0);
      emit('L', 0);
      firstVowel = false;
      i += 3;
      continue;
    }

    // Vowel digraphs.
    if (c == 'e' && (c1 == 'a' || c1 == 'e')) {
      emit('IY', firstVowel ? 1 : 0);
      firstVowel = false;
      i += 2;
      continue;
    }
    if (c == 'o' && c1 == 'o') {
      emit('UW', firstVowel ? 1 : 0);
      firstVowel = false;
      i += 2;
      continue;
    }
    if (c == 'o' && c1 == 'u') {
      emit('AW', firstVowel ? 1 : 0);
      firstVowel = false;
      i += 2;
      continue;
    }
    if (c == 'o' && c1 == 'w') {
      emit('OW', firstVowel ? 1 : 0);
      firstVowel = false;
      i += 2;
      continue;
    }
    if (c == 'a' && (c1 == 'i' || c1 == 'y')) {
      emit('EY', firstVowel ? 1 : 0);
      firstVowel = false;
      i += 2;
      continue;
    }
    if (c == 'o' && (c1 == 'i' || c1 == 'y')) {
      emit('OY', firstVowel ? 1 : 0);
      firstVowel = false;
      i += 2;
      continue;
    }
    if (c == 'a' && c1 == 'w') {
      emit('AO', firstVowel ? 1 : 0);
      firstVowel = false;
      i += 2;
      continue;
    }
    if (c == 'e' && c1 == 'w') {
      emit('UW', firstVowel ? 1 : 0);
      firstVowel = false;
      i += 2;
      continue;
    }
    if (c == 'e' && c1 == 'r') {
      emit('ER', firstVowel ? 1 : 0);
      firstVowel = false;
      i += 2;
      continue;
    }

    // Silent final e.
    if (c == 'e' && i == len - 1 && i > 0) {
      i++;
      continue;
    }

    // Single consonants.
    const singleCons = {
      'b': 'B',
      'd': 'D',
      'f': 'F',
      'g': 'G',
      'h': 'HH',
      'j': 'JH',
      'k': 'K',
      'l': 'L',
      'm': 'M',
      'n': 'N',
      'p': 'P',
      'q': 'K',
      'r': 'R',
      's': 'S',
      't': 'T',
      'v': 'V',
      'w': 'W',
      'y': 'Y',
      'z': 'Z',
    };
    final sc = singleCons[c];
    if (sc != null) {
      emit(sc, 0);
      i++;
      continue;
    }
    if (c == 'x') {
      emit('K', 0);
      emit('S', 0);
      i++;
      continue;
    }

    // Single vowels.
    if (c == 'a') {
      emit('AE', firstVowel ? 1 : 0);
      firstVowel = false;
      i++;
      continue;
    }
    if (c == 'e') {
      emit('EH', firstVowel ? 1 : 0);
      firstVowel = false;
      i++;
      continue;
    }
    if (c == 'i') {
      emit('IH', firstVowel ? 1 : 0);
      firstVowel = false;
      i++;
      continue;
    }
    if (c == 'o') {
      emit('AA', firstVowel ? 1 : 0);
      firstVowel = false;
      i++;
      continue;
    }
    if (c == 'u') {
      emit('AH', firstVowel ? 1 : 0);
      firstVowel = false;
      i++;
      continue;
    }
    if (c == 'c') {
      emit((c1 == 'e' || c1 == 'i' || c1 == 'y') ? 'S' : 'K', 0);
      i++;
      continue;
    }
    i++; // unknown
  }
  return out;
}

// ── Minimal espeak override table (truly irregular function words) ──────────
const Map<String, String> _espeakOverrides = {
  'THE': 'ðə',
  'A': 'ə',
  'WOMEN': 'wˈɪmɪn',
  'COLONEL': 'kˈɜːnəl',
  'WEDNESDAY': 'wˈɛnzdeɪ',
};

/// Context-sensitive ARPAbet→IPA conversion of a full phoneme sequence.
/// Applies T-flapping (T/D between a vowel and an unstressed vowel → ɾ) and
/// linking-ɹ after ER before a vowel.
String _arpaSeqToIpa(List<String> phones) {
  final ipa = StringBuffer();
  final n = phones.length;
  for (var pi = 0; pi < n; pi++) {
    final ph = phones[pi];
    final parts = _splitArpa(ph);
    final base = parts[0] as String;

    // T-flapping.
    if ((base == 'T' || base == 'D') && pi > 0 && pi + 1 < n) {
      final prevBase = (_splitArpa(phones[pi - 1])[0]) as String;
      final next = phones[pi + 1];
      final nextUnstressed = next.isNotEmpty && next.endsWith('0');
      if (_arpaVowels.contains(prevBase) && nextUnstressed) {
        ipa.write('ɾ');
        continue;
      }
    }

    final p = _arpaToIpa(ph);
    if (p.isEmpty) continue;
    ipa.write(p);

    // Linking-ɹ after ER before a vowel.
    if (base == 'ER' && pi + 1 < n) {
      final nextBase = (_splitArpa(phones[pi + 1])[0]) as String;
      if (_arpaVowels.contains(nextBase)) ipa.write('ɹ');
    }
  }
  return ipa.toString();
}

/// Convert a CMUdict-style ARPAbet phone list (e.g. `['HH','AH0','L','OW1']`)
/// to espeak-style IPA using the same context-sensitive conversion as the LTS
/// path (T-flapping, linking-ɹ, stress-dependent reductions). Public so the
/// dictionary tier ([PronunciationDictionary.fromCmudict]) and the bundled-dict
/// generator can turn public-domain CMUdict into IPA with our own mapping.
String arpabetToIpa(List<String> arpaPhones) => _arpaSeqToIpa(arpaPhones);

/// Single word → IPA (LTS path only: overrides / bundled lexicon / rules).
String wordToIpaEn(String word) {
  final lower = word.toLowerCase();
  final upper = word.toUpperCase();

  // Bundled high-frequency exception lexicon (espeak-style IPA).
  final lex = kEnLexicon[lower];
  if (lex != null) return lex;

  // espeak override table.
  final ov = _espeakOverrides[upper];
  if (ov != null) return ov;

  return _arpaSeqToIpa(_ltsPredict(word));
}

// ── Technical-token normalization (C++, C++ → "C plus plus", etc.) ──────────
const List<List<String>> _techTokenRules = [
  ['C++', 'C plus plus'],
  ['C#', 'C sharp'],
  ['F#', 'F sharp'],
  ['.NET', 'dot net'],
  ['Node.js', 'Node J S'],
  ['TypeScript', 'Type Script'],
  ['JavaScript', 'Java Script'],
  ['GitHub', 'Git Hub'],
  ['GitLab', 'Git Lab'],
  ['iOS', 'I O S'],
  ['macOS', 'mac O S'],
];

bool _isWordBoundaryChar(String ch) => ' ,.!?;:-\n\t()"\''.contains(ch);

String _normalizeTechnicalTokens(String text) {
  final sb = StringBuffer();
  var i = 0;
  while (i < text.length) {
    var matched = false;
    final atStart = i == 0 || _isWordBoundaryChar(text[i - 1]);
    if (atStart) {
      for (final rule in _techTokenRules) {
        final pat = rule[0];
        final plen = pat.length;
        if (i + plen <= text.length &&
            text.substring(i, i + plen).toLowerCase() == pat.toLowerCase() &&
            (i + plen >= text.length || _isWordBoundaryChar(text[i + plen]))) {
          sb.write(rule[1]);
          i += plen;
          matched = true;
          break;
        }
      }
    }
    if (!matched) {
      sb.write(text[i]);
      i++;
    }
  }
  return sb.toString();
}

const String _punct = ',.!?;:-';

/// Split text into words + kept punctuation tokens.
List<String> _tokenize(String text) {
  final tokens = <String>[];
  final cur = StringBuffer();
  for (final ch in text.split('')) {
    if (ch == ' ' || ch == '\n' || _punct.contains(ch)) {
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

/// Full text → IPA string (words joined by spaces; punctuation collapses to a
/// space, mirroring the reference builtin path).
///
/// [lookup] is an optional dictionary tier consulted per word BEFORE the
/// lexicon/LTS fallback ([wordToIpaEn]); the phonemizer wires the injected +
/// bundled dicts through it. Returning null defers to the rules.
String textToIpaEn(String text, {String? Function(String word)? lookup}) {
  final words = _tokenize(_normalizeTechnicalTokens(text));
  final ipa = StringBuffer();
  for (final w in words) {
    if (w.length == 1 && _punct.contains(w)) {
      if (ipa.isNotEmpty && !ipa.toString().endsWith(' ')) ipa.write(' ');
      continue;
    }
    if (ipa.isNotEmpty) ipa.write(' ');
    ipa.write(lookup?.call(w) ?? wordToIpaEn(w));
  }
  return ipa.toString();
}
