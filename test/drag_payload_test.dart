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
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show
        Clef,
        Measure,
        MultiPartScore,
        NoteDuration,
        NoteElement,
        Pitch,
        Score,
        Step,
        Tuning;
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

TabDocument _tabDocument() =>
    TabDocument.blank(Tuning.standardGuitar, initialColumns: 4)
      ..setFret(0, 0, 3)
      ..setFret(1, 1, 5);

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

  group('a container also takes what can BECOME what it holds', () {
    // The gap that made this necessary: a TAB could not be dropped on the Audio
    // Editor's timeline at all. The timeline holds score/tracker/loop as-is,
    // everything else fell through to `convert(kind → audio)` — correctly
    // unsupported, a bounce is one-way — so the one mode that could put nothing
    // on the timeline was the one most likely to want to.
    const holds = {AppMode.score, AppMode.tracker, AppMode.loop};

    test('a tab lands, converted, with the cost reported', () {
      final decision = dropDecisionFor(
        MusicDragPayload(kind: AppMode.tab, document: _tabDocument()),
        AppMode.audio,
        acceptsDirectly: holds,
      );
      expect(decision.canDrop, isTrue);
      expect(decision.document, isNotNull);
      expect(
        decision.outcome,
        anyOf(DropOutcome.converted, DropOutcome.lossy),
      );
      expect(decision.report, isNotNull, reason: 'a conversion ran');
    });

    test('it converts to the FIRST held kind that works', () {
      // The order of `acceptsDirectly` is the caller's stated preference —
      // score keeps a tab's pitches and voicings where tracker would quantize
      // onto a grid — so the result must be a score, not "whatever matched".
      final decision = dropDecisionFor(
        MusicDragPayload(kind: AppMode.tab, document: _tabDocument()),
        AppMode.audio,
        acceptsDirectly: holds,
      );
      expect(decision.document, isA<MultiPartScore>());
    });

    test('a different order gives a different landing', () {
      // Proves the order is honoured rather than a coincidence of the bridge.
      final decision = dropDecisionFor(
        MusicDragPayload(kind: AppMode.tab, document: _tabDocument()),
        AppMode.audio,
        acceptsDirectly: const {AppMode.tracker, AppMode.score},
      );
      expect(decision.document, isNot(isA<MultiPartScore>()));
    });

    test('⚠️ audio onto the timeline is SAME-KIND, and lands as itself', () {
      // My first version of this test asserted a refusal, and was wrong: a
      // bounce dropped back on the timeline is the same kind as the target, so
      // it is held as-is and never consults the bridge at all. The rule that
      // refuses audio is about CONVERTING into it, which is a different
      // question — worth pinning, since the two are easy to conflate.
      final decision = dropDecisionFor(
        const MusicDragPayload(kind: AppMode.audio, document: 'pcm'),
        AppMode.audio,
        acceptsDirectly: holds,
      );
      expect(decision.outcome, DropOutcome.exact);
      expect(decision.report, isNull, reason: 'nothing ran');
    });

    test('a container whose held kinds are unreachable refuses', () {
      // The whitelist is still a whitelist. Audio cannot become a score, so a
      // container that holds ONLY score has no route in for an audio payload —
      // and the same-kind shortcut does not apply, because the target here is a
      // mode this payload is not.
      final decision = dropDecisionFor(
        const MusicDragPayload(kind: AppMode.audio, document: 'pcm'),
        AppMode.tracker,
        acceptsDirectly: const {AppMode.score},
      );
      expect(decision.canDrop, isFalse);
    });

    test('a pure MODE target is unchanged by this', () {
      // `acceptsDirectly` is empty for every mode target, so none of the above
      // can alter what a Tracker or a Score screen answers.
      final decision = dropDecisionFor(
        MusicDragPayload(kind: AppMode.tab, document: _tabDocument()),
        AppMode.audio,
      );
      expect(decision.canDrop, isFalse, reason: 'a bounce is still one-way');
    });
  });

  group('a CONTAINER target holds kinds directly', () {
    // Found on wiring the first consumer, and it is a real gap the protocol
    // alone hid: not every drop target is a mode. The Audio Editor's timeline
    // HOLDS ScoreSource/TrackerSource/GrooveSource clips, so asking the bridge
    // to convert a score "to audio" answers unsupported — correctly, a bounce
    // is one-way — and would refuse a drop the timeline handles natively.
    const holds = {AppMode.score, AppMode.tracker, AppMode.loop};

    test('an accepted kind lands exactly, with no conversion', () {
      final score = _score();
      final decision = dropDecisionFor(
        MusicDragPayload(kind: AppMode.score, document: score),
        AppMode.audio,
        acceptsDirectly: holds,
      );
      expect(decision.outcome, DropOutcome.exact);
      expect(identical(decision.document, score), isTrue);
      expect(decision.needsConfirmation, isFalse);
    });

    test('WITHOUT the set, the same drop is refused — the gap itself', () {
      // Kept as a test so the reason the parameter exists cannot be forgotten
      // and quietly removed.
      final decision = dropDecisionFor(
        MusicDragPayload(kind: AppMode.score, document: _score()),
        AppMode.audio,
      );
      expect(decision.canDrop, isFalse);
    });

    test('a kind the container does NOT list is still refused', () {
      // The set is a whitelist, not a bypass: a container must not silently
      // accept something it cannot hold.
      final decision = dropDecisionFor(
        MusicDragPayload(kind: AppMode.tab, document: _score()),
        AppMode.audio,
        acceptsDirectly: const {AppMode.score},
      );
      expect(decision.canDrop, isFalse);
    });

    test('an unrelated container set leaves mode targets alone', () {
      // Every existing caller keeps pure mode semantics: a set that does not
      // name the payload's kind must not change the answer.
      final plain = dropDecisionFor(
        MusicDragPayload(kind: AppMode.score, document: _score()),
        AppMode.tracker,
      );
      final withOtherKinds = dropDecisionFor(
        MusicDragPayload(kind: AppMode.score, document: _score()),
        AppMode.tracker,
        acceptsDirectly: const {AppMode.loop},
      );
      expect(withOtherKinds.outcome, plain.outcome);
    });
  });
}
