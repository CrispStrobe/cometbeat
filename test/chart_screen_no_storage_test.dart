// The chart screen with NO storage plugin at all.
//
// Its own file on purpose: `SharedPreferences.setMockInitialValues` installs a
// process-wide handler that stays installed for the rest of the FILE, so a
// "there is no plugin" assertion cannot be made in a file that mocks one — it
// would silently be testing the opposite. Nothing here mocks anything.
//
// The unguarded version threw from an unawaited future in `initState`, which
// fails the enclosing test rather than the screen. Losing persistence is a
// degraded screen; throwing is a broken one, and the working slot is
// best-effort by design.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/harmony/chart_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('the screen works when shared_preferences is unavailable',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Provider<AudioService>(
          create: (_) => AudioService(),
          child: const ChartScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The starter chart is still there, and still editable.
    expect(find.text('C7'), findsWidgets);
    expect(find.byKey(const Key('chartPlayButton')), findsOneWidget);
  });

  testWidgets('editing a chart without storage does not throw', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Provider<AudioService>(
          create: (_) => AudioService(),
          child: const ChartScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // _persist() runs on every edit; with no store it must be a no-op, not a
    // crash. Tapping a bar opens the keypad, which is the edit entry point.
    await tester.tap(find.text('F7').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
