// The capable "Browse catalog" modal over OUR curated HF catalog: renders every
// kind with licence + attribution, filters by kind chip and by licence bucket,
// searches, and opens a per-item detail sheet whose action routes to the right
// editor (a sample offers "Add to library"). Driven by an injected
// ContentSource + store — no network, no real SharedPreferences backend needed
// beyond the mock.

import 'dart:typed_data';

import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/features/sound_lab/catalog_browse_sheet.dart';
import 'package:comet_beat/features/sound_lab/instrument_library_store.dart';
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSource implements ContentSource {
  _FakeSource(this._items, {Uint8List? bytes}) : _bytes = bytes;
  final List<LibraryItem> _items;
  final Uint8List? _bytes;

  @override
  String get id => 'fake';
  @override
  String get name => 'CometBeat Library';
  @override
  String get homepage => 'https://example';
  @override
  String get licenseSummary => 'CC0 / CC-BY / PD';

  @override
  Future<LibraryPage> browsePage({
    String query = '',
    LibraryFilter filter = const LibraryFilter(),
    int limit = 60,
    int offset = 0,
  }) =>
      browsePageByFiltering(
        this,
        query: query,
        filter: filter,
        limit: limit,
        offset: offset,
      );

  @override
  Future<List<LibraryItem>> browse({String query = '', int limit = 60}) async =>
      _items;

  @override
  Future<Uint8List> fetch(LibraryItem item) async => _bytes ?? Uint8List(0);
}

LibraryItem _item(String title, String kind, String fmt, String lic) =>
    LibraryItem(
      sourceId: 'fake',
      sourceName: 'CometBeat Library',
      id: title,
      title: title,
      composer: 'Alice',
      collection: kind,
      declaredLicense: lic,
      downloadUrl: Uri.parse('https://h/$title'),
      format: fmt,
    );

final _fixture = [
  _item('FluidR3 GM', 'soundfont', 'sf2', 'MIT License'),
  _item('Cello VCSL', 'instrument', 'sfz', 'CC0 / Public Domain'),
  _item('Snare hit', 'sample', 'wav', 'CC0 / Public Domain'),
  _item('Chiptune', 'module', 'xm', 'CC BY 4.0'),
  _item('Kyrie', 'score', 'gabc', 'CC0 / Public Domain'),
];

// The capable all-kinds browser (soundfonts + instruments + samples + modules +
// songs) — the shape the Song Book / catalog surface opens.
const _allKinds = {'soundfont', 'instrument', 'sample', 'module', 'score'};

