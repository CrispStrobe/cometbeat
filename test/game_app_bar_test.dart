// GameAppBar — the shared bar 125 game screens use.
//
// Restored after `ba96a26f` deleted it along with an earlier scroll attempt.
// The maintainer has since asked for horizontal scroll explicitly, so the
// behaviour is back — and these tests pin the two things that made the first
// attempt unacceptable: the app-wide controls must NOT scroll away, and a long
// action row must not overflow.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Future<void> _pump(
  WidgetTester tester, {
  required List<Widget> actions,
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        // SoundToggle watches SettingsService and reads AudioService; without
        // them the bar throws before anything can be asserted.
        ChangeNotifierProvider(create: (_) => SettingsService()),
        Provider<AudioService>(create: (_) => AudioService()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          appBar: GameAppBar(title: 'Tracker', actions: actions),
          body: const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<Widget> _manyActions(int n) => [
      for (var i = 0; i < n; i++)
        IconButton(
          key: ValueKey('act$i'),
          icon: const Icon(Icons.star),
          tooltip: 'Action $i',
          onPressed: () {},
        ),
    ];

void main() {
  testWidgets('the title and the sound toggle are there', (tester) async {
    await _pump(tester, actions: const []);
    expect(find.text('Tracker'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
  });

  testWidgets('a long action row does NOT overflow', (tester) async {
    // The bug this fixes: the Tracker's row overflowed by ~370px on a phone,
    // and an overflowing Flex throws during layout — so the assertion is simply
    // that pumping produces no exception.
    await _pump(tester, actions: _manyActions(12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sound toggle stays REACHABLE however many actions there are',
      (tester) async {
    // The reverted attempt scrolled the sound toggle too. An app-wide mute you
    // have to go hunting for is worse than no scroll at all, so it is pinned
    // outside the scroll view and must remain hit-testable.
    await _pump(tester, actions: _manyActions(12));
    final toggle = find.byIcon(Icons.volume_up_rounded);
    expect(toggle, findsOneWidget);
    expect(
      toggle.hitTestable(),
      findsOneWidget,
      reason: 'pinned outside the scroll view, so it never scrolls away',
    );
  });

  testWidgets('overflowing actions are reachable by scrolling', (tester) async {
    // The point of the change: actions past the edge are not lost, just
    // scrolled. The last one starts off-screen and becomes hit-testable after
    // dragging the row.
    await _pump(tester, actions: _manyActions(12));
    final last = find.byKey(const ValueKey('act11'));
    expect(last, findsOneWidget);
    expect(last.hitTestable(), findsNothing, reason: 'starts past the edge');

    await tester.drag(find.byType(GameAppBar), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(last.hitTestable(), findsOneWidget);
  });

  testWidgets('a short action row is untouched', (tester) async {
    // 125 screens use this bar and most have two or three actions; they must
    // look exactly as before, with no scroll behaviour in the way.
    await _pump(tester, actions: _manyActions(2), size: const Size(1200, 800));
    expect(tester.takeException(), isNull);
    for (var i = 0; i < 2; i++) {
      expect(find.byKey(ValueKey('act$i')).hitTestable(), findsOneWidget);
    }
  });
}
