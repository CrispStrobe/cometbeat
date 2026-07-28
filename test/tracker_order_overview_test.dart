// WS-T2 — the song order at a glance, and draggable.
//
// The strip in the toolbar is a horizontal Wrap of chips with move-left /
// move-right buttons. At eight patterns that is fine. At sixty-four it is a
// wall you scroll sideways through, and moving a slot to the end is sixty
// presses because the buttons SWAP with a neighbour.
//
// So the tests are about the two things that actually change: that a drag is a
// remove-and-insert (the slots between shift, rather than one being displaced),
// and that the cursor keeps pointing at the slot the user was holding — which
// is the part that is easy to get subtly wrong and hard to notice.

import 'dart:async';

import 'package:comet_beat/core/services/beat_bridge.dart';
import 'package:comet_beat/core/services/melody_bridge.dart';
import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

AdvancedTrackerTester _game(WidgetTester tester) =>
    tester.state<State<AdvancedTrackerScreen>>(
      find.byType(AdvancedTrackerScreen),
    ) as AdvancedTrackerTester;

/// A song whose order is [0, 1, 2, 3] — four distinct slots, so a move is
/// visible in the list itself rather than inferred.
Future<AdvancedTrackerTester> _pump(WidgetTester tester) async {
  await pumpGame(tester, const AdvancedTrackerScreen());
  // Never pumpAndSettle on this screen: it runs a continuous ticker.
  await tester.pump();
  final game = _game(tester);
  for (var i = 0; i < 3; i++) {
    game.addPattern();
  }
  await tester.pump();
  for (var p = 1; p < 4; p++) {
    game.addToOrder(p);
  }
  await tester.pump();
  return game;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BeatBridge.instance.clear();
    MelodyBridge.instance.clear();
  });

  group('a drag is a move, not a swap', () {
    testWidgets('moving the first slot to the end shifts the rest along',
        (tester) async {
      // The move buttons SWAP with a neighbour, so the same operation there
      // would displace whichever slot was at the end. A drag must not.
      final game = await _pump(tester);
      final before = [...game.orderList];
      expect(before.length, greaterThanOrEqualTo(4));

      game.reorderOrderSlot(0, before.length - 1);
      await tester.pump();

      final after = game.orderList;
      expect(
        after.last,
        before.first,
        reason: 'the dragged slot went to the end',
      );
      expect(
        after.sublist(0, after.length - 1),
        before.sublist(1),
        reason: 'everything else kept its relative order',
      );
    });

    testWidgets('the song keeps exactly the same slots', (tester) async {
      // A reorder must never lose or duplicate a slot — a silent way to lose
      // part of an arrangement.
      final game = await _pump(tester);
      final before = [...game.orderList]..sort();
      game.reorderOrderSlot(1, 3);
      await tester.pump();
      final after = [...game.orderList]..sort();
      expect(after, before);
    });
  });

  group('the cursor follows the slot you dragged', () {
    testWidgets('it lands on the dragged slot, not on an index',
        (tester) async {
      // The easy bug: keep the cursor on the same NUMBER and it now points at
      // whatever slid into that position, so the next edit lands elsewhere.
      final game = await _pump(tester);
      final pattern = game.orderList.first;

      game.reorderOrderSlot(0, 2);
      await tester.pump();

      expect(game.orderCursor, 2);
      expect(game.orderList[game.orderCursor], pattern);
    });

    testWidgets('a slot dragged PAST the cursor shifts it back by one',
        (tester) async {
      // The cursor must keep pointing at the SAME SLOT, not the same index.
      // Dragging something from before it to after it means its slot has moved
      // one place earlier.
      final game = await _pump(tester);
      game.setOrderCursor(2);
      await tester.pump();
      final held = game.orderList[2];

      game.reorderOrderSlot(0, 3); // crosses index 2
      await tester.pump();

      expect(game.orderCursor, 1, reason: 'the held slot slid one earlier');
      expect(game.orderList[game.orderCursor], held);
    });

    testWidgets('a slot dragged from after to before shifts it forward',
        (tester) async {
      // The mirror case, and the one an off-by-one usually gets wrong.
      final game = await _pump(tester);
      game.setOrderCursor(1);
      await tester.pump();
      final held = game.orderList[1];

      game.reorderOrderSlot(3, 0); // crosses index 1 the other way
      await tester.pump();

      expect(game.orderCursor, 2);
      expect(game.orderList[game.orderCursor], held);
    });
  });

  group('guards', () {
    testWidgets('out-of-range indices do nothing', (tester) async {
      final game = await _pump(tester);
      final before = [...game.orderList];
      game.reorderOrderSlot(-1, 2);
      game.reorderOrderSlot(0, 99);
      game.reorderOrderSlot(99, 0);
      await tester.pump();
      expect(game.orderList, before);
    });

    testWidgets('moving a slot onto itself changes nothing', (tester) async {
      final game = await _pump(tester);
      final before = [...game.orderList];
      game.reorderOrderSlot(1, 1);
      await tester.pump();
      expect(game.orderList, before);
    });
  });

  group('the overview is reachable and shows the song', () {
    testWidgets('it lists every slot', (tester) async {
      final game = await _pump(tester);
      final slots = game.orderLength;

      unawaited(game.openOrderOverview());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('$slots slots'), findsOneWidget);
      // Every slot has a row, keyed by its position.
      for (var i = 0; i < slots; i++) {
        expect(
          find.byKey(ValueKey('order-slot-$i')),
          findsOneWidget,
          reason: 'slot $i should be listed',
        );
      }
    });
  });
}
