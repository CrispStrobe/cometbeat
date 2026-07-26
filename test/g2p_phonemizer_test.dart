// Tests for the pure-Dart Kokoro G2P phonemizer.
//
// dart:io is used HERE (test only, runs on the VM) to read the CrispASR
// ground-truth TSVs. The library under test stays pure Dart.
//
// The built-in LTS G2P *approximates* espeak-ng, so exact match to the espeak
// ground truth is not expected to be 100%. This test measures and prints the
// honest exact-match and close-match (phoneme-set overlap) rates, separating
// the bundled-lexicon subset from the pure-LTS (generalising) subset, and
// asserts conservative floors so it documents the real numbers.

import 'dart:io';

import 'package:comet_beat/core/audio/tts/g2p/g2p_de_lexicon.dart';
import 'package:comet_beat/core/audio/tts/g2p/g2p_en_lexicon.dart';
import 'package:comet_beat/core/audio/tts/g2p/g2p_phonemizer.dart';
import 'package:comet_beat/core/audio/tts/g2p/kokoro_vocab.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Normalisation helpers for comparison ────────────────────────────────────

const _zwj = '‍'; // zero-width joiner (espeak diphthong glue)
const _stress = {'ˈ', 'ˌ'};
const _combining = {'̃', '̯', '̩', '͡'}; // tilde, breve, syllabic, tie

/// Normalise for exact comparison: drop ZWJ and stray tie/combining glue that
/// differ only in representation, keep everything else (stress, length, vowels).
String _normExact(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    if (c == _zwj) continue;
    b.write(c);
  }
  return b.toString();
}

/// Reduce to a bag of "phoneme atoms" for overlap scoring: drop ZWJ, stress
/// marks and combining diacritics; keep base IPA symbols.
List<String> _atoms(String s) {
  final out = <String>[];
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    if (c == _zwj || c == ' ') continue;
    if (_stress.contains(c)) continue;
    if (_combining.contains(c)) continue;
    out.add(c);
  }
  return out;
}

/// Jaccard overlap of the phoneme-atom multisets (as sets).
double _jaccard(String a, String b) {
  final sa = _atoms(a).toSet();
  final sb = _atoms(b).toSet();
  if (sa.isEmpty && sb.isEmpty) return 1.0;
  final inter = sa.intersection(sb).length;
  final union = sa.union(sb).length;
  return union == 0 ? 1.0 : inter / union;
}

/// Locate a ground-truth TSV relative to the repo (mus/ → ../CrispASR/tools).
File? _findTsv(String name) {
  final candidates = [
    '../CrispASR/tools/$name',
    '${Directory.current.path}/../CrispASR/tools/$name',
    '/Users/christianstrobele/code/CrispASR/tools/$name',
  ];
  for (final p in candidates) {
    final f = File(p);
    if (f.existsSync()) return f;
  }
  return null;
}

class _Report {
  int total = 0;
  int exact = 0;
  int close = 0; // Jaccard >= 0.5
  double jaccardSum = 0;
  int lexCovered = 0;
  int lexExact = 0;
  int ltsTotal = 0;
  int ltsExact = 0;
  int ltsClose = 0;
  final examples = <String>[];
}

_Report _evaluate(File tsv, String lang, Set<String> lexKeys) {
  final r = _Report();
  final lines = tsv.readAsLinesSync();
  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final cols = line.split('\t');
    if (cols.length < 2) continue;
    if (cols[0] == 'word') continue; // header
    final word = cols[0];
    final truth = _normExact(cols[1]);
    final pred = _normExact(phonemizeToIpa(word, lang: lang));

    r.total++;
    final isExact = pred == truth;
    final jac = _jaccard(pred, truth);
    r.jaccardSum += jac;
    if (isExact) r.exact++;
    if (jac >= 0.5) r.close++;

    final inLex = lexKeys.contains(word.toLowerCase());
    if (inLex) {
      r.lexCovered++;
      if (isExact) r.lexExact++;
    } else {
      r.ltsTotal++;
      if (isExact) r.ltsExact++;
      if (jac >= 0.5) r.ltsClose++;
    }

    if (r.examples.length < 8) {
      r.examples.add('  $word → "$pred"  (espeak "$truth")  '
          'exact=$isExact jac=${jac.toStringAsFixed(2)}');
    }
  }
  return r;
}

void _print(String lang, _Report r) {
  double pct(int a, int b) => b == 0 ? 0 : 100 * a / b;
  // ignore: avoid_print
  print('\n═══ $lang ground truth (n=${r.total}) ═══');
  // ignore: avoid_print
  print('  exact-match    : ${r.exact}/${r.total}  '
      '(${pct(r.exact, r.total).toStringAsFixed(1)}%)');
  // ignore: avoid_print
  print('  close-match≥.5 : ${r.close}/${r.total}  '
      '(${pct(r.close, r.total).toStringAsFixed(1)}%)');
  // ignore: avoid_print
  print('  mean Jaccard   : ${(r.jaccardSum / r.total).toStringAsFixed(3)}');
  // ignore: avoid_print
  print('  lexicon subset : exact ${r.lexExact}/${r.lexCovered}');
  // ignore: avoid_print
  print('  LTS-only subset: exact ${r.ltsExact}/${r.ltsTotal} '
      '(${pct(r.ltsExact, r.ltsTotal).toStringAsFixed(1)}%), '
      'close ${r.ltsClose}/${r.ltsTotal} '
      '(${pct(r.ltsClose, r.ltsTotal).toStringAsFixed(1)}%)');
  // ignore: avoid_print
  print('  examples:');
  for (final e in r.examples) {
    // ignore: avoid_print
    print(e);
  }
}

