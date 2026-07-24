// Composition Workshop — the touch-first score editor shell. Verifies it
// renders the multi-line score canvas + bottom input dock (piano), adds rests,
// and undoes/redoes. Note placement (from the piano) is covered by the
// ScoreDocument model tests.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/loop_engine.dart' show PatternCell;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show SampleInstrument;
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/core/services/melody_bridge.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart';
import 'package:comet_beat/features/workshop/widgets/multi_part_canvas.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/piano_keyboard.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show
        InteractiveGrandStaffView,
        InteractiveMultiPartView,
        MultiSystemView,
        NoteElement,
        NoteNameStyle,
        bekernToScore,
        multiPartScoreFromGpif,
        readGpifFromGp;
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app() => MultiProvider(
      providers: [
        Provider<AudioService>(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => UserSongsService()),
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider(create: (_) => DawService()),
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

// Same providers as [_app], but hosts an arbitrary [home] so a test can inject
// the CompositionWorkshopScreen's debug seams (e.g. debugScanImage for OMR).
Widget _appHome(Widget home) => MultiProvider(
      providers: [
        Provider<AudioService>(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => UserSongsService()),
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider(create: (_) => DawService()),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('de')],
        home: home,
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

// The Studio-tier controls (voice toggle, input-mode toggle, inspector) live on
// the Studio shelf; flip it on via the ⋮ menu.
Future<void> _enterStudio(WidgetTester tester) async {
  final l10n = await AppLocalizations.delegate.load(const Locale('en'));
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.workshopStudioMode));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MelodyBridge.instance.clear();
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

  testWidgets('To Multitrack sends the document as a DAW clip', (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    final daw = Provider.of<DawService>(
      tester.element(find.byType(CompositionWorkshopScreen)),
      listen: false,
    );
    expect(daw.clipCount, 0);

    await tester.tap(_pianoKey()); // place a note
    await tester.pump();
    editor.sendToDaw();
    expect(daw.clipCount, 1);
    expect(daw.bake(), isNotEmpty); // the placed note renders as a clip
  });

  testWidgets('loads a shared tune (MelodyBridge) in as notes + a rest',
      (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    expect(editor.canLoadSharedMelody, isFalse);
    expect(editor.noteCount, 0);

    // A riff built on the 16-step grid elsewhere (C quarter, E quarter, G half,
    // then a whole-bar rest) → 3 notes + 1 rest = 4 score elements.
    MelodyBridge.instance.publish(
      SharedMelody(
        cells: const <PatternCell>[
          (midis: [60], steps: 2),
          (midis: [64], steps: 2),
          (midis: [67], steps: 4),
          (midis: null, steps: 8),
        ],
        tempoBpm: 100,
        source: 'loopmixer',
      ),
    );
    expect(editor.canLoadSharedMelody, isTrue);

    editor.loadSharedMelody();
    await tester.pump();
    expect(editor.noteCount, 4);

    // Publish the notated melody back onto the bridge — the active voice is
    // quantized onto the 2-bar eighth grid (source 'workshop').
    expect(editor.canShareMelody, isTrue);
    MelodyBridge.instance.clear();
    editor.shareMelody();
    final shared = MelodyBridge.instance.current;
    expect(shared, isNotNull);
    expect(shared!.source, 'workshop');
    expect(shared.isEmpty, isFalse);
    // C quarter, E quarter, G half → the three pitched cells, in order.
    final pitched = shared.cells.where((c) => c.midis != null).toList();
    expect(pitched.map((c) => c.midis!.first), [60, 64, 67]);
    expect(pitched.map((c) => c.steps), [2, 2, 4]);
    expect(
      shared.cells.fold<int>(0, (a, c) => a + c.steps),
      16, // fills the 2-bar grid
    );
  });

  testWidgets('the Analysis toggle shows the live harmony banner',
      (tester) async {
    await pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    // No analysis banner until the toggle is on.
    expect(find.text('C Major'), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.workshopAnalysis));
    await tester.pumpAndSettle();

    // The banner appears with the detected key (empty score → C major default).
    expect(find.text('C Major'), findsOneWidget);

    // Toggling it off removes the banner again.
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.workshopAnalysis));
    await tester.pumpAndSettle();
    expect(find.text('C Major'), findsNothing);
  });

  testWidgets('🔍 Inspect mode: tapping a note opens its Looking-Glass card',
      (tester) async {
    await pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final editor = _editor(tester);

    // Place a note via the piano so there is something to inspect.
    await tester.tap(_pianoKey());
    await tester.pump();
    final id = editor.debugFirstNoteId;
    expect(id, isNotNull);

    // A drag is live while editing…
    expect(editor.debugTryDragStart(id!), isTrue);

    // Turn Inspect on from the ⋮ menu.
    expect(editor.inspectMode, isFalse);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.inspectMode));
    await tester.pumpAndSettle();
    expect(editor.inspectMode, isTrue);

    // …but a drag is suppressed in Inspect mode so a note can't be moved.
    expect(editor.debugTryDragStart(id), isFalse);

    // Inspecting the note opens the info sheet with its scale-degree phrase.
    editor.debugInspect(id);
    await tester.pumpAndSettle();
    expect(find.textContaining('major'), findsOneWidget); // "… of C major"
  });

  testWidgets('🔍 Inspect mode: desktop hover shows a floating note card',
      (tester) async {
    await pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final editor = _editor(tester);

    await tester.tap(_pianoKey());
    await tester.pump();
    final id = editor.debugFirstNoteId;
    expect(id, isNotNull);

    // Hover does nothing until Inspect mode is on.
    editor.debugHoverElement(id);
    await tester.pump();
    expect(editor.debugHoverCardShown, isFalse);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.inspectMode));
    await tester.pumpAndSettle();

    // Now hovering the note raises the floating card…
    editor.debugHoverElement(id);
    await tester.pump();
    expect(editor.debugHoverCardShown, isTrue);
    expect(find.byType(Card), findsWidgets);
    expect(find.textContaining('major'), findsOneWidget); // "… of C major"

    // …and leaving the note clears it.
    editor.debugHoverElement(null);
    await tester.pump();
    expect(editor.debugHoverCardShown, isFalse);
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

  testWidgets('the time-signature picker offers compound + wider meters',
      (tester) async {
    await pump(tester);
    // Open the meter dropdown (its closed value is the default 4/4).
    await tester.tap(find.text('4/4').first);
    await tester.pumpAndSettle();
    // The old picker stopped at 2/4·3/4·4/4; these were a UI cap only.
    for (final meter in ['6/8', '9/8', '5/4', '2/2']) {
      expect(
        find.text(meter),
        findsWidgets,
        reason: '$meter should be offerable now',
      );
    }
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

  testWidgets('play-with-instrument renders the piece through a saved voice',
      (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    await tester.tap(_pianoKey()); // put a note in the piece
    await tester.pump();

    // A "My Instruments" voice (embedded sample) plays the piece — the picker
    // minus the sheet. It must render + play without throwing.
    final pcm = Float64List(1024);
    for (var i = 0; i < pcm.length; i++) {
      pcm[i] = 0.4 * math.sin(2 * math.pi * 220 * i / 44100);
    }
    expect(
      () => editor.debugPlayWithInstrument(SampleInstrument('v', pcm)),
      returnsNormally,
    );
    // the transport button is present + enabled with content
    expect(find.byIcon(Icons.piano_outlined), findsWidgets);
  });

  testWidgets('the voice toggle routes note entry to the active voice',
      (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _enterStudio(tester); // the voice toggle is a Studio control

    // A note in voice 1.
    await tester.tap(_pianoKey());
    await tester.pump();
    expect(editor.noteCount, 1);

    // Switch to voice 2 — the active voice is empty, so noteCount reads 0.
    await tester.tap(find.text(l10n.workshopVoice2));
    await tester.pump();
    expect(editor.noteCount, 0);

    // Entry now lands in voice 2.
    await tester.tap(_pianoKey());
    await tester.pump();
    expect(editor.noteCount, 1);

    // Voice 1 kept its note.
    await tester.tap(find.text(l10n.workshopVoice1));
    await tester.pump();
    expect(editor.noteCount, 1);
  });

  testWidgets('Studio editing controls explain voice and insert modes',
      (tester) async {
    await pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _enterStudio(tester);

    expect(find.byTooltip(l10n.workshopVoiceSelectorHelp), findsOneWidget);
    expect(find.byTooltip(l10n.workshopInsertModeHelp), findsOneWidget);
  });

  testWidgets('score title can be set before saving', (tester) async {
    await pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.tap(find.byTooltip(l10n.workshopSetTitle));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Morning Demo');
    await tester.tap(
      find.text(
        MaterialLocalizations.of(tester.element(find.byType(AlertDialog)))
            .okButtonLabel,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(l10n.workshopSetTitle));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Morning Demo'), findsOneWidget);
    expect(
      _editor(tester).debugMusicXmlExport(),
      contains('<part-name>Morning Demo</part-name>'),
    );
  });

  testWidgets('narrow workshop keeps title and menu actions reachable',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _appHome(
        const MediaQuery(
          data: MediaQueryData(size: Size(320, 640)),
          child: CompositionWorkshopScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Set score title'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Studio inspector is off by default and toggles on',
      (tester) async {
    await pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Place + select a note.
    await tester.tap(_pianoKey());
    await tester.pump();

    // On the Sandbox shelf the inspector isn't even offered.
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text(l10n.workshopInspector), findsNothing);
    await tester.tap(find.text(l10n.workshopStudioMode)); // enter Studio
    await tester.pumpAndSettle();

    // In Studio, toggle the inspector on from the ⋮ menu.
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.workshopInspector));
    await tester.pumpAndSettle();

    // The panel now shows, with the selected note's editable properties.
    expect(find.text(l10n.workshopInspector), findsOneWidget);
    expect(find.byType(FilterChip), findsWidgets); // articulation/tie chips
    expect(find.text(l10n.workshopStaccato), findsOneWidget);
  });

  testWidgets('the inspector edits a multi-note selection', (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Two notes, then extend the selection to cover both.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pump();
    expect(editor.noteCount, 2);
    await tester.ensureVisible(
      find.byIcon(Icons.keyboard_double_arrow_left),
    );
    await tester.tap(find.byIcon(Icons.keyboard_double_arrow_left));
    await tester.pump();
    expect(editor.selectedCount, 2);

    // Studio inspector shows the shared controls for the whole selection
    // (a multi-note selection, not just a single note).
    await _enterStudio(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.workshopInspector));
    await tester.pumpAndSettle();
    expect(find.text(l10n.workshopStaccato), findsOneWidget);
  });

  testWidgets('the inspector gives a rest a Structure view (not a dead end)',
      (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // A rest is selected on insertion — it carries no note properties, so the
    // inspector used to show only a "Rest" label with nothing to do.
    await tester.ensureVisible(find.byIcon(Icons.music_off_outlined));
    await tester.tap(find.byIcon(Icons.music_off_outlined));
    await tester.pump();
    expect(editor.selectedCount, 1);

    await _enterStudio(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.workshopInspector));
    await tester.pumpAndSettle();

    // The rest now has a bar-anchored Structure section: it defaults to "No
    // change" and hosts the "Change from here…" editor, which opens for a rest.
    expect(find.text(l10n.workshopStructure), findsOneWidget);
    expect(find.text(l10n.workshopNoChange), findsWidgets);
    await tester.tap(find.text(l10n.workshopChangeHere));
    await tester.pumpAndSettle();
    expect(find.text(l10n.workshopChangeHereTitle), findsOneWidget);
  });

  testWidgets('the inspector Structure section lists an anchored change',
      (tester) async {
    await pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.tap(_pianoKey()); // place + select a note
    await tester.pump();

    // Anchor a repeat-end at the note via the ⌃ palette.
    final palette = find.byIcon(Icons.expand_less);
    await tester.ensureVisible(palette);
    await tester.pumpAndSettle();
    await tester.tap(palette);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.workshopRepeatEnd));
    await tester.pumpAndSettle();

    // The Studio inspector's Structure section reflects that anchored change
    // instead of "No change".
    await _enterStudio(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.workshopInspector));
    await tester.pumpAndSettle();

    expect(find.text(l10n.workshopStructure), findsOneWidget);
    expect(find.text(l10n.workshopRepeatEnd), findsOneWidget);
    expect(find.text(l10n.workshopNoChange), findsNothing);
  });

  testWidgets('the Studio shelf reveals the depth controls', (tester) async {
    await pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Sandbox (default): the voice + input-mode toggles are hidden, so the kid
    // surface is simple.
    expect(find.text(l10n.workshopVoice2), findsNothing);
    expect(find.text(l10n.workshopInsertMode), findsNothing);

    await _enterStudio(tester);

    // Studio: the depth controls appear.
    expect(find.text(l10n.workshopVoice2), findsOneWidget);
    expect(find.text(l10n.workshopInsertMode), findsOneWidget);
  });

  testWidgets('tapping a voice-2 note follows the caret to voice 2',
      (tester) async {
    await pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _enterStudio(tester);

    int selectedVoice() => tester
        .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
        .selected
        .first;

    // A voice-1 note, then switch to voice 2, add one there, and switch back.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();
    await tester.tap(find.text(l10n.workshopVoice2));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    await tester.tap(find.text(l10n.workshopVoice1));
    await tester.pump();
    expect(selectedVoice(), 0);

    // crisp_notation reports voice-2 ids on tap; drive the real onElementTap
    // callback with the rendered voice-2 note's id.
    final view = tester.widget<MultiSystemView>(find.byType(MultiSystemView));
    final v2id = view.score.measures
        .expand((m) => m.voice2)
        .firstWhere((e) => e.id != null)
        .id!;
    view.onElementTap!(v2id);
    await tester.pump();

    // The editor followed the tap: the active voice is now voice 2.
    expect(selectedVoice(), 1);
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
    expect(find.text(l10n.workshopLoadFromLibrary), findsOneWidget);
    expect(find.text(l10n.workshopExport), findsOneWidget);
  });

  testWidgets('Play with an instrument is available before note entry',
      (tester) async {
    await pump(tester);
    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.piano_outlined),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNotNull);
    expect(_editor(tester).noteCount, 0);
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
    // Repeat barlines are toggles in the same palette.
    expect(find.text(l10n.workshopRepeatStart), findsOneWidget);
    expect(find.text(l10n.workshopRepeatEnd), findsOneWidget);
    // The palette reads as labelled sections (categorized insertion palette):
    // a non-selectable header opens each group.
    expect(find.text(l10n.workshopArticulations.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.workshopDynamics.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.workshopStructure.toUpperCase()), findsOneWidget);
    // Ornaments too, grouped under the categorized "Ornament" section header.
    expect(find.text(l10n.workshopOrnament.toUpperCase()), findsOneWidget);
    expect(find.text('Trill'), findsOneWidget);
  });

  testWidgets('the palette sets a trill on the selected note', (tester) async {
    await pump(tester);
    await tester.tap(_pianoKey()); // place + select a note
    await tester.pump();
    final palette = find.byIcon(Icons.expand_less);
    await tester.ensureVisible(palette);
    await tester.pumpAndSettle();
    await tester.tap(palette);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trill'));
    await tester.pumpAndSettle();

    // Reopen; the Trill item is now checked.
    await tester.ensureVisible(palette);
    await tester.pumpAndSettle();
    await tester.tap(palette);
    await tester.pumpAndSettle();
    final item = tester.widget<CheckedPopupMenuItem<(String, Object?)>>(
      find.ancestor(
        of: find.text('Trill'),
        matching: find.byType(CheckedPopupMenuItem<(String, Object?)>),
      ),
    );
    expect(item.checked, isTrue);
  });

  testWidgets('the palette toggles a repeat end on the selected note',
      (tester) async {
    await pump(tester);
    await tester.tap(_pianoKey()); // place + select a note
    await tester.pump();
    final palette = find.byIcon(Icons.expand_less);
    await tester.ensureVisible(palette);
    await tester.pumpAndSettle();
    await tester.tap(palette);
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.workshopRepeatEnd));
    await tester.pumpAndSettle();

    // The single bar now ends with a repeat barline.
    expect(_editor(tester).barCount, 1);
    // Reopen the palette; the repeat-end item is now checked.
    await tester.ensureVisible(palette);
    await tester.pumpAndSettle();
    await tester.tap(palette);
    await tester.pumpAndSettle();
    final checked = tester.widget<CheckedPopupMenuItem<(String, Object?)>>(
      find.ancestor(
        of: find.text(l10n.workshopRepeatEnd),
        matching: find.byType(CheckedPopupMenuItem<(String, Object?)>),
      ),
    );
    expect(checked.checked, isTrue);
  });

  testWidgets('the palette opens the mid-score "change from here" dialog',
      (tester) async {
    await pump(tester);
    await tester.tap(_pianoKey()); // place + select a note
    await tester.pump();
    final palette = find.byIcon(Icons.expand_less);
    await tester.ensureVisible(palette);
    await tester.pumpAndSettle();
    await tester.tap(palette);
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.workshopChangeHere));
    await tester.pumpAndSettle();

    // The dialog offers all five bar-anchored changes, each with a "no change"
    // default, anchored to the selected note.
    expect(find.text(l10n.workshopChangeHereTitle), findsOneWidget);
    expect(find.text(l10n.workshopClef), findsOneWidget);
    expect(find.text(l10n.workshopClefMidBar), findsOneWidget);
    expect(find.text(l10n.workshopKey), findsOneWidget);
    expect(find.text(l10n.workshopTimeSignature), findsOneWidget);
    expect(find.text(l10n.workshopTempo), findsOneWidget);
    expect(find.text(l10n.workshopVolta), findsOneWidget);
    expect(find.text(l10n.workshopNavigation), findsOneWidget);
    expect(find.text(l10n.workshopNoChange), findsNWidgets(7));
  });

  testWidgets('the transport plays and stops, toggling its icon',
      (tester) async {
    await pump(tester);
    await tester.tap(_pianoKeyAt(16)); // a non-empty document
    await tester.pump();
    await tester.tap(_pianoKeyAt(18));
    await tester.pump();

    // Play → the button flips to a stop icon (set synchronously in
    // _startPlayback). Avoid pumpAndSettle (the periodic timer never settles)
    // AND a timed pump (playback rides a real Stopwatch, so under load a short
    // piece could end before the assert).
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump(); // start
    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);

    // Stop → back to the play icon (and the timer is cancelled, so the test
    // tears down cleanly).
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsNothing);
  });

  testWidgets('playback drives both voices without crashing', (tester) async {
    await pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(_pianoKey()); // a voice-1 note
    await tester.pump();
    await _enterStudio(tester); // the voice toggle is a Studio control
    await tester.tap(find.text(l10n.workshopVoice2));
    await tester.pump();
    await tester.tap(_pianoKey()); // a voice-2 note
    await tester.pump();

    // The transport renders both voices into the mix (voice 2 used to be silent).
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    expect(find.byIcon(Icons.stop), findsOneWidget);
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('count-in and loop are ⋮ toggles, off by default',
      (tester) async {
    await pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    // Both start off, so playback is unchanged until armed.
    for (final label in [l10n.workshopCountIn, l10n.workshopLoopSelection]) {
      final item = tester.widget<CheckedPopupMenuItem<String>>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(CheckedPopupMenuItem<String>),
        ),
      );
      expect(item.checked, isFalse, reason: '$label defaults off');
    }

    // Arming count-in sticks.
    await tester.tap(find.text(l10n.workshopCountIn));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    final countIn = tester.widget<CheckedPopupMenuItem<String>>(
      find.ancestor(
        of: find.text(l10n.workshopCountIn),
        matching: find.byType(CheckedPopupMenuItem<String>),
      ),
    );
    expect(countIn.checked, isTrue);
  });

  testWidgets('playback still runs with count-in and loop armed',
      (tester) async {
    await pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(_pianoKeyAt(16));
    await tester.pump();
    await tester.tap(_pianoKeyAt(18)); // a second note, and it stays selected
    await tester.pump();

    // Arm both.
    for (final label in [l10n.workshopCountIn, l10n.workshopLoopSelection]) {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    // The transport starts (count-in prepended, selection looped) and stops.
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    expect(find.byIcon(Icons.stop), findsOneWidget);
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('the playback speed control switches the shown speed',
      (tester) async {
    await pump(tester);
    await tester.tap(_pianoKey());
    await tester.pump();

    // Defaults to 1×; open the speed menu and pick 0.5× (slow practice).
    expect(find.text('1×'), findsOneWidget);
    await tester.tap(find.text('1×'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('0.5×').last); // the menu item
    await tester.pumpAndSettle();

    // The chip now reads 0.5× and 1× is no longer shown.
    expect(find.text('0.5×'), findsOneWidget);
    expect(find.text('1×'), findsNothing);
  });

  testWidgets('multi-part playback: the transport plays all parts',
      (tester) async {
    await pump(tester);
    await tester.tap(_pianoKeyAt(16)); // a note in part 1
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('workshop-add-instrument')));
    await tester.pump();
    await tester.tap(_pianoKeyAt(18)); // a note in part 2 (now active)
    await tester.pump();
    expect(_editor(tester).partCount, 2);

    // Play → the button flips to stop synchronously (set in _startPlayback).
    // Don't advance the fake clock here: playback timing rides a real Stopwatch,
    // so a timed pump under load could end this short piece before we assert.
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    expect(find.byIcon(Icons.stop), findsOneWidget);

    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('a part can be muted from its menu', (tester) async {
    await pump(tester);
    await tester.tap(_pianoKeyAt(16));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('workshop-add-instrument')));
    await tester.pump();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Open part 1's menu (its tune icon) and mute it.
    await tester.tap(find.byIcon(Icons.tune).first);
    await tester.pumpAndSettle();
    expect(find.text(l10n.workshopMutePart), findsOneWidget);
    await tester.tap(find.text(l10n.workshopMutePart));
    await tester.pumpAndSettle();

    // Reopen: the mute item is now checked.
    await tester.tap(find.byIcon(Icons.tune).first);
    await tester.pumpAndSettle();
    final item = tester.widget<CheckedPopupMenuItem<void Function()>>(
      find.ancestor(
        of: find.text(l10n.workshopMutePart),
        matching: find.byType(CheckedPopupMenuItem<void Function()>),
      ),
    );
    expect(item.checked, isTrue);
  });

  testWidgets('the palette opens the grace-notes editor', (tester) async {
    await pump(tester);
    await tester.tap(_pianoKey()); // place + select a note
    await tester.pump();
    final palette = find.byIcon(Icons.expand_less);
    await tester.ensureVisible(palette);
    await tester.pumpAndSettle();
    await tester.tap(palette);
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.workshopGraceNotes).last);
    await tester.pumpAndSettle();

    // The editor shows the empty hint, the note buttons and the style toggle.
    expect(find.text(l10n.workshopGraceEmpty), findsOneWidget);
    expect(find.text(l10n.workshopGraceAcciaccatura), findsOneWidget);
    expect(find.text(l10n.workshopGraceAppoggiatura), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'C'), findsOneWidget);

    // Adding a grace note replaces the hint with a chip.
    await tester.tap(find.widgetWithText(OutlinedButton, 'D'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.workshopGraceEmpty), findsNothing);
    expect(find.byType(InputChip), findsOneWidget);
  });

  testWidgets('the ⋮ menu opens the initial-tempo dialog', (tester) async {
    await pump(tester);
    await tester.tap(_pianoKey()); // a non-empty document
    await tester.pump();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.workshopInitialTempo));
    await tester.pumpAndSettle();

    // The dialog offers the tempo presets, defaulting to "None" (unset).
    expect(find.text(l10n.workshopInitialTempo), findsOneWidget); // title
    expect(find.text(l10n.workshopTempo), findsOneWidget); // row label
    expect(find.text(l10n.workshopTempoNone), findsOneWidget); // default value
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

  testWidgets('Select mode stops the keyboard from placing notes',
      (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Insert (default): a letter places a note.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();
    expect(editor.noteCount, 1);

    await _enterStudio(tester); // the mode toggle is a Studio control

    // Switch to Select mode (the toggle shows the current mode's name).
    await tester.ensureVisible(find.text(l10n.workshopInsertMode));
    await tester.tap(find.text(l10n.workshopInsertMode));
    await tester.pumpAndSettle();
    expect(find.text(l10n.workshopSelectMode), findsOneWidget);

    // Typing no longer places notes.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pump();
    expect(editor.noteCount, 1, reason: 'select mode: typing does not place');

    // Back to Insert → placement resumes.
    await tester.ensureVisible(find.text(l10n.workshopSelectMode));
    await tester.tap(find.text(l10n.workshopSelectMode));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    expect(editor.noteCount, 2);
  });

  testWidgets('Sandbox: the value strip still rewrites the selection',
      (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    // Four quarters fill one 4/4 bar; the last stays selected.
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pump();
    }
    expect(editor.barCount, 1);

    // Sandbox keeps the forgiving dual behaviour: picking "whole" (digit 1)
    // also fixes the selected quarter, which then spills into a second bar.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(editor.barCount, 2, reason: 'Sandbox rewrites the selection');
  });

  testWidgets('Studio: insert mode arms without rewriting; select mode applies',
      (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pump();
    }
    expect(editor.barCount, 1);

    await _enterStudio(tester); // insert is still the default mode

    // Studio + insert: picking a value arms the NEXT note and leaves the
    // selected quarter alone — no silent rewrite (Cause 2).
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(editor.barCount, 1, reason: 'Studio insert leaves the selection');

    // Studio + select: the palette applies to the selection instead.
    await tester.ensureVisible(find.text(l10n.workshopInsertMode));
    await tester.tap(find.text(l10n.workshopInsertMode));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(
      editor.barCount,
      2,
      reason: 'Studio select applies to the selection',
    );
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

  testWidgets('the triplet button groups a two-note range into a tuplet',
      (tester) async {
    await pump(tester);
    await tester.tap(_pianoKeyAt(16));
    await tester.pump();
    await tester.tap(_pianoKeyAt(18)); // two notes, second selected
    await tester.pump();
    final extend = find.byIcon(Icons.keyboard_double_arrow_left);
    await tester.ensureVisible(extend);
    await tester.tap(extend);
    await tester.pump();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final triplet = find.byTooltip(l10n.workshopTuplet);
    await tester.ensureVisible(triplet);
    await tester.tap(triplet);
    await tester.pump();

    // The button now reflects that the selection is a tuplet (highlighted).
    // (The '³' glyph identifies the IconButton; find.byTooltip points at the
    // Tooltip, not the button.)
    final btn = tester.widget<IconButton>(
      find.widgetWithText(IconButton, '³'),
    );
    expect(btn.isSelected, isTrue);
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

  // MusicXML/.mxl (library) + MIDI/ABC (our own multi-part writers) carry every
  // part; the remaining single-Score text formats drop all but the active one,
  // so the sheet must say which.
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

    // MusicXML/.mxl + MIDI/ABC carry everything; the rest warn.
    final multiPartCount = kExportFormats.where((f) => f.multiPart).length;
    expect(
      find.text(l10n.workshopExportAllParts(2)),
      findsNWidgets(multiPartCount),
    );
    expect(
      find.text(l10n.workshopExportActivePartOnly('Part 2')),
      findsNWidgets(kExportFormats.length - multiPartCount),
      reason: 'every single-Score format must admit it drops the other parts',
    );
  });

  test('exactly the multi-part-capable formats claim multi-part support', () {
    // Guards the flag against a new format being added without deciding.
    // MusicXML/mxl via the library; MIDI/ABC via our own multi-part writers;
    // GP tab via multiPartToGpif (one track per part); LilyPond via
    // multiPartToLilyPond (a StaffGroup per part).
    expect(
      kExportFormats.where((f) => f.multiPart).map((f) => f.ext),
      ['musicxml', 'mxl', 'mid', 'abc', 'gp', 'ly'],
    );
  });

  testWidgets('multi-part MIDI + ABC export carries every part',
      (tester) async {
    await pump(tester);
    // Two parts, each with a note.
    await tester.tap(_pianoKey());
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('workshop-add-instrument')));
    await tester.pump();
    await tester.tap(_pianoKey());
    await tester.pump();
    expect(_editor(tester).partCount, 2);

    // MIDI → a format-1 SMF with 2 tracks.
    final (midi, _) = await _editor(tester).debugGenerateExport('mid');
    expect(midi, isNotNull);
    expect(String.fromCharCodes(midi!.sublist(0, 4)), 'MThd');
    expect((midi[8] << 8) | midi[9], 1); // format 1
    expect((midi[10] << 8) | midi[11], 2); // 2 tracks

    // ABC → two V: voices.
    final (_, abc) = await _editor(tester).debugGenerateExport('abc');
    expect(abc, isNotNull);
    final voices = RegExp(r'^V:\d+ name=', multiLine: true).allMatches(abc!);
    expect(voices.length, 2);

    // GP tab → a .gp (ZIP/PK header) with two GP tracks, notes recoverable.
    final (gp, _) = await _editor(tester).debugGenerateExport('gp');
    expect(gp, isNotNull);
    expect(gp!.sublist(0, 2), [0x50, 0x4B]); // PK — .gp is a ZIP
    final back = multiPartScoreFromGpif(readGpifFromGp(gp));
    expect(back.parts, hasLength(2));
    for (final part in back.parts) {
      expect(
        part.measures.expand((m) => m.elements).whereType<NoteElement>(),
        isNotEmpty,
      );
    }
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
    expect(
      tester.widget<MultiPartCanvas>(find.byType(MultiPartCanvas)).onMarquee,
      isNotNull,
    );
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

  testWidgets('the ⋮ menu toggles split-notes mode (checked round-trip)',
      (tester) async {
    await pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    Future<CheckedPopupMenuItem<String>> openAndFindSplit() async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      return tester.widget<CheckedPopupMenuItem<String>>(
        find.ancestor(
          of: find.text(l10n.workshopSplitNotes),
          matching: find.byType(CheckedPopupMenuItem<String>),
        ),
      );
    }

    expect((await openAndFindSplit()).checked, isFalse);
    await tester.tap(find.text(l10n.workshopSplitNotes));
    await tester.pumpAndSettle();
    expect(
      (await openAndFindSplit()).checked,
      isTrue,
      reason: 'split mode is now on',
    );
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

    // Names are painted by the app overlay so octave numbers (for example F2)
    // are available even when the notation package's letter-only labels are
    // enabled internally.
    expect(view().showNoteNames, isFalse);
    // EN locale + auto naming → English letters in the overlay.
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

  testWidgets('Scan sheet music (OMR): a recognised image loads as notes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Fake recogniser: ignores the bytes, returns a known 4-note score (as the
    // native CrispEmbed engine's recognizeSheetMusic would, minus the model).
    final canned =
        bekernToScore('**kern <b> 4 c <b> 4 d <b> 4 e <b> 4 f <b> *-');
    await tester.pumpWidget(
      _appHome(CompositionWorkshopScreen(debugScanImage: (_) async => canned)),
    );
    await tester.pumpAndSettle();

    final editor = _editor(tester);
    expect(editor.noteCount, 0);
    await editor.debugScanBytes(Uint8List.fromList([1, 2, 3]));
    await tester.pumpAndSettle();
    expect(editor.noteCount, greaterThan(0));
  });

  testWidgets(
      'Scan sheet music (OMR): an unreadable/unavailable scan is a '
      'no-op (keeps the document)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // null = couldn't read / no on-device model — the document is untouched.
    await tester.pumpWidget(
      _appHome(CompositionWorkshopScreen(debugScanImage: (_) async => null)),
    );
    await tester.pumpAndSettle();

    final editor = _editor(tester);
    await editor.debugScanBytes(Uint8List.fromList([1, 2, 3]));
    await tester.pumpAndSettle();
    expect(editor.noteCount, 0);
    expect(tester.takeException(), isNull);
  });
}
