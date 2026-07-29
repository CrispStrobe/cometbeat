// WS-X2 — Loop Studio as a drop target.
//
// The protocol shipped with one consumer (the Audio Editor's timeline) and the
// card left the other three "adoptable by whoever owns the file". This is Loop
// Studio's, and the interesting half is a trap the protocol hides:
//
//   `AppMode.loop` carries TWO different document shapes. Loop Studio's own
//   `addToProject` stores a whole `GrooveSpec`; `ProjectBridge` converting
//   something INTO loop produces a `List<PatternCell>` — one melodic line. And
//   a same-kind drop never consults the bridge, so `dropDecisionFor` answers
//   *exact* for both. A handler keyed on `payload.kind` would therefore hand a
//   cell list to `applySpec` and lose it silently, with the drag-over hint
//   cheerfully reading "Moves here unchanged".
//
// So most of what follows pins the two shapes landing in the two right places,
// and the lossy path asking first.

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/interop/drag_payload.dart';
import 'package:comet_beat/core/services/undo_service.dart';
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

LoopMixerTester _game(WidgetTester tester) =>
    tester.state<State<LoopMixerScreen>>(find.byType(LoopMixerScreen))
        as LoopMixerTester;

/// Mounts Loop Studio with a draggable payload sitting above it, so a drag can
/// actually be performed rather than simulated by calling the handler.
Future<LoopMixerTester> _open(
  WidgetTester tester,
  MusicDragPayload payload, {
  UndoService? undo,
}) async {
  final screen = undo == null
      ? const LoopMixerScreen()
      : ChangeNotifierProvider<UndoService>.value(
          value: undo,
          child: const LoopMixerScreen(),
        );
  await pumpGame(
    tester,
    Column(
      children: [
        Draggable<MusicDragPayload>(
          data: payload,
          feedback: const SizedBox(width: 40, height: 20),
          child: const SizedBox(
            key: Key('drag-source'),
            width: 40,
            height: 20,
            child: ColoredBox(color: Color(0xFF000000)),
          ),
        ),
        Expanded(child: screen),
      ],
    ),
  );
  final game = _game(tester)..debugFreezeSeams();
  await tester.pump(const Duration(milliseconds: 50));
  return game;
}

