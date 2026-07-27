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
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart'
    show AdvancedTrackerScreen;
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart'
    show LoopMixerScreen;
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

    testWidgets('a beat now gets the cross-mode door too (via drum→tracker)',
        (tester) async {
      // Maintainer directive (reverses the earlier deliberate absence): a drum
      // grid has no ProjectBridge document of its own, but it reads LOSSLESSLY
      // as a percussion tracker song, so it earns the cross-mode door as well.
      // Its exact Drum Kit "Open in editor" door stays too (strictly better when
      // you just want the beat back).
      await _pumpDaw(tester);
      _service(tester)
          .addClip(DrumSource(_beat(), const LoopTiming(tempoBpm: 100)));
      await tester.pumpAndSettle();
      await _openInspector(tester, '🥁');
      expect(find.text('Open in editor'), findsOneWidget);
      expect(find.byKey(const ValueKey('open-in')), findsOneWidget);
    });

    testWidgets('a groove gets it too (via grooveParts→score)', (tester) async {
      // A groove with a pitched track engraves to a score, so it earns the
      // cross-mode door; a purely-percussive groove would not (nothing to
      // engrave) — that's the grooveParts-null case.
      await _pumpDaw(tester);
      _service(tester)
          .addClip(GrooveSource(const GrooveSpec(enabled: {'melody'})));
      await tester.pumpAndSettle();
      await _openInspector(tester, '🎛️');
      expect(find.text('Open in editor'), findsOneWidget);
      expect(find.byKey(const ValueKey('open-in')), findsOneWidget);
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

  group('all four other modes are offered', () {
    testWidgets('Loop is now offered too (seeds the user track from cells)',
        (tester) async {
      // The Loop Mixer is seeded from the converted cells via a GrooveSpec whose
      // 'voice' track holds them — so the once-dropped Loop target is now live.
      await _pumpDaw(tester);
      _service(tester).addClip(ScoreSource(_score()));
      await tester.pumpAndSettle();
      await _openInspector(tester, '🎼');

      await tester.tap(find.byKey(const ValueKey('open-in')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('open-in-tab')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-in-tracker')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-in-loop')), findsOneWidget);
    });

    testWidgets('picking Loop opens the Loop Mixer', (tester) async {
      await _pumpDaw(tester);
      _service(tester).addClip(ScoreSource(_score()));
      await tester.pumpAndSettle();
      await _openInspector(tester, '🎼');

      await tester.tap(find.byKey(const ValueKey('open-in')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-in-loop')));
      await tester.pumpAndSettle();
      // Score → Loop snaps to the eighth grid, so it warns; confirm and go.
      if (find
          .byKey(const ValueKey('open-in-loss-dialog'))
          .evaluate()
          .isNotEmpty) {
        await tester.tap(find.byKey(const ValueKey('open-in-confirm')));
      }
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(LoopMixerScreen), findsOneWidget);
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
