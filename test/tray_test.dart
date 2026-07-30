// WS-X6 slice 1 — the clipboard.
//
// The feature exists to answer a question four drop targets could not: how does
// anything ever get dragged anywhere? So the test that carries this file is the
// one at the bottom — a chip dragged from the clipboard band onto the surface
// below it, landing through the drop path that already shipped, **with no change
// to that path**. Everything above it is the machinery that makes that possible.
//
// The band is INLINE rather than an overlay, and that is the design's whole
// load-bearing choice: a menu or a sheet would put a barrier between the chip
// and the surface, and you would be able to look at your samples and never drag
// one onto anything.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show SampleInstrument, TrackerInstrument;
import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/interop/drag_payload.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/core/tray/tray.dart';
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:comet_beat/shared/widgets/tray_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

TrayItem _put(TrayService tray, String label, {int? at}) => tray.add(
      kind: AppMode.loop,
      label: label,
      document: const GrooveSpec(enabled: {'bass'}),
      nowMs: at,
    );

/// A sample-backed voice, the heavy kind the clipboard was worried about.
TrackerInstrument _voice() => SampleInstrument('Rhodes', Float64List(64));

LoopMixerTester _game(WidgetTester tester) =>
    tester.state<State<LoopMixerScreen>>(find.byType(LoopMixerScreen))
        as LoopMixerTester;

