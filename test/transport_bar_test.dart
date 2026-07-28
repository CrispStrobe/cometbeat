// WS-W3 — the shared transport bar.
//
// The card's acceptance: mount it ONCE and assert the controls drive
// TransportService. That is the whole contract — the bar owns no state, so
// "does the button call the service" and "does the service's state reach the
// screen" is everything there is to prove.

import 'package:comet_beat/core/audio/daw_tempo_map.dart';
import 'package:comet_beat/core/services/transport_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/transport_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
  TransportService transport, {
  VoidCallback? onUndo,
  VoidCallback? onRedo,
  bool canUndo = false,
  bool canRedo = false,
  bool showRecord = true,
  List<Widget> trailing = const [],
  double width = 1000,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        width: width,
        child: TransportBar(
          transport: transport,
          onUndo: onUndo,
          onRedo: onRedo,
          canUndo: canUndo,
          canRedo: canRedo,
          showRecord: showRecord,
          trailing: trailing,
        ),
      ),
    ),
  );
}

Finder _byTip(String tip) => find.byTooltip(tip);

/// The IconButton behind a tooltip. `find.byTooltip` matches the Tooltip
/// itself, so reading the button's own properties needs the ancestor.
IconButton _button(WidgetTester tester, String tip) =>
    tester.widget<IconButton>(
      find.ancestor(of: _byTip(tip), matching: find.byType(IconButton)),
    );

