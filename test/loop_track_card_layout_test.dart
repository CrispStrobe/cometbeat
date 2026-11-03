// Loop Studio's track cards must lay out at EVERY window width.
//
// The header row used to decide by SCREEN width (< 420 px) whether to move its
// buttons to a second row, but a card's width comes from the lane's column
// count: an ~800 px desktop window gives four ~182 px cards, narrower than the
// ~188 px of fixed-size controls in the header, and the row overflowed (0.5 px
// on macOS, a few px under the test font). The header now reflows by the
// card's own width. This sweeps the side-by-side lane across its whole range.

import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final simple in [false, true]) {
    testWidgets(
        'no track-card overflow from 560 to 1300 px '
        '(${simple ? 'Simple' : 'Advanced'} view)', (tester) async {
      await pumpGame(tester, LoopMixerScreen(simpleLayout: simple));
      final loop = tester.state<State<LoopMixerScreen>>(
        find.byType(LoopMixerScreen),
      ) as LoopMixerTester;
      for (final id in ['drums', 'bass', 'chords', 'melody']) {
        if (!loop.enabledTracks.contains(id)) loop.toggleTrack(id);
      }
      loop.setTrackPan('chords', -0.6);
      await tester.pump();

      for (var w = 560.0; w <= 1300; w += 1.5) {
        await tester.binding.setSurfaceSize(Size(w, 900));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'overflow at $w px');
      }
      // The loop-length control is still there on a wide window — moved, not
      // dropped.
      expect(find.byKey(const Key('loop-steps-Drums')), findsOneWidget);
    });
  }
}
