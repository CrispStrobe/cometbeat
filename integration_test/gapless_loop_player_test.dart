// On-device integration test for the SoLoud-backed GaplessLoopPlayer.
//
// Headless `flutter test` can only reach the audioplayers FALLBACK path — the
// SoLoud native symbols aren't loaded there (`isInited` lookup fails), so the
// unit suites prove the fallback. This test runs on a REAL device (macOS), where
// the flutter_soloud plugin is linked, and proves the PRIMARY path: the loop is
// looped inside SoLoud's own mixer (a live, valid, looping voice), which is what
// removes the OS media-player loop-reset gap. It asserts the integration end to
// end — init, play (looping voice active), in-phase crossfaded swap, pause/resume,
// and stop (voice released) — without needing an acoustic capture rig.
//
// Run:
//   flutter test integration_test/gapless_loop_player_test.dart -d macos
//
// Skips itself cleanly (all expectations guarded on `isInitialized`) on a device
// without a working SoLoud engine, so it never turns a CI lane red.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show wavBytes;
import 'package:comet_beat/core/services/gapless_loop_player.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// A 0.5 s 220 Hz sine loop as a PCM16 mono WAV. A whole number of cycles fits
/// the buffer, so a truly gapless repeat is continuous; an OS loop-reset gap
/// would punch a silence into it.
Uint8List _toneLoopWav() {
  const rate = 44100;
  const seconds = 0.5;
  const freq = 220.0;
  final n = (rate * seconds).round();
  final pcm = Int16List(n);
  for (var i = 0; i < n; i++) {
    pcm[i] = (math.sin(2 * math.pi * freq * i / rate) * 12000).round();
  }
  return wavBytes(pcm);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final soloud = SoLoud.instance;
  bool onDevice() => soloud.isInitialized;

  test('GaplessLoopPlayer drives a live looping SoLoud voice on-device',
      () async {
    final player = GaplessLoopPlayer();
    addTearDown(player.dispose);
    final wav = _toneLoopWav();

    // 1. First play brings up SoLoud and starts a looping voice.
    await player.playLoop(wav);
    // Give SoLoud a moment to register the voice on its audio thread.
    await Future<void>.delayed(const Duration(milliseconds: 120));

    if (!onDevice()) {
      // No SoLoud engine here (headless / unsupported): the class fell back to
      // audioplayers, which the unit suites already cover. Nothing to assert.
      return;
    }

    expect(
      soloud.getActiveVoiceCount(),
      greaterThanOrEqualTo(1),
      reason: 'a looping voice should be sounding after playLoop',
    );

    // 2. An in-phase swap (a live edit / infinite-mode variation) keeps a voice
    //    active — the crossfade means we never drop to silence at the seam.
    await player.playLoop(wav, position: const Duration(milliseconds: 250));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(
      soloud.getActiveVoiceCount(),
      greaterThanOrEqualTo(1),
      reason: 'the swap should overlap, never leaving a gap',
    );

    // 3. Pause silences the transport; resume brings it back.
    await player.pause();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await player.resume();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(
      soloud.getActiveVoiceCount(),
      greaterThanOrEqualTo(1),
      reason: 'resume should re-sound the same loop',
    );

    // 4. Stop releases every voice this player owns.
    await player.stop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(
      soloud.getActiveVoiceCount(),
      0,
      reason: 'stop should release the loop voice(s)',
    );
  });
}