Widget _host(
  ContentSource src, {
  Future<void> Function(SampleClip clip)? onInsertSample,
  bool preferSampleInsert = false,
  Set<String> kinds = _allKinds,
}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: CatalogBrowseSheet(
          source: src,
          store: InstrumentLibraryStore(),
          kinds: kinds,
          onInsertSample: onInsertSample,
          preferSampleInsert: preferSampleInsert,
        ),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('lists every kind with licence + attribution + kind icons',
      (tester) async {
    await tester.pumpWidget(_host(_FakeSource(_fixture)));
    await tester.pumpAndSettle();

    expect(find.text('FluidR3 GM'), findsOneWidget);
    expect(find.text('Cello VCSL'), findsOneWidget);
    expect(find.text('Snare hit'), findsOneWidget);
    expect(find.text('Chiptune'), findsOneWidget);
    expect(find.text('Kyrie'), findsOneWidget);
    expect(find.textContaining('MIT License'), findsOneWidget);
    expect(find.textContaining('Alice'), findsWidgets); // attribution
    // per-kind icons in the list
    expect(find.byIcon(Icons.piano), findsOneWidget); // soundfont
    expect(find.byIcon(Icons.grid_on), findsOneWidget); // module
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget); // sample
    expect(find.byIcon(Icons.library_music), findsOneWidget); // score
  });

  testWidgets('kind dropdown filters to one kind', (tester) async {
    await tester.pumpWidget(_host(_FakeSource(_fixture)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('kindFilter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modules').last);
    await tester.pumpAndSettle();

    expect(find.text('Chiptune'), findsOneWidget);
    expect(find.text('FluidR3 GM'), findsNothing);
    expect(find.text('Snare hit'), findsNothing);
  });

  testWidgets('a sound-library scope hides Modules/Songs (options AND items)',
      (tester) async {
    await tester.pumpWidget(
      _host(_FakeSource(_fixture), kinds: kSoundLibraryKinds),
    );
    await tester.pumpAndSettle();

    // Sound kinds are listed…
    expect(find.text('FluidR3 GM'), findsOneWidget); // soundfont
    expect(find.text('Cello VCSL'), findsOneWidget); // instrument
    expect(find.text('Snare hit'), findsOneWidget); // sample
    // …but a module and a song are NOT, even though the source returned them.
    expect(find.text('Chiptune'), findsNothing); // module
    expect(find.text('Kyrie'), findsNothing); // score
    // …and the kind dropdown offers no Modules/Songs options.
    await tester.tap(find.byKey(const ValueKey('kindFilter')));
    await tester.pumpAndSettle();
    expect(find.text('Modules'), findsNothing);
    expect(find.text('Songs'), findsNothing);
  });

  testWidgets('a single-kind scope hides the kind dropdown entirely',
      (tester) async {
    await tester.pumpWidget(
      _host(_FakeSource(_fixture), kinds: const {'instrument'}),
    );
    await tester.pumpAndSettle();

    // Only the instrument shows.
    expect(find.text('Cello VCSL'), findsOneWidget);
    expect(find.text('FluidR3 GM'), findsNothing);
    expect(find.text('Snare hit'), findsNothing);
    // No kind dropdown at all — there is nothing to filter.
    expect(find.byKey(const ValueKey('kindFilter')), findsNothing);
  });

  testWidgets('licence dropdown filters by bucket', (tester) async {
    await tester.pumpWidget(_host(_FakeSource(_fixture)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('licenceFilter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MIT').last);
    await tester.pumpAndSettle();

    expect(find.text('FluidR3 GM'), findsOneWidget); // MIT
    expect(find.text('Cello VCSL'), findsNothing); // CC0
    expect(find.text('Chiptune'), findsNothing); // CC-BY
  });

  testWidgets('search narrows the list', (tester) async {
    await tester.pumpWidget(_host(_FakeSource(_fixture)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'fluid');
    await tester.pumpAndSettle();

    expect(find.text('FluidR3 GM'), findsOneWidget);
    expect(find.text('Cello VCSL'), findsNothing);
  });

  testWidgets('initialKind pre-filters the list (Samples rubric)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CatalogBrowseSheet(
            source: _FakeSource(_fixture),
            store: InstrumentLibraryStore(),
            initialKind: 'sample',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // only the sample shows; the others are filtered out on open
    expect(find.text('Snare hit'), findsOneWidget);
    expect(find.text('FluidR3 GM'), findsNothing);
    expect(find.text('Chiptune'), findsNothing);
    expect(find.text('Kyrie'), findsNothing);
  });

  testWidgets('a sample opens a detail sheet offering "Add to library"',
      (tester) async {
    await tester.pumpWidget(_host(_FakeSource(_fixture)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Snare hit'));
    await tester.pumpAndSettle();

    // detail sheet shows the sample's action route
    expect(find.text('Add to library'), findsOneWidget);
  });

  testWidgets('a catalog score opens the score editor path', (tester) async {
    await tester.pumpWidget(_host(_FakeSource(_fixture)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kyrie'));
    await tester.pumpAndSettle();

    expect(find.text('Open this music in…'), findsOneWidget);
    expect(find.text('Open in Tracker'), findsOneWidget);
  });

  testWidgets('a catalog module offers both Tracker and score editor paths',
      (tester) async {
    await tester.pumpWidget(_host(_FakeSource(_fixture)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chiptune'));
    await tester.pumpAndSettle();

    expect(find.text('Open in Tracker'), findsOneWidget);
    expect(find.text('Open in Score Workshop'), findsOneWidget);
  });

  testWidgets('a sample can be inserted directly into the audio track',
      (tester) async {
    SampleClip? inserted;
    final wav = pcmFloatToWav(
      Float64List.fromList(const [0.0, 0.25, -0.25, 0.0]),
      sampleRate: 22050,
    );
    await tester.pumpWidget(
      _host(
        _FakeSource(_fixture, bytes: wav),
        onInsertSample: (clip) async => inserted = clip,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Snare hit'));
    await tester.pumpAndSettle();

    expect(find.text('Add to library'), findsOneWidget);
    expect(find.text('Insert in audio track'), findsOneWidget);

    await tester.tap(find.text('Insert in audio track'));
    await tester.pumpAndSettle();

    expect(inserted, isNotNull);
    expect(inserted!.name, 'Snare hit');
    expect(inserted!.sampleRate, 22050);
    expect(inserted!.pcm, hasLength(4));
  });

  testWidgets('DAW mode puts "Insert in audio track" before library install',
      (tester) async {
    final wav = pcmFloatToWav(
      Float64List.fromList(const [0.0, 0.25, -0.25, 0.0]),
      sampleRate: 22050,
    );
    await tester.pumpWidget(
      _host(
        _FakeSource(_fixture, bytes: wav),
        onInsertSample: (_) async {},
        preferSampleInsert: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Snare hit'));
    await tester.pumpAndSettle();

    final actionLabels = [
      for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
        if (tile.title case final Text title)
          if (title.data == 'Insert in audio track' ||
              title.data == 'Add to library')
            title.data!,
    ];
    expect(actionLabels.take(2), [
      'Insert in audio track',
      'Add to library',
    ]);
  });
}
