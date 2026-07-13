// Composition Workshop — the touch-first score editor shell. Verifies it
// renders the multi-line score canvas + bottom input dock (piano), adds rests,
// and undoes/redoes. Note placement (from the piano) is covered by the
// ScoreDocument model tests.

import 'package:flutter/material.dart' hide Step;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/features/games/songs/user_songs_service.dart';
import 'package:klang_universum/features/workshop/screens/composition_workshop_screen.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/widgets/piano_keyboard.dart';
import 'package:partitura/partitura.dart'
    show InteractiveGrandStaffView, MultiSystemView;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app() => MultiProvider(
      providers: [
        Provider<AudioService>(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => UserSongsService()),
        ChangeNotifierProvider(create: (_) => SettingsService()),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('en'), Locale('de')],
        home: CompositionWorkshopScreen(),
      ),
    );

CompositionWorkshopTester _editor(WidgetTester tester) =>
    tester.state<State<CompositionWorkshopScreen>>(
      find.byType(CompositionWorkshopScreen),
    ) as CompositionWorkshopTester;

// The piano is a wide, horizontally-scrollable keyboard; its widget centre is
// off-screen, so tap a specific visible white-key GestureDetector instead.
Finder _pianoKeyAt(int i) => find
    .descendant(
      of: find.byType(PianoKeyboard),
      matching: find.byType(GestureDetector),
    )
    .at(i);

Finder _pianoKey() => _pianoKeyAt(16);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
  }

  testWidgets('renders the multi-line canvas and the piano input dock',
      (tester) async {
    await pump(tester);
    expect(find.byType(MultiSystemView), findsOneWidget);
    expect(find.byType(PianoKeyboard), findsOneWidget);
  });

  testWidgets('the rest button adds a rest; bars fill per the meter',
      (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    expect(editor.noteCount, 0);
    expect(editor.barCount, 1); // an empty rest bar

    // Default value is a quarter; five rests in 4/4 → a second bar.
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byIcon(Icons.music_off_outlined));
      await tester.pump();
    }
    expect(editor.noteCount, 5);
    expect(editor.barCount, 2, reason: '4 quarters fill a 4/4 bar');
  });

  testWidgets('undo then redo round-trips an added element', (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    await tester.tap(find.byIcon(Icons.music_off_outlined));
    await tester.pump();
    expect(editor.noteCount, 1);

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(editor.noteCount, 0);

    await tester.tap(find.byIcon(Icons.redo));
    await tester.pump();
    expect(editor.noteCount, 1);
  });

  testWidgets('tapping the piano places a note and selects it', (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    await tester.tap(_pianoKey());
    await tester.pump();
    expect(editor.noteCount, 1);
    expect(editor.hasSelection, isTrue);
  });

  testWidgets('copy then paste duplicates the selection', (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    await tester.tap(_pianoKey());
    await tester.pump();
    expect(editor.noteCount, 1);

    await tester.tap(find.byIcon(Icons.copy));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.content_paste));
    await tester.pump();
    expect(editor.noteCount, 2);
  });

  testWidgets('the overflow menu offers open and export', (tester) async {
    await pump(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.importMusicXmlFile), findsOneWidget);
    expect(find.text(l10n.workshopExportXml), findsOneWidget);
  });

  testWidgets('the note palette offers articulations and dynamics',
      (tester) async {
    await pump(tester);
    await tester.tap(_pianoKey()); // places + selects a note
    await tester.pump();
    // The action row is scrollable; reveal the palette button before tapping.
    final palette = find.byIcon(Icons.expand_less);
    await tester.ensureVisible(palette);
    await tester.pumpAndSettle();
    await tester.tap(palette);
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.workshopStaccato), findsOneWidget);
    expect(find.textContaining('mf'), findsWidgets); // a dynamic entry
  });

  testWidgets('computer keyboard: letters place notes, Del deletes',
      (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    expect(editor.noteCount, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(editor.noteCount, 1);
  });

  testWidgets('chord mode stacks a second note onto the first', (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    await tester.tap(_pianoKeyAt(16)); // first note, auto-selected
    await tester.pump();
    expect(editor.noteCount, 1);

    await tester.tap(find.byIcon(Icons.layers)); // enable chord mode
    await tester.pump();
    await tester.tap(_pianoKeyAt(18)); // a different key → stacks
    await tester.pump();
    expect(editor.noteCount, 1, reason: 'the pitch stacks, not a new element');
  });

  testWidgets('a second piano tap places another note (not a move)',
      (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    await tester.tap(_pianoKeyAt(16));
    await tester.pump();
    await tester.tap(_pianoKeyAt(18)); // a different key
    await tester.pump();
    expect(editor.noteCount, 2, reason: 'each tap adds a note like a keyboard');
  });

  testWidgets('the info button opens the keyboard-shortcuts sheet',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.workshopShortcuts), findsOneWidget);
    expect(find.textContaining('A – G'), findsOneWidget);
  });

  testWidgets('selecting a note reveals the inline lyric field',
      (tester) async {
    await pump(tester);
    await tester.tap(_pianoKey()); // places + selects one note
    await tester.pump();
    expect(find.byIcon(Icons.lyrics_outlined), findsOneWidget);
  });

  testWidgets('slurring a two-note range records a slur', (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    await tester.tap(_pianoKeyAt(16));
    await tester.pump();
    await tester.tap(_pianoKeyAt(18)); // two notes, second selected
    await tester.pump();
    // Extend the selection left to cover both, so a slur can span them.
    final extend = find.byIcon(Icons.keyboard_double_arrow_left);
    await tester.ensureVisible(extend);
    await tester.tap(extend);
    await tester.pump();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final slur = find.byTooltip(l10n.workshopSlur);
    await tester.ensureVisible(slur);
    await tester.tap(slur);
    await tester.pump();
    expect(editor.slurCount, 1);
  });

  testWidgets('the lyric field carries a verse selector', (tester) async {
    await pump(tester);
    await tester.tap(_pianoKey()); // one note selected
    await tester.pump();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.byTooltip(l10n.workshopLyricVerse), findsOneWidget);
  });

  testWidgets('a crescendo over a two-note range records a hairpin',
      (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    await tester.tap(_pianoKeyAt(16));
    await tester.pump();
    await tester.tap(_pianoKeyAt(18));
    await tester.pump();
    final extend = find.byIcon(Icons.keyboard_double_arrow_left);
    await tester.ensureVisible(extend);
    await tester.tap(extend);
    await tester.pump();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final cresc = find.byTooltip(l10n.workshopCrescendo);
    await tester.ensureVisible(cresc);
    await tester.tap(cresc);
    await tester.pump();
    expect(editor.hairpinCount, 1);
  });

  testWidgets('the pickup dropdown is present in the top bar', (tester) async {
    await pump(tester);
    // The pickup control renders its "no pickup" dash; behaviour is covered by
    // the model tests (a quarter pickup shortens the opening bar).
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('switching to grand-staff mode shows both clefs', (tester) async {
    await pump(tester);
    expect(find.byType(MultiSystemView), findsOneWidget);
    // Open the staff-mode dropdown (currently the treble glyph) and pick grand.
    await tester.tap(find.text('𝄞').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('𝄞𝄢').last);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveGrandStaffView), findsOneWidget);
    expect(find.byType(MultiSystemView), findsNothing);
  });
}
