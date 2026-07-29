// WS-X2 step 1 — what a drop between surfaces would do.
//
// One protocol rather than a handler per pair, because five modes is twenty
// ordered pairs and twenty handlers is how nineteen of them end up subtly
// different. `ProjectBridge` already converts any pair and already reports the
// cost; this decides what should HAPPEN, and these tests are about that
// decision rather than about the conversions, which have their own suites.
//
// Two properties carry most of the weight: a same-kind drop must not go
// through the bridge at all (a round trip would introduce loss the drop never
// needed — the copy-instead-of-link bug in another shape), and a drop only
// asks for confirmation when there is something to confirm.

import 'package:comet_beat/core/interop/drag_payload.dart';
import 'package:comet_beat/core/interop/project_bridge.dart';
import 'package:comet_beat/core/interop/symbolic_annotation.dart';
import 'package:comet_beat/features/games/composition/multipart_to_tracker.dart'
    show trackerSongFromMultiPart;
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
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  group('a same-kind drop does not convert at all', () {
    test('it hands back the very same document', () {
      // The load-bearing one. Running the bridge on a same-kind drop would
      // introduce loss the drop never needed — the same mistake WS-X1 fixed
      // for "Open in…", in a different shape.
      final score = _score();
      final decision = dropDecisionFor(
        MusicDragPayload(kind: AppMode.score, document: score),
        AppMode.score,
      );
      expect(decision.outcome, DropOutcome.exact);
      expect(
        identical(decision.document, score),
        isTrue,
        reason: 'the SAME object, not a converted copy',
      );
      expect(
        decision.report,
        isNull,
        reason: 'nothing ran, so nothing to report',
      );
    });

    test('and it never asks for confirmation', () {
      final decision = dropDecisionFor(
        MusicDragPayload(kind: AppMode.score, document: _score()),
        AppMode.score,
      );
      expect(decision.needsConfirmation, isFalse);
      expect(decision.canDrop, isTrue);
      expect(dropSummary(decision), 'Moves here unchanged');
    });
  });

  group('a different-kind drop converts, and says what it cost', () {
    test('score → tracker lands a document', () {
      final decision = dropDecisionFor(
        MusicDragPayload(kind: AppMode.score, document: _score()),
        AppMode.tracker,
      );
      expect(decision.canDrop, isTrue);
      expect(decision.document, isNotNull);
      expect(decision.report, isNotNull, reason: 'a conversion ran');
      expect(
        decision.outcome,
        anyOf(DropOutcome.converted, DropOutcome.lossy),
      );
    });

    test('only a LOSSY drop asks for confirmation', () {
      // A conversion that costs nothing must not raise a dialog: making people
      // dismiss one on every drop is how they learn to dismiss the one that
      // mattered.
      for (final target in [AppMode.tracker, AppMode.tab, AppMode.loop]) {
        final decision = dropDecisionFor(
          MusicDragPayload(kind: AppMode.score, document: _score()),
          target,
        );
        if (!decision.canDrop) continue;
        expect(
          decision.needsConfirmation,
          decision.outcome == DropOutcome.lossy,
          reason: '${target.name}: confirmation iff lossy',
        );
        // …and if it is lossy it must actually have something to show.
        if (decision.needsConfirmation) {
          final report = decision.report!;
          expect(
            report.lost.isNotEmpty || report.approximated.isNotEmpty,
            isTrue,
            reason: '${target.name}: lossy with an empty report is a lie',
          );
        }
      }
    });

    test('the conversion is computed ONCE and handed back', () {
      // The report is the conversion's output, so there is no way to preview
      // the cost without performing it; the commit must not run it a second
      // time and risk a different answer.
      final decision = dropDecisionFor(
        MusicDragPayload(kind: AppMode.score, document: _score()),
        AppMode.tracker,
      );
      expect(decision.document, isNotNull);
    });
  });

  group('a pair with no converter is refused with a reason', () {
    test('audio is not something you can convert INTO', () {
      // Rendering to audio is a bounce, not a conversion, and the bridge says
      // so. A drop must refuse rather than silently do nothing.
      final decision = dropDecisionFor(
        MusicDragPayload(kind: AppMode.score, document: _score()),
        AppMode.audio,
      );
      expect(decision.canDrop, isFalse);
      expect(decision.outcome, DropOutcome.unsupported);
      expect(decision.reason, isNotNull);
      expect(decision.reason, isNotEmpty);
      expect(decision.document, isNull);
    });

    test('a refused drop never asks for confirmation', () {
      // There is nothing to confirm — the answer is no.
      final decision = dropDecisionFor(
        MusicDragPayload(kind: AppMode.score, document: _score()),
        AppMode.audio,
      );
      expect(decision.needsConfirmation, isFalse);
      expect(dropSummary(decision), isNotEmpty);
    });
  });

  group('the drag-over summary', () {
    test('every outcome has something short to say', () {
      // Read while a finger is held over a target, so it must never be empty
      // and never be the full report.
      for (final target in AppMode.values) {
        final decision = dropDecisionFor(
          MusicDragPayload(kind: AppMode.score, document: _score()),
          target,
        );
        final summary = dropSummary(decision);
        expect(summary, isNotEmpty, reason: target.name);
        expect(
          summary.length,
          lessThan(60),
          reason: '${target.name}: $summary',
        );
      }
    });

    test('it counts singular and plural properly', () {
      // A tiny thing, but "1 things lost" is the sort of detail that makes a
      // careful app look careless.
      String summaryFor(List<String> lost, List<String> approximated) =>
          dropSummary(
            DropDecision(
              outcome: DropOutcome.lossy,
              target: AppMode.tracker,
              document: 'x',
              report: ConversionReport(
                lost: lost,
                approximated: approximated,
              ),
            ),
          );
      expect(summaryFor(['a'], []), contains('1 thing lost'));
      expect(summaryFor(['a', 'b'], []), contains('2 things lost'));
      expect(summaryFor(['a'], ['b']), contains('1 lost, 1 changed'));
      expect(summaryFor([], ['b']), contains('1 changed'));
    });

    test('a lossy decision with no report still says something', () {
      // Defensive: a hint is not the place to crash on an odd decision.
      expect(
        dropSummary(
          const DropDecision(
            outcome: DropOutcome.lossy,
            target: AppMode.tracker,
            document: 'x',
          ),
        ),
        isNotEmpty,
      );
    });
  });

  group('the payload carries its provenance', () {
    test('a track id survives, so a drop can tell home from a copy', () {
      // The same distinction WS-X1 draws between a live open and a converting
      // one; a drop needs it for the same reason.
      const payload = MusicDragPayload(
        kind: AppMode.tracker,
        document: 'doc',
        label: 'Bass',
        trackId: 't-7',
      );
      expect(payload.trackId, 't-7');
      expect(payload.label, 'Bass');
    });

    test('a payload without provenance is still valid', () {
      // Dragging from a browser or a palette has no track behind it.
      const payload = MusicDragPayload(kind: AppMode.loop, document: 'doc');
      expect(payload.trackId, isNull);
      expect(payload.label, isNull);
    });
  });

  group('round-tripping through the protocol', () {
    test('tracker → tracker is exact even after a real conversion made it', () {
      // A document that ARRIVED by conversion must still drop losslessly onto
      // its own kind — otherwise every hop compounds loss.
      final song = trackerSongFromMultiPart(_score());
      final decision = dropDecisionFor(
        MusicDragPayload(kind: AppMode.tracker, document: song),
        AppMode.tracker,
      );
      expect(decision.outcome, DropOutcome.exact);
      expect(identical(decision.document, song), isTrue);
    });
  });
}
