// The narration voice picker (Settings + lesson override) and the lesson
// sheet's fallback note, against a fake neural runtime — no libcrispasr.
import 'package:comet_beat/core/audio/tts/neural_voice_catalog.dart';
import 'package:comet_beat/core/audio/tts/neural_voice_runtime.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/tts_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/tts/narration_voice_picker.dart';
import 'package:comet_beat/shared/tutorial/tutorial.dart';
import 'package:comet_beat/shared/tutorial/tutorial_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBackend implements TtsBackend {
  final List<String> spoken = [];
  @override
  Future<void> speak(String text, {required String langCode}) async =>
      spoken.add(text);
  @override
  Future<void> stop() async {}
}

class _FakeRuntime implements NeuralVoiceRuntime {
  _FakeRuntime({Set<String>? installed, this.unavailable})
      : installed = installed ?? {};
  final Set<String> installed;
  final String? unavailable;
  final List<String> spokenBy = [];

  @override
  Future<String?> unavailableReason() async => unavailable;
  @override
  Future<bool> isInstalled(NeuralVoice voice) async =>
      installed.contains(voice.id);
  @override
  Future<void> download(
    NeuralVoice voice, {
    TtsDownloadProgress? onProgress,
  }) async =>
      installed.add(voice.id);
  @override
  Future<void> remove(NeuralVoice voice) async => installed.remove(voice.id);
  @override
  Future<void> speak(NeuralVoice voice, String text) async =>
      spokenBy.add(voice.id);
  @override
  Future<void> stop() async {}
}

const _thorsten = 'piper-de-thorsten-medium';
const _kerstin = 'piper-de-kerstin-low';

Future<TtsService> _pump(
  WidgetTester tester,
  _FakeRuntime rt, {
  NarrationScope scope = NarrationScope.global,
  _FakeBackend? backend,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final tts = TtsService(backend: backend ?? _FakeBackend(), neural: rt);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TtsService>.value(value: tts),
        ChangeNotifierProvider(create: (_) => SettingsService()),
      ],
      child: MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('de')],
        home: Scaffold(body: NarrationVoicePicker(scope: scope)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tts;
}

void main() {
  testWidgets('lists the German voices with size + licence', (tester) async {
    await _pump(tester, _FakeRuntime(installed: {_thorsten}));
    expect(find.text('Thorsten'), findsOneWidget);
    expect(find.text('Kerstin'), findsOneWidget);
    expect(find.textContaining('30 MB · CC0 · Heruntergeladen'), findsOne);
    // English-only voices are not offered for German narration.
    expect(find.text('Cori'), findsNothing);
  });

  testWidgets('Settings scope: choosing persists the global choice',
      (tester) async {
    final tts = await _pump(tester, _FakeRuntime(installed: {_thorsten}));
    await tester.tap(find.text('Thorsten'));
    await tester.pumpAndSettle();
    expect(tts.globalVoiceChoice('de'), _thorsten);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tts_voice_choice_de'), _thorsten);

    await tester.tap(find.byKey(const ValueKey('voice-device')));
    await tester.pumpAndSettle();
    expect(tts.globalVoiceChoice('de'), kNarrationVoiceDevice);
  });

  testWidgets('lesson scope: an override, then back to "same as Settings"',
      (tester) async {
    final tts = await _pump(
      tester,
      _FakeRuntime(installed: {_thorsten, _kerstin}),
      scope: NarrationScope.lesson,
    );
    expect(find.text('Wie in den Einstellungen'), findsOneWidget);
    await tester.tap(find.text('Kerstin'));
    await tester.pumpAndSettle();
    expect(tts.lessonVoiceOverride('de'), _kerstin);
    expect(tts.globalVoiceChoice('de'), kNarrationVoiceAuto); // untouched
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tts_lesson_voice_de'), _kerstin);

    await tester.tap(find.byKey(const ValueKey('voice-follow-settings')));
    await tester.pumpAndSettle();
    expect(tts.lessonVoiceOverride('de'), isNull);
    expect(prefs.getString('tts_lesson_voice_de'), isNull);
  });

  testWidgets('tapping a voice that is not downloaded downloads + selects it',
      (tester) async {
    final rt = _FakeRuntime();
    final tts = await _pump(tester, rt);
    await tester.tap(find.byKey(const ValueKey('voice-download-$_thorsten')));
    await tester.pumpAndSettle();
    expect(rt.installed, contains(_thorsten));
    expect(tts.isInstalledCached(_thorsten), isTrue);
    expect(tts.globalVoiceChoice('de'), _thorsten);
  });

  testWidgets('no engine: the reason is shown and voices are disabled',
      (tester) async {
    await _pump(tester, _FakeRuntime(unavailable: 'image not found'));
    expect(find.byKey(const ValueKey('voice-unavailable')), findsOneWidget);
    expect(find.textContaining('image not found'), findsOneWidget);
    final tile = tester.widget<ListTile>(
      find.byKey(const ValueKey('voice-$_thorsten')),
    );
    expect(tile.enabled, isFalse);
  });

  testWidgets(
      'lesson sheet: voice button + fallback note when the chosen '
      'voice is missing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = _FakeBackend();
    final tts = TtsService(backend: backend, neural: _FakeRuntime());
    await tts.setVoiceChoice('de', _thorsten, scope: NarrationScope.lesson);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TtsService>.value(value: tts),
          ChangeNotifierProvider(create: (_) => SettingsService()),
        ],
        child: MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('de')],
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showTutorial(
                  context,
                  Tutorial(
                    title: 'Viertelnote',
                    steps: const [TutorialStep(text: 'Ein Schlag.')],
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tutorial-voice-picker')), findsOneWidget);

    await tester.tap(find.byTooltip('Vorlesen'));
    await tester.pumpAndSettle();
    // Still spoken (device voice) — and the sheet says why.
    expect(backend.spoken, ['Ein Schlag.']);
    expect(find.byKey(const ValueKey('tutorial-voice-fallback')), findsOne);
    expect(find.textContaining('Thorsten ist noch nicht geladen'), findsOne);

    // The voice button opens the picker in lesson scope.
    await tester.tap(find.byKey(const ValueKey('tutorial-voice-picker')));
    await tester.pumpAndSettle();
    expect(find.text('Stimme für Lektionen'), findsOneWidget);
  });

  test('formatVoiceBytes rounds to MB', () {
    expect(formatVoiceBytes(10089664), '10 MB');
    expect(formatVoiceBytes(141322336 + 522784), '135 MB');
  });
}
