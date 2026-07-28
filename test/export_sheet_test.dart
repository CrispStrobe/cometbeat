// WS-X6 — one export door.
//
// The card's premise ("every mode exports differently") was half stale by the
// time I got to it: `showAudioExportSheet` was already shared by eight screens.
// What was actually missing was that audio and notation were two SEPARATE
// doors, and that the project archive appeared in neither — so someone in the
// Audio Editor was offered a WAV and never learned their arrangement could
// leave as MusicXML.
//
// So these tests are about what the door SAYS, not about format handling
// (which is covered by the existing export tests). In particular: an option
// that is unavailable has to explain itself, because a greyed-out row with no
// reason reads as a bug rather than as a fact about the project.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_sources.dart';
import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:comet_beat/shared/music_io/export_sheet.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show
        Clef,
        Measure,
        MultiPartScore,
        NoteDuration,
        NoteElement,
        Pitch,
        Score,
        Step;
import 'package:flutter/material.dart' hide Step;
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

const _quarter = NoteDuration.quarter;

/// A tiny score, so a clip in the timeline genuinely carries notes.
MultiPartScore _score() => MultiPartScore([
      Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement.note(const Pitch(Step.c), _quarter),
            NoteElement.note(const Pitch(Step.e), _quarter),
          ]),
        ],
      ),
    ]);

