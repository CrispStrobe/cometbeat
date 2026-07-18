// Library connector (A0) — the license gate, OpenScore path parsing, the import
// pipeline, and a widget pass over the browser. No live network: sources/http
// are faked; MusicXML is round-tripped through crisp_notation so it really
// parses.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/library/attribution_screen.dart';
import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/features/library/donation.dart';
import 'package:comet_beat/features/library/library_browser_screen.dart';
import 'package:comet_beat/features/library/library_import.dart';
import 'package:comet_beat/features/library/license_policy.dart';
import 'package:comet_beat/features/library/sources/commons_source.dart';
import 'package:comet_beat/features/library/sources/openscore_source.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Fakes ────────────────────────────────────────────────────────────────
class _FakeSource implements ContentSource {
  final List<LibraryItem> items;
  final Uint8List Function() fetchBytes;
  int fetchCount = 0;
  _FakeSource(this.items, this.fetchBytes);

  @override
  String get id => 'fake';
  @override
  String get name => 'Fake Source';
  @override
  String get homepage => 'https://example.org';
  @override
  String get licenseSummary => 'CC0 — public domain';

  @override
  Future<List<LibraryItem>> browse({String query = '', int limit = 60}) async {
    final q = query.toLowerCase();
    return items
        .where(
          (i) =>
              q.isEmpty ||
              i.title.toLowerCase().contains(q) ||
              i.composer.toLowerCase().contains(q),
        )
        .take(limit)
        .toList();
  }

  @override
  Future<Uint8List> fetch(LibraryItem item) async {
    fetchCount++;
    return fetchBytes();
  }
}

LibraryItem _item({
  String license = 'CC0',
  String format = 'musicxml',
  String id = 'x1',
}) =>
    LibraryItem(
      sourceId: 'fake',
      sourceName: 'Fake Source',
      id: id,
      title: 'Test Song',
      composer: 'A. Composer',
      declaredLicense: license,
      downloadUrl: Uri.parse('https://example.org/$id'),
      format: format,
      sourceUrl: 'https://example.org/work/$id',
    );

/// A minimal, really-parseable MusicXML string via a round-trip.
String _validMusicXml() =>
    scoreToMusicXml(Score.simple(notes: 'c4:q d4 e4 f4'));

