// WS-A3 — the Audio Editor's keyboard.
//
// "Four shortcuts today, on a surface that lives on shortcuts." These are the
// verbs a timeline is actually driven by, resolved through the shared keymap so
// a rebinding made in the Tracker applies here too.
//
// The property most of these tests are really about: each shortcut acts on the
// SELECTION and does nothing without one. A timeline shortcut that guesses
// which clip you meant is worse than one that does nothing, because the guess
// is silent and the arrangement is already wrong by the time you notice.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:comet_beat/shared/keymap/intents.dart';
import 'package:comet_beat/shared/keymap/keymap.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

Float64List _tone(double ms) {
  final n = (ms * kDawSampleRate / 1000).round();
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = 0.4 * math.sin(2 * math.pi * 220 * i / kDawSampleRate);
  }
  return out;
}

Future<DawService> _pump(WidgetTester tester) async {
  await pumpGame(
    tester,
    const DawScreen(),
    extraProviders: [ChangeNotifierProvider(create: (_) => DawService())],
  );
  await tester.pump();
  // Autofocus loses to the route's focus scope in the test binding — claim the
  // node or every press below is silently swallowed.
  tester
      .widgetList<Focus>(find.byType(Focus))
      .firstWhere((f) => f.autofocus && f.onKeyEvent != null)
      .focusNode!
      .requestFocus();
  await tester.pump();
  return Provider.of<DawService>(
    tester.element(find.byType(DawScreen)),
    listen: false,
  );
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool ctrl = false,
}) async {
  if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

/// Select the clip through the screen's own selection, the way a tap does.
void _select(WidgetTester tester, int track, int index) {
  final state = tester.state(find.byType(DawScreen)) as DawTester;
  state.selectClip(track, index);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('nudge', () {
    testWidgets('the comma/period pair moves the selected clip',
        (tester) async {
      final daw = await _pump(tester);
      daw.addClip(SampleSource(_tone(1000)));
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      daw.moveClip(track, 0, 1000);
      daw.endCoalescedEdit();
      await tester.pump();
      _select(tester, track, 0);
      await tester.pump();

      final before = daw.clipStartMs(track, 0);
      await _press(tester, LogicalKeyboardKey.period);
      expect(daw.clipStartMs(track, 0), greaterThan(before));

      await _press(tester, LogicalKeyboardKey.comma);
      expect(daw.clipStartMs(track, 0), closeTo(before, 0.01));
    });

    testWidgets('with NOTHING selected it does nothing', (tester) async {
      // The property that matters across all of these: a timeline shortcut
      // that guesses which clip you meant is worse than one that refuses.
      final daw = await _pump(tester);
      daw.addClip(SampleSource(_tone(1000)));
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      daw.moveClip(track, 0, 1000);
      daw.endCoalescedEdit();
      await tester.pump();

      await _press(tester, LogicalKeyboardKey.period);
      expect(daw.clipStartMs(track, 0), 1000);
    });
  });

  group('split at the playhead', () {
    testWidgets('Ctrl+S splits the selected clip', (tester) async {
      final daw = await _pump(tester);
      daw.addClip(SampleSource(_tone(2000)));
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      daw.moveClip(track, 0, 0);
      daw.endCoalescedEdit();
      await tester.pump();

      final state = tester.state(find.byType(DawScreen)) as DawTester;
      state.seekTo(1000);
      _select(tester, track, 0);
      await tester.pump();

      expect(daw.timeline.tracks[track].clips, hasLength(1));
      await _press(tester, LogicalKeyboardKey.keyS, ctrl: true);
      expect(daw.timeline.tracks[track].clips, hasLength(2));
    });

    testWidgets('it does nothing when the playhead is outside the clip',
        (tester) async {
      final daw = await _pump(tester);
      daw.addClip(SampleSource(_tone(1000)));
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      daw.moveClip(track, 0, 0);
      daw.endCoalescedEdit();
      await tester.pump();

      final state = tester.state(find.byType(DawScreen)) as DawTester;
      state.seekTo(8000); // well past the end
      _select(tester, track, 0);
      await tester.pump();

      await _press(tester, LogicalKeyboardKey.keyS, ctrl: true);
      expect(daw.timeline.tracks[track].clips, hasLength(1));
    });
  });

  group('markers', () {
    testWidgets('the bracket keys jump the playhead between markers',
        (tester) async {
      final daw = await _pump(tester);
      daw.addClip(SampleSource(_tone(1000)));
      daw.addMarker(2000, 'verse');
      daw.addMarker(5000, 'chorus');
      await tester.pump();

      final state = tester.state(find.byType(DawScreen)) as DawTester;
      state.seekTo(3000);
      await tester.pump();

      await _press(tester, LogicalKeyboardKey.bracketRight);
      expect(state.playheadMs, 5000);

      await _press(tester, LogicalKeyboardKey.bracketLeft);
      expect(state.playheadMs, 2000);
    });

    testWidgets('past the last marker it stays put', (tester) async {
      final daw = await _pump(tester);
      daw.addClip(SampleSource(_tone(1000)));
      daw.addMarker(1000, 'only');
      await tester.pump();

      final state = tester.state(find.byType(DawScreen)) as DawTester;
      state.seekTo(6000);
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.bracketRight);
      expect(state.playheadMs, 6000);
    });
  });

  group('mute and solo', () {
    testWidgets('M mutes the lane the selection is on', (tester) async {
      final daw = await _pump(tester);
      daw.addClip(SampleSource(_tone(1000)));
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      await tester.pump();
      _select(tester, track, 0);
      await tester.pump();

      expect(daw.timeline.tracks[track].muted, isFalse);
      await _press(tester, LogicalKeyboardKey.keyM);
      expect(daw.timeline.tracks[track].muted, isTrue);
      await _press(tester, LogicalKeyboardKey.keyM);
      expect(daw.timeline.tracks[track].muted, isFalse);
    });

    testWidgets('S solos it', (tester) async {
      final daw = await _pump(tester);
      daw.addClip(SampleSource(_tone(1000)));
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      await tester.pump();
      _select(tester, track, 0);
      await tester.pump();

      await _press(tester, LogicalKeyboardKey.keyS);
      expect(daw.timeline.tracks[track].soloed, isTrue);
    });

    testWidgets('a selection spanning two lanes is AMBIGUOUS and does nothing',
        (tester) async {
      // Mute is per-lane, so a selection across two of them has no single
      // answer. Picking one would be a coin toss the user cannot see.
      final daw = await _pump(tester);
      daw.addClip(SampleSource(_tone(1000)));
      daw.addClip(SampleSource(_tone(1000)), track: 1);
      await tester.pump();
      _select(tester, 0, 0);
      _select(tester, 1, 0);
      await tester.pump();

      await _press(tester, LogicalKeyboardKey.keyM);
      expect(daw.timeline.tracks[0].muted, isFalse);
      expect(daw.timeline.tracks[1].muted, isFalse);
    });
  });

  group('the shared table', () {
    test('every intent the screen declares is actually bound', () {
      // A declared-but-unbound intent shows up in the keymap sheet with no key
      // beside it, which reads as a broken reference.
      final map = Keymap();
      for (final intent in kDawIntents) {
        expect(map.chordsFor(intent), isNotEmpty, reason: intent.name);
      }
    });

    test('the screen declares every intent it handles', () {
      // The sheet is filtered by kDawIntents, so a handled-but-undeclared
      // intent is a shortcut that works and is documented nowhere.
      expect(kDawIntents, contains(AppIntent.clipSplit));
      expect(kDawIntents, contains(AppIntent.nudgeLeft));
      expect(kDawIntents, contains(AppIntent.markerNext));
      expect(kDawIntents, contains(AppIntent.toggleSolo));
    });
  });
}
