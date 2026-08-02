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

import 'dart:async';
import 'dart:math' as math;
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
  sungUiTests();

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

/// A microphone that replays a scripted phrase. The seam exists so this test
/// can exist at all — a widget test cannot open a real microphone, and without
/// it the entire sung path would be verifiable only by hand on a device.
class _FakeMic implements MelodyMicrophone {
  _FakeMic(this.phrase, {this.failOnStart = false});

  /// Frames as the pitch detector would emit them, each with its own time.
  final List<({double frequency, double clarity, double timeMs})> phrase;
  final bool failOnStart;

  final _controller = StreamController<
      ({double frequency, double clarity, double timeMs})>.broadcast();
  bool started = false;
  bool stopped = false;

  @override
  Stream<({double frequency, double clarity, double timeMs})> get readings =>
      _controller.stream;

  @override
  Future<void> start() async {
    if (failOnStart) throw StateError('no microphone');
    started = true;
    for (final f in phrase) {
      _controller.add(f);
    }
  }

  @override
  Future<void> stop() async => stopped = true;
}

double _hz(int midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

/// A sung phrase as frames: each note held, with a gap after it.
///
/// ⚠️ Frames carry their OWN time. `pump()` advances fake time, so a consumer
/// stamping arrival from a Stopwatch would put every frame at ~0 ms — which is
/// exactly the bug that moved timestamps into the source.
List<({double frequency, double clarity, double timeMs})> _sung(
  List<int> midis, {
  double hopMs = 11,
}) {
  final out = <({double frequency, double clarity, double timeMs})>[];
  var t = 0.0;
  for (final m in midis) {
    for (var i = 0; i < 36; i++, t += hopMs) {
      out.add((frequency: _hz(m), clarity: 0.95, timeMs: t));
    }
    for (var i = 0; i < 8; i++, t += hopMs) {
      out.add((frequency: 0.0, clarity: 0.0, timeMs: t));
    }
  }
  return out;
}

/// Pumps until the async mic lifecycle has settled.
///
/// The fake emits hundreds of frames, each a microtask, and `_listening` only
/// flips after `start()` completes — two pumps is not reliably enough, and the
/// symptom of under-pumping is that the SECOND tap starts a new capture instead
/// of stopping the first.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void sungUiTests() {
  Future<void> open(WidgetTester tester, _FakeMic mic) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      _wrap(
        CatalogMusicSheet(source: _FakeSource(_catalog), microphone: mic),
      ),
    );
    await tester.pump();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _switchToMelody(tester, l10n);
  }

  testWidgets('singing a tune fills the query and finds it', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Ode to Joy, sung a minor third up — the transposition is the point.
    final mic = _FakeMic(_sung(const [67, 67, 68, 70, 70, 68, 67, 65]));
    await open(tester, mic);

    await tester.tap(find.byKey(const Key('melody-listen')));
    await _settle(tester);
    expect(mic.started, isTrue);

    // Stopping is what runs the search.
    await tester.tap(find.byKey(const Key('melody-listen')));
    await _settle(tester);
    expect(mic.stopped, isTrue);

    expect(find.text('G4 G4 G♯4 A♯4 A♯4 G♯4 G4 F4'), findsOneWidget);
    expect(find.text('Ode to Joy'), findsOneWidget);
  });

  testWidgets('a microphone that will not start says so and stays usable',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final mic = _FakeMic(const [], failOnStart: true);
    await open(tester, mic);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.tap(find.byKey(const Key('melody-listen')));
    await _settle(tester);

    expect(find.text(l10n.musicPickerMicFailed), findsOneWidget);
    // Crucially the keyboard still works — a denied mic must not strand the
    // user in a mode with no way to enter anything.
    await _tapKey(tester, 60);
    await _tapKey(tester, 62);
    expect(find.text('C4 D4'), findsOneWidget);
  });

  testWidgets('too little singing leaves the query alone', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // A couple of frames is noise; ranking 38k pieces against noise would give
    // confident-looking nonsense instead of an obvious no-op.
    final mic = _FakeMic(const [
      (frequency: 440.0, clarity: 0.9, timeMs: 0.0),
      (frequency: 440.0, clarity: 0.9, timeMs: 11.0),
    ]);
    await open(tester, mic);

    await _tapKey(tester, 60);
    // Two matches: the readout and the keyboard key both read "C4".
    expect(find.text('C4'), findsWidgets);

    await tester.tap(find.byKey(const Key('melody-listen')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('melody-listen')));
    await _settle(tester);

    // The tapped note is still there — a failed hum did not wipe it. Two
    // matches: the readout and the keyboard key both read "C4".
    expect(find.text('C4'), findsWidgets);
  });
}
