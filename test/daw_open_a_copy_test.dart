// C3 — crossing modes from the Audio Editor, with the cost named first.
//
// The inspector has two doors and they are NOT the same door:
//
//   "Open in editor"   the clip's OWN model to its OWN editor. Nothing is
//                      converted, so nothing can be lost, and the edit comes
//                      back into the SAME clip (C2 / the earlier round trips).
//   "Open a copy in…"  a different mode's editor. That always costs something,
//                      so it goes through OpenInMenu, which names the cost per
//                      edge and makes a lossy conversion confirm before running.
//
// What these tests pin is the distinction: which clips get the second door, that
// the loss dialog actually gates the conversion, and that a converted document
// opens as a COPY — routing it back into the source clip would overwrite the
// user's original with a degraded version of itself.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_sources.dart';
import 'package:comet_beat/core/audio/daw_timeline.dart'
    show SampleSource, kDawSampleRate;
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/interop/project_bridge.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart'
    show AdvancedTrackerScreen;
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:comet_beat/features/games/composition/multipart_to_tracker.dart'
    show trackerSongFromMultiPart;
import 'package:comet_beat/features/games/composition/tab_workshop_screen.dart'
    show TabWorkshopScreen;
import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart'
    show CompositionWorkshopScreen;
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

const _quarter = NoteDuration.quarter;

MultiPartScore _score() => MultiPartScore([
      Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement.note(const Pitch(Step.c), _quarter),
            NoteElement.note(const Pitch(Step.e), _quarter),
            NoteElement.note(const Pitch(Step.g), _quarter),
          ]),
        ],
      ),
    ]);

/// A tracker song with actual notes in it.
///
/// An EMPTY one is not a valid fixture here: `MultiPartScore` requires at least
/// one part, so the bridge (correctly) reports tracker→score as unsupported for
/// a song with nothing in it, and the menu would show that instead of
/// converting. Using an empty song hid exactly that.
TrackerSong _song() => trackerSongFromMultiPart(_score());

DrumRowsPattern _beat() => DrumRowsPattern({
      Drum.kick: [for (var i = 0; i < kPatternSteps; i++) i % 4 == 0],
    });

Future<void> _pumpDaw(WidgetTester tester) => pumpGame(
      tester,
      const DawScreen(),
      extraProviders: [ChangeNotifierProvider(create: (_) => DawService())],
    );

DawService _service(WidgetTester tester) => Provider.of<DawService>(
      tester.element(find.byType(DawScreen)),
      listen: false,
    );

