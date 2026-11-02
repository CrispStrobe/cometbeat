// On-device integration test for "Practise with your song", in the REAL app:
// the glint FFI plugin decodes, libcrispasr separates and tracks beats,
// SoLoud plays the stems. Headless `flutter test` reaches none of those.
//
// The song is made here — a Loop Mixer groove, encoded to MP3 by the app's
// own glint encoder — and handed to the screen through its debugPickSong
// seam in place of the file dialog.
//
// Run (macOS):
//   flutter test integration_test/practice_stems_test.dart -d macos
//
// The app is sandboxed: libcrispasr and the models are looked up in the
// CONTAINER's ~/.cache/crispasr
// (~/Library/Containers/com.crispstrobe.cometBeat/Data/.cache/crispasr).
// Without them the screen reports the engine unavailable and the test stops
// there, saying so.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/sf2/encode_capability.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:comet_beat/features/games/playalong/play_along_screen.dart';
import 'package:comet_beat/features/games/practice/practice_stems_screen.dart';
import 'package:comet_beat/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ~[seconds] of the default groove (all four tracks) as interleaved stereo.
Float64List _groove(int seconds) {
  final engine = LoopEngine()
    ..progression = kProgressions.first
    ..enabled.addAll(['drums', 'bass', 'chords', 'melody']);
  final wav = readWavPcm16(engine.renderLoop());
  final ch = wav.channels;
  final frames = wav.samples.length ~/ ch;
  final reps = math.max(1, (seconds * kSampleRate / frames).ceil());
  final out = Float64List(frames * reps * 2);
  for (var r = 0; r < reps; r++) {
    for (var i = 0; i < frames; i++) {
      final l = wav.samples[i * ch] / 32768;
      final rr = wav.samples[i * ch + (ch > 1 ? 1 : 0)] / 32768;
      out[2 * (r * frames + i)] = l;
      out[2 * (r * frames + i) + 1] = rr;
    }
  }
  return out;
}

/// Pumps frames while real time passes until [done] or [limit].
Future<bool> _waitFor(
  WidgetTester tester,
  bool Function() done, {
  Duration limit = const Duration(minutes: 6),
}) async {
  final sw = Stopwatch()..start();
  var lastReport = Duration.zero;
  while (sw.elapsed < limit) {
    final tick = Stopwatch()..start();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    if (tick.elapsed > const Duration(seconds: 5)) {
      debugPrint('[practice] one tick took ${tick.elapsed.inSeconds} s '
          '(main isolate blocked?)');
    }
    if (done()) return true;
    if (sw.elapsed - lastReport > const Duration(seconds: 20)) {
      lastReport = sw.elapsed;
      final texts = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .whereType<String>()
          .join(' | ');
      debugPrint('[practice] ${sw.elapsed.inSeconds} s: $texts');
    }
  }
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('practise with your song: decode, split, play, loop, slow, sing',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // The song: 20 s of groove, encoded to MP3 by the app's own glint.
    final encode = loadGlintEncoder();
    expect(encode, isNotNull, reason: 'glint plugin must be in a real build');
    final pcm = _groove(20);
    final mp3 = encode!(
      pcm,
      channels: 2,
      sampleRate: kSampleRate,
      format: EncodedAudioFormat.mp3,
      bitrateKbps: 192,
    );
    expect(mp3, isNotNull);
    final Uint8List bytes = mp3!;

    // Open the screen on the app's own navigator, so every service exists.
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    unawaited(
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => PracticeStemsScreen(
            debugPickSong: () async => (
              name: 'groove.mp3',
              path: '/nonexistent/groove.mp3',
              bytes: bytes
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pick = find.byKey(const Key('practice-stems-pick'));
    if (pick.evaluate().isEmpty) {
      fail('separation engine unavailable in the app — stage libcrispasr '
          'and the models in the container .cache/crispasr (see header)');
    }
    final sw = Stopwatch()..start();
    await tester.tap(pick);
    await tester.pump();

    // Decode (glint) → separate (htdemucs) → beats (beat-this) → mixer.
    final failed = find.text("That file couldn't be read or split.");
    final ready = await _waitFor(
      tester,
      () =>
          find.byKey(const Key('practice-stems-play')).evaluate().isNotEmpty ||
          failed.evaluate().isNotEmpty,
    );
    expect(failed, findsNothing, reason: 'the split failed (see log)');
    expect(ready, isTrue, reason: 'never reached the mixer');
    debugPrint('[practice] split ready after ${sw.elapsed.inSeconds} s');
    for (final stem in ['vocals', 'drums', 'bass', 'other']) {
      expect(
        find.byKey(Key('practice-stem-$stem')),
        findsOneWidget,
        reason: '$stem stem row',
      );
    }

    // Play: the transport flips to pause and the clock moves.
    await tester.tap(find.byKey(const Key('practice-stems-play')));
    await _waitFor(tester, () => false, limit: const Duration(seconds: 3));
    expect(find.byIcon(Icons.pause), findsOneWidget, reason: 'playing');
    expect(
      find.textContaining('0:00 /'),
      findsNothing,
      reason: 'the clock advanced',
    );

    // Mute the drums while playing: instant, nothing rebuilds.
    await tester.tap(find.byKey(const Key('practice-mute-drums')));
    await tester.pump();

    // Loop a part, then slow it to 75 %.
    await tester.tap(find.byKey(const Key('practice-stems-loop')));
    await _waitFor(
      tester,
      () => find.byType(RangeSlider).evaluate().isNotEmpty,
      limit: const Duration(seconds: 20),
    );
    await tester.tap(find.text('75%'));
    await tester.pump();
    final slowed = await _waitFor(
      tester,
      () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
      limit: const Duration(minutes: 3),
    );
    expect(slowed, isTrue, reason: 'slow-down never finished');
    expect(
      find.byIcon(Icons.pause),
      findsOneWidget,
      reason: 'still playing after the rebuild',
    );

    // Sing the melody: the voice stem → CREPE/pYIN → the note highway over
    // the song minus its voice. A groove has no singer, so "no melody found"
    // is also a correct outcome — but it must be one of the two.
    final singAlong = find.byKey(const Key('practice-sing-along'));
    await tester.scrollUntilVisible(
      singAlong,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(singAlong);
    final sang = await _waitFor(
      tester,
      () =>
          find.byType(PlayAlongScreen).evaluate().isNotEmpty ||
          find.byType(SnackBar).evaluate().isNotEmpty,
      limit: const Duration(minutes: 3),
    );
    expect(sang, isTrue, reason: 'sing-along neither opened nor declined');
    debugPrint('[practice] sing-along: '
        '${find.byType(PlayAlongScreen).evaluate().isNotEmpty ? 'opened' : 'no melody (snackbar)'}');
  });
}
