// The last answer's musical example must ring out before the result screen and
// the finish fanfare (QuizRoundMixin.resolveAnswer). Regression: the fanfare
// shares the app's single audio player, so playing it at once cut the example
// off and the result screen replaced the question mid-phrase.

import 'dart:typed_data';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/games/songs/instrument_family_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

/// Audio double: reports a fixed amount of example still sounding and counts
/// fanfares instead of touching the platform player.
class _FakeAudio extends AudioService {
  _FakeAudio(this.remaining);
  final Duration remaining;
  int fanfares = 0;

  @override
  Duration get playbackRemaining => remaining;
  @override
  Future<void> playFanfare() async => fanfares++;
  @override
  Future<void> playCorrect() async {}
  @override
  Future<void> playWrong() async {}
}

/// The REAL service with only the platform start made slow — the case the
/// fixed-remaining fake above cannot show: the remaining time is unknown until
/// the player has started, which takes platform round trips.
class _SlowStartAudio extends AudioService {
  int fanfares = 0;
  @override
  Future<void> startPlayer(Uint8List wav) =>
      Future<void>.delayed(const Duration(milliseconds: 60));
  @override
  Future<void> playFanfare() async => fanfares++;
  @override
  Future<void> playCorrect() async {}
  @override
  Future<void> playWrong() async {}
}

const _label = {
  'strings': 'Strings',
  'woodwind': 'Woodwind',
  'brass': 'Brass',
  'percussion': 'Percussion',
  'keyboard': 'Keyboard',
};

InstrumentFamilyTester _game(WidgetTester tester) =>
    tester.state<State<InstrumentFamilyScreen>>(
      find.byType(InstrumentFamilyScreen),
    ) as InstrumentFamilyTester;

/// Answers every round correctly; returns right after the LAST answer.
///
/// [exampleBeforeLastTap]: start a 1.5 s example in the same turn as the last
/// answer, the way a game's answer handler does (play, then resolveAnswer).
Future<void> _playToLastAnswer(
  WidgetTester tester,
  AudioService audio, {
  bool exampleBeforeLastTap = false,
}) async {
  await pumpGame(
    tester,
    const InstrumentFamilyScreen(),
    extraProviders: [Provider<AudioService>.value(value: audio)],
  );
  for (var i = 0; i < 9; i++) {
    await tester.tap(find.text(_label[_game(tester).answerFamily]!));
    await tester.pump(const Duration(milliseconds: 800));
  }
  if (exampleBeforeLastTap) {
    // ignore: unawaited_futures
    audio.playMidiNote(60, ms: 1500);
  }
  await tester.tap(find.text(_label[_game(tester).answerFamily]!));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('result screen waits for the last example to finish', (
    tester,
  ) async {
    final audio = _FakeAudio(const Duration(seconds: 2));
    await _playToLastAnswer(tester, audio);

    await tester.pump(const Duration(milliseconds: 1900));
    expect(_game(tester).isFinished, isFalse);
    expect(audio.fanfares, 0);

    await tester.pump(const Duration(milliseconds: 200));
    expect(_game(tester).isFinished, isTrue);
    expect(audio.fanfares, 1);
  });

  testWidgets('the wait is capped at ~4 s', (tester) async {
    final audio = _FakeAudio(const Duration(seconds: 30));
    await _playToLastAnswer(tester, audio);

    await tester.pump(const Duration(milliseconds: 3900));
    expect(_game(tester).isFinished, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    expect(_game(tester).isFinished, isTrue);
  });

  testWidgets('a tap skips the wait', (tester) async {
    final audio = _FakeAudio(const Duration(seconds: 3));
    await _playToLastAnswer(tester, audio);

    await tester.pump(const Duration(milliseconds: 500));
    expect(_game(tester).isFinished, isFalse);
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(_game(tester).isFinished, isTrue);
    expect(audio.fanfares, 1);
  });

  testWidgets('nothing sounding: finishes immediately', (tester) async {
    final audio = _FakeAudio(Duration.zero);
    await _playToLastAnswer(tester, audio);
    await tester.pump(const Duration(milliseconds: 1));
    expect(_game(tester).isFinished, isTrue);
  });

  testWidgets('a slow platform start still holds the result screen', (
    tester,
  ) async {
    // Regression: the finish flow read playbackRemaining one tick after the
    // answer, while the player was still starting — it read zero, and the
    // result screen cut the last example off in the real app.
    final audio = _SlowStartAudio();
    await _playToLastAnswer(tester, audio, exampleBeforeLastTap: true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      _game(tester).isFinished,
      isFalse,
      reason: 'the example had only just started',
    );
    expect(audio.fanfares, 0);
    await tester.pump(const Duration(seconds: 5));
    expect(_game(tester).isFinished, isTrue);
    expect(audio.fanfares, 1);
  });

  test('playbackRemainingAfterStart waits for the start', () async {
    final audio = _SlowStartAudio();
    // ignore: unawaited_futures
    audio.playMidiNote(60, ms: 1500);
    await Future<void>.delayed(Duration.zero);
    expect(audio.playbackRemaining, Duration.zero, reason: 'still starting');
    final left = await audio.playbackRemainingAfterStart();
    expect(left, greaterThan(const Duration(milliseconds: 1000)));
  });
}
