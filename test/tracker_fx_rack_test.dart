// test/tracker_fx_rack_test.dart
//
// E1 — the shared FX rack, hosted in the Tracker's channel-effect sheet.
//
// The wiring has to be ADDITIVE: the seven-chip picker is still the quick path
// and a channel that only ever uses it must render through exactly the old
// code, so the tests below check both that the advanced rack works AND that the
// simple path is untouched.
//
// The other thing worth pinning is that "Customise" seeds the chain from what
// the user is CURRENTLY hearing. Starting from silence would make the advanced
// view feel like it threw their sound away.

import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/features/games/composition/tracker_screen.dart';
import 'package:comet_beat/shared/widgets/fx_rack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

/// The Tracker animates continuously (oscilloscope, mascot), so `pumpAndSettle`
/// never returns here — every wait is a bounded pump, matching the existing
/// tracker tests.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<TrackerTester> _open(WidgetTester tester) async {
  await pumpGame(tester, const TrackerScreen());
  await _settle(tester);
  return tester.state<State<TrackerScreen>>(find.byType(TrackerScreen))
      as TrackerTester;
}

/// Opens the channel-effect sheet from its toolbar button.
Future<void> _openFxSheet(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.graphic_eq).first);
  await _settle(tester);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the tester exposes the chain alongside the presets', (t) async {
    final s = await _open(t);
    expect(s.channelFxChain, isEmpty);
    expect(s.channelEffects, isEmpty);
  });

  testWidgets('setting a chain clears the presets, and vice versa', (t) async {
    // The engine enforces this so the two views cannot disagree about what the
    // channel sounds like; the screen must not work around it.
    final s = await _open(t);

    s.setChannelFxChain([defaultFx(FxType.reverb)]);
    await _settle(t);
    expect(s.channelFxChain, hasLength(1));
    expect(s.channelEffects, isEmpty);

    s.setChannelEffects([TrackerChannelEffect.delay]);
    await _settle(t);
    expect(s.channelFxChain, isEmpty);
    expect(s.channelEffects, [TrackerChannelEffect.delay]);
  });

  testWidgets('an empty chain returns the channel to dry', (t) async {
    final s = await _open(t);
    s.setChannelFxChain([defaultFx(FxType.phaser)]);
    await _settle(t);
    s.setChannelFxChain(const []);
    await _settle(t);
    expect(s.channelFxChain, isEmpty);
    expect(s.channelEffects, isEmpty);
  });

  testWidgets('the chain survives switching channels and coming back',
      (t) async {
    final s = await _open(t);
    s.setChannelFxChain([defaultFx(FxType.bitCrush)]);
    await _settle(t);
    final first = s.selectedChannel;

    s.selectChannel(first == 0 ? 1 : 0);
    await _settle(t);
    expect(s.channelFxChain, isEmpty, reason: 'chains are per channel');

    s.selectChannel(first);
    await _settle(t);
    expect(s.channelFxChain, hasLength(1));
    expect(s.channelFxChain.single.type, FxType.bitCrush);
  });

  testWidgets(
      'the sheet shows the rack, and Customise seeds it from the '
      'presets the user is hearing', (t) async {
    final s = await _open(t);
    s.setChannelEffects([TrackerChannelEffect.reverb]);
    await _settle(t);

    await _openFxSheet(t);
    final tile = find.byKey(const ValueKey('tracker-fx-advanced'));
    expect(tile, findsOneWidget, reason: 'the advanced section is missing');
    await t.tap(tile);
    await _settle(t);

    final customise = find.byKey(const ValueKey('tracker-fx-customise'));
    expect(customise, findsOneWidget);
    await t.tap(customise);
    await _settle(t);

    // Seeded from the reverb chip, not from nothing.
    expect(s.channelFxChain, hasLength(1));
    expect(s.channelFxChain.single.type, FxType.reverb);
    expect(find.byType(FxRack), findsOneWidget);
  });
}