Future<void> _pumpSheet(WidgetTester tester, List<ExportOption> options) =>
    tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ExportSheetBody(options: options))),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the sheet groups by what you are trying to do', () {
    testWidgets('each kind gets its own heading', (tester) async {
      await _pumpSheet(tester, [
        ExportOption(
          kind: ExportKind.audio,
          label: 'Mix',
          run: () async {},
        ),
        ExportOption(
          kind: ExportKind.project,
          label: 'Project file',
          run: () async {},
        ),
      ]);
      expect(find.text('Sound'), findsOneWidget);
      expect(find.text('Project'), findsOneWidget);
      // …and no heading for a kind this surface cannot produce.
      expect(find.text('Notes'), findsNothing);
      expect(find.text('Share'), findsNothing);
    });

    testWidgets('an empty sheet says so instead of showing nothing',
        (tester) async {
      await _pumpSheet(tester, const []);
      expect(find.textContaining('Nothing to export'), findsOneWidget);
    });

    testWidgets('tapping an option runs it', (tester) async {
      var ran = false;
      await _pumpSheet(tester, [
        ExportOption(
          kind: ExportKind.audio,
          label: 'Mix',
          run: () async => ran = true,
        ),
      ]);
      await tester.tap(find.text('Mix'));
      await tester.pumpAndSettle();
      expect(ran, isTrue);
    });
  });

  group('an unavailable option explains itself', () {
    testWidgets('the reason replaces the detail', (tester) async {
      // The point: greyed out with no explanation reads as broken software.
      // With a reason it reads as a fact about the project, which it is.
      await _pumpSheet(tester, [
        ExportOption(
          kind: ExportKind.symbolic,
          label: 'Notes',
          detail: 'the normal subtitle',
          run: () async {},
          enabled: false,
          disabledReason: 'These clips are audio',
        ),
      ]);
      expect(find.text('These clips are audio'), findsOneWidget);
      expect(find.text('the normal subtitle'), findsNothing);
    });

    testWidgets('a disabled option cannot be run', (tester) async {
      var ran = false;
      await _pumpSheet(tester, [
        ExportOption(
          kind: ExportKind.audio,
          label: 'Stems',
          run: () async => ran = true,
          enabled: false,
          disabledReason: 'No lanes',
        ),
      ]);
      await tester.tap(find.text('Stems'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(ran, isFalse);
    });
  });

  group('the Audio Editor offers everything it can actually make', () {
    Future<DawService> pump(WidgetTester tester) async {
      await pumpGame(
        tester,
        const DawScreen(),
        extraProviders: [ChangeNotifierProvider(create: (_) => DawService())],
      );
      await tester.pump();
      return Provider.of<DawService>(
        tester.element(find.byType(DawScreen)),
        listen: false,
      );
    }

    testWidgets('a project of pure RECORDINGS says why notes are unavailable',
        (tester) async {
      // The honest case, and the one the old single-door UI could not express
      // at all: there is nothing symbolic here, so there is nothing to write.
      // Saying "these clips are audio" is a fact about the project; offering an
      // empty MusicXML would be a lie.
      final daw = await pump(tester);
      daw.addClip(SampleSource(_tone(1000)));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.download));
      await tester.pumpAndSettle();

      expect(find.text('Mix'), findsOneWidget);
      expect(find.text('Project file'), findsOneWidget);
      expect(
        find.textContaining('written as notes'),
        findsOneWidget,
        reason: 'the notes option should explain itself, not just grey out',
      );
    });

    testWidgets('a project with a SCORE clip offers notation', (tester) async {
      // Previously reachable only by converting a clip and leaving for another
      // editor entirely — nothing on this screen said the notes could go out
      // directly.
      final daw = await pump(tester);
      daw.addClip(ScoreSource(_score()));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.download));
      await tester.pumpAndSettle();

      expect(find.textContaining('written as notes'), findsNothing);
      expect(find.textContaining('MusicXML'), findsOneWidget);
    });

    testWidgets('a DRUM clip is symbolic and still cannot be engraved',
        (tester) async {
      // Recorded because it surprised me and it shapes the wording: a drum clip
      // IS symbolic, but the tracker→score bridge returns null for a
      // percussion-only song, so there is still nothing to write. The disabled
      // reason therefore states the OUTCOME ("nothing can be written as notes")
      // rather than claiming the clips are audio, which would be false here.
      final daw = await pump(tester);
      daw.addClip(
        DrumSource(
          DrumRowsPattern({
            Drum.kick: [for (var i = 0; i < kPatternSteps; i++) i % 4 == 0],
          }),
          const LoopTiming(tempoBpm: 120),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.download));
      await tester.pumpAndSettle();
      expect(find.textContaining('written as notes'), findsOneWidget);
    });
  });

  group('the door reaches the other surfaces too', () {
    // The point of finishing this rather than leaving it on one screen: a
    // shared door wired into a single place is exactly the "two separate
    // doors" problem it was built to fix.

    testWidgets('the Tracker groups its five exports by kind', (tester) async {
      // They were five sibling rows in a flat menu, so the difference between
      // "a sound file", "the notes" and "a tracker module" was something you
      // had to already know.
      await pumpGame(tester, const AdvancedTrackerScreen());
      await tester.pump();
      final state = tester.state<State<AdvancedTrackerScreen>>(
        find.byType(AdvancedTrackerScreen),
      );
      unawaited((state as dynamic).debugOpenExportDoor() as Future<void>);
      // Explicit pumps, never pumpAndSettle: these screens run continuous
      // tickers so settling never completes.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Sound'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      // The module export is the format this editor is native to and it sat
      // unremarked between MusicXML and audio.
      expect(find.textContaining('Tracker module'), findsOneWidget);
    });

    testWidgets('Loop Studio offers its SHARE CODE as an export',
        (tester) async {
      // The thing people here actually pass to each other lived under "copy",
      // where nothing suggested it was a way of getting the music out.
      await pumpGame(tester, const LoopMixerScreen());
      await tester.pump();
      final state = tester.state<State<LoopMixerScreen>>(
        find.byType(LoopMixerScreen),
      );
      unawaited((state as dynamic).debugOpenExportDoor() as Future<void>);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Share'), findsOneWidget);
      expect(find.textContaining('share code'), findsOneWidget);
    });

    testWidgets('a drums-only groove says why notation is unavailable',
        (tester) async {
      // Drums are unpitched, so there is no score — the same honest refusal
      // the Audio Editor makes, rather than an empty file.
      await pumpGame(tester, const LoopMixerScreen());
      await tester.pump();
      final game = tester.state<State<LoopMixerScreen>>(
        find.byType(LoopMixerScreen),
      ) as LoopMixerTester;
      game.toggleTrack('drums');
      await tester.pump();

      unawaited((game as dynamic).debugOpenExportDoor() as Future<void>);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('no pitched notes'), findsOneWidget);
    });
  });
}
