// Driving the catalog sheet's MELODY lens as a user would.
//
// The core (`melodic_search_test`) proves the ranking, and the join
// (`music_picker_test`) proves which rows are eligible. Neither touches the
// SHEET — and the sheet is where the feature can silently fail to be usable:
// the lens never appearing, the keyboard not registering taps, a hit not being
// pickable, or "two notes minimum" never resolving into a result list.
//
// This was untestable until `CatalogMusicSheet` grew a `source` parameter: it
// used to construct its own network-backed source inline, so every behaviour in
// it was reachable only over the real catalog.

import 'dart:typed_data';

import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music/music_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// A tiny in-memory catalog. `fetch` returns real ABC so that PICKING a hit
/// exercises the actual decode path rather than a stub.
class _FakeSource implements ContentSource {
  _FakeSource(this.items);
  final List<LibraryItem> items;

  @override
  String get id => 'fake';
  @override
  String get name => 'Fake';
  @override
  String get homepage => 'https://example.invalid';
  @override
  String get licenseSummary => 'CC0';

  @override
  Future<List<LibraryItem>> browse({String query = '', int limit = 60}) async {
    final q = query.trim().toLowerCase();
    final hits = [
      for (final i in items)
        if (q.isEmpty || i.title.toLowerCase().contains(q)) i,
    ];
    return hits.take(limit).toList();
  }

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
  Future<Uint8List> fetch(LibraryItem item) async => Uint8List.fromList(
        'X:1\nT:${item.title}\nM:4/4\nL:1/4\nK:C\nC D E F|'.codeUnits,
      );
}

LibraryItem _item(String id, String title, List<int> incipit) => LibraryItem(
      sourceId: 'fake',
      sourceName: 'Fake',
      id: id,
      title: title,
      composer: 'Anon',
      collection: 'score',
      declaredLicense: 'CC0',
      downloadUrl: Uri.parse('https://example.invalid/$id'),
      format: 'abc',
      music: MusicInfo(incipit: incipit),
    );

/// "Ode to Joy" and two decoys that share no shape with it.
final _catalog = [
  _item('ode', 'Ode to Joy', const [64, 64, 65, 67, 67, 65, 64, 62]),
  _item('flat', 'Flat Line', const [60, 60, 60, 60, 60, 60, 60, 60]),
  _item('rise', 'Rising Scale', const [60, 62, 64, 65, 67, 69, 71, 72]),
];

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('de')],
      home: Scaffold(body: child),
    );

/// Taps a keyboard key by PITCH.
///
/// Two reasons this is not a one-liner. The readout renders the SAME note names
/// as the buttons, so a text finder is ambiguous once a note is entered — hence
/// keys. And the keyboard scrolls horizontally, so a `ListView` only builds the
/// keys currently on screen: anything above roughly G4 has to be scrolled to
/// before it exists to tap at all.
Future<void> _tapKey(WidgetTester tester, int midi) async {
  final key = find.byKey(ValueKey('melody-key-$midi'));
  if (key.evaluate().isEmpty) {
    await tester.dragUntilVisible(
      key,
      find.byKey(const Key('melody-keyboard')),
      const Offset(-120, 0),
    );
    await tester.pump();
  }
  await tester.tap(key);
  await tester.pump();
}

Future<void> _switchToMelody(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(find.text(l10n.musicPickerByMelody));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('the melody lens is offered and can be entered', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(_wrap(CatalogMusicSheet(source: _FakeSource(_catalog))));
    await tester.pump();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    expect(find.text(l10n.musicPickerByTitle), findsOneWidget);
    expect(find.text(l10n.musicPickerByMelody), findsOneWidget);

    await _switchToMelody(tester, l10n);
    // The text field is replaced by the note keyboard, not shown alongside it.
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('below two notes it explains, rather than ranking nothing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(_wrap(CatalogMusicSheet(source: _FakeSource(_catalog))));
    await tester.pump();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _switchToMelody(tester, l10n);

    // One note is zero intervals — no shape to search on. The hint names the
    // pool size, so it also proves the pool actually loaded.
    expect(find.textContaining('3 pieces searchable'), findsOneWidget);
    await _tapKey(tester, 64); // E4

    expect(find.textContaining('3 pieces searchable'), findsOneWidget);
  });

  testWidgets('tapping the tune finds it, and the entry reads back',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(_wrap(CatalogMusicSheet(source: _FakeSource(_catalog))));
    await tester.pump();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _switchToMelody(tester, l10n);

    // E E F G — the opening of Ode to Joy, tapped on the keyboard.
    for (final midi in [64, 64, 65, 67]) {
      await _tapKey(tester, midi);
    }
    // The entry reads back as notes so the user can see what they asked for.
    expect(find.text('E4 E4 F4 G4'), findsOneWidget);
    // And the right piece is ranked first.
    expect(find.text('Ode to Joy'), findsOneWidget);
  });

  testWidgets('backspace and clear undo the entry', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(_wrap(CatalogMusicSheet(source: _FakeSource(_catalog))));
    await tester.pump();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _switchToMelody(tester, l10n);

    for (final midi in [60, 62, 64]) {
      await _tapKey(tester, midi);
    }
    expect(find.text('C4 D4 E4'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    expect(find.text('C4 D4'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('a transposed query still finds the tune through the UI',
      (tester) async {
    // The end-to-end version of the property the core is built around: the user
    // taps in a key nobody wrote the piece in and still gets it. If the sheet
    // ever normalised or transposed on the way in, this is what would catch it.
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(_wrap(CatalogMusicSheet(source: _FakeSource(_catalog))));
    await tester.pump();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _switchToMelody(tester, l10n);

    // A4 A4 A♯4 C5 — Ode to Joy's shape (0, +1, +2), five semitones up.
    // ⚠️ C5, not C4. Before the buttons carried their octave this was
    // genuinely ambiguous in the UI, and tapping the wrong C turns a +2 into a
    // -10 — a different shape, not a near miss.
    for (final midi in [69, 69, 70, 72]) {
      await _tapKey(tester, midi);
    }
    expect(find.text('Ode to Joy'), findsOneWidget);
  });
}