/// Drags the source onto the middle of the Loop Studio surface and releases.
Future<void> _dragOnto(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(const Key('drag-source'))),
  );
  await tester.pump();
  await gesture.moveTo(tester.getCenter(find.byType(LoopMixerScreen)));
  // Two pumps: the first delivers the move, the second lets the target rebuild
  // with the hint before anything is released.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the two shapes that both travel as AppMode.loop', () {
    testWidgets('a GrooveSpec replaces the band', (tester) async {
      final game = await _open(
        tester,
        const MusicDragPayload(
          kind: AppMode.loop,
          document: GrooveSpec(enabled: {'bass'}, tempoBpm: 75),
        ),
      );
      expect(game.tempoBpm, isNot(75));

      await _dragOnto(tester);
      expect(game.tempoBpm, 75);
      expect(game.enabledTracks, {'bass'});
    });

    testWidgets('a cell list becomes the USER track, not the whole groove',
        (tester) async {
      // The trap. Keyed on `kind` this would reach `applySpec`, which does not
      // know what a cell list is — and the drop would appear to succeed.
      final before = await _open(
        tester,
        const MusicDragPayload(
          kind: AppMode.loop,
          document: [
            PatternCell(midis: [60], steps: 4),
            PatternCell(midis: [64], steps: 4),
          ],
        ),
      );
      final band = before.enabledTracks.toSet();

      await _dragOnto(tester);

      expect(
        before.enabledTracks,
        containsAll(band),
        reason: 'one dropped line must not wipe the band',
      );
      expect(
        before.enabledTracks,
        contains(LoopEngine.userTrackId),
        reason: 'it lands in the slot that means "a melody you brought in" — '
            'and ENABLED, or the drop is silent and looks like it failed',
      );
    });

    testWidgets('a melody longer than two bars ASKS before trimming',
        (tester) async {
      // A loss the bridge's report cannot know about, because it happens after
      // the conversion: this surface plays a two-bar grid. Landing the head and
      // silently dropping the tail would be precisely the lossy-drop-that-did-
      // not-ask that the protocol exists to prevent.
      final game = await _open(
        tester,
        MusicDragPayload(
          kind: AppMode.loop,
          document: [
            for (var i = 0; i < 24; i++) PatternCell(midis: [60 + i], steps: 2),
          ],
        ),
      );
      final tempo = game.tempoBpm;

      await _dragOnto(tester);
      expect(find.text('This conversion loses something'), findsOneWidget);
      expect(
        find.textContaining('trimmed'),
        findsOneWidget,
        reason: 'the dialog has to SAY what is lost — an empty one is a lie',
      );

      // Declining leaves the groove exactly as it was.
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.enabledTracks, isNot(contains(LoopEngine.userTrackId)));
      expect(game.tempoBpm, tempo);
    });

    testWidgets('and accepting the trim lands a melody that actually renders',
        (tester) async {
      // The bug this whole path had: `MelodicPattern.render` ASSERTS that the
      // cells fill the two-bar grid exactly. Every existing caller feeds it
      // cells recorded against the grid, so nothing had ever handed it a
      // foreign melody — and the first one crashed the render.
      final game = await _open(
        tester,
        MusicDragPayload(
          kind: AppMode.loop,
          document: [
            for (var i = 0; i < 24; i++) PatternCell(midis: [60 + i], steps: 2),
          ],
        ),
      );

      await _dragOnto(tester);
      await tester.tap(find.text('Drop anyway'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(game.enabledTracks, contains(LoopEngine.userTrackId));
      expect(tester.takeException(), isNull, reason: 'it must RENDER');
    });

    testWidgets('a short melody is tiled to fill the grid, not left ragged',
        (tester) async {
      final game = await _open(
        tester,
        const MusicDragPayload(
          kind: AppMode.loop,
          document: [
            PatternCell(midis: [60], steps: 4),
            PatternCell(midis: [64], steps: 4),
          ],
        ),
      );

      await _dragOnto(tester);
      // Short enough to need no trim, so no dialog — it just lands.
      expect(find.text('This conversion loses something'), findsNothing);
      expect(game.enabledTracks, contains(LoopEngine.userTrackId));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty cell list changes nothing rather than clearing',
        (tester) async {
      // `ProjectBridge` really does return `const <PatternCell>[]` for a song
      // with no channels, so this arrives in practice, not just in theory.
      final game = await _open(
        tester,
        const MusicDragPayload(kind: AppMode.loop, document: <PatternCell>[]),
      );
      final band = game.enabledTracks.toSet();
      final tempo = game.tempoBpm;

      await _dragOnto(tester);

      expect(game.enabledTracks, band);
      expect(game.tempoBpm, tempo);
      expect(game.enabledTracks, isNot(contains(LoopEngine.userTrackId)));
    });
  });

  group('what the surface says while the finger is down', () {
    testWidgets('a same-kind drag reads as unchanged', (tester) async {
      await _open(
        tester,
        const MusicDragPayload(
          kind: AppMode.loop,
          document: GrooveSpec(enabled: {'bass'}),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('drag-source'))),
      );
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.byType(LoopMixerScreen)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Moves here unchanged'), findsOneWidget);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('and nothing is shown when nothing is being dragged',
        (tester) async {
      await _open(
        tester,
        const MusicDragPayload(
          kind: AppMode.loop,
          document: GrooveSpec(enabled: {'bass'}),
        ),
      );
      expect(find.text('Moves here unchanged'), findsNothing);
    });
  });

  group('a drop is an edit like any other', () {
    testWidgets('it is undoable — which is what makes replacing acceptable',
        (tester) async {
      // A drop that replaced the groove irreversibly would be a bad trade. It
      // goes through the ordinary edit path, so the shared history holds it.
      final shared = UndoService();
      final game = await _open(
        tester,
        const MusicDragPayload(
          kind: AppMode.loop,
          document: GrooveSpec(enabled: {'bass'}, tempoBpm: 75),
        ),
        undo: shared,
      );
      final tempo = game.tempoBpm;

      await _dragOnto(tester);
      expect(game.tempoBpm, 75);
      expect(shared.canUndoScope(kLoopUndoScope), isTrue);

      game.undo();
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.tempoBpm, tempo, reason: 'the drop was taken back');
    });
  });

  group('the decision itself', () {
    // Cheap to assert directly, and it documents what this surface answers to
    // each of the other modes without pumping four screens.
    test('Loop Studio is NOT a container — it converts rather than holds', () {
      // The timeline holds foreign clips as they are; this surface is one
      // groove played by a band, so a foreign kind must become groove material.
      final decision = dropDecisionFor(
        const MusicDragPayload(
          kind: AppMode.score,
          document: <PatternCell>[],
        ),
        AppMode.loop,
      );
      expect(
        decision.outcome,
        isNot(DropOutcome.exact),
        reason: 'a score is not held here unchanged',
      );
    });

    test('a same-kind drop never consults the bridge — either shape', () {
      for (final document in <Object>[
        const GrooveSpec(enabled: {'bass'}),
        const <PatternCell>[
          PatternCell(midis: [60], steps: 4),
        ],
      ]) {
        final decision = dropDecisionFor(
          MusicDragPayload(kind: AppMode.loop, document: document),
          AppMode.loop,
        );
        expect(decision.outcome, DropOutcome.exact);
        expect(
          identical(decision.document, document),
          isTrue,
          reason: 'handed back by identity — a round trip would add loss',
        );
      }
    });
  });
}
