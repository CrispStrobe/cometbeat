// WS-W2 step 2 — the transport can DRIVE a surface, not only mirror it.
//
// ⚠️ Why this matters, and how the gap stayed invisible: the shared
// `TransportBar` calls `transport.togglePlay` directly, while every surface
// published its own state through `syncTo` and listened to nothing. So a bar
// hosted on any screen would have moved a readout and sounded NOTHING — and
// `transport_bar_test` would still have passed, because it asserts the bar
// drives the SERVICE, which it does. The missing half was on the other side.
//
// Position authority deliberately does NOT move: each surface's own clock stays
// the reference (that is what `syncTo` documents), so these tests are about
// play/stop reaching the surface, not about who counts the milliseconds.

import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/core/services/transport_service.dart';
import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/game_test_support.dart';

AdvancedTrackerTester _tracker(WidgetTester tester) =>
    tester.state<State<AdvancedTrackerScreen>>(
      find.byType(AdvancedTrackerScreen),
    ) as AdvancedTrackerTester;

DawTester _daw(WidgetTester tester) =>
    tester.state<State<DawScreen>>(find.byType(DawScreen)) as DawTester;

void main() {
  group('the Tracker', () {
    testWidgets('transport.play() starts it — the inert-button fix', (
      tester,
    ) async {
      final transport = TransportService();
      await pumpGame(
        tester,
        const AdvancedTrackerScreen(),
        extraProviders: [
          ChangeNotifierProvider<TransportService>.value(value: transport),
        ],
      );
      final game = _tracker(tester);
      game.setNote(0, 0, 60); // something to play
      await tester.pump();
      expect(game.isPlaying, isFalse);

      transport.play();
      await tester.pump();

      expect(game.isPlaying, isTrue, reason: 'the surface followed');
      transport.stop();
      await tester.pump();
    });

    testWidgets('transport.stop() stops it', (tester) async {
      final transport = TransportService();
      await pumpGame(
        tester,
        const AdvancedTrackerScreen(),
        extraProviders: [
          ChangeNotifierProvider<TransportService>.value(value: transport),
        ],
      );
      final game = _tracker(tester);
      game.setNote(0, 0, 60);
      game.togglePlay();
      await tester.pump();
      expect(game.isPlaying, isTrue);

      transport.stop();
      await tester.pump();
      expect(game.isPlaying, isFalse);
    });

    testWidgets('its own play still reaches the transport — both ways now', (
      tester,
    ) async {
      // The direction that already worked must keep working: the point is two
      // ways, not a swap.
      final transport = TransportService();
      await pumpGame(
        tester,
        const AdvancedTrackerScreen(),
        extraProviders: [
          ChangeNotifierProvider<TransportService>.value(value: transport),
        ],
      );
      final game = _tracker(tester);
      game.setNote(0, 0, 60);
      game.togglePlay();
      await tester.pump();

      expect(transport.isPlaying, isTrue);
      game.stop();
      await tester.pump();
      expect(transport.isPlaying, isFalse);
    });
  });

  testWidgets('⚠️ record-arm goes BOTH ways now', (tester) async {
    // I made it one-way in WS-T7: arming here told the transport, and arming
    // the transport told nobody — so a shared record button would light up and
    // record nothing, which is the inert-control shape one level down.
    final transport = TransportService();
    await pumpGame(
      tester,
      const AdvancedTrackerScreen(),
      extraProviders: [
        ChangeNotifierProvider<TransportService>.value(value: transport),
      ],
    );
    final game = _tracker(tester);
    expect(game.isRecording, isFalse);

    transport.setRecordArmed(true);
    await tester.pump();
    expect(game.isRecording, isTrue, reason: 'the surface armed');

    transport.setRecordArmed(false);
    await tester.pump();
    expect(game.isRecording, isFalse);
  });

  testWidgets('and the direction that already worked still does', (
    tester,
  ) async {
    final transport = TransportService();
    await pumpGame(
      tester,
      const AdvancedTrackerScreen(),
      extraProviders: [
        ChangeNotifierProvider<TransportService>.value(value: transport),
      ],
    );
    _tracker(tester).toggleRecord();
    await tester.pump();
    expect(transport.isRecordArmed, isTrue);
  });

  group('the Audio Editor', () {
    Future<(DawTester, TransportService)> open(WidgetTester tester) async {
      final transport = TransportService();
      await pumpGame(
        tester,
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TransportService>.value(value: transport),
            ChangeNotifierProvider(create: (_) => DawService()),
          ],
          child: const DawScreen(),
        ),
      );
      return (_daw(tester), transport);
    }

    testWidgets('transport.play() starts it', (tester) async {
      final (game, transport) = await open(tester);
      game.addDemoBeat();
      await tester.pump();
      expect(game.isPlaying, isFalse);

      transport.play();
      await tester.pump();
      expect(game.isPlaying, isTrue);

      transport.stop();
      await tester.pump();
      expect(game.isPlaying, isFalse);
    });

    testWidgets('no feedback loop — one press does not ping-pong', (
      tester,
    ) async {
      // Our play() tells the transport, which notifies us, which would tell it
      // again. The guard is what keeps that from recursing.
      final (game, transport) = await open(tester);
      game.addDemoBeat();
      await tester.pump();

      game.play();
      await tester.pump();
      expect(game.isPlaying, isTrue);
      expect(transport.isPlaying, isTrue);

      game.stop();
      await tester.pump();
      expect(game.isPlaying, isFalse);
      expect(transport.isPlaying, isFalse);
    });
  });

  testWidgets('a surface with no transport in scope is unaffected', (
    tester,
  ) async {
    // The common path: most of these screens' tests mount them bare.
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _tracker(tester);
    game.setNote(0, 0, 60);
    game.togglePlay();
    await tester.pump();
    expect(game.isPlaying, isTrue);
    game.stop();
    await tester.pump();
  });
}
