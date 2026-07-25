// The Audio Editor's app-bar transport/edit actions must never overflow the row
// on a narrow (phone/web) window: essential actions stay as icons, the rest fold
// into a single "more" menu below the width threshold, and expand back to icons
// when wide.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _phone = Size(360, 900);
const _desktop = Size(1400, 900);

Future<AppLocalizations> _l10n(Locale locale) =>
    AppLocalizations.delegate.load(locale);

// Size the surface BEFORE the first pump so the app bar builds at the target
// width from frame one (pumpGame would force its own wide surface).
Future<void> _pumpDawAt(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider(
          create: (_) => SriService(getNow: () => DateTime(2026, 7, 11)),
        ),
        Provider<AudioService>(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => ProgressService()),
        ChangeNotifierProvider(create: (_) => DawService()),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('en'), Locale('de')],
        home: DawScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

DawTester _daw(WidgetTester tester) =>
    tester.state<State<DawScreen>>(find.byType(DawScreen)) as DawTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('wide toolbar shows secondary actions as icons, no more-menu',
      (tester) async {
    await _pumpDawAt(tester, _desktop);

    // Export/clear are top-level icons; there is no overflow menu.
    expect(find.byIcon(Icons.download), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow toolbar folds secondary actions into a more-menu',
      (tester) async {
    final l = await _l10n(const Locale('en'));
    await _pumpDawAt(tester, _phone);

    // The overflow menu is present; secondary icons are NOT loose in the bar.
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(find.byIcon(Icons.download), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    // Essential actions remain as icons.
    expect(find.byIcon(Icons.help_outline), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    // No overflow at phone width.
    expect(tester.takeException(), isNull);

    // Opening the menu reveals the folded actions (labelled + localized).
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text(l.audioExportTitle), findsOneWidget);
    expect(find.text(l.dawLoop), findsOneWidget);
    expect(find.text(l.dawSnap), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow more-menu still runs a folded action (snap toggle)',
      (tester) async {
    await _pumpDawAt(tester, _phone);
    final daw = _daw(tester);
    final before = daw.snapOn;

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(daw.snapOn ? Icons.grid_on : Icons.grid_off));
    await tester.pumpAndSettle();

    expect(daw.snapOn, isNot(before));
  });
}
