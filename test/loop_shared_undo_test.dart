// WS-W4 for Loop Studio — the second surface the shared history needed.
//
// The service shipped with one consumer, so its central promise ("an edit in
// Loop Studio is undoable from the Audio Editor's history") could not be tested
// at all: with a single surface there is nothing to be shared WITH. @daw-suite
// said as much when they claimed the DAW half — the acceptance "needs a second
// surface. I will say so rather than tick it." This is that surface, so most of
// what follows is about the interaction between two of them, which is where
// every remaining sharp edge lives:
//
//   * an edit made HERE must be reversible from THERE (the acceptance);
//   * pressing Undo HERE must not silently rewind an edit made THERE;
//   * and REDO must respect the same boundary — the service shipped
//     `undoScope` with only a global `redo()`, an asymmetry that could not bite
//     while one surface used it and bites immediately once two do.
//
// Plus the trap a game screen has and a long-lived editor does not: its undo
// closures capture the State, and it gets popped.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/audio/groove_change_label.dart';
import 'package:comet_beat/core/audio/loop_automation.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/services/daw_service.dart';
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

/// Mounts the screen with a shared history in scope.
Future<(LoopMixerTester, UndoService)> _open(
  WidgetTester tester, {
  UndoService? undo,
}) async {
  final service = undo ?? UndoService();
  await pumpGame(
    tester,
    ChangeNotifierProvider<UndoService>.value(
      value: service,
      child: const LoopMixerScreen(),
    ),
  );
  final game = _game(tester)..debugFreezeSeams();
  await tester.pump(const Duration(milliseconds: 50));
  return (game, service);
}

