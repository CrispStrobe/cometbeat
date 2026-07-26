// test/loop_master_fx_test.dart
//
// E3 — the shared FX rack on the Loop Mixer's master bus.
//
// The two LoopSend presets stay as the quick path; this is everything else. The
// engine already guarantees the chain takes precedence over the preset and that
// it runs INSIDE the two-copy seam warm-up (so tails carry across the loop
// wrap) — what the screen has to get right is narrower: the chain reaches the
// engine, an empty one returns the mix to dry, and setting it invalidates the
// rendered WAV so the change is actually heard.

import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/core/audio/loop_engine.dart' show LoopSend;
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:comet_beat/shared/widgets/fx_rack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

/// The Loop Mixer animates while a groove plays, so waits are bounded pumps.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<LoopMixerTester> _open(WidgetTester tester) async {
  await pumpGame(tester, const LoopMixerScreen());
  await _settle(tester);
  return tester.state<State<LoopMixerScreen>>(find.byType(LoopMixerScreen))
      as LoopMixerTester;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the master bus starts with no chain, so nothing changes',
      (t) async {
    final s = await _open(t);
    expect(s.masterFxChain, isEmpty);
    expect(s.send, LoopSend.none);
  });

  testWidgets('a chain set through the screen reaches the engine', (t) async {
    final s = await _open(t);
    s.setMasterFxChain([defaultFx(FxType.bitCrush)]);
    await _settle(t);
    expect(s.masterFxChain, hasLength(1));
    expect(s.masterFxChain.single.type, FxType.bitCrush);
  });

  testWidgets('an empty chain returns the mix to dry', (t) async {
    final s = await _open(t);
    s.setMasterFxChain([defaultFx(FxType.reverb)]);
    await _settle(t);
    s.setMasterFxChain(const []);
    await _settle(t);
    expect(s.masterFxChain, isEmpty);
  });

  testWidgets('the chain and the legacy send coexist, chain winning',
      (t) async {
    // The engine gives the chain precedence; the screen must not fight that by
    // clearing one when the other is set — a user may want the preset back.
    final s = await _open(t);
    s.setSend(LoopSend.reverb);
    await _settle(t);
    s.setMasterFxChain([defaultFx(FxType.lowpass)]);
    await _settle(t);

    expect(s.send, LoopSend.reverb, reason: 'the preset should be remembered');
    expect(s.masterFxChain, hasLength(1));
  });

  testWidgets('the menu opens a sheet hosting the rack', (t) async {
    await _open(t);
    await t.tap(find.byIcon(Icons.more_vert).last);
    await _settle(t);

    final entry = find.text('Master effects');
    await t.ensureVisible(entry);
    await _settle(t);
    await t.tap(entry);
    await _settle(t);

    expect(find.byKey(const ValueKey('loop-master-fx')), findsOneWidget);
    expect(find.byType(FxRack), findsOneWidget);
  });

  testWidgets('adding an effect from the sheet reaches the engine', (t) async {
    final s = await _open(t);
    await t.tap(find.byIcon(Icons.more_vert).last);
    await _settle(t);
    final entry = find.text('Master effects');
    await t.ensureVisible(entry);
    await _settle(t);
    await t.tap(entry);
    await _settle(t);

    await t.tap(find.byKey(const ValueKey('fx-add')));
    await _settle(t);
    await t.tap(find.text('Gain').last);
    await _settle(t);

    expect(s.masterFxChain, hasLength(1));
    expect(s.masterFxChain.single.type, FxType.gain);
  });
}
