// Accessibility of the custom widgets a screen reader would otherwise see as
// anonymous boxes: the piano keyboard, the fretboard, the home module cards.
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/debug_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/drums/drum_kit_visual.dart';
import 'package:comet_beat/features/home/screens/home_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/guitar_fretboard.dart';
import 'package:comet_beat/shared/widgets/piano_keyboard.dart';
import 'package:comet_beat/shared/widgets/step_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Widget child) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('de')],
      home: Scaffold(body: child),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('piano keys are named buttons, and a lit key is selected',
      (tester) async {
    final handle = tester.ensureSemantics();
    var tapped = -1;
    await tester.pumpWidget(
      _app(
        SizedBox(
          height: 120,
          width: 700,
          child: PianoKeyboard(
            whiteKeyCount: 7,
            keyColors: const {64: Colors.green},
            onKeyTap: (m) => tapped = m,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('C4'), findsOneWidget);
    expect(find.bySemanticsLabel('C♯4'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('E4')),
      matchesSemantics(
        label: 'E4',
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    // The semantic tap is the real tap.
    tester.semantics.tap(find.semantics.byLabel('D4'));
    expect(tapped, 62);
    handle.dispose();
  });

  testWidgets('a name-the-key quiz announces keys by position, not by name',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        const SizedBox(
          height: 120,
          width: 700,
          child: PianoKeyboard(whiteKeyCount: 7, semanticNames: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('C4'), findsNothing);
    expect(find.bySemanticsLabel('Piano key 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Piano key 12'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('fretboard cells announce string and fret', (tester) async {
    final handle = tester.ensureSemantics();
    var tapped = -1;
    await tester.pumpWidget(
      _app(GuitarFretboard(maxFret: 3, onTap: (m) => tapped = m)),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('String 1, fret 0'), findsOneWidget);
    expect(find.bySemanticsLabel('String 6, fret 3'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('String 1, fret 2'));
    expect(tapped, 66); // high E (64) + 2
    handle.dispose();
  });

  testWidgets('home: every tap target is labelled, locked cards say why',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsService()),
          ChangeNotifierProvider(
            create: (_) => SriService(getNow: () => DateTime(2026, 7, 11)),
          ),
          Provider<AudioService>(create: (_) => AudioService()),
          ChangeNotifierProvider(create: (_) => ProgressService()),
          ChangeNotifierProvider(create: (_) => DebugService()),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('en'), Locale('de')],
          home: HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

    expect(
      find.bySemanticsLabel(
        '${l10n.moduleNoteValues}, ${l10n.moduleNoteValuesSubtitle}',
      ),
      findsOneWidget,
    );
    final locked = find.bySemanticsLabel(
      RegExp('^${RegExp.escape(l10n.moduleMeasures)}, ${l10n.locked}'),
    );
    await tester.scrollUntilVisible(locked, 200);
    expect(locked, findsOneWidget);
    handle.dispose();
  });

  testWidgets('step-grid cells are named, toggled, and tappable',
      (tester) async {
    final handle = tester.ensureSemantics();
    final toggled = <(int, int)>[];
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 400,
          child: StepGridView(
            cells: const [StepCell(1, 4)],
            steps: 8,
            percussive: true,
            onToggle: (row, step) => toggled.add((row, step)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    final on = find.bySemanticsLabel(l10n.a11yStepCell(l10n.drumkitSnare, 5));
    expect(on, findsOneWidget);
    expect(
      tester.getSemantics(on),
      matchesSemantics(
        label: l10n.a11yStepCell(l10n.drumkitSnare, 5),
        isButton: true,
        hasToggledState: true,
        isToggled: true,
        hasTapAction: true,
      ),
    );
    final off = find.bySemanticsLabel(l10n.a11yStepCell(l10n.drumkitKick, 1));
    expect(
      tester.getSemantics(off),
      matchesSemantics(
        label: l10n.a11yStepCell(l10n.drumkitKick, 1),
        isButton: true,
        hasToggledState: true,
        hasTapAction: true,
      ),
    );

    tester.semantics.tap(
      find.semantics.byLabel(
        l10n.a11yStepCell(l10n.drumkitHat, 2),
      ),
    );
    expect(toggled, [(0, 1)]);
    // A finger tap still reaches the grid through the overlay.
    await tester.tapAt(
      tester.getTopLeft(find.byType(StepGridView)) + const Offset(10, 5),
    );
    expect(toggled.last, (0, 0));
    handle.dispose();
  });

  testWidgets('drum-kit pieces are named buttons that play', (tester) async {
    final handle = tester.ensureSemantics();
    final hits = <Drum>[];
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 400,
          height: 300,
          child: DrumKitVisual(
            step: ValueNotifier(0),
            hitAt: (_, __) => false,
            onHit: hits.add,
          ),
        ),
      ),
    );
    await tester.pump();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.bySemanticsLabel(l10n.drumkitRide), findsOneWidget);
    tester.semantics.tap(find.semantics.byLabel(l10n.drumkitSnare));
    expect(hits, [Drum.snare]);
    handle.dispose();
  });
}