/// An entry from some other surface, so scope boundaries have something to
/// cross. It records into [log] rather than touching real state.
UndoEntry _foreignEdit(List<String> log, {String label = 'Move clip'}) =>
    UndoEntry(
      label: label,
      scope: 'daw',
      undo: () => log.add('undo:$label'),
      redo: () => log.add('redo:$label'),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the label says what you did', () {
    // Derived by diffing the two snapshots, so no edit site has to remember to
    // set one. These pin the derivation, not the wording of any single row.
    const base = GrooveSpec(enabled: {'drums', 'bass'});

    test('tempo carries both numbers', () {
      expect(
        describeGrooveChange(
          base,
          const GrooveSpec(enabled: {'drums', 'bass'}, tempoBpm: 140),
        ),
        'Tempo 100 → 140',
      );
    });

    test('turning a track on or off names the track', () {
      const off = GrooveSpec(enabled: {'drums'});
      expect(describeGrooveChange(base, off), 'Turn off bass');
      expect(describeGrooveChange(off, base), 'Turn on bass');
    });

    test('a per-track setting names the track it was made on', () {
      const louder = GrooveSpec(
        enabled: {'drums', 'bass'},
        levels: {'bass': 0.5},
      );
      expect(describeGrooveChange(base, louder), 'Level: bass');
    });

    test('a bulk change of the same setting names no single track', () {
      // Naming one of several would be actively misleading.
      const many = GrooveSpec(
        enabled: {'drums', 'bass'},
        levels: {'bass': 0.5, 'drums': 0.5},
      );
      expect(describeGrooveChange(base, many), 'Level');
    });

    test('adding a track beats the fact that it also turned one on', () {
      // One gesture moves several keys; the structural one is what the player
      // thinks they did.
      const added = GrooveSpec(
        enabled: {'drums', 'bass', 't1'},
        extraTracks: {'t1': 'bass'},
      );
      expect(describeGrooveChange(base, added), 'Add track');
      expect(describeGrooveChange(added, base), 'Remove track');
    });

    test('automation lanes are recognised through their nesting', () {
      final lane = AutomationLane(List<double>.filled(16, 0.5));
      final automated = GrooveSpec(
        enabled: const {'drums', 'bass'},
        automation: {
          'bass': {AutomationParam.level: lane},
        },
      );
      expect(describeGrooveChange(base, automated), 'Automation');
    });

    test('an unrecognised change falls back rather than lying', () {
      // A new GrooveSpec field arrives as a json key nothing below names. That
      // must read as a missing label, never as a wrong one — which is why the
      // fallback exists at all.
      expect(describeGrooveChange(base, base), kGenericGrooveEditLabel);
    });

    test('the whole-groove settings are distinguishable from each other', () {
      const kit = GrooveSpec(enabled: {'drums', 'bass'}, kitId: 'acoustic');
      const key = GrooveSpec(enabled: {'drums', 'bass'}, key: 5);
      const scale = GrooveSpec(
        enabled: {'drums', 'bass'},
        scale: GrooveScale.minorPentatonic,
      );
      expect(describeGrooveChange(base, kit), 'Drum kit');
      expect(describeGrooveChange(base, key), 'Key');
      expect(describeGrooveChange(base, scale), 'Scale');
    });
  });

  group('redo respects the scope boundary too', () {
    test('redoScope replays THIS scope, not whatever is on top', () {
      final undo = UndoService();
      final log = <String>[];
      final mine = <String>[];
      undo
        ..push(
          UndoEntry(
            label: 'Mine',
            scope: 'loop',
            undo: () => mine.add('undo'),
            redo: () => mine.add('redo'),
          ),
        )
        ..push(_foreignEdit(log));

      // Both surfaces undo their own edit; the foreign one lands on top of the
      // redo branch. A global redo would now replay the DAW's.
      expect(undo.undoScope('daw'), isTrue);
      expect(undo.undoScope('loop'), isTrue);

      expect(undo.canRedoScope('loop'), isTrue);
      expect(undo.redoScope('loop'), isTrue);
      expect(mine, ['undo', 'redo']);
      expect(log, ['undo:Move clip'], reason: 'the DAW entry stays undone');
    });

    test('redoScope reports when there is nothing of that scope to redo', () {
      final undo = UndoService()..push(_foreignEdit(<String>[]));
      undo.undoScope('daw');
      expect(undo.canRedoScope('loop'), isFalse);
      expect(undo.redoScope('loop'), isFalse);
      expect(undo.canRedoScope('daw'), isTrue);
    });
  });

  group('an edit here is an edit in the shared history', () {
    testWidgets('it arrives labelled and scoped', (tester) async {
      final (game, undo) = await _open(tester);
      expect(undo.history, isEmpty);

      game.setTempo(140);
      await tester.pump(const Duration(milliseconds: 50));

      expect(undo.history, hasLength(1));
      expect(undo.history.single.scope, kLoopUndoScope);
      expect(undo.history.single.label, 'Tempo 100 → 140');
    });

    testWidgets('undoing it from ANOTHER surface reverts the groove here',
        (tester) async {
      // The card's acceptance, and the thing a single-surface service could not
      // demonstrate: `undo()` here stands in for Cmd-Z pressed in the Audio
      // Editor — nothing calls back into this screen except the entry's own
      // closure.
      final (game, undo) = await _open(tester);
      game.setTempo(140);
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.tempoBpm, 140);

      undo.undo();
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.tempoBpm, 100);

      undo.redo();
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.tempoBpm, 140);
    });

    testWidgets('the two surfaces interleave in ONE ordered history',
        (tester) async {
      final (game, undo) = await _open(tester);
      final log = <String>[];
      game.setTempo(120);
      await tester.pump(const Duration(milliseconds: 50));
      undo.push(_foreignEdit(log));
      game.setKey(5);
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        undo.history.map((e) => e.scope).toList(),
        [kLoopUndoScope, 'daw', kLoopUndoScope],
        reason: 'one list, in the order the edits happened',
      );
    });
  });

  group('but Undo here is not Undo everywhere', () {
    testWidgets("this screen's button leaves another surface's edit alone",
        (tester) async {
      final (game, undo) = await _open(tester);
      final log = <String>[];
      game.setTempo(140);
      await tester.pump(const Duration(milliseconds: 50));
      // The other surface edits LAST, so a global undo would take theirs.
      undo.push(_foreignEdit(log));

      game.undo();
      await tester.pump(const Duration(milliseconds: 50));

      expect(log, isEmpty, reason: 'their edit must not be rewound by us');
      expect(game.tempoBpm, 100, reason: 'ours is the one that went back');
    });

    testWidgets("and its Redo does not replay another surface's edit",
        (tester) async {
      final (game, undo) = await _open(tester);
      final log = <String>[];
      game.setTempo(140);
      await tester.pump(const Duration(milliseconds: 50));
      undo.push(_foreignEdit(log));
      undo.undoScope('daw');
      game.undo();
      await tester.pump(const Duration(milliseconds: 50));

      game.redo();
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.tempoBpm, 140);
      expect(
        log,
        ['undo:Move clip'],
        reason: 'their entry stayed undone — no stray redo',
      );
    });

    testWidgets(
        'the buttons enable on OUR scope, not on anyone else having '
        'something to undo', (tester) async {
      final (game, undo) = await _open(tester);
      undo.push(_foreignEdit(<String>[]));
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        game.canUndo,
        isFalse,
        reason: 'a DAW edit must not light up Loop Studio’s Undo',
      );

      game.setTempo(140);
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.canUndo, isTrue);
    });
  });

  group('leaving the screen', () {
    testWidgets('drops its entries, because their closures are going away',
        (tester) async {
      // Every entry closes over this State. The service outlives the screen, so
      // an undo pressed elsewhere afterwards would restore into a dead screen.
      final (game, undo) = await _open(tester);
      game.setTempo(140);
      await tester.pump(const Duration(milliseconds: 50));
      expect(undo.canUndoScope(kLoopUndoScope), isTrue);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(milliseconds: 50));

      expect(undo.canUndoScope(kLoopUndoScope), isFalse);
      expect(undo.history, isEmpty);
    });

    testWidgets("leaves OTHER surfaces' entries exactly where they were",
        (tester) async {
      final (game, undo) = await _open(tester);
      final log = <String>[];
      undo.push(_foreignEdit(log));
      game.setTempo(140);
      await tester.pump(const Duration(milliseconds: 50));

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(milliseconds: 50));

      expect(undo.history.map((e) => e.scope), ['daw']);
      undo.undo();
      expect(log, ['undo:Move clip'], reason: 'still perfectly usable');
    });
  });

  group('the acceptance, with the REAL Audio Editor on the other end', () {
    // Everything above pairs this screen against a hand-made `'daw'`-scoped
    // entry, because when it was written the DAW's own fold-in was still in
    // flight. It has since landed (`cc099d96`), so the card's acceptance can
    // stop being approximated: a real `DawService` and the real Loop Studio,
    // sharing one history. Both halves' authors declined to tick the card
    // because neither could demonstrate this alone. These are the tests that
    // do, and they are worth more than either surface's own — a scope boundary
    // is only real once something is on the other side of it.

    testWidgets('an edit in Loop Studio is undoable from the Audio Editor',
        (tester) async {
      final shared = UndoService();
      final daw = DawService(history: shared);
      final (game, _) = await _open(tester, undo: shared);

      game.setTempo(140);
      await tester.pump(const Duration(milliseconds: 50));

      // The Audio Editor can SEE it — the visible half of the feature.
      expect(shared.history.map((e) => e.label), ['Tempo 100 → 140']);
      // And a plain Cmd-Z, which takes the most recent edit in ANY surface,
      // reverses it without knowing what Loop Studio is.
      shared.undo();
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.tempoBpm, 100);

      // The Audio Editor's OWN button, however, must not have offered to:
      // that edit was never its to undo.
      expect(daw.canUndo, isFalse);
    });

    testWidgets('and neither surface can rewind the other with its own button',
        (tester) async {
      final shared = UndoService();
      final daw = DawService(history: shared)
        ..addClip(SampleSource(Float64List(4410)));
      final (game, _) = await _open(tester, undo: shared);

      daw.renameTrack(0, 'Vocals');
      game.setTempo(140);
      await tester.pump(const Duration(milliseconds: 50));

      // Loop's edit is the most recent, so a GLOBAL undo would take it.
      daw.undo();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        game.tempoBpm,
        140,
        reason: "the Audio Editor's undo must not reach into Loop Studio",
      );
      expect(daw.trackName(0), isNot('Vocals'));

      game.undo();
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.tempoBpm, 100);
    });

    testWidgets('nor replay it — the redo branch respects the boundary too',
        (tester) async {
      // The asymmetry both fold-ins independently hit: with only a global
      // redo(), this sequence replays the OTHER surface's edit.
      final shared = UndoService();
      final daw = DawService(history: shared)
        ..addClip(SampleSource(Float64List(4410)));
      final (game, _) = await _open(tester, undo: shared);

      game.setTempo(140);
      await tester.pump(const Duration(milliseconds: 50));
      daw.renameTrack(0, 'Vocals');
      daw.undo();
      game.undo();
      await tester.pump(const Duration(milliseconds: 50));

      game.redo();
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.tempoBpm, 140);
      expect(
        daw.trackName(0),
        isNot('Vocals'),
        reason: "Loop's redo must not resurrect the Audio Editor's rename",
      );
    });

    testWidgets('leaving Loop Studio leaves the Audio Editor fully usable',
        (tester) async {
      // The trap on this side only: Loop's entries close over a State that is
      // about to die, while the DAW's service outlives everything.
      final shared = UndoService();
      final daw = DawService(history: shared)
        ..addClip(SampleSource(Float64List(4410)));
      final (game, _) = await _open(tester, undo: shared);

      daw.renameTrack(0, 'Vocals');
      game.setTempo(140);
      await tester.pump(const Duration(milliseconds: 50));

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(milliseconds: 50));

      expect(shared.canUndoScope(kLoopUndoScope), isFalse);
      expect(daw.canUndo, isTrue);
      daw.undo();
      expect(daw.trackName(0), isNot('Vocals'));
      expect(tester.takeException(), isNull);
    });
  });

  group('with no shared history in scope', () {
    testWidgets('undo still works, because it always has', (tester) async {
      // The registry and most of this screen's own tests mount it with no
      // providers at all, and undo has worked there since it shipped. Recording
      // only when a service is present would have deleted a working feature for
      // every player who never opens a project.
      await pumpGame(tester, const LoopMixerScreen());
      final game = _game(tester)..debugFreezeSeams();
      await tester.pump(const Duration(milliseconds: 50));

      expect(game.canUndo, isFalse);
      game.setTempo(140);
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.canUndo, isTrue);

      game.undo();
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.tempoBpm, 100);

      game.redo();
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.tempoBpm, 140);
    });

    testWidgets('and leaving disposes it without complaint', (tester) async {
      await pumpGame(tester, const LoopMixerScreen());
      final game = _game(tester)..debugFreezeSeams();
      game.setTempo(140);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    });
  });
}