/// Mounts Loop Studio with a shared clipboard and opens the band.
Future<(LoopMixerTester, TrayService)> _open(
  WidgetTester tester, {
  TrayService? tray,
}) async {
  final service = tray ?? TrayService();
  await pumpGame(
    tester,
    Provider<TrayService>.value(
      value: service,
      child: const LoopMixerScreen(),
    ),
  );
  final game = _game(tester)..debugFreezeSeams();
  await tester.pump(const Duration(milliseconds: 50));
  return (game, service);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('what the clipboard holds', () {
    test('newest first — what you just put down is what you reach for', () {
      final tray = TrayService();
      _put(tray, 'first', at: 1);
      _put(tray, 'second', at: 2);
      expect(tray.items.map((i) => i.label), ['second', 'first']);
    });

    test('it holds MANY — a whole kit, not four things', () {
      // The maintainer's own examples are bulk: every instrument of a tracker
      // track, every sample of a drum kit.
      final tray = TrayService();
      for (var i = 0; i < 50; i++) {
        _put(tray, 'sample $i');
      }
      expect(tray.length, 50);
    });

    test('and when it is full the OLDEST goes, never the newest', () {
      final tray = TrayService(maxItems: 3);
      for (final label in ['a', 'b', 'c', 'd']) {
        _put(tray, label);
      }
      expect(tray.items.map((i) => i.label), ['d', 'c', 'b']);
    });

    test('(X) removes exactly one, and twice is not an error', () {
      final tray = TrayService();
      final a = _put(tray, 'a');
      _put(tray, 'b');
      tray
        ..remove(a.id)
        ..remove(a.id);
      expect(tray.items.map((i) => i.label), ['b']);
    });

    test('two identical things are two items', () {
      // Putting the same riff on twice was a deliberate act, not a mistake to
      // be deduplicated away.
      final tray = TrayService();
      _put(tray, 'riff');
      _put(tray, 'riff');
      expect(tray.length, 2);
      expect(tray.items.first.id, isNot(tray.items.last.id));
    });

    test('it can be asked for only what a surface can take', () {
      final tray = TrayService();
      _put(tray, 'a groove');
      tray.add(kind: AppMode.tab, label: 'a riff', document: 'x');
      expect(tray.ofKind(AppMode.tab).map((i) => i.label), ['a riff']);
      expect(tray.ofKind(AppMode.loop).map((i) => i.label), ['a groove']);
    });

    test('an item hands over the SAME payload the drop targets accept', () {
      final tray = TrayService();
      final item = _put(tray, 'x');
      final payload = item.payload;
      expect(payload, isA<MusicDragPayload>());
      expect(payload!.kind, AppMode.loop);
      expect(payload.document, item.document);
    });
  });

  group('the band', () {
    testWidgets('shows what is on it, and says so when it is empty',
        (tester) async {
      final tray = TrayService();
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TrayPanel(tray: tray))),
      );
      expect(find.textContaining('Nothing here yet'), findsOneWidget);

      final item = _put(tray, 'Drums');
      await tester.pump();
      expect(find.text('Drums'), findsOneWidget);
      expect(find.byKey(Key('tray-chip-${item.id}')), findsOneWidget);
    });

    testWidgets('the (X) on a chip removes it, live', (tester) async {
      final tray = TrayService();
      final item = _put(tray, 'Drums');
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TrayPanel(tray: tray))),
      );
      await tester.tap(find.byKey(Key('tray-remove-${item.id}')));
      await tester.pump();
      expect(tray.isEmpty, isTrue);
      expect(find.text('Drums'), findsNothing);
    });

    testWidgets('tapping a chip places it, when the host offers that',
        (tester) async {
      final tray = TrayService();
      final placed = <String>[];
      _put(tray, 'Drums');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrayPanel(
              tray: tray,
              onPlace: (item) => placed.add(item.label),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Drums'));
      await tester.pump();
      expect(placed, ['Drums']);
    });
  });

  group('instruments — a voice, not a document', () {
    test('an instrument item has no payload, because it is not droppable', () {
      // Inventing one would make it land as a silent, empty clip.
      final tray = TrayService()
        ..addInstrument(label: 'Rhodes', instrument: _voice());
      final item = tray.items.single;
      expect(item.isInstrument, isTrue);
      expect(item.payload, isNull);
      expect(item.instrument, isNotNull);
    });

    test('putting one on the clipboard does NOT copy its samples', () {
      // Corrects how slice 1 described this: Dart hands out references, so the
      // clipboard holds the very same object the engine does. The by-reference
      // question is real only at persistence time.
      final voice = _voice();
      final tray = TrayService()
        ..addInstrument(label: 'Rhodes', instrument: voice);
      expect(identical(tray.items.single.instrument, voice), isTrue);
    });

    testWidgets('its chip is tappable but NOT draggable', (tester) async {
      final tray = TrayService()
        ..addInstrument(label: 'Rhodes', instrument: _voice());
      final placed = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrayPanel(
              tray: tray,
              onPlace: (i) => placed.add(i.label),
            ),
          ),
        ),
      );
      expect(
        find.byType(Draggable<MusicDragPayload>),
        findsNothing,
        reason: 'no document to drop — offering the gesture would lie',
      );
      await tester.tap(find.text('Rhodes'));
      await tester.pump();
      expect(placed, ['Rhodes']);
    });

    testWidgets(
        'Loop Studio can put a track voice on it and play another '
        'track with it', (tester) async {
      final shared = TrayService();
      final (game, _) = await _open(tester, tray: shared);
      // A fresh screen has nothing enabled, so there would be no track to
      // offer — the picker correctly shows nothing rather than inventing one.
      game
        ..toggleTrack('bass')
        ..toggleTrack('chords');
      await tester.pump(const Duration(milliseconds: 50));

      // A track with no voice cannot contribute one.
      expect(game.putVoiceOnTray('bass'), isFalse);

      game.debugSetTrackVoice('bass', _voice());
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.putVoiceOnTray('bass'), isTrue);
      await tester.pump(const Duration(milliseconds: 50));
      expect(shared.items.single.isInstrument, isTrue);

      // Placing it ASKS which track — applying it to a guessed one would be a
      // change the player did not make, on a track they may not be looking at.
      // Explicit pumps, not `pumpAndSettle`: this screen runs a loop clock and
      // never reaches a quiescent frame.
      await tester.tap(find.text('Rhodes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('tray-voice-target-chords')), findsOneWidget);

      await tester.tap(find.byKey(const Key('tray-voice-target-chords')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(game.voiceIdOf('chords'), 'Rhodes');
    });
  });

  group('across editors — the actual promise', () {
    testWidgets(
        'a SAMPLE taken in the Audio Editor plays a track in Loop Studio',
        (tester) async {
      // The maintainer's first example, end to end: "we can put from Audio
      // Editor a few samples there, use them again as Instruments e.g. in Loop
      // Studio."
      final shared = TrayService();
      final daw = DawService()
        ..addClip(SampleSource(Float64List(4410)))
        ..renameTrack(0, 'Snare');
      await pumpGame(
        tester,
        const DawScreen(),
        extraProviders: [
          ChangeNotifierProvider<DawService>.value(value: daw),
          Provider<TrayService>.value(value: shared),
        ],
      );
      await tester.pumpAndSettle();

      // Open the clip and put its audio on the clipboard.
      await tester.tap(find.byKey(const Key('daw-clip-0-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('daw-clip-to-tray')));
      await tester.pumpAndSettle();

      expect(shared.length, 1);
      expect(
        shared.items.single.isInstrument,
        isTrue,
        reason: 'a voice, not a document that would only land back on a lane',
      );
      expect(shared.items.single.label, 'Snare');

      // Now Loop Studio, same clipboard: play a track with it.
      final (game, _) = await _open(tester, tray: shared);
      game
        ..toggleTrack('bass')
        ..toggleTrack('chords');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const Key('loop-tray-toggle')));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Snare'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('tray-voice-target-bass')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(game.voiceIdOf('bass'), 'Snare');
    });

    testWidgets(
        'a groove put on in Loop Studio is on the band in the Audio Editor, '
        'and lands on a lane', (tester) async {
      // The maintainer's own second example: "From Loop Studio, we can copy a
      // guitar riff or a drum beat, to implement them then in Audio Editor."
      // One shared service, two screens, and the Audio Editor's timeline needs
      // no change — it already accepted this payload.
      final shared = TrayService();
      final (game, _) = await _open(tester, tray: shared);
      game.putGrooveOnTray();
      await tester.pump(const Duration(milliseconds: 50));
      expect(shared.length, 1);

      // Now the other editor, with the SAME clipboard.
      final daw = DawService();
      await pumpGame(
        tester,
        const DawScreen(),
        extraProviders: [
          ChangeNotifierProvider<DawService>.value(value: daw),
          Provider<TrayService>.value(value: shared),
        ],
      );
      await tester.pumpAndSettle();
      expect(daw.clipCount, 0);

      // Open the band here and place the groove.
      final toggle = find.byIcon(Icons.inventory_2_outlined);
      if (toggle.evaluate().isEmpty) {
        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byIcon(Icons.inventory_2_outlined).first);
      await tester.pumpAndSettle();
      expect(find.byType(TrayPanel), findsOneWidget);

      // By key, not by text: the Audio Editor has its own "BPM" readout, and
      // a text finder matches both it and the chip.
      await tester.tap(find.byKey(Key('tray-chip-${shared.items.single.id}')));
      await tester.pumpAndSettle();
      expect(
        daw.clipCount,
        1,
        reason: 'the groove became a clip on a lane in the other editor',
      );
    });
  });

  group('in Loop Studio', () {
    testWidgets('the app-bar button opens and closes the band', (tester) async {
      // In the APP BAR, not the toolbar below it — that Row is full and has
      // overflowed twice.
      final (_, tray) = await _open(tester);
      // NOT 'Drums': Loop Studio's own track card is labelled that, and the
      // finder would match the card instead of the chip.
      _put(tray, 'Kit bits');
      expect(find.text('Kit bits'), findsNothing);

      await tester.tap(find.byKey(const Key('loop-tray-toggle')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Kit bits'), findsOneWidget);

      await tester.tap(find.byKey(const Key('loop-tray-toggle')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Kit bits'), findsNothing);
    });

    testWidgets('putting the groove on the clipboard opens it and adds one',
        (tester) async {
      final (game, tray) = await _open(tester);
      expect(tray.isEmpty, isTrue);

      game.putGrooveOnTray();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tray.length, 1);
      expect(tray.items.single.kind, AppMode.loop);
      expect(tray.items.single.document, isA<GrooveSpec>());
      expect(find.byType(TrayPanel), findsOneWidget, reason: 'it opened');
    });

    testWidgets('an item put on it elsewhere is here — that is the point',
        (tester) async {
      // The cross-editor promise, from this side: the service is shared, so a
      // sample put on in the Audio Editor is on the band in Loop Studio.
      final shared = TrayService();
      _put(shared, 'From the Audio Editor');
      final (_, _) = await _open(tester, tray: shared);

      await tester.tap(find.byKey(const Key('loop-tray-toggle')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('From the Audio Editor'), findsOneWidget);
    });

    testWidgets('TAPPING a chip applies it to the surface', (tester) async {
      final shared = TrayService()
        ..add(
          kind: AppMode.loop,
          label: 'Slow one',
          document: const GrooveSpec(enabled: {'bass'}, tempoBpm: 75),
        );
      final (game, _) = await _open(tester, tray: shared);
      expect(game.tempoBpm, isNot(75));

      await tester.tap(find.byKey(const Key('loop-tray-toggle')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Slow one'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(game.tempoBpm, 75);
    });

    testWidgets(
        'DRAGGING a chip onto the surface lands it — the thing WS-X2 could '
        'never do', (tester) async {
      // The payoff. The clipboard is the drag SOURCE the protocol never had,
      // and because the band is inline rather than an overlay the chip and the
      // drop target are in one tree — so this lands through the drop path that
      // already shipped, with nothing in it changed.
      final shared = TrayService()
        ..add(
          kind: AppMode.loop,
          label: 'Slow one',
          document: const GrooveSpec(enabled: {'bass'}, tempoBpm: 75),
        );
      final (game, _) = await _open(tester, tray: shared);
      await tester.tap(find.byKey(const Key('loop-tray-toggle')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.tempoBpm, isNot(75));

      final chip = find.text('Slow one');
      final gesture = await tester.startGesture(tester.getCenter(chip));
      await tester.pump();
      // Down onto the mixer surface below the band.
      await gesture.moveBy(const Offset(0, 320));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        game.tempoBpm,
        75,
        reason: 'the dragged groove landed on the surface',
      );
    });

    testWidgets('with NO shared clipboard the screen still works',
        (tester) async {
      // The registry mounts this screen bare. It keeps a private clipboard, the
      // same rule the undo history follows.
      await pumpGame(tester, const LoopMixerScreen());
      final game = _game(tester)..debugFreezeSeams();
      await tester.pump(const Duration(milliseconds: 50));

      game.putGrooveOnTray();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(TrayPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
