// Tests for the pure-Dart Kokoro G2P phonemizer.
//
// dart:io is used HERE (test only, runs on the VM) to read the CrispASR
// ground-truth TSVs (espeak IPA — TEST ORACLE ONLY, never bundled) and, when
// present, the full clean-licensed dicts (CMUdict PD / OLaPh MIT) to report the
// production-ceiling accuracy. The library under test stays pure Dart.
//
// The rules + bundled dicts APPROXIMATE espeak-ng, so exact match to the espeak
// ground truth is not 100%. This test measures and prints the honest exact and
// close (phoneme-set overlap) rates, split into dict-covered / lexicon / pure-
// LTS buckets, and asserts conservative floors that document the real numbers.

import 'dart:io';

import 'package:comet_beat/core/audio/tts/g2p/g2p_de_lexicon.dart';
import 'package:comet_beat/core/audio/tts/g2p/g2p_en_lexicon.dart';
import 'package:comet_beat/core/audio/tts/g2p/g2p_phonemizer.dart';
import 'package:comet_beat/core/audio/tts/g2p/kokoro_vocab.dart';
import 'package:comet_beat/core/audio/tts/g2p/pron_dict.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Normalisation helpers for comparison ────────────────────────────────────

const _zwj = '‍'; // U+200D zero-width joiner (espeak diphthong glue)
const _nonSyll = '̯'; // U+032F combining inverted breve (non-syllabic marker)
const _stress = {'ˈ', 'ˌ'};
const _combining = {'̃', '̯', '̩', '͡', '̪', '̬', '̥'};

/// Normalise for exact comparison: strip the two ways of writing the same
/// diphthong tie (espeak's ZWJ vs our combining breve) — both drop to nothing
/// under Kokoro tokenisation anyway — and keep stress/length/vowels.
String _normExact(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    if (c == _zwj || c == _nonSyll) continue;
    b.write(c);
  }
  return b.toString();
}

/// Bag of phoneme atoms: drop ZWJ/space/stress/combining, keep base symbols.
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

double _jaccard(String a, String b) {
  final sa = _atoms(a).toSet();
  final sb = _atoms(b).toSet();
  if (sa.isEmpty && sb.isEmpty) return 1.0;
  final union = sa.union(sb).length;
  return union == 0 ? 1.0 : sa.intersection(sb).length / union;
}

File? _find(String name, List<String> dirs) {
  for (final d in dirs) {
    final f = File('$d/$name');
    if (f.existsSync()) return f;
  }
  return null;
}

File? _findTsv(String name) => _find(name, [
      '../CrispASR/tools',
      '${Directory.current.path}/../CrispASR/tools',
      '/Users/christianstrobele/code/CrispASR/tools',
    ]);

// Scratch dir where the full clean dicts may have been downloaded (optional).
File? _findDict(String name) => _find(name, [
      '/private/tmp/claude-501/-Users-christianstrobele-code-mus/'
          '8f182077-f4c7-48f0-afac-eac2a3af741a/scratchpad',
      Directory.systemTemp.path,
    ]);

class _Report {
  int total = 0, exact = 0, close = 0;
  double jaccardSum = 0;
  int dictCovered = 0, dictExact = 0;
  int lexTotal = 0, lexExact = 0;
  int ltsTotal = 0, ltsExact = 0, ltsClose = 0;
  final examples = <String>[];
}

