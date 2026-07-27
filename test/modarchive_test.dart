// The Mod Archive BYOK source + sheet. The XML tag names are verified against
// the archived docs + several OSS API clients; NOT live (no key here), so this
// pins the PARSE + the CC0/PD filtering + the key-gated sheet flow against a
// fixture faithful to that schema.

import 'dart:typed_data';

import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/features/library/license_policy.dart';
import 'package:comet_beat/features/library/modarchive_key_store.dart';
import 'package:comet_beat/features/library/modarchive_sheet.dart';
import 'package:comet_beat/features/library/sources/modarchive_source.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A PD module + a CC-BY module (the second must be dropped by default policy).
// Each `<module>` has its own <id> AND an <artist_info><artist><id> — the parse
// must scope the module id to the direct child.
const _xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<modarchive>
  <results>2</results>
  <totalpages>1</totalpages>
  <module>
    <filename>freebeat.mod</filename>
    <format>MOD</format>
    <url>https://api.modarchive.org/downloads.php?moduleid=88676</url>
    <id>88676</id>
    <songtitle>Free Beat</songtitle>
    <license><licenseid>publicdomain</licenseid><title>Public Domain</title>
      <legalurl>https://creativecommons.org/publicdomain/mark/1.0/legalcode</legalurl></license>
    <artist_info><artists>1</artists><artist><id>89200</id><alias>Chippy</alias></artist></artist_info>
  </module>
  <module>
    <filename>attrib.xm</filename>
    <format>XM</format>
    <url>https://api.modarchive.org/downloads.php?moduleid=99</url>
    <id>99</id>
    <songtitle>Attribution Tune</songtitle>
    <license><licenseid>by</licenseid><title>CC BY</title></license>
    <artist_info><artist><id>7</id><alias>SomeoneElse</alias></artist></artist_info>
  </module>
</modarchive>''';

class _FakeSource implements ContentSource {
  final List<LibraryItem> items;
  final Uint8List bytes;
  int fetchCount = 0;
  _FakeSource(this.items, this.bytes);
  @override
  String get id => 'fake';
  @override
  String get name => 'Fake Archive';
  @override
  String get homepage => 'https://x';
  @override
  String get licenseSummary => 'CC0 / PD';
  @override
  Future<List<LibraryItem>> browse({String query = '', int limit = 60}) async =>
      items;
  @override
  Future<Uint8List> fetch(LibraryItem item) async {
    fetchCount++;
    return bytes;
  }
}

Widget _wrap(Widget home) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('de')],
      home: home,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ModArchiveSource parse', () {
    final src = ModArchiveSource((_) async => Uint8List(0), 'KEY');

    test('parses modules; module id is scoped, artist id is not mixed in', () {
      final items = src.parseModules(_xml);
      expect(items, hasLength(2));
      final pd = items.first;
      expect(pd.id, 'ma_88676'); // NOT ma_89200 (that's the artist id)
      expect(pd.title, 'Free Beat');
      expect(pd.composer, 'Chippy');
      expect(pd.declaredLicense, 'Public Domain');
      expect(pd.format, 'mod');
      expect(pd.downloadUrl.toString(), contains('moduleid=88676'));
    });

    test('requestUrl: search with a query, browse-by-letter when empty', () {
      expect(src.requestUrl('drum').toString(), contains('request=search'));
      expect(src.requestUrl('drum').toString(), contains('key=KEY'));
      expect(src.requestUrl('').toString(), contains('request=view_by_list'));
    });

    test('bad XML yields no items (never throws)', () {
      expect(src.parseModules('not xml <'), isEmpty);
    });
  });

  test('browse hard-filters to CC0/PD by default; opt-in admits CC BY',
      () async {
    final def = ModArchiveSource((_) async => utf8(_xml), 'K');
    expect(
      (await def.browse()).map((i) => i.declaredLicense).toList(),
      ['Public Domain'],
    ); // CC BY dropped

    final opted = ModArchiveSource(
      (_) async => utf8(_xml),
      'K',
      policy: const LicensePolicy(allowAttributionLicenses: true),
    );
    expect(
      (await opted.browse()).map((i) => i.declaredLicense).toList(),
      ['Public Domain', 'CC BY'],
    );
  });

  testWidgets('sheet: no key → key form; save → browse → pick returns bytes',
      (tester) async {
    final items = [
      LibraryItem(
        sourceId: 'fake',
        sourceName: 'Fake Archive',
        id: 'ma_1',
        title: 'PD Module',
        composer: 'Chippy',
        declaredLicense: 'Public Domain',
        downloadUrl: Uri.parse('https://x/1'),
        format: 'mod',
      ),
    ];
    final fake = _FakeSource(items, Uint8List.fromList([77, 79, 68]));
    Uint8List? result;

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showModArchiveSheet(
                  ctx,
                  keyStore: ModArchiveKeyStore(),
                  builder: (_) => fake,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // No stored key → the key form is shown.
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'my-key');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Now the CC0/PD module is listed; picking it returns its bytes.
    expect(find.text('PD Module'), findsOneWidget);
    await tester.tap(find.text('PD Module'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result, [77, 79, 68]);
    expect(fake.fetchCount, 1);
  });
}

Uint8List utf8(String s) => Uint8List.fromList(s.codeUnits);
