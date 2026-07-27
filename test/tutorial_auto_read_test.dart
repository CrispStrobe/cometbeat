// Covers the opt-in "auto-read" tutorial narration: when SettingsService's
// autoReadTutorials is on, each step's text is spoken as it becomes visible; the
// header toggle flips the setting and reads the current step immediately.

import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/tts_service.dart';
import 'package:comet_beat/shared/tutorial/tutorial.dart';
import 'package:comet_beat/shared/tutorial/tutorial_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

class _FakeBackend implements TtsBackend {
  final List<String> spoken = [];
  @override
  Future<void> speak(String text, {required String langCode}) async =>
      spoken.add(text);
  @override
  Future<void> stop() async {}
}

final _tutorial = Tutorial(
  title: 'How to play',
  steps: const [
    TutorialStep(text: 'First step text'),
    TutorialStep(text: 'Second step text'),
  ],
);

Future<(_FakeBackend, SettingsService)> _open(
  WidgetTester tester, {
  required bool autoRead,
}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsService();
  if (autoRead) await settings.setAutoReadTutorials(true);
  final fake = _FakeBackend();
  final tts = TtsService(backend: fake);
  await pumpGame(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showTutorial(context, _tutorial),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    extraProviders: [
      ChangeNotifierProvider<SettingsService>.value(value: settings),
      ChangeNotifierProvider<TtsService>.value(value: tts),
    ],
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (fake, settings);
}

void main() {
  testWidgets('auto-read ON narrates each step as it becomes visible',
      (tester) async {
    final (fake, _) = await _open(tester, autoRead: true);

    // First step is read on open.
    expect(fake.spoken, ['First step text']);

    // Paging to the next step reads it too.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(fake.spoken, ['First step text', 'Second step text']);
  });

  testWidgets('auto-read OFF stays silent until the read-aloud button',
      (tester) async {
    final (fake, _) = await _open(tester, autoRead: false);
    expect(fake.spoken, isEmpty); // nothing auto-spoken

    // The manual read-aloud button still works.
    await tester.tap(find.byTooltip('Read aloud'));
    await tester.pumpAndSettle();
    expect(fake.spoken, ['First step text']);
  });

  testWidgets('the header toggle turns auto-read on, persists, reads now',
      (tester) async {
    final (fake, settings) = await _open(tester, autoRead: false);
    expect(fake.spoken, isEmpty);

    await tester.tap(find.byTooltip('Read each step aloud'));
    await tester.pumpAndSettle();

    // Setting flipped (persisted) + the current step was read immediately.
    expect(settings.autoReadTutorials, isTrue);
    expect(fake.spoken, ['First step text']);
  });
}
