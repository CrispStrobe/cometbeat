// WS-W4's last clause — "and the label says what it was".
//
// Both fold-ins produced good labels and neither could be READ: the Audio
// Editor got them from its coalesce token ("Move clip"), Loop Studio derives
// them by diffing groove snapshots ("Tempo 100 → 140"), and `UndoService`
// exposed `history` and `nextUndoLabel` to nobody. An output with no reader is
// this ladder's recurring defect one level up from the usual one, and harder to
// spot because every test passes and the data is genuinely correct.
//
// So these tests are about what the list SAYS and what a tap DOES — including
// the part that is easy to get wrong and impossible to see: a tap reverts
// several edits at once, in one ordered list, across surfaces.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/core/services/undo_service.dart';
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:comet_beat/shared/undo/undo_history_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/game_test_support.dart';

/// Records what it did, so a revert can be checked by its EFFECT rather than by
/// the history's own bookkeeping.
UndoEntry _entry(List<String> log, String label, {String? scope}) => UndoEntry(
      label: label,
      scope: scope,
      undo: () => log.add('undo:$label'),
      redo: () => log.add('redo:$label'),
    );

Future<void> _pump(WidgetTester tester, UndoService history) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: UndoHistorySheetBody(history: history))),
  );
  await tester.pump();
}

