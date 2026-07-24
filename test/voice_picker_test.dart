// The full-palette "Instrument sound" voice: id→voice resolution, the settings
// persistence + migration from the legacy 4-way enum, and the picker UI (search
// + category filter + choose-on-long-press).

import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/voice_options.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/settings/screens/voice_picker_sheet.dart';
import 'package:comet_beat/features/sound_lab/instrument_library_store.dart';
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('resolveVoiceSync', () {
    test('additive ids map to the enum with NO override', () {
      final r = resolveVoiceSync('cello');
      expect(r.instrument, Instrument.cello);
      expect(r.voice, isNull); // classic additive path
    });

    test('a procedural id builds a voice override (piano fallback timbre)', () {
      final r = resolveVoiceSync('blip');
      expect(r.instrument, Instrument.piano);
      expect(r.voice, isNotNull);
    });

    test('an unknown id falls back to plain piano', () {
      final r = resolveVoiceSync('nonsense');
      expect(r.instrument, Instrument.piano);
      expect(r.voice, isNull);
    });
  });

  group('SettingsService voice', () {
    test('selecting a procedural voice sets the override + persists', () async {
      SharedPreferences.setMockInitialValues({});
      final s = SettingsService();
      await s.load();
      await s.setVoiceId('pluck');
      expect(s.voiceId, 'pluck');
      expect(s.voice, isNotNull);

      // reloads from disk
      final s2 = SettingsService();
      await s2.load();
      expect(s2.voiceId, 'pluck');
      expect(s2.voice, isNotNull);
    });

    test('migrates from the legacy enum key when voice_id is absent', () async {
      SharedPreferences.setMockInitialValues({'instrument': 'flute'});
      final s = SettingsService();
      await s.load();
      expect(s.voiceId, 'flute');
      expect(s.instrument, Instrument.flute);
      expect(s.voice, isNull);
    });

    test('setInstrument still works (routes through voiceId)', () async {
      SharedPreferences.setMockInitialValues({});
      final s = SettingsService();
      await s.load();
      await s.setInstrument(Instrument.cello);
      expect(s.voiceId, 'cello');
      expect(s.instrument, Instrument.cello);
      expect(s.voice, isNull);
    });
  });

  group('VoicePickerSheet', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Widget host({InstrumentLibraryStore? store}) => MultiProvider(
          providers: [Provider<AudioService>(create: (_) => AudioService())],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: VoicePickerSheet(
                currentId: 'piano',
                store: store ?? InstrumentLibraryStore(),
              ),
            ),
          ),
        );

    testWidgets('lists procedural voices beyond the four additive', (t) async {
      await t.pumpWidget(host());
      await t.pumpAndSettle();
      expect(find.text('Piano'), findsOneWidget); // an additive voice
      // more than the four classic additive voices are offered (the rest are
      // below the viewport; the filter/search tests reach them).
      expect(find.byType(ListTile).evaluate().length, greaterThan(4));
    });

    testWidgets('instrument selector reaches Generate FX through Sound Library',
        (t) async {
      await t.pumpWidget(host());
      await t.pumpAndSettle();

      await t.tap(find.byIcon(Icons.library_music_outlined));
      await t.pumpAndSettle();
      expect(find.text('Sound Library'), findsOneWidget);

      await t.tap(find.byIcon(Icons.add));
      await t.pumpAndSettle();
      expect(find.text('New FX'), findsOneWidget);
    });

    testWidgets('generated FX is saved to the selector library store',
        (t) async {
      final store = InstrumentLibraryStore();
      await t.pumpWidget(
        MultiProvider(
          providers: [Provider<AudioService>(create: (_) => AudioService())],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    await showVoicePicker(context, store: store);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.library_music_outlined));
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.add));
      await t.pumpAndSettle();
      await t.tap(find.text('New FX'));
      await t.pumpAndSettle();
      await t.tap(find.text('laser'));
      await t.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Save');
      await t.ensureVisible(save);
      await t.tap(save);
      await t.pumpAndSettle();

      expect((await store.load()).map((s) => s.name), contains('laser'));
      expect(find.text('Sound Library'), findsOneWidget);
    });

    testWidgets('the Chiptune filter narrows to chiptune voices', (t) async {
      await t.pumpWidget(host());
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ChoiceChip, 'Chiptune'));
      await t.pumpAndSettle();
      expect(find.text('Piano'), findsNothing); // tonal, filtered out
      expect(find.text('Blip'), findsWidgets); // chiptune, kept
    });

    testWidgets('search narrows the list', (t) async {
      await t.pumpWidget(host());
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'pluck');
      await t.pumpAndSettle();
      expect(find.textContaining('Pluck'), findsWidgets);
      expect(find.text('Piano'), findsNothing);
    });

    testWidgets('long-press chooses a built-in voice (id, no resolved)',
        (t) async {
      VoiceChoice? picked;
      await t.pumpWidget(
        MultiProvider(
          providers: [Provider<AudioService>(create: (_) => AudioService())],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async =>
                      picked = await showVoicePicker(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.longPress(find.text('Blip').first);
      await t.pumpAndSettle();
      expect(picked?.id, 'blip');
      expect(picked?.resolved, isNull); // built-in resolves from its id
    });

    testWidgets('shows a saved library voice + chooses it with a resolved inst',
        (t) async {
      final store = InstrumentLibraryStore();
      await store.save(
        SavedInstrument.fromSampleClip(
          SampleClip(
            name: 'My Clip',
            sampleRate: 22050,
            pcm: Float64List.fromList(const [0.0, 0.3, -0.3, 0.0]),
          ),
        ),
      );
      await t.pumpWidget(host(store: store));
      await t.pumpAndSettle();

      // a My Library filter chip appears; tapping it surfaces the saved voice
      // (library items sit below the ~20 procedural voices otherwise).
      expect(find.widgetWithText(ChoiceChip, 'Sound Library'), findsOneWidget);
      await t.tap(find.widgetWithText(ChoiceChip, 'Sound Library'));
      await t.pumpAndSettle();
      expect(find.text('My Clip'), findsOneWidget);
      expect(find.text('Piano'), findsNothing); // procedural filtered out
    });

    testWidgets('a library voice pops (lib:<name>, resolved instrument)',
        (t) async {
      final store = InstrumentLibraryStore();
      await store.save(
        SavedInstrument.fromSampleClip(
          SampleClip(
            name: 'My Clip',
            sampleRate: 22050,
            pcm: Float64List.fromList(const [0.0, 0.3, -0.3, 0.0]),
          ),
        ),
      );
      VoiceChoice? picked;
      await t.pumpWidget(
        MultiProvider(
          providers: [Provider<AudioService>(create: (_) => AudioService())],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async =>
                      picked = await showVoicePicker(context, store: store),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ChoiceChip, 'Sound Library'));
      await t.pumpAndSettle();
      await t.longPress(find.text('My Clip'));
      await t.pumpAndSettle();
      expect(picked?.id, 'lib:My Clip');
      expect(picked?.resolved, isNotNull); // carries its built voice
    });
  });
}