/// Open the inspector of the only clip on the timeline, by its badge.
Future<void> _openInspector(WidgetTester tester, String badge) async {
  await tester.tap(find.text(badge));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('which clips get the cross-mode door', () {
    testWidgets('engraved music does', (tester) async {
      await _pumpDaw(tester);
      _service(tester).addClip(ScoreSource(_score()));
      await tester.pumpAndSettle();
      await _openInspector(tester, '🎼');
      expect(find.byKey(const ValueKey('open-in')), findsOneWidget);
    });

    testWidgets('a tracker song does', (tester) async {
      await _pumpDaw(tester);
      _service(tester).addClip(TrackerSource(_song()));
      await tester.pumpAndSettle();
      await _openInspector(tester, '🎹');
      expect(find.byKey(const ValueKey('open-in')), findsOneWidget);
    });

    testWidgets('a recording does NOT — audio is not notes', (tester) async {
      // The rule the whole interop matrix rests on: a waveform has no model to
      // convert, and offering a conversion we would have to invent is worse
      // than offering nothing. Transcription stays an explicit feature.
      await _pumpDaw(tester);
      _service(tester).addClip(SampleSource(Float64List(kDawSampleRate * 2)));
      await tester.pumpAndSettle();
      await _openInspector(tester, '🎵');
      expect(find.byKey(const ValueKey('open-in')), findsNothing);
    });

    testWidgets('a beat does not — it still has its own door', (tester) async {
      // A drum grid is not a ProjectBridge document, and the Drum Kit door
      // (C2) already gives it an EXACT way home, which is strictly better than
      // a conversion. Not a gap; a deliberate absence.
      await _pumpDaw(tester);
      _service(tester)
          .addClip(DrumSource(_beat(), const LoopTiming(tempoBpm: 100)));
      await tester.pumpAndSettle();
      await _openInspector(tester, '🥁');
      expect(find.text('Open in editor'), findsOneWidget);
      expect(find.byKey(const ValueKey('open-in')), findsNothing);
    });
  });

  group('the cost is named before the conversion runs', () {
    testWidgets('a lossy target warns, and Cancel means nothing happens',
        (tester) async {
      await _pumpDaw(tester);
      _service(tester).addClip(ScoreSource(_score()));
      await tester.pumpAndSettle();
      await _openInspector(tester, '🎼');

      await tester.tap(find.byKey(const ValueKey('open-in')));
      await tester.pumpAndSettle();
      // Score → Tab has to invent a fingering, so it must confirm.
      await tester.tap(find.byKey(const ValueKey('open-in-tab')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('open-in-loss-dialog')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('open-in-cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(TabWorkshopScreen), findsNothing);
    });

    testWidgets('confirming opens the target editor', (tester) async {
      await _pumpDaw(tester);
      _service(tester).addClip(ScoreSource(_score()));
      await tester.pumpAndSettle();
      await _openInspector(tester, '🎼');

      await tester.tap(find.byKey(const ValueKey('open-in')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-in-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-in-confirm')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(TabWorkshopScreen), findsOneWidget);
    });

    testWidgets('a tracker song can be read as notation', (tester) async {
      await _pumpDaw(tester);
      _service(tester).addClip(TrackerSource(_song()));
      await tester.pumpAndSettle();
      await _openInspector(tester, '🎹');

      await tester.tap(find.byKey(const ValueKey('open-in')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-in-score')));
      await tester.pumpAndSettle();
      // Tracker → Score drops effect columns, so it warns; confirm and go.
      if (find
          .byKey(const ValueKey('open-in-loss-dialog'))
          .evaluate()
          .isNotEmpty) {
        await tester.tap(find.byKey(const ValueKey('open-in-confirm')));
      }
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CompositionWorkshopScreen), findsOneWidget);
    });
  });

  group('the copy is a copy', () {
    testWidgets('converting does not change the clip it came from',
        (tester) async {
      // The load-bearing difference from "Open in editor". A lossy conversion
      // routed back into the source clip would silently replace the user's
      // original with a degraded version of itself.
      await _pumpDaw(tester);
      final service = _service(tester);
      service.addClip(TrackerSource(_song()));
      await tester.pumpAndSettle();
      final track =
          service.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      final before = service.clipSourceAt(track, 0);

      await _openInspector(tester, '🎹');
      await tester.tap(find.byKey(const ValueKey('open-in')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-in-score')));
      await tester.pumpAndSettle();
      if (find
          .byKey(const ValueKey('open-in-loss-dialog'))
          .evaluate()
          .isNotEmpty) {
        await tester.tap(find.byKey(const ValueKey('open-in-confirm')));
      }
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Same clip, same source object — the tracker song is untouched.
      expect(service.clipCount, 1);
      expect(identical(service.clipSourceAt(track, 0), before), isTrue);
      expect(service.isTrackerClip(track, 0), isTrue);
    });
  });

  group('only reachable destinations are offered', () {
    testWidgets('Loop is not offered — the Audio Editor cannot push it',
        (tester) async {
      // OpenInMenu.targets exists precisely so a screen cannot offer a
      // destination it has no route to. The bridge CAN convert to Loop, but a
      // loop document is the sung user track's cells and seeding a groove from
      // them needs the Loop Mixer's own track vocabulary — offering it would
      // convert the user's work and then have nowhere to put it.
      await _pumpDaw(tester);
      _service(tester).addClip(ScoreSource(_score()));
      await tester.pumpAndSettle();
      await _openInspector(tester, '🎼');

      await tester.tap(find.byKey(const ValueKey('open-in')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('open-in-tab')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-in-tracker')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-in-loop')), findsNothing);
    });

    test('the bridge itself still reaches Loop — this is a UI limit', () {
      // Stated as a test so the day the Loop Mixer can be seeded from cells,
      // whoever removes the restriction knows the bridge was never the blocker.
      expect(ProjectBridge.canConvert(AppMode.score, AppMode.loop), isTrue);
      expect(
        ProjectBridge.targetsFrom(AppMode.score),
        contains(AppMode.loop),
      );
    });
  });

  testWidgets('a converted document reaches the editor intact', (tester) async {
    // Not just "a screen opened" — the notes have to arrive. Score → Tracker
    // is the route with the most machinery under it.
    await _pumpDaw(tester);
    _service(tester).addClip(ScoreSource(_score()));
    await tester.pumpAndSettle();
    await _openInspector(tester, '🎼');

    await tester.tap(find.byKey(const ValueKey('open-in')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-in-tracker')));
    await tester.pumpAndSettle();
    if (find
        .byKey(const ValueKey('open-in-loss-dialog'))
        .evaluate()
        .isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('open-in-confirm')));
    }
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final screen = tester.widget<AdvancedTrackerScreen>(
      find.byType(AdvancedTrackerScreen),
    );
    final song = screen.initialSong;
    expect(song, isNotNull);
    // The three notes made the trip.
    final cells = song!.engine.exportCells();
    final sounded = cells.expand((c) => c).where((c) => c.midi != null).length;
    expect(sounded, greaterThanOrEqualTo(3));
  });

  group('open & replace — the in-place twin of the copy door', () {
    testWidgets('score & tracker clips offer it; a recording does not',
        (tester) async {
      await _pumpDaw(tester);
      _service(tester).addClip(TrackerSource(_song()));
      await tester.pumpAndSettle();
      await _openInspector(tester, '🎹');
      expect(find.byKey(const ValueKey('replace-open-in')), findsOneWidget);
      // The copy door and the replace door coexist without a key collision.
      expect(find.byKey(const ValueKey('open-in')), findsOneWidget);
    });

    testWidgets('a recording offers neither door', (tester) async {
      await _pumpDaw(tester);
      _service(tester).addClip(SampleSource(Float64List(kDawSampleRate)));
      await tester.pumpAndSettle();
      await _openInspector(tester, '🎵');
      expect(find.byKey(const ValueKey('replace-open-in')), findsNothing);
    });

    testWidgets('replacing routes the edited document back into the SAME clip',
        (tester) async {
      // The load-bearing difference from the copy door: this REPLACES the
      // source in place. Driven directly through the onReturn mechanism the
      // door wires (replaceScoreClipSource) — the clip changes type, count 1.
      await _pumpDaw(tester);
      final service = _service(tester);
      service.addClip(TrackerSource(_song()));
      await tester.pumpAndSettle();
      final track =
          service.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      expect(service.isTrackerClip(track, 0), isTrue);

      final source = service.clipSourceAt(track, 0);
      service.replaceScoreClipSource(source, _score());
      await tester.pump();

      // Same slot, now a score clip — the mix continues on it, not a fork.
      expect(service.clipCount, 1);
      expect(service.clipSourceAt(track, 0), isA<ScoreSource>());
      expect(service.isTrackerClip(track, 0), isFalse);
    });

    testWidgets('confirming a lossy replace opens the target editor',
        (tester) async {
      await _pumpDaw(tester);
      _service(tester).addClip(TrackerSource(_song()));
      await tester.pumpAndSettle();
      await _openInspector(tester, '🎹');

      await tester.tap(find.byKey(const ValueKey('replace-open-in')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('replace-open-in-score')));
      await tester.pumpAndSettle();
      if (find
          .byKey(const ValueKey('replace-open-in-loss-dialog'))
          .evaluate()
          .isNotEmpty) {
        await tester.tap(find.byKey(const ValueKey('replace-open-in-confirm')));
      }
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CompositionWorkshopScreen), findsOneWidget);
    });
  });
}
