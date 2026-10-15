import 'package:comet_beat/core/audio/daw_sources.dart' show GrooveSource;
import 'package:comet_beat/core/audio/loop_engine.dart' show GrooveSpec;
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/composition/arrangement_recorder.dart';
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

/// WS-W7 — a live Loop Studio session, recorded as an arrangement.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ArrangementRecorder', () {
    const a = GrooveSpec(enabled: {'drums'});
    const b = GrooveSpec(enabled: {'drums', 'bass'});

    test('merges consecutive identical passes, keeps changes in order', () {
      final r = ArrangementRecorder()..start();
      for (final spec in [a, a, b, a]) {
        r.passEnded(spec, 2000);
      }
      expect([for (final run in r.runs) run.passes], [2, 1, 1]);
      expect(r.durationMs, 8000);
    });

    test('a tempo change is a new run even for the same mix', () {
      final r = ArrangementRecorder()
        ..start()
        ..passEnded(a, 2000)
        ..passEnded(a, 1500);
      expect(r.runs, hasLength(2));
    });

    test('nothing is logged unless recording; start discards the old take', () {
      final r = ArrangementRecorder()..passEnded(a, 2000);
      expect(r.isEmpty, isTrue);
      r
        ..start()
        ..passEnded(a, 2000)
        ..stop()
        ..passEnded(b, 2000);
      expect(r.runs.single.passes, 1, reason: 'stopped: kept, not extended');
      r.start();
      expect(r.isEmpty, isTrue);
    });
  });

  test('addArrangement lays clips end to end on a new track, one undo', () {
    final daw = DawService();
    final before = daw.timeline.tracks.length;
    final source = GrooveSource(const GrooveSpec(enabled: {'drums'}));
    final track = daw.addArrangement(
      [
        (source: source, durationMs: 2000),
        (source: source, durationMs: 2000),
        (source: source, durationMs: 1500),
      ],
      name: 'Session',
    );
    final clips = daw.timeline.tracks[track].clips;
    expect([for (final c in clips) c.startMs], [0, 2000, 4000]);
    expect(daw.timeline.tracks[track].name, 'Session');
    daw.undo();
    expect(daw.timeline.tracks.length, before);
  });

  testWidgets('Loop Studio records its passes and sends them as clips',
      (tester) async {
    final daw = DawService();
    await pumpGame(
      tester,
      const LoopMixerScreen(),
      extraProviders: [ChangeNotifierProvider<DawService>.value(value: daw)],
    );
    final game =
        tester.state<State<LoopMixerScreen>>(find.byType(LoopMixerScreen))
            as LoopMixerTester;
    game
      ..toggleTrack('drums')
      ..startArrangementRecording();
    await tester.pump();
    game
      ..debugLoopWrap()
      ..debugLoopWrap();
    game.toggleTrack('bass');
    await tester.pump();
    game.debugLoopWrap();
    expect(game.recordedPasses, 3);

    final before = daw.timeline.tracks.length;
    game.sendArrangementToDaw();
    await tester.pump();
    final lane = daw.timeline.tracks[before];
    expect(lane.clips, hasLength(3));
    for (var i = 1; i < lane.clips.length; i++) {
      expect(lane.clips[i].startMs, greaterThan(lane.clips[i - 1].startMs));
    }
    game.toggleTrack('drums');
    game.toggleTrack('bass');
    await tester.pump(const Duration(milliseconds: 100));
  });
}