_Report _evaluate(
  File tsv,
  String lang,
  Set<String> lexKeys,
  PronunciationDictionary bundled, {
  PronunciationDictionary? inject,
}) {
  final r = _Report();
  for (final line in tsv.readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final cols = line.split('\t');
    if (cols.length < 2 || cols[0] == 'word') continue;
    final word = cols[0];
    final truth = _normExact(cols[1]);
    final pred = _normExact(phonemizeToIpa(word, lang: lang, dict: inject));

    r.total++;
    final isExact = pred == truth;
    final jac = _jaccard(pred, truth);
    r.jaccardSum += jac;
    if (isExact) r.exact++;
    if (jac >= 0.5) r.close++;

    final inDict = (inject?.contains(word) ?? false) || bundled.contains(word);
    final inLex = lexKeys.contains(word.toLowerCase());
    if (inDict) {
      r.dictCovered++;
      if (isExact) r.dictExact++;
    } else if (inLex) {
      r.lexTotal++;
      if (isExact) r.lexExact++;
    } else {
      r.ltsTotal++;
      if (isExact) r.ltsExact++;
      if (jac >= 0.5) r.ltsClose++;
    }
    if (r.examples.length < 6) {
      r.examples.add('  $word → "$pred"  (espeak "$truth")  '
          'exact=$isExact jac=${jac.toStringAsFixed(2)}');
    }
  }
  return r;
}

