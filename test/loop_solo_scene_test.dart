// Loop Studio: solo interacting with scenes.
//
// Solo is deliberately an isolation mode that FREEZES the mix — it snapshots
// `enabled`, plays one track, and puts the snapshot back on exit (see the
// comment on `_toggle`). That design is fine, but it means any code path that
// REPLACES the enabled set has to forget the snapshot first, and two scene paths
// did not:
//
//   * Launching a scene while soloing left `_enabledBeforeSolo` holding the
//     PRE-solo mix, so the next un-solo silently threw the launched scene away
//     and put the old mix back.
//   * Capturing a scene while soloing stored `enabled` — which during solo is
//     just the soloed track — so the scene saved "only the lead" as the mix.
//
// Both are now routed through `_discardSolo()` / `_mixUnderSolo`. These tests
// pin the behaviour so the next "reset solo" site cannot half-do it again.

import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

LoopMixerTester _game(WidgetTester tester) =>
    tester.state<State<LoopMixerScreen>>(find.byType(LoopMixerScreen))
        as LoopMixerTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('launching a scene while soloing does not resurrect the old mix',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);

    // Scene A = drums + bass.
    game.toggleTrack('drums');
    game.toggleTrack('bass');
    await tester.pump();
    game.captureScene(0);
    await tester.pump();

    // Scene B = melody + chords.
    game.toggleTrack('drums');
    game.toggleTrack('bass');
    game.toggleTrack('melody');
    game.toggleTrack('chords');
    await tester.pump();
    expect(game.enabledTracks, {'melody', 'chords'});
    game.captureScene(1);
    await tester.pump();

    // Solo one track, then launch scene A.
    game.toggleSolo('melody');
    await tester.pump();
    expect(game.soloTrack, 'melody');

    game.launchScene(0);
    await tester.pump();

    // The scene defines the mix now, so solo must be gone — not lingering with a
    // stale snapshot of the pre-solo mix.
    expect(game.soloTrack, isNull, reason: 'solo survived a scene launch');
    expect(game.enabledTracks, {'drums', 'bass'});

    // The bug: toggling solo again used to restore {melody, chords} — the mix
    // from before the solo — silently discarding scene A.
    game.toggleSolo('drums');
    await tester.pump();
    game.toggleSolo('drums');
    await tester.pump();
    expect(
      game.enabledTracks,
      {'drums', 'bass'},
      reason: 'un-solo clobbered the launched scene',
    );
  });

  testWidgets('capturing a scene while soloing stores the real mix',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);

    game.toggleTrack('drums');
    game.toggleTrack('bass');
    await tester.pump();

    // Solo the bass, THEN capture. `enabled` is {bass} at this moment, so a
    // naive capture would store a one-track scene.
    game.toggleSolo('bass');
    await tester.pump();
    expect(game.enabledTracks, {'bass'});
    game.captureScene(0);
    await tester.pump();

    // Leave solo and clear the board, then launch what we captured.
    game.toggleSolo('bass');
    await tester.pump();
    game.stopAll();
    await tester.pump();
    expect(game.enabledTracks, isEmpty);

    game.launchScene(0);
    await tester.pump();
    expect(
      game.enabledTracks,
      {'drums', 'bass'},
      reason: 'the scene saved the solo state instead of the mix',
    );
  });

  testWidgets('the ordinary solo round-trip is unchanged', (tester) async {
    // The deliberate design: solo freezes the mix and leaving solo restores it
    // exactly. This is the behaviour the fix must NOT alter.
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);

    game.toggleTrack('melody');
    game.toggleTrack('bass');
    await tester.pump();

    game.toggleSolo('melody');
    await tester.pump();
    expect(game.soloTrack, 'melody');
    expect(game.enabledTracks, {'melody'});

    // Card taps stay inert during solo, on purpose.
    game.toggleTrack('chords');
    await tester.pump();
    expect(game.enabledTracks, {'melody'});

    game.toggleSolo('melody');
    await tester.pump();
    expect(game.soloTrack, isNull);
    expect(game.enabledTracks, {'melody', 'bass'});
  });

  testWidgets('Stop and Surprise-me forget solo without restoring',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);

    game.toggleTrack('drums');
    game.toggleTrack('bass');
    await tester.pump();
    game.toggleSolo('drums');
    await tester.pump();

    game.stopAll();
    await tester.pump();
    expect(game.soloTrack, isNull);
    expect(game.enabledTracks, isEmpty, reason: 'Stop must leave it silent');

    // And a later solo/un-solo must not resurrect the pre-Stop mix.
    game.toggleTrack('melody');
    await tester.pump();
    game.toggleSolo('melody');
    await tester.pump();
    game.toggleSolo('melody');
    await tester.pump();
    expect(game.enabledTracks, {'melody'});
  });
}
