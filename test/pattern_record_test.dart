// WS-T7 — the decisions a live record pass makes.
//
// These are unit tests rather than screen tests on purpose: the Tracker's
// playhead Ticker never stops, so `pumpAndSettle` hangs on it and anything
// timing-related is painful to assert through the widget. The precedent is
// `tracker_follow_test.dart`, which tests the pure `followScrollOffset` after
// the widget-level version proved flaky and silently vacuous.

import 'package:comet_beat/core/audio/pattern_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('which row a played note lands on', () {
    test('unquantized, it is the row you were on', () {
      expect(
        recordRow(
          row: 5,
          phase: 0.9,
          quantize: false,
          stepsPerBeat: 4,
          totalRows: 16,
        ),
        5,
        reason:
            'late in row 5 is still row 5 — that is what playing feels like',
      );
    });

    test('quantized, a note played slightly LATE snaps back to the beat', () {
      // The bug the phase exists to prevent: without it, a note played a hair
      // after the beat quantizes from the row it has already entered, and a
      // performance that drags slightly comes out a whole row behind.
      expect(
        recordRow(
          row: 4,
          phase: 0.1,
          quantize: true,
          stepsPerBeat: 4,
          totalRows: 16,
        ),
        4,
      );
    });

    test('quantized, a note played slightly EARLY snaps forward', () {
      expect(
        recordRow(
          row: 3,
          phase: 0.9,
          quantize: true,
          stepsPerBeat: 4,
          totalRows: 16,
        ),
        4,
        reason: 'row 3 at 90% is nearly row 4, and row 4 is the beat',
      );
    });

    test('it wraps rather than falling off the end of the pattern', () {
      // A note played just before the loop point belongs to the downbeat you
      // were aiming at, which is row 0 of the next pass.
      expect(
        recordRow(
          row: 15,
          phase: 0.9,
          quantize: true,
          stepsPerBeat: 4,
          totalRows: 16,
        ),
        0,
      );
    });
  });

  group('a chord spreads across channels', () {
    test('three notes land on three consecutive channels, lowest first', () {
      // The old path wrote every note to the cursor channel, so a triad became
      // one cell and two notes vanished.
      final notes = allocateChord(
        notes: [67, 60, 64],
        row: 4,
        startChannel: 1,
        channelCount: 8,
      );
      expect(notes, [
        const RecordedNote(channel: 1, row: 4, midi: 60),
        const RecordedNote(channel: 2, row: 4, midi: 64),
        const RecordedNote(channel: 3, row: 4, midi: 67),
      ]);
    });

    test('a single note stays exactly where the player was', () {
      // The common case must not move: a melody recorded on channel 3 stays on
      // channel 3.
      expect(
        allocateChord(
          notes: [60],
          row: 0,
          startChannel: 3,
          channelCount: 8,
        ),
        [const RecordedNote(channel: 3, row: 0, midi: 60)],
      );
    });

    test('notes past the last channel are DROPPED, not wrapped', () {
      // Wrapping onto channel 0 would overwrite the bottom of the same chord
      // with its own top notes — which looks exactly like the bug this fixes.
      final notes = allocateChord(
        notes: [60, 64, 67, 72],
        row: 0,
        startChannel: 2,
        channelCount: 4,
      );
      expect(notes.map((n) => n.channel), [2, 3]);
      expect(notes.map((n) => n.midi), [60, 64], reason: 'the lowest survive');
    });

    test('nothing played, nothing written', () {
      expect(
        allocateChord(
          notes: const [],
          row: 0,
          startChannel: 0,
          channelCount: 8,
        ),
        isEmpty,
      );
    });
  });

  group('how LONG a note was held', () {
    // Without a length every recorded note runs until the next one on its
    // channel, so a staccato stab and a held pad come out identical.
    test('released three rows later, the cut is three rows later', () {
      expect(releaseRowFor(startRow: 4, releaseRow: 7, totalRows: 16), 7);
    });

    test('released in its own row, it is cut on the NEXT one', () {
      // A key-off in the row the note starts in cancels it before it sounds.
      expect(releaseRowFor(startRow: 4, releaseRow: 4, totalRows: 16), 5);
    });

    test('the cut wraps with the pattern', () {
      expect(releaseRowFor(startRow: 14, releaseRow: 2, totalRows: 16), 2);
    });

    test('an empty pattern has nowhere to put one', () {
      expect(releaseRowFor(startRow: 0, releaseRow: 2, totalRows: 0), isNull);
    });

    test('rows outside the pattern are wrapped, not trusted', () {
      // The playhead of a SONG counts through the order list, so a row can
      // arrive already past the end of one pattern.
      expect(releaseRowFor(startRow: 20, releaseRow: 23, totalRows: 16), 7);
    });
  });

  group('the count-in gates the WRITES, not the clock', () {
    // The Tracker's Stopwatch is the authority the transport follows, so a
    // count-in cannot hold time back. It keeps playing and refuses to commit —
    // which is what a count-in is for: you hear the beat and play along.
    const bar = 2000.0; // 4/4 at 120 BPM

    test('nothing commits during the count', () {
      const countIn = RecordCountIn(startedAtMs: 0, bars: 2, barMs: bar);
      expect(countIn.commits(0), isFalse);
      expect(countIn.commits(bar), isFalse);
      expect(countIn.commits(bar * 2 - 1), isFalse);
    });

    test('the note ON the downbeat that ends it IS kept', () {
      // Inclusive on purpose: that is the note the count-in exists to prepare,
      // and dropping it would punish the player who was perfectly in time.
      const countIn = RecordCountIn(startedAtMs: 0, bars: 2, barMs: bar);
      expect(countIn.commits(bar * 2), isTrue);
    });

    test('zero bars means commit immediately', () {
      expect(RecordCountIn.none.commits(0), isTrue);
      expect(
        const RecordCountIn(startedAtMs: 500, bars: 0, barMs: bar).commits(500),
        isTrue,
      );
    });

    test('it counts from where playback STARTED, not from zero', () {
      // Recording armed mid-song counts from there; anchoring at zero would
      // mean no count-in at all.
      const countIn = RecordCountIn(startedAtMs: 8000, bars: 1, barMs: bar);
      expect(countIn.commits(8000), isFalse);
      expect(countIn.commits(9999), isFalse);
      expect(countIn.commits(10000), isTrue);
    });

    test('the readout counts DOWN and reaches zero', () {
      const countIn = RecordCountIn(startedAtMs: 0, bars: 2, barMs: bar);
      expect(countIn.barsRemaining(0), 2);
      expect(countIn.barsRemaining(bar), 1);
      expect(countIn.barsRemaining(bar * 2), 0);
      expect(countIn.barsRemaining(bar * 3), 0, reason: 'never negative');
    });
  });

  group('a record pass is ONE undo entry', () {
    // The screen snapshots the whole pattern per undo entry against an
    // 80-entry cap, so a note per entry meant ten seconds of jamming evicted
    // every earlier edit — the work you wanted to keep, pushed out by the take
    // you were still trying.
    test('only the first committed note asks for a snapshot', () {
      final pass = RecordPass();
      expect(pass.commit(0)?.needsSnapshot, isTrue);
      expect(pass.commit(100)?.needsSnapshot, isFalse);
      expect(pass.commit(200)?.needsSnapshot, isFalse);
      expect(pass.committedCount, 3);
    });

    test('an empty pass costs no history at all', () {
      // Arming, playing nothing, and stopping must leave the history untouched
      // — otherwise undo silently becomes a no-op the user has to press twice.
      final pass = RecordPass();
      expect(pass.hasCommitted, isFalse);
      expect(pass.committedCount, 0);
    });

    test('notes during a count-in commit nothing and cost no snapshot', () {
      final pass = RecordPass(
        countIn: const RecordCountIn(startedAtMs: 0, bars: 1, barMs: 2000),
      );
      expect(pass.commit(500), isNull);
      expect(pass.commit(1999), isNull);
      expect(pass.hasCommitted, isFalse, reason: 'nothing was written yet');

      expect(pass.commit(2000)?.needsSnapshot, isTrue);
      expect(pass.commit(2100)?.needsSnapshot, isFalse);
      expect(pass.committedCount, 1 + 1);
    });

    test('a NEW pass takes its own snapshot', () {
      // Two takes are two things to undo; one entry for both would make the
      // second take unrecoverable without losing the first.
      final first = RecordPass()..commit(0);
      expect(first.commit(10)?.needsSnapshot, isFalse);
      final second = RecordPass();
      expect(second.commit(20)?.needsSnapshot, isTrue);
    });
  });
}
