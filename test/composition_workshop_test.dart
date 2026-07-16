// Composition Workshop — the touch-first score editor shell. Verifies it
// renders the multi-line score canvas + bottom input dock (piano), adds rests,
// and undoes/redoes. Note placement (from the piano) is covered by the
// ScoreDocument model tests.

import 'package:crisp_notation/crisp_notation.dart'
    show
        InteractiveGrandStaffView,
        InteractiveMultiPartView,
        MultiSystemView,
        NoteNameStyle;
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

    // The action strip is scrollable; reveal the buttons before tapping.
    await tester.ensureVisible(find.byIcon(Icons.copy));
    await tester.tap(find.byIcon(Icons.copy));
    await tester.pump();
    await tester.ensureVisible(find.byIcon(Icons.content_paste));
    await tester.tap(find.byIcon(Icons.content_paste));
    await tester.pump();
    expect(editor.noteCount, 2);
  });

  testWidgets('the overflow menu offers a single Open and Export', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    // One unified Open and one unified Export (not one item per file type).
    expect(find.text(l10n.workshopOpen), findsOneWidget);
    expect(find.text(l10n.workshopExport), findsOneWidget);
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

  testWidgets('the export sheet lists many formats', (tester) async {
    await pump(tester);
    await tester.tap(_pianoKey()); // a note so export enables
    await tester.pump();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.workshopExport));
    await tester.pumpAndSettle();
    expect(find.text(l10n.workshopExportChoose), findsOneWidget);
    // A rich set of formats, not just the old MusicXML/ABC/SVG/PNG four.
    expect(find.textContaining('MusicXML'), findsWidgets);
    expect(find.textContaining('MIDI'), findsOneWidget);
    expect(find.textContaining('MEI'), findsOneWidget);
    expect(find.textContaining('LilyPond'), findsOneWidget);
    expect(find.textContaining('SVG'), findsOneWidget);
    expect(find.textContaining('PNG'), findsOneWidget);
  });

  // Only MusicXML/.mxl can carry every part (crisp_notation ships no other
  // multiPartTo… writer), so exporting a multi-part score to MIDI/LilyPond/etc
  // silently dropped every part but the active one. The sheet must say so.
  testWidgets('the export sheet is silent about parts for a single-part score',
      (tester) async {
    await pump(tester);
    await tester.tap(_pianoKey());
    await tester.pump();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.workshopExport));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Only'),
      findsNothing,
      reason: 'nothing is lost with one part, so do not nag',
    );
  });

  testWidgets('the export sheet warns which formats drop the other parts',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('workshop-add-instrument')));
    await tester.pump();
    await tester.tap(_pianoKey());
    await tester.pump();
    expect(_editor(tester).partCount, 2);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.workshopExport));
    await tester.pumpAndSettle();

    // MusicXML + .mxl say they carry everything; the other nine warn.
    expect(find.text(l10n.workshopExportAllParts(2)), findsNWidgets(2));
    expect(
      find.text(l10n.workshopExportActivePartOnly('Part 2')),
      findsNWidgets(kExportFormats.length - 2),
      reason: 'every non-MusicXML format must admit it drops the other parts',
    );
  });

  test('exactly the MusicXML formats claim multi-part support', () {
    // Guards the flag against a new format being added without deciding.
    expect(
      kExportFormats.where((f) => f.multiPart).map((f) => f.ext),
      ['musicxml', 'mxl'],
    );
  });

  testWidgets('enabling marquee mode shows the selection overlay',
      (tester) async {
    await pump(tester);
    final marquee = find.byIcon(Icons.highlight_alt);
    await tester.ensureVisible(marquee);
    await tester.tap(marquee);
    await tester.pump();
    // A GestureDetector overlay is stacked over the canvas in marquee mode.
    expect(find.byType(CustomPaint), findsWidgets);
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

  // ---- G6: multi-instrument ------------------------------------------------

  testWidgets('starts as a single-part editor (one part, single-staff canvas)',
      (tester) async {
    await pump(tester);
    expect(_editor(tester).partCount, 1);
    expect(_editor(tester).activePartIndex, 0);
    expect(find.byType(MultiSystemView), findsOneWidget);
    expect(find.byType(InteractiveMultiPartView), findsNothing);
  });

  testWidgets('adding an instrument swaps to the full-score multi-part canvas',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('workshop-add-instrument')));
    await tester.pump();
    expect(_editor(tester).partCount, 2);
    expect(_editor(tester).activePartIndex, 1, reason: 'new part is active');
    expect(find.byType(InteractiveMultiPartView), findsOneWidget);
    expect(find.byType(MultiSystemView), findsNothing);
  });

  testWidgets('tapping a part chip switches the active part', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('workshop-add-instrument')));
    await tester.pump();
    expect(_editor(tester).activePartIndex, 1);
    await tester.tap(find.byKey(const ValueKey('workshop-part-0')));
    await tester.pump();
    expect(_editor(tester).activePartIndex, 0);
  });

  testWidgets('removing an instrument returns to the single-part editor',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('workshop-add-instrument')));
    await tester.pump();
    expect(_editor(tester).partCount, 2);
    // Open part 0's ⋮ (tune) menu and remove it.
    await tester.tap(find.byIcon(Icons.tune).first);
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.workshopRemoveInstrument));
    await tester.pump();
    expect(_editor(tester).partCount, 1);
    expect(find.byType(MultiSystemView), findsOneWidget);
    expect(find.byType(InteractiveMultiPartView), findsNothing);
  });

  testWidgets('the full-score canvas is interactive (staff-tap + drag wired)',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('workshop-add-instrument')));
    await tester.pump();
    final view = tester.widget<InteractiveMultiPartView>(
      find.byType(InteractiveMultiPartView),
    );
    // C12 in-place editing entry points are all wired from the screen.
    expect(view.onStaffTap, isNotNull);
    expect(view.onHover, isNotNull);
    expect(view.onElementTap, isNotNull);
    expect(view.onElementDragStart, isNotNull);
    expect(view.onElementDragEnd, isNotNull);
  });

  testWidgets('in multi-part mode the piano places into the active part',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('workshop-add-instrument')));
    await tester.pump(); // part 1 (empty) is now active
    expect(_editor(tester).noteCount, 0);
    await tester.tap(_pianoKey());
    await tester.pump();
    expect(_editor(tester).noteCount, 1, reason: 'note lands in active part 1');
    expect(_editor(tester).activePartIndex, 1);
  });

  testWidgets('the full-score canvas wires regions + live-drag + caret',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('workshop-add-instrument')));
    await tester.pump();
    final view = tester.widget<InteractiveMultiPartView>(
      find.byType(InteractiveMultiPartView),
    );
    expect(view.controller, isNotNull); // C12c marquee / region queries
    expect(view.onElementDragUpdate, isNotNull); // live drag preview feed
    expect(view.suppressElementIds, isA<Set<String>>()); // drag-source hide
  });

  testWidgets('marquee mode is available in multi-part mode', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('workshop-add-instrument')));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.highlight_alt)); // toggle marquee
    await tester.pump();
    expect(find.byType(InteractiveMultiPartView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ---- Paste notation tokens (bekern import bridge) ------------------------

  testWidgets('pasting bekern tokens loads a playable score', (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    expect(editor.noteCount, 0);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.workshopPasteTokens));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '**kern <b> 4 c <b> 4 d <b> 4 e <b> *-',
    );
    await tester.tap(find.text(l10n.workshopPasteTokensLoad));
    await tester.pumpAndSettle();

    expect(editor.noteCount, greaterThan(0), reason: 'tokens became notes');
  });

  testWidgets('the Bar numbers toggle flips showMeasureNumbers on the canvas',
      (tester) async {
    await pump(tester);
    MultiSystemView view() =>
        tester.widget<MultiSystemView>(find.byType(MultiSystemView));
    expect(view().showMeasureNumbers, isFalse);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.workshopBarNumbers));
    await tester.pumpAndSettle();

    expect(view().showMeasureNumbers, isTrue);
  });

  testWidgets('Bar numbers also apply to the multi-part canvas',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('workshop-add-instrument')));
    await tester.pump();
    InteractiveMultiPartView view() => tester.widget<InteractiveMultiPartView>(
          find.byType(InteractiveMultiPartView),
        );
    expect(view().showMeasureNumbers, isFalse);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.workshopBarNumbers));
    await tester.pumpAndSettle();

    expect(view().showMeasureNumbers, isTrue);
  });

  testWidgets('the Note names toggle flips showNoteNames on the canvas',
      (tester) async {
    await pump(tester);
    MultiSystemView view() =>
        tester.widget<MultiSystemView>(find.byType(MultiSystemView));
    expect(view().showNoteNames, isFalse);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.workshopNoteNames));
    await tester.pumpAndSettle();

    expect(view().showNoteNames, isTrue);
    // EN locale + auto naming → English letters.
    expect(view().noteNameStyle, NoteNameStyle.letter);
  });

  testWidgets('Break barline below splits the multi-part barline groups',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('workshop-add-instrument')));
    await tester.pump();
    InteractiveMultiPartView view() => tester.widget<InteractiveMultiPartView>(
          find.byType(InteractiveMultiPartView),
        );
    expect(view().document.barlineGroups, isEmpty); // all connected

    // Open part 0's ⋮ (tune) menu and break the barline below it.
    await tester.tap(find.byIcon(Icons.tune).first);
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.workshopBreakBarlineBelow));
    await tester.pump();

    expect(view().document.barlineGroups, isNotEmpty);
  });

  testWidgets('Note names also apply to the multi-part canvas', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('workshop-add-instrument')));
    await tester.pump();
    InteractiveMultiPartView view() => tester.widget<InteractiveMultiPartView>(
          find.byType(InteractiveMultiPartView),
        );
    expect(view().showNoteNames, isFalse);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.workshopNoteNames));
    await tester.pumpAndSettle();

    expect(view().showNoteNames, isTrue);
  });

  testWidgets('Bar numbers also apply in grand-staff mode', (tester) async {
    await pump(tester);
    // Switch the staff-mode dropdown to grand (𝄞𝄢).
    await tester.tap(find.text('𝄞').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('𝄞𝄢').last);
    await tester.pumpAndSettle();

    InteractiveGrandStaffView view() =>
        tester.widget<InteractiveGrandStaffView>(
          find.byType(InteractiveGrandStaffView),
        );
    expect(view().showMeasureNumbers, isFalse);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.workshopBarNumbers));
    await tester.pumpAndSettle();

    expect(view().showMeasureNumbers, isTrue);
  });
}