void main() {
  group('the list says what you did', () {
    testWidgets('every entry shows its own label', (tester) async {
      final log = <String>[];
      final history = UndoService()
        ..push(_entry(log, 'Move clip'))
        ..push(_entry(log, 'Tempo 100 → 140'));
      await _pump(tester, history);

      expect(find.text('Move clip'), findsOneWidget);
      expect(find.text('Tempo 100 → 140'), findsOneWidget);
    });

    testWidgets('and which surface it came from, by its human name',
        (tester) async {
      // Registered by each surface rather than baked into the sheet, so a row
      // reads "Loop Studio" and not "loop".
      registerUndoScopeName('loop', 'Loop Studio');
      final log = <String>[];
      final history = UndoService()..push(_entry(log, 'Tempo', scope: 'loop'));
      await _pump(tester, history);

      expect(find.text('Loop Studio'), findsOneWidget);
    });

    testWidgets('an unregistered scope falls back to its id, never to nothing',
        (tester) async {
      // Ugly but never wrong — the failure mode to avoid is a row that cannot
      // say where it came from at all.
      final log = <String>[];
      final history = UndoService()
        ..push(_entry(log, 'Something', scope: 'not-registered'));
      await _pump(tester, history);

      expect(find.text('not-registered'), findsOneWidget);
    });

    testWidgets('a scopeless entry reads as project-wide', (tester) async {
      final log = <String>[];
      final history = UndoService()..push(_entry(log, 'Rename project'));
      await _pump(tester, history);
      expect(find.text('Project'), findsOneWidget);
    });

    testWidgets('newest first — the thing you want back is not at the bottom',
        (tester) async {
      final log = <String>[];
      final history = UndoService()
        ..push(_entry(log, 'First'))
        ..push(_entry(log, 'Second'));
      await _pump(tester, history);

      final first = tester.getTopLeft(find.text('First')).dy;
      final second = tester.getTopLeft(find.text('Second')).dy;
      expect(second, lessThan(first));
    });

    testWidgets('an empty history says so rather than showing a blank sheet',
        (tester) async {
      await _pump(tester, UndoService());
      expect(find.text('Nothing has been edited yet.'), findsOneWidget);
    });
  });

  group('a tap reverts to that point', () {
    testWidgets('tapping the newest entry undoes exactly one edit',
        (tester) async {
      final log = <String>[];
      final history = UndoService()
        ..push(_entry(log, 'First'))
        ..push(_entry(log, 'Second'));
      await _pump(tester, history);

      await tester.tap(find.text('Second'));
      await tester.pump();
      expect(log, ['undo:Second']);
    });

    testWidgets(
        'tapping an older entry undoes it AND everything after it, '
        'newest first', (tester) async {
      // The order matters and is not arbitrary: an entry's undo closure was
      // captured assuming everything after it is already undone. Running them
      // out of order restores into a state they were never captured against.
      final log = <String>[];
      final history = UndoService()
        ..push(_entry(log, 'First'))
        ..push(_entry(log, 'Second'))
        ..push(_entry(log, 'Third'));
      await _pump(tester, history);

      await tester.tap(find.text('First'));
      await tester.pump();
      expect(log, ['undo:Third', 'undo:Second', 'undo:First']);
    });

    testWidgets('the row says how many edits its tap will take back',
        (tester) async {
      // The honest half of making the rows tappable: reverting several edits at
      // once is the useful behaviour AND the surprising one, so the count is on
      // screen before the tap rather than explained afterwards.
      final log = <String>[];
      final history = UndoService()
        ..push(_entry(log, 'First'))
        ..push(_entry(log, 'Second'))
        ..push(_entry(log, 'Third'));
      await _pump(tester, history);

      expect(find.text('Undo'), findsOneWidget, reason: 'the newest is one');
      expect(find.text('Undo 2'), findsOneWidget);
      expect(find.text('Undo 3'), findsOneWidget);
    });

    testWidgets('reverting crosses surfaces, because one list has one order',
        (tester) async {
      // Unavoidable rather than chosen: you cannot undo entry 1 without first
      // undoing 2 and 3. It is safe because redo puts it all back, which the
      // next test pins.
      final log = <String>[];
      final history = UndoService()
        ..push(_entry(log, 'Rename track', scope: 'audio'))
        ..push(_entry(log, 'Tempo', scope: 'loop'));
      await _pump(tester, history);

      await tester.tap(find.text('Rename track'));
      await tester.pump();
      expect(log, ['undo:Tempo', 'undo:Rename track']);
    });

    testWidgets('the list shrinks as it is reverted, live', (tester) async {
      // The sheet rebuilds from the service rather than from a snapshot taken
      // when it opened — otherwise a second tap would act on a stale row.
      final log = <String>[];
      final history = UndoService()
        ..push(_entry(log, 'First'))
        ..push(_entry(log, 'Second'));
      await _pump(tester, history);

      await tester.tap(find.text('Second'));
      await tester.pump();
      expect(find.text('Second'), findsNothing);
      expect(find.text('First'), findsOneWidget);
    });
  });

  group('redo', () {
    testWidgets('is labelled with what it would put back', (tester) async {
      // "Redo" alone makes you press it to find out what it does — which is the
      // exact complaint this card exists to fix, in the other direction.
      final log = <String>[];
      final history = UndoService()..push(_entry(log, 'Move clip'));
      await _pump(tester, history);
      expect(find.byKey(const Key('undo-history-redo')), findsNothing);

      await tester.tap(find.text('Move clip'));
      await tester.pump();
      expect(find.text('Redo Move clip'), findsOneWidget);
    });

    testWidgets('puts back what a multi-step revert took, one step at a time',
        (tester) async {
      final log = <String>[];
      final history = UndoService()
        ..push(_entry(log, 'First'))
        ..push(_entry(log, 'Second'));
      await _pump(tester, history);

      await tester.tap(find.text('First'));
      await tester.pump();
      log.clear();

      await tester.tap(find.byKey(const Key('undo-history-redo')));
      await tester.pump();
      expect(log, ['redo:First']);
      expect(find.text('Redo Second'), findsOneWidget);
    });
  });

  group('the hosts actually open it', () {
    // The failure this whole card is about is a thing that exists and is never
    // reached. A sheet nobody can open would be the same defect wearing the
    // fix's clothes, and no test of the widget alone would catch it — so both
    // hosts are driven through their real UI, not by calling the function.

    testWidgets('Loop Studio, from its overflow menu', (tester) async {
      final shared = UndoService();
      await pumpGame(
        tester,
        ChangeNotifierProvider<UndoService>.value(
          value: shared,
          child: const LoopMixerScreen(),
        ),
      );
      final game = tester.state<State<LoopMixerScreen>>(
        find.byType(LoopMixerScreen),
      ) as LoopMixerTester;
      game.debugFreezeSeams();
      game.setTempo(140);
      await tester.pump(const Duration(milliseconds: 50));

      // Explicit pumps, not `pumpAndSettle`: this screen runs a loop clock, so
      // it never reaches a quiescent frame and settling times out.
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Edit history').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Tempo 100 → 140'), findsOneWidget);
      expect(
        find.text('Loop Studio'),
        findsOneWidget,
        reason: 'the surface registered its own name on mount',
      );
    });

    testWidgets('the Audio Editor, from its toolbar', (tester) async {
      final shared = UndoService();
      final daw = DawService(history: shared);
      await pumpGame(
        tester,
        const DawScreen(),
        extraProviders: [ChangeNotifierProvider<DawService>.value(value: daw)],
      );
      daw
        ..addClip(SampleSource(Float64List(4410)))
        ..renameTrack(0, 'Vocals');
      await tester.pumpAndSettle();

      // Wide or narrow, the action is either an icon or a menu row — this list
      // is width-aware by design, so the test drives whichever is showing.
      final icon = find.byIcon(Icons.history);
      if (icon.evaluate().isEmpty) {
        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byIcon(Icons.history).first);
      await tester.pumpAndSettle();

      expect(find.text('Audio Editor'), findsWidgets);
    });
  });

  testWidgets('an entry arriving while the sheet is open shows up',
      (tester) async {
    // The shared history's whole point: another surface is editing too.
    final log = <String>[];
    final history = UndoService();
    await _pump(tester, history);
    expect(find.text('Nothing has been edited yet.'), findsOneWidget);

    history.push(_entry(log, 'Move clip', scope: 'audio'));
    await tester.pump();
    expect(find.text('Move clip'), findsOneWidget);
  });

  testWidgets('a surface closing removes its rows from an open sheet',
      (tester) async {
    // `clearScope` runs when a screen is disposed, because its closures capture
    // state that is going away. A sheet holding a stale snapshot would offer a
    // tap that reverts into nothing.
    final log = <String>[];
    final history = UndoService()
      ..push(_entry(log, 'Move clip', scope: 'audio'))
      ..push(_entry(log, 'Tempo', scope: 'loop'));
    await _pump(tester, history);

    history.clearScope('loop');
    await tester.pump();
    expect(find.text('Tempo'), findsNothing);
    expect(find.text('Move clip'), findsOneWidget);
  });
}
