// Covers the master sound switch: SettingsService.soundOn persistence and the
// SoundToggle app-bar control (icon reflects state, tap flips + persists). The
// AudioService gate (`if (!soundOn) return;`) is exercised implicitly — a muted
// service returns before any plugin call.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/sound_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(SettingsService settings) => MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        Provider<AudioService>(create: (_) => AudioService()),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: [Locale('en'), Locale('de')],
        home: Scaffold(body: SoundToggle()),
      ),
    );

void main() {
  test('SettingsService.soundOn defaults on and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsService();
    await s.load();
    expect(s.soundOn, isTrue, reason: 'sound on by default');

    var notified = 0;
    s.addListener(() => notified++);
    await s.setSoundOn(false);
    expect(s.soundOn, isFalse);
    expect(notified, 1);

    final reloaded = SettingsService();
    await reloaded.load();
    expect(reloaded.soundOn, isFalse, reason: 'persisted across loads');
  });

  testWidgets('SoundToggle shows the right icon and flips the setting',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.load();

    await tester.pumpWidget(_host(settings));
    await tester.pumpAndSettle();

    // On → speaker icon.
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    expect(find.byIcon(Icons.volume_off_rounded), findsNothing);

    await tester.tap(find.byType(SoundToggle));
    await tester.pumpAndSettle();

    expect(settings.soundOn, isFalse);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);

    await tester.tap(find.byType(SoundToggle));
    await tester.pumpAndSettle();
    expect(settings.soundOn, isTrue);
  });

  test('muted AudioService.playMidiNote is a no-op that does not throw',
      () async {
    final audio = AudioService()..soundOn = false;
    // Returns before touching the (absent-in-tests) audioplayers plugin.
    await audio.playMidiNote(60);
    audio.dispose();
  });
}