void main() {
  testWidgets('play/pause drives the service and follows it back', (
    tester,
  ) async {
    final transport = TransportService();
    await tester.pumpWidget(_host(transport));

    expect(_byTip('Play'), findsOneWidget);
    await tester.tap(_byTip('Play'));
    await tester.pump();

    expect(transport.isPlaying, isTrue, reason: 'the tap drove the service');
    expect(
      _byTip('Pause'),
      findsOneWidget,
      reason: 'and the service drove the icon back',
    );

    await tester.tap(_byTip('Pause'));
    await tester.pump();
    expect(transport.isPlaying, isFalse);
  });

  testWidgets('stop calls stop, not pause', (tester) async {
    final transport = TransportService()
      ..play()
      ..advance(2000);
    await tester.pumpWidget(_host(transport));

    await tester.tap(_byTip('Stop'));
    await tester.pump();

    expect(transport.isPlaying, isFalse);
    expect(
      transport.positionMs,
      0,
      reason: 'stop returns to the start; pause would have left it at 2000',
    );
  });

  testWidgets('record arms without rolling, and lights while armed', (
    tester,
  ) async {
    final transport = TransportService();
    await tester.pumpWidget(_host(transport));

    await tester.tap(_byTip('Record'));
    await tester.pump();

    expect(transport.isRecordArmed, isTrue);
    expect(
      transport.isPlaying,
      isFalse,
      reason: 'arming is not starting — that is the point of a separate arm',
    );

    expect(
      _button(tester, 'Record').color,
      isNotNull,
      reason: 'an armed record button is lit',
    );
  });

  testWidgets('record can be hidden for a surface that cannot record', (
    tester,
  ) async {
    await tester.pumpWidget(_host(TransportService(), showRecord: false));
    expect(
      _byTip('Record'),
      findsNothing,
      reason: 'better absent than permanently disabled',
    );
  });

  testWidgets('loop toggles', (tester) async {
    final transport = TransportService();
    await tester.pumpWidget(_host(transport));
    await tester.tap(_byTip('Loop'));
    await tester.pump();
    expect(transport.isLoopEnabled, isTrue);
  });

  testWidgets('metronome toggles', (tester) async {
    final transport = TransportService();
    await tester.pumpWidget(_host(transport));
    await tester.tap(_byTip('Metronome'));
    await tester.pump();
    expect(transport.metronomeEnabled, isTrue);
  });

  group('position readout', () {
    testWidgets('shows bar.beat and updates as the transport moves', (
      tester,
    ) async {
      final transport = TransportService();
      await tester.pumpWidget(_host(transport));
      expect(find.text('1.1'), findsOneWidget);

      transport
        ..play()
        ..advance(2500); // five beats at 120 BPM → bar 2, beat 2
      await tester.pump();
      expect(find.text('2.2'), findsOneWidget);
    });

    testWidgets('says it is counting in rather than showing a frozen 1.1', (
      tester,
    ) async {
      // A stuck "1.1" during a count-in reads as a hang; the bar has to say
      // what is actually happening.
      final transport = TransportService()..countInBars = 1;
      transport.play();
      await tester.pumpWidget(_host(transport));

      expect(find.text('Counting in…'), findsOneWidget);
      expect(find.text('1.1'), findsNothing);

      transport.advance(2000); // the whole count-in
      await tester.pump();
      expect(find.text('Counting in…'), findsNothing);
      expect(find.text('1.1'), findsOneWidget);
    });
  });

  group('tempo field', () {
    testWidgets('edits a constant tempo', (tester) async {
      final transport = TransportService();
      await tester.pumpWidget(_host(transport));

      await tester.enterText(
        find.byKey(const ValueKey('transport-tempo')),
        '90',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(transport.bpm, 90);
    });

    testWidgets('clamps out-of-range rather than accepting nonsense', (
      tester,
    ) async {
      final transport = TransportService();
      await tester.pumpWidget(_host(transport));

      await tester.enterText(
        find.byKey(const ValueKey('transport-tempo')),
        '9000',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(transport.bpm, kMaxBpm);
    });

    testWidgets('ignores unparseable input instead of zeroing the tempo', (
      tester,
    ) async {
      final transport = TransportService();
      await tester.pumpWidget(_host(transport));

      await tester.enterText(
        find.byKey(const ValueKey('transport-tempo')),
        'allegro',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(transport.bpm, 120);
    });

    testWidgets('a tempo MAP is read-only, not silently flattened', (
      tester,
    ) async {
      // Offering an editable field here would throw away every tempo change the
      // user made the moment they touched it.
      final transport = TransportService(
        tempo: TempoMap([
          const TempoChange(ms: 0, bpm: 120),
          const TempoChange(ms: 4000, bpm: 90),
        ]),
      );
      await tester.pumpWidget(_host(transport));

      expect(find.byKey(const ValueKey('transport-tempo')), findsNothing);
      expect(find.text('120'), findsOneWidget);

      transport.seekMs(5000);
      await tester.pump();
      expect(
        find.text('90'),
        findsOneWidget,
        reason: 'it reports the tempo in force at the playhead',
      );
    });
  });

  group('undo / redo', () {
    testWidgets('absent when the host passes no callbacks', (tester) async {
      await tester.pumpWidget(_host(TransportService()));
      expect(
        _byTip('Undo'),
        findsNothing,
        reason: 'a surface with no undo should not appear to have one',
      );
    });

    testWidgets('present and enabled by the host flags', (tester) async {
      var undone = 0;
      await tester.pumpWidget(
        _host(
          TransportService(),
          onUndo: () => undone++,
          onRedo: () {},
          canUndo: true,
        ),
      );

      await tester.tap(_byTip('Undo'));
      expect(undone, 1);

      expect(
        _button(tester, 'Redo').onPressed,
        isNull,
        reason: 'canRedo was false',
      );
    });
  });

  testWidgets('per-surface extras go in trailing, not in a fork', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        TransportService(),
        trailing: [
          IconButton(
            icon: const Icon(Icons.grid_on),
            tooltip: 'Snap',
            onPressed: () {},
          ),
        ],
      ),
    );
    expect(_byTip('Snap'), findsOneWidget);
  });

  testWidgets('narrow layout keeps the transport, drops the tempo field', (
    tester,
  ) async {
    // The controls a surface cannot lose are play/stop/position; the tempo
    // field is the first thing that may go.
    await tester.pumpWidget(_host(TransportService(), width: 400));
    expect(_byTip('Play'), findsOneWidget);
    expect(_byTip('Stop'), findsOneWidget);
    expect(find.text('1.1'), findsOneWidget);
    expect(find.byKey(const ValueKey('transport-tempo')), findsNothing);
  });

  testWidgets('two bars on one service stay in agreement', (tester) async {
    // The point of a shared transport: a surface showing the bar twice, or two
    // surfaces showing it at once, cannot disagree — there is no local state to
    // drift.
    final transport = TransportService();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(width: 1000, child: TransportBar(transport: transport)),
              SizedBox(width: 1000, child: TransportBar(transport: transport)),
            ],
          ),
        ),
      ),
    );

    expect(find.text('1.1'), findsNWidgets(2));
    await tester.tap(_byTip('Play').first);
    await tester.pump();
    expect(
      _byTip('Pause'),
      findsNWidgets(2),
      reason: 'the second bar followed without being touched',
    );
  });

  testWidgets('German locale labels the controls', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            child: TransportBar(transport: TransportService()),
          ),
        ),
      ),
    );
    expect(_byTip('Abspielen'), findsOneWidget);
    expect(_byTip('Stopp'), findsOneWidget);
  });
}
