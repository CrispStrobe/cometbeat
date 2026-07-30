// The ADVANCED Tracker gets a per-channel effect rack.
//
// ⚠️ It had none — while the BEGINNER tracker did. Found by an interop matrix
// rather than by reading any card, and it reads as an oversight rather than a
// decision: `TrackerChannel.fxChain` and `TrackerEngine.setChannelFxChain`
// already existed and this screen simply never offered them, so the serious
// tracker was the one surface in the app with no per-channel effects.

import 'package:comet_beat/core/audio/fx/fx_chain_codec.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

AdvancedTrackerTester _game(WidgetTester tester) =>
    tester.state<State<AdvancedTrackerScreen>>(
      find.byType(AdvancedTrackerScreen),
    ) as AdvancedTrackerTester;

void main() {
  testWidgets('a channel starts with no effects', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    expect(_game(tester).channelFxChain(0), isEmpty);
  });

  testWidgets('a chain set on one channel stays on THAT channel', (
    tester,
  ) async {
    // The property that makes it per-channel rather than per-song: a rack that
    // applied to everything would be a master bus wearing a channel's name.
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    game.setChannelFxChain(1, parseFxChain('lowpass freq=400').chain);
    await tester.pump();

    expect(game.channelFxChain(1).single.type, FxType.lowpass);
    expect(game.channelFxChain(0), isEmpty);
  });

  testWidgets('clearing it leaves the channel dry', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester)
      ..setChannelFxChain(0, parseFxChain('reverb mix=20%').chain);
    await tester.pump();
    expect(game.channelFxChain(0), isNotEmpty);

    game.setChannelFxChain(0, const []);
    await tester.pump();
    expect(game.channelFxChain(0), isEmpty);
  });
}
