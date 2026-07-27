// C2 — a beat and a groove can go home again.
//
// Score and tracker clips already round-tripped in place from the Audio Editor;
// drum and groove clips could not, at all. They still HOLD their grid and their
// spec — the clip was never a bounce — so the way back is exact retrieval, not a
// conversion: nothing is transcribed and nothing is approximated. These tests
// pin that, and pin the two things a round trip must not quietly change: where
// the clip sits, and what its licence obliges.
//
// The engine half is headless; the UI half checks that the door is actually
// offered, because an accessor no screen calls is not a feature.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_sources.dart';
import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:comet_beat/features/games/drums/drumkit_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

DrumRowsPattern _beat({bool ghost = false}) => DrumRowsPattern(
      {
        Drum.kick: [for (var i = 0; i < kPatternSteps; i++) i % 4 == 0],
        Drum.snare: [for (var i = 0; i < kPatternSteps; i++) i % 8 == 4],
      },
      velocities: ghost
          ? {
              Drum.kick: [
                for (var i = 0; i < kPatternSteps; i++) i == 0 ? 1.0 : 0.5,
              ],
            }
          : null,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the engine can hand a beat back', () {
    test('a drum clip reports its grid and its timing', () {
      final daw = DawService();
      const timing = LoopTiming(tempoBpm: 140, swing: 0.3);
      daw.addClip(DrumSource(_beat(), timing));
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      expect(daw.isDrumClip(track, 0), isTrue);
      expect(daw.isGrooveClip(track, 0), isFalse);
      expect(daw.clipDrumPattern(track, 0)?.rows[Drum.kick]?[0], isTrue);
      // The timing travels WITH the grid: without it a round trip would
      // silently re-time the beat to the Kit's default.
      expect(daw.clipDrumTiming(track, 0)?.tempoBpm, 140);
      expect(daw.clipDrumTiming(track, 0)?.swing, closeTo(0.3, 1e-9));
    });

    test('a groove clip reports its spec', () {
      final daw = DawService();
      const spec = GrooveSpec(swing: 0.25, key: 5);
      daw.addClip(GrooveSource(spec));
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      expect(daw.isGrooveClip(track, 0), isTrue);
      expect(daw.clipGroove(track, 0)?.cacheKey, spec.cacheKey);
    });

    test('other clip kinds report neither', () {
      final daw = DawService();
      daw.addClip(SampleSource(Float64List(8)));
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      expect(daw.isDrumClip(track, 0), isFalse);
      expect(daw.isGrooveClip(track, 0), isFalse);
      expect(daw.clipDrumPattern(track, 0), isNull);
      expect(daw.clipDrumTiming(track, 0), isNull);
      expect(daw.clipGroove(track, 0), isNull);
    });
  });

  group('an edit goes back into the SAME clip', () {
    test('a beat replaces in place, keeping where it sits', () {
      final daw = DawService();
      const timing = LoopTiming(tempoBpm: 100);
      daw.addClip(DrumSource(_beat(), timing));
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      daw.moveClip(track, 0, 2500);
      daw.setClipGain(track, 0, 0.4);
      final source = daw.clipSourceAt(track, 0);

      daw.replaceDrumClipSource(
        source,
        _beat(ghost: true),
        const LoopTiming(tempoBpm: 132, swing: 0.1),
      );

      // Still ONE clip — not a second copy of the same beat on the timeline.
      expect(daw.clipCount, 1);
      expect(daw.clipStartMs(track, 0), 2500);
      expect(daw.clipGain(track, 0), 0.4);
      expect(daw.clipDrumTiming(track, 0)?.tempoBpm, 132);
      // The ghost notes made it back — half of why a beat sounds like itself.
      expect(
        daw.clipDrumPattern(track, 0)?.velocities?[Drum.kick]?[1],
        closeTo(0.5, 1e-9),
      );
    });

    test('a groove replaces in place', () {
      final daw = DawService();
      daw.addClip(GrooveSource(const GrooveSpec(key: 1)));
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      final source = daw.clipSourceAt(track, 0);
      daw.replaceGrooveClipSource(source, const GrooveSpec(key: 7, swing: 0.4));
      expect(daw.clipCount, 1);
      expect(daw.clipGroove(track, 0)?.key, 7);
      expect(daw.clipGroove(track, 0)?.swing, closeTo(0.4, 1e-9));
    });

    test('a licence obligation rides along with the edit', () {
      // Editing borrowed material is an ARRANGEMENT of it, not a new work.
      // Dropping the licence on the way back would launder it.
      final daw = DawService();
      const work =
          LicensedWork(title: 'Borrowed beat', license: 'CC-BY-SA-4.0');
      daw.addClip(
        DrumSource(_beat(), const LoopTiming(tempoBpm: 100)),
        provenance: work,
      );
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      final source = daw.clipSourceAt(track, 0);
      daw.replaceDrumClipSource(
        source,
        _beat(ghost: true),
        const LoopTiming(tempoBpm: 100),
      );
      expect(
        daw.timeline.tracks[track].clips[0].provenance?.license,
        'CC-BY-SA-4.0',
      );
    });

    test('an edit whose clip is gone lands as a new clip, not nowhere', () {
      // The user edited something and pressed Done; losing that because the
      // clip was deleted meanwhile would be the worst possible answer.
      final daw = DawService();
      daw.addClip(DrumSource(_beat(), const LoopTiming(tempoBpm: 100)));
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      final source = daw.clipSourceAt(track, 0);
      daw.removeClip(track, 0);
      expect(daw.clipCount, 0);
      daw.replaceDrumClipSource(
        source,
        _beat(),
        const LoopTiming(tempoBpm: 100),
      );
      expect(daw.clipCount, 1);
    });

    test('the replacement is undoable', () {
      final daw = DawService();
      daw.addClip(GrooveSource(const GrooveSpec(key: 1)));
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      daw.replaceGrooveClipSource(
        daw.clipSourceAt(track, 0),
        const GrooveSpec(key: 9),
      );
      expect(daw.clipGroove(track, 0)?.key, 9);
      daw.undo();
      expect(daw.clipGroove(track, 0)?.key, 1);
    });
  });

  group('the door is actually offered', () {
    // The shared game harness, like daw_screen_test — these editors carry the
    // app bar's sound toggle, so they need the real provider set around them.
    Future<void> pumpDaw(WidgetTester tester) => pumpGame(
          tester,
          const DawScreen(),
          extraProviders: [ChangeNotifierProvider(create: (_) => DawService())],
        );

    DawService serviceOf(WidgetTester tester) => Provider.of<DawService>(
          tester.element(find.byType(DawScreen)),
          listen: false,
        );

    testWidgets('a drum clip opens the Drum Kit', (tester) async {
      await pumpDaw(tester);
      serviceOf(tester)
          .addClip(DrumSource(_beat(), const LoopTiming(tempoBpm: 100)));
      await tester.pumpAndSettle();

      // 🥁 is the drum clip's badge on the timeline (🎛️ is a groove, 🎹 a
      // tracker song) — tapping it opens that clip's inspector.
      await tester.tap(find.text('🥁'));
      await tester.pumpAndSettle();
      expect(find.text('Open in editor'), findsOneWidget);

      await tester.tap(find.text('Open in editor'));
      // Explicit pumps: these editors run continuous tickers, so settling
      // never completes.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(DrumkitScreen), findsOneWidget);
    });

    testWidgets('a groove clip opens the Loop Mixer', (tester) async {
      await pumpDaw(tester);
      serviceOf(tester).addClip(GrooveSource(const GrooveSpec()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('🎛️'));
      await tester.pumpAndSettle();
      expect(find.text('Open in editor'), findsOneWidget);

      await tester.tap(find.text('Open in editor'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(LoopMixerScreen), findsOneWidget);
    });
  });
}