void _print(String label, _Report r) {
  double pct(int a, int b) => b == 0 ? 0 : 100 * a / b;
  // ignore: avoid_print
  print('\n═══ $label (n=${r.total}) ═══');
  // ignore: avoid_print
  print('  exact-match    : ${r.exact}/${r.total}  '
      '(${pct(r.exact, r.total).toStringAsFixed(1)}%)');
  // ignore: avoid_print
  print('  close-match≥.5 : ${r.close}/${r.total}  '
      '(${pct(r.close, r.total).toStringAsFixed(1)}%)');
  // ignore: avoid_print
  print('  mean Jaccard   : ${(r.jaccardSum / r.total).toStringAsFixed(3)}');
  // ignore: avoid_print
  print('  dict-covered   : exact ${r.dictExact}/${r.dictCovered} '
      '(${pct(r.dictExact, r.dictCovered).toStringAsFixed(1)}%)');
  // ignore: avoid_print
  print('  lexicon subset : exact ${r.lexExact}/${r.lexTotal}');
  // ignore: avoid_print
  print('  pure-LTS subset: exact ${r.ltsExact}/${r.ltsTotal} '
      '(${pct(r.ltsExact, r.ltsTotal).toStringAsFixed(1)}%), '
      'close ${r.ltsClose}/${r.ltsTotal} '
      '(${pct(r.ltsClose, r.ltsTotal).toStringAsFixed(1)}%)');
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
      final interior = t.sublist(1, t.length - 1);
      expect(interior, isNotEmpty);
      for (final id in interior) {
        expect(id, inInclusiveRange(1, 177));
      }
    });

    test('vocab is the 178-slot Kokoro space, pad "\$"=0', () {
      expect(kKokoroPadId, 0);
      expect(kKokoroTokenToId[r'$'], 0);
      expect(kKokoroTokenToId['ˈ'], 156);
      expect(kKokoroTokenToId['ː'], 158);
      expect(kKokoroTokenToId['ɡ'], 92);
      expect(kKokoroTokenToId[' '], 16);
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
      expect(phonemizeToIpa('hello', useBundledDict: false), 'hɐlˈoʊ');
      expect(phonemizeToIpa('world'), contains('w'));
      final lts = phonemizeToIpa('splunge');
      expect(lts, isNotEmpty);
      expect(lts, contains('l'));
    });

    test('German words phonemize to plausible IPA', () {
      expect(
        phonemizeToIpa('hallo', lang: 'de', useBundledDict: false),
        'hˈaloː',
      );
      expect(
        phonemizeToIpa('welt', lang: 'de', useBundledDict: false),
        'vˈɛlt',
      );
      // German LTS now emits primary stress + tap r.
      expect(
        phonemizeToIpa('morgen', lang: 'de', useBundledDict: false),
        'mˈɔɾɡən',
      );
      final lts = phonemizeToIpa('schlafenzimmer', lang: 'de');
      expect(lts, contains('ʃ'));
      expect(lts, contains('ˈ')); // stress mark present
    });

    test('empty input yields just pad wrap', () {
      expect(kokoroTokens(''), [kKokoroPadId, kKokoroPadId]);
    });
  });

  group('injectable pronunciation dictionary', () {
    test('injected dict overrides rules (case-insensitive)', () {
      final d = PronunciationDictionary({'flibbertigibbet': 'fˈuːbɑː'});
      expect(phonemizeToIpa('flibbertigibbet', dict: d), 'fˈuːbɑː');
      expect(d.lookup('FLIBBERTIGIBBET'), isNotNull);
    });

    test('CMUdict parser converts ARPAbet to IPA', () {
      final d = PronunciationDictionary.fromCmudict(
        'hello HH AH0 L OW1\nworld W ER1 L D\n;;; comment\n',
      );
      expect(d.length, 2);
      // CMUdict HH AH0 L OW1 → AH0 reduces to schwa ə (vs the espeak-tuned
      // lexicon form hɐlˈoʊ); both are valid.
      expect(d.lookup('hello'), 'həlˈoʊ');
      expect(d.lookup('world'), contains('ɜː'));
    });

    test('espeak/OLaPh slash-wrapped TSV parser', () {
      final d = PronunciationDictionary.fromTsv(
        'word\tespeak_ipa\nhallo\t/hˈaloː/\n',
        slashWrapped: true,
      );
      expect(d.lookup('hallo'), 'hˈaloː');
    });

    test('bundled dicts load and are non-trivial', () {
      expect(bundledEnDict().length, greaterThan(1000));
      expect(bundledDeDict().length, greaterThan(1000));
    });
  });

  group('ground-truth match rates (honest, documented)', () {
    test('English + German espeak ground truth', () {
      final en = _findTsv('g2p_ground_truth_en.tsv');
      final de = _findTsv('g2p_ground_truth_de.tsv');
      if (en == null || de == null) {
        // ignore: avoid_print
        print('ground-truth TSVs not found — skipping rate asserts');
        return;
      }

      final enR = _evaluate(en, 'en', kEnLexicon.keys.toSet(), bundledEnDict());
      final deR = _evaluate(de, 'de', kDeLexicon.keys.toSet(), bundledDeDict());
      _print('EN out-of-box (rules + lexicon + bundled)', enR);
      _print('DE out-of-box (rules + lexicon + bundled)', deR);

      // Optional: production ceiling with the FULL clean dicts injected
      // (CMUdict PD / OLaPh MIT), if the source files are available.
      final cmu = _findDict('cmudict.dict');
      final olaph = _findDict('olaph_de.txt');
      if (cmu != null) {
        final full =
            PronunciationDictionary.fromCmudict(cmu.readAsStringSync());
        _print(
          'EN with full CMUdict injected (${full.length} words)',
          _evaluate(
            en,
            'en',
            kEnLexicon.keys.toSet(),
            bundledEnDict(),
            inject: full,
          ),
        );
      }
      if (olaph != null) {
        final full = PronunciationDictionary.fromTsv(
          olaph.readAsStringSync(),
          slashWrapped: true,
        );
        _print(
          'DE with full OLaPh injected (${full.length} words)',
          _evaluate(
            de,
            'de',
            kDeLexicon.keys.toSet(),
            bundledDeDict(),
            inject: full,
          ),
        );
      }

      // Conservative floors (just below measured; document the real numbers).
      expect(
        enR.exact / enR.total,
        greaterThanOrEqualTo(0.28),
        reason: 'EN exact regressed',
      );
      expect(
        enR.close / enR.total,
        greaterThanOrEqualTo(0.66),
        reason: 'EN close regressed',
      );
      expect(
        deR.exact / deR.total,
        greaterThanOrEqualTo(0.45),
        reason: 'DE exact regressed',
      );
      expect(
        deR.close / deR.total,
        greaterThanOrEqualTo(0.90),
        reason: 'DE close regressed',
      );
      expect(
        enR.ltsClose / enR.ltsTotal,
        greaterThanOrEqualTo(0.55),
        reason: 'EN pure-LTS close regressed',
      );
      expect(
        deR.ltsExact / deR.ltsTotal,
        greaterThanOrEqualTo(0.30),
        reason: 'DE pure-LTS exact regressed',
      );
    });
  });
}