void main() {
  group('kokoro token contract', () {
    test('kokoroTokens is pad-wrapped [0, ...ids, 0]', () {
      final t = kokoroTokens('hello');
      expect(t.length, greaterThanOrEqualTo(2));
      expect(t.first, kKokoroPadId);
      expect(t.last, kKokoroPadId);
      // Interior ids are real vocab ids (0 only appears as the wrap pads here).
      final interior = t.sublist(1, t.length - 1);
      expect(interior, isNotEmpty);
      for (final id in interior) {
        expect(id, inInclusiveRange(1, 177));
      }
    });

    test('vocab is the 178-slot Kokoro space, pad "\$"=0', () {
      expect(kKokoroPadId, 0);
      expect(kKokoroTokenToId[r'$'], 0);
      expect(kKokoroTokenToId['ˈ'], 156); // primary stress
      expect(kKokoroTokenToId['ː'], 158); // length
      expect(kKokoroTokenToId['ɡ'], 92); // script g
      expect(kKokoroTokenToId[' '], 16); // space is a token
      // Every id is within the 0..177 Kokoro range.
      for (final id in kKokoroTokenToId.values) {
        expect(id, inInclusiveRange(0, 177));
      }
    });

    test('ids round-trip against phonemizeToIpa', () {
      const text = 'the music';
      final ipa = phonemizeToIpa(text);
      final raw = ipaToTokenIds(ipa);
      final wrapped = kokoroTokens(text);
      expect(wrapped, [kKokoroPadId, ...raw, kKokoroPadId]);
    });
  });

  group('hand-picked unit cases', () {
    test('English words phonemize to plausible IPA', () {
      expect(phonemizeToIpa('hello'), 'hɐlˈoʊ');
      expect(phonemizeToIpa('world'), contains('w'));
      // A word not in the lexicon still produces IPA via LTS.
      final lts = phonemizeToIpa('splunge');
      expect(lts, isNotEmpty);
      expect(lts, contains('l'));
    });

    test('German words phonemize to plausible IPA', () {
      expect(phonemizeToIpa('hallo', lang: 'de'), 'hˈaloː');
      expect(phonemizeToIpa('welt', lang: 'de'), 'vˈɛlt');
      // LTS fallback for an OOV German word: sch→ʃ, open-syllable lengthening.
      final lts = phonemizeToIpa('schlafenzimmerlampe', lang: 'de');
      expect(lts, contains('ʃ'));
    });

    test('empty / punctuation-only input yields just pad wrap', () {
      final t = kokoroTokens('');
      expect(t, [kKokoroPadId, kKokoroPadId]);
    });
  });

  group('ground-truth match rates (honest, documented)', () {
    test('English + German espeak ground truth', () {
      final en = _findTsv('g2p_ground_truth_en.tsv');
      final de = _findTsv('g2p_ground_truth_de.tsv');
      if (en == null || de == null) {
        // ignore: avoid_print
        print(
          'ground-truth TSVs not found next to repo — skipping rate asserts',
        );
        return;
      }

      final enR = _evaluate(en, 'en', kEnLexicon.keys.toSet());
      final deR = _evaluate(de, 'de', kDeLexicon.keys.toSet());
      _print('EN', enR);
      _print('DE', deR);

      // Conservative floors set just below the measured rates (printed above).
      // They document the real numbers and guard against regressions:
      //   EN exact ≈32.5%, close ≈71.7% (LTS-only close ≈60.8%)
      //   DE exact ≈26.6%, close ≈95.7% (LTS-only close ≈93.1%)
      expect(
        enR.exact / enR.total,
        greaterThanOrEqualTo(0.28),
        reason: 'EN exact-match regressed',
      );
      expect(
        enR.close / enR.total,
        greaterThanOrEqualTo(0.66),
        reason: 'EN close-match regressed',
      );
      expect(
        deR.exact / deR.total,
        greaterThanOrEqualTo(0.22),
        reason: 'DE exact-match regressed',
      );
      expect(
        deR.close / deR.total,
        greaterThanOrEqualTo(0.90),
        reason: 'DE close-match regressed',
      );
      // Pure-LTS generalisation floor (non-lexicon subset).
      expect(
        enR.ltsClose / enR.ltsTotal,
        greaterThanOrEqualTo(0.55),
        reason: 'EN LTS-only close-match regressed',
      );
    });
  });
}
