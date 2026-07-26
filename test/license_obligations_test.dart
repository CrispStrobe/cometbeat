// SA-propagation: what the app owes when licensed material reaches an export.
//
// docs/CORPUS_LICENSING.md blocks Tier C (share-alike) from shipping until "the
// app enforces SA-propagation". These tests are that rule, and they lean on the
// cases that actually bite: a licence string that contradicts its label, NC
// hidden inside a share-alike name, and two copylefts that cannot legally be
// merged.

import 'package:comet_beat/core/licensing/license_obligations.dart';
import 'package:flutter_test/flutter_test.dart';

LicensedWork _w(String license, {String title = 'thing', String? creator}) =>
    LicensedWork(title: title, license: license, creator: creator);

void main() {
  group('licenseTierOf — the licence text decides', () {
    test('public-domain-ish strings are tier A', () {
      for (final s in [
        'CC0-1.0',
        'CC0 1.0 Universal',
        'public domain',
        'MIT',
        'Apache-2.0',
        'BSD-3-Clause',
      ]) {
        expect(licenseTierOf(s), LicenseTier.a, reason: s);
      }
    });

    test('"Gemeinfrei" alone is NOT treated as free', () {
      // Deliberate, and it cost me a wrong assumption: docs/CORPUS_LICENSING.md
      // says "gemeinfrei" / "GEMA-frei" ≠ "free to bundle". The word describes
      // a belief about the underlying work, not a licence grant, so it fails
      // closed rather than being read as public domain.
      expect(licenseTierOf('Gemeinfrei'), LicenseTier.unknown);
      expect(licenseTierOf('Gemeinfrei').isShippable, isFalse);
    });

    test('attribution licences are tier B', () {
      for (final s in [
        'CC-BY-4.0',
        'CC BY 3.0',
        'Creative Commons Attribution 4.0',
      ]) {
        expect(licenseTierOf(s), LicenseTier.b, reason: s);
      }
    });

    test('share-alike is tier C, including ODbL and GPL', () {
      for (final s in [
        'CC-BY-SA-4.0',
        'CC BY-SA 3.0',
        'ODbL',
        'Open Database License',
        'GPL-3.0',
        'CPDL License',
      ]) {
        expect(licenseTierOf(s), LicenseTier.c, reason: s);
      }
    });

    test('non-commercial is tier D even when it also says share-alike', () {
      // The trap: "CC BY-NC-SA" contains "SA". Reading it as share-alike-and-
      // therefore-shippable would ship NC material.
      expect(licenseTierOf('CC-BY-NC-SA-4.0'), LicenseTier.d);
      expect(licenseTierOf('CC BY-NC 4.0'), LicenseTier.d);
    });

    test('a bare "Noncommercial" is at least non-shippable', () {
      // The shared classifier only reads NC as a CC clause, so a licence-less
      // "Noncommercial" lands in unknown rather than D. Both are blocked, which
      // is what actually matters — asserted on the OUTCOME so this test doesn't
      // pin an implementation detail of the spine.
      expect(licenseTierOf('Noncommercial').isShippable, isFalse);
    });

    test('no-derivatives cannot be used in a derived work', () {
      expect(licenseTierOf('CC-BY-ND-4.0'), LicenseTier.unknown);
    });

    test('unstated or unrecognised is unknown, never assumed free', () {
      for (final s in ['', '   ', 'all rights reserved', 'ask me', '?']) {
        expect(licenseTierOf(s), LicenseTier.unknown, reason: '"$s"');
      }
    });

    test('an optimistic label cannot downgrade a restrictive licence', () {
      // The emit_catalog lesson: 8,790 rows said CC0 but carried CC-BY text.
      // Only the text is consulted here, so the tier follows the licence.
      expect(
        licenseTierOf('Creative Commons Attribution 4.0'),
        LicenseTier.b,
      );
    });
  });

  group('obligations', () {
    test('all-permissive owes nothing', () {
      final o = obligationsFor([_w('CC0-1.0'), _w('MIT')]);
      expect(o.isClear, isTrue);
      expect(o.requiresAttribution, isFalse);
      expect(o.requiresShareAlike, isFalse);
      expect(o.noticeText(), isEmpty);
    });

    test('one CC-BY work requires attribution but not share-alike', () {
      final o = obligationsFor([
        _w('CC0-1.0'),
        _w('CC-BY-4.0', title: 'Sample', creator: 'A. Person'),
      ]);
      expect(o.requiresAttribution, isTrue);
      expect(o.requiresShareAlike, isFalse);
      expect(o.strongestTier, LicenseTier.b);
      expect(o.noticeText(), contains('A. Person'));
      expect(o.noticeText(), isNot(contains('share-alike')));
    });

    test('ONE share-alike work makes the whole output share-alike', () {
      // The infectiousness is the entire point of the requirement.
      final o = obligationsFor([
        _w('CC0-1.0'),
        _w('MIT'),
        _w('CC-BY-SA-4.0', title: 'Setting', creator: 'U. Wolf'),
      ]);
      expect(o.requiresShareAlike, isTrue);
      expect(o.shareAlikeLicense, 'CC BY-SA 4.0');
      expect(o.strongestTier, LicenseTier.c);
      expect(
        o.noticeText(),
        contains('the whole of it is licensed CC BY-SA 4.0'),
      );
      expect(o.noticeText(), contains('U. Wolf'));
    });

    test('mixed CC-BY-SA versions resolve to the NEWEST', () {
      // BY-SA allows relicensing an adaptation under a later version, so 3.0 +
      // 4.0 ships as 4.0. Claiming 3.0 would under-license the 4.0 material.
      final o = obligationsFor([
        _w('CC-BY-SA-3.0'),
        _w('CC-BY-SA-4.0'),
      ]);
      expect(o.shareAlikeLicense, 'CC BY-SA 4.0');
      expect(o.conflicts, isEmpty);
    });

    test('ODbL + CC-BY-SA is a CONFLICT, not a silent choice', () {
      // Two different copylefts cannot both govern one output, and picking one
      // for the user would be inventing permission.
      final o = obligationsFor([
        _w('ODbL', title: 'Tune database'),
        _w('CC-BY-SA-4.0', title: 'Setting'),
      ]);
      expect(o.hasProblem, isTrue);
      expect(o.conflicts, hasLength(1));
      expect(o.conflicts.single, contains('CC BY-SA'));
      expect(o.conflicts.single, contains('ODbL'));
      expect(o.shareAlikeLicense, isNull); // refuses to guess
    });

    test('NC material is reported as blocking, not merely attributed', () {
      final o = obligationsFor([
        _w('CC0-1.0'),
        _w('CC-BY-NC-4.0', title: 'IDMT eval set'),
      ]);
      expect(o.hasProblem, isTrue);
      expect(o.blocking.single.title, 'IDMT eval set');
      expect(o.strongestTier, LicenseTier.d);
    });

    test('unstated material blocks too', () {
      final o = obligationsFor([_w('')]);
      expect(o.blocking, hasLength(1));
      expect(o.strongestTier, LicenseTier.unknown);
    });

    test('the same work twice is credited once', () {
      final w = _w('CC-BY-4.0', title: 'Loop', creator: 'A');
      final o = obligationsFor([w, w, w]);
      expect(o.works, hasLength(1));
      expect('\n'.allMatches(o.noticeText()).length, 1);
    });

    test('credit order is stable, so a notice does not churn', () {
      // Distinctive titles on purpose: a single letter "B" would also match the
      // B inside "CC BY-SA" in the notice header and test nothing.
      final works = [
        _w('CC-BY-4.0', title: 'Bravo loop'),
        _w('CC-BY-SA-4.0', title: 'Alpha setting'),
        _w('CC-BY-4.0', title: 'Charlie sample'),
      ];
      final first = obligationsFor(works).noticeText();
      final second = obligationsFor(works).noticeText();
      expect(first, second);
      expect(
        first.indexOf('Bravo loop'),
        lessThan(first.indexOf('Charlie sample')),
      );
      // Input order, not licence order — the SA work stays where it was.
      expect(
        first.indexOf('Bravo loop'),
        lessThan(first.indexOf('Alpha setting')),
      );
    });

    test('an empty document owes nothing', () {
      final o = obligationsFor(const []);
      expect(o.isClear, isTrue);
      expect(o.works, isEmpty);
      expect(o.noticeText(), isEmpty);
    });

    test('tier A works are still listed, for callers that want a full bill',
        () {
      final o = obligationsFor([_w('CC0-1.0', title: 'Free thing')]);
      expect(o.works, hasLength(1));
      expect(o.attributable, isEmpty); // listed, but nothing owed
    });
  });

  group('the notice itself', () {
    test('names the licence the OUTPUT must carry, not just the inputs', () {
      final o = obligationsFor([_w('CC-BY-SA-4.0', title: 'X')]);
      final notice = o.noticeText();
      // The requirement is that the export "affirms SA on the output" — so the
      // notice has to say the whole work is SA, not merely list an SA input.
      expect(notice, contains('the whole of it is licensed'));
    });

    test('includes a url when there is one', () {
      final o = obligationsFor([
        const LicensedWork(
          title: 'Song',
          license: 'CC-BY-4.0',
          url: 'https://example.org/song',
        ),
      ]);
      expect(o.noticeText(), contains('<https://example.org/song>'));
    });

    test('skips unknown fields instead of printing null', () {
      final o = obligationsFor([_w('CC-BY-4.0', title: 'Bare')]);
      expect(o.noticeText(), isNot(contains('null')));
    });
  });
}