Widget _wrap(Widget home, UserSongsService svc) => ChangeNotifierProvider.value(
      value: svc,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('de')],
        home: home,
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('LicensePolicy.classify', () {
    const p = LicensePolicy();
    test('classifies each family', () {
      expect(p.classify('CC0'), LicenseKind.cc0);
      expect(p.classify('Public Domain'), LicenseKind.publicDomain);
      expect(p.classify('CC BY 4.0'), LicenseKind.ccBy);
      expect(p.classify('CC BY-SA 4.0'), LicenseKind.ccBySa);
      expect(p.classify('CC BY-NC 4.0'), LicenseKind.ccByNc);
      expect(p.classify('CC BY-NC-SA'), LicenseKind.ccByNc);
      expect(p.classify('CC BY-ND'), LicenseKind.ccByNd);
      expect(p.classify('MIT'), LicenseKind.mit);
      expect(p.classify('MIT License'), LicenseKind.mit);
      expect(p.classify('Apache-2.0'), LicenseKind.apache2);
      expect(p.classify('BSD-3-Clause'), LicenseKind.bsd);
      expect(p.classify('All Rights Reserved'), LicenseKind.allRightsReserved);
      expect(p.classify(''), LicenseKind.unknown);
      expect(p.classify('some weird thing'), LicenseKind.unknown);
      // A word that merely contains "mit"/"bsd" must NOT match.
      expect(p.classify('permitted for personal use'), LicenseKind.unknown);
    });

    test('only CC0/PD are unconditional; CC BY/BY-SA need attribution', () {
      expect(LicenseKind.cc0.isUnconditional, isTrue);
      expect(LicenseKind.publicDomain.isUnconditional, isTrue);
      expect(LicenseKind.ccBy.isUnconditional, isFalse);
      expect(LicenseKind.ccBy.needsAttribution, isTrue);
      expect(LicenseKind.ccBySa.needsAttribution, isTrue);
      expect(LicenseKind.ccByNc.needsAttribution, isFalse);
    });
  });

  test('default policy = CC0/PD + permissive-software (MIT/Apache/BSD)', () {
    const p = LicensePolicy(); // default
    expect(p.gate(_item()), LicenseKind.cc0); // CC0 ok
    for (final lic in ['Public Domain', 'MIT', 'Apache-2.0', 'BSD-3-Clause']) {
      expect(p.isAllowed(_item(license: lic)), isTrue, reason: lic);
    }
    // Attribution + restrictive families are all blocked by default.
    for (final lic in ['CC BY 4.0', 'CC BY-SA 4.0', 'CC BY-NC 4.0', '']) {
      expect(
        () => p.gate(_item(license: lic)),
        throwsA(isA<LicenseBlocked>()),
        reason: lic,
      );
    }
  });

  test('opting into attribution licenses admits CC BY / CC BY-SA, not NC', () {
    const p = LicensePolicy(allowAttributionLicenses: true);
    expect(p.isAllowed(_item(license: 'CC BY 4.0')), isTrue);
    expect(p.isAllowed(_item(license: 'CC BY-SA 4.0')), isTrue);
    expect(p.isAllowed(_item(license: 'CC BY-NC 4.0')), isFalse);
    expect(p.isAllowed(_item(license: 'CC BY-ND')), isFalse);
  });

  test('attributionFor names the work, composer and license', () {
    const p = LicensePolicy();
    final a = p.attributionFor(_item());
    expect(a, contains('Test Song'));
    expect(a, contains('A. Composer'));
    expect(a, contains('CC0'));
    expect(a, contains('Fake Source'));
  });

  group('OpenScoreSource path parsing', () {
    final lieder = OpenScoreSource.lieder((_) async => Uint8List(0));
    final quartets = OpenScoreSource.stringQuartets((_) async => Uint8List(0));

    test('parseTreePaths keeps only scores files of the given extension', () {
      const tree = '''
      {"tree": [
        {"path": "data/corpus_conversion.json"},
        {"path": "scores/Arne,_Thomas/_/Rule,_Britannia!/lc29233346.mscx"},
        {"path": "scores/Arne,_Thomas/_/Rule,_Britannia!/lc29233346.mxl"},
        {"path": "scores/Abbott,_Jane/Set_One/A_Song/lc1.mxl"}
      ]}''';
      expect(OpenScoreSource.parseTreePaths(tree, 'mxl'), hasLength(2));
      expect(OpenScoreSource.parseTreePaths(tree, 'mscx'), hasLength(1));
    });

    test('Lieder: itemForPath humanizes composer/title + builds a raw URL', () {
      final item = lieder.itemForPath(
        'scores/Arne,_Thomas/_/Rule,_Britannia!/lc29233346.mxl',
      )!;
      expect(item.composer, 'Thomas Arne');
      expect(item.title, 'Rule, Britannia!');
      expect(item.collection, '');
      expect(item.id, 'lc29233346');
      expect(item.declaredLicense, 'CC0');
      expect(item.format, 'mxl');
      expect(item.downloadUrl.host, 'raw.githubusercontent.com');
      expect(item.downloadUrl.path, contains('lc29233346.mxl'));
    });

    test('Quartets: shallower path + .mscx format parse', () {
      final item = quartets.itemForPath(
        'scores/Beach,_Amy/String_Quartet,_Op._89/sq14387632.mscx',
      )!;
      expect(item.composer, 'Amy Beach');
      expect(item.title, 'String Quartet, Op. 89');
      expect(item.id, 'sq14387632');
      expect(item.format, 'mscx');
      expect(item.downloadUrl.path, contains('OpenScore/StringQuartets/main'));
    });

    test('browse filters by query against a faked tree', () async {
      const tree = '''
      {"tree": [
        {"path": "scores/Arne,_Thomas/_/Rule,_Britannia!/lc1.mxl"},
        {"path": "scores/Schubert,_Franz/_/Ave_Maria/lc2.mxl"}
      ]}''';
      final s = OpenScoreSource.lieder((_) async => utf8.encode(tree));
      final all = await s.browse();
      expect(all, hasLength(2));
      final schubert = await s.browse(query: 'schubert');
      expect(schubert, hasLength(1));
      expect(schubert.single.composer, 'Franz Schubert');
    });
  });

  group('CommonsSource (per-file licenses)', () {
    const commonsJson = '''
    {"query":{"pages":{
      "1":{"pageid":1,"title":"File:Free Tune.mid","imageinfo":[{"url":"https://upload.wikimedia.org/x/Free_Tune.mid","extmetadata":{"LicenseShortName":{"value":"CC0"},"Artist":{"value":"<a>Jane Doe</a>"}}}]},
      "2":{"pageid":2,"title":"File:Share Alike.mid","imageinfo":[{"url":"https://upload.wikimedia.org/x/Share_Alike.mid","extmetadata":{"LicenseShortName":{"value":"CC BY-SA 4.0"}}}]},
      "3":{"pageid":3,"title":"File:No Commercial.mid","imageinfo":[{"url":"https://upload.wikimedia.org/x/No_Commercial.mid","extmetadata":{"LicenseShortName":{"value":"CC BY-NC 2.0"}}}]}
    }}}''';

    test('parseSearch reads title/license/composer, strips File:/.mid + HTML',
        () {
      final src = CommonsSource((_) async => Uint8List(0));
      final items = src.parseSearch(commonsJson);
      expect(items, hasLength(3));
      final free = items.firstWhere((i) => i.title == 'Free Tune');
      expect(free.declaredLicense, 'CC0');
      expect(free.composer, 'Jane Doe'); // <a> stripped
      expect(free.format, 'midi');
      expect(free.sourceUrl, contains('commons.wikimedia.org/wiki/'));
    });

    test('default browse surfaces ONLY totally-free (CC0/PD) files', () async {
      final src = CommonsSource((_) async => utf8.encode(commonsJson));
      final items = await src.browse();
      // Default policy: only the CC0 file; CC BY-SA and NC both dropped.
      expect(items.map((i) => i.declaredLicense).toList(), ['CC0']);
    });

    test('opting into attribution licenses also admits CC BY-SA, never NC',
        () async {
      final src = CommonsSource(
        (_) async => utf8.encode(commonsJson),
        policy: const LicensePolicy(allowAttributionLicenses: true),
      );
      final licenses = (await src.browse()).map((i) => i.declaredLicense);
      expect(licenses, contains('CC0'));
      expect(licenses, contains('CC BY-SA 4.0'));
      expect(licenses.any((l) => l.contains('NC')), isFalse); // still filtered
    });
  });

  group('pipeline decodes multiple formats + donation config', () {
    final xml = _validMusicXml();

    test('bytesToMusicXml handles mscx and midi', () {
      final score = scoreFromMusicXml(xml);
      final mscx = Uint8List.fromList(utf8.encode(scoreToMscx(score)));
      final midi = scoreToMidi(score);
      // Each decodes back to a parseable MusicXML.
      expect(
        scoreFromMusicXml(bytesToMusicXml('mscx', mscx)).measures,
        isNotEmpty,
      );
      expect(
        scoreFromMusicXml(bytesToMusicXml('midi', midi)).measures,
        isNotEmpty,
      );
    });

    test('DonationConfig is off by default and needs a URL', () {
      expect(const DonationConfig().isActive, isFalse);
      expect(const DonationConfig(enabled: true).isActive, isFalse);
      expect(
        const DonationConfig(enabled: true, url: 'https://ko-fi.com/x')
            .isActive,
        isTrue,
      );
    });
  });

  group('importLibraryItem pipeline', () {
    test('permissive item → ImportedSong with provenance', () async {
      final src = _FakeSource(
        [_item()],
        () => utf8.encode(_validMusicXml()),
      );
      final song = await importLibraryItem(_item(), src);
      expect(song.title, 'Test Song');
      expect(song.attribution, contains('CC0'));
      expect(song.sourceUrl, isNotNull);
      expect(song.score.measures, isNotEmpty); // really parsed
      expect(src.fetchCount, 1);
    });

    test('non-permissive item is blocked BEFORE any fetch', () async {
      final src = _FakeSource(
        [],
        () => Uint8List(0),
      );
      await expectLater(
        importLibraryItem(_item(license: 'CC BY-NC 4.0'), src),
        throwsA(isA<LicenseBlocked>()),
      );
      expect(src.fetchCount, 0); // gate ran before fetch
    });
  });

  testWidgets('donation tile hidden by default, shown when enabled',
      (tester) async {
    final svc = UserSongsService();

    await tester.pumpWidget(_wrap(const AttributionScreen(), svc));
    await tester.pump();
    expect(find.byIcon(Icons.local_cafe), findsNothing);

    await tester.pumpWidget(
      _wrap(
        const AttributionScreen(
          donation: DonationConfig(enabled: true, url: 'https://ko-fi.com/x'),
        ),
        svc,
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.local_cafe), findsOneWidget);
  });

  testWidgets('browser lists items and imports one into the Song Book',
      (tester) async {
    final svc = UserSongsService();
    final src = _FakeSource(
      [_item()],
      () => utf8.encode(_validMusicXml()),
    );
    await tester.pumpWidget(
      _wrap(LibraryBrowserScreen(sources: [src]), svc),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Song'), findsOneWidget);
    expect(svc.songs, isEmpty);

    await tester.tap(find.byIcon(Icons.download));
    await tester.pumpAndSettle();

    expect(svc.songs, hasLength(1));
    expect(svc.songs.single.attribution, contains('CC0'));
  });
}
