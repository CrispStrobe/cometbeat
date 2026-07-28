// Tremor is three different machines, and this pins all three tick by tick.
//
// PLAN.md §6 X9. The audio measurement needs openmpt123/xmp and lives in the
// opt-in sweep; these are pure trajectory assertions through `traceChannel`, so
// they run in CI. Each expected string was READ OFF the reference renders — one
// character per tick, `#` sounding and `.` gated — rather than derived from a
// rule, because deriving the rule from the source was exactly what failed:
//
//   IT   ###..###..      x on, y off
//   S3M  ####...####...  x+1 on, y+1 off — ScreamTracker 3's off-by-one
//   XM   #####....#####...  FT2 skips tick 0 and suppresses the gate after a
//                           note, and that beats against the 6-tick row
//
// The parameter is `I32` at speed 6 on purpose: five does not divide six, so a
// gate that restarts each row (which is what ours did — `k % (x + y)` on the
// tick WITHIN the row) cannot coincidentally agree with a free-running one. The
// counter is per channel and runs for as long as the command is held.
//
// ⚠️ The S3M row is the one place in this audit where the references genuinely
// disagree: libxmp plays S3M with the plain IT counter, openmpt applies ST3's
// x+1/y+1. There is no consensus to measure, so it is a documented judgement
// call — see [TremorModel.screamTracker].

import 'package:comet_beat/core/audio/tracker_engine.dart' show TrackerCell;
import 'package:comet_beat/core/audio/tracker_replay.dart'
    show kDefaultTicksPerRow;
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:flutter_test/flutter_test.dart';

/// `I32` — three ticks on, two off, before each format's own adjustment.
const int _tremorParam = 0x32;

/// The gate as a string, one character per tick, starting at row 1 tick 0 —
/// the first tick on which the command is in force.
String _gate(ReplayProfile profile, {int ticks = 40}) {
  final cells = [
    const TrackerCell(midi: 60, instrument: 1),
    for (var i = 0; i < 12; i++)
      const TrackerCell(fxCmd: kFxTremor, fxParam: _tremorParam),
  ];
  final trace = traceChannel(cells, profile: profile);
  final out = StringBuffer();
  for (var i = 0; i < ticks; i++) {
    final row = 1 + i ~/ kDefaultTicksPerRow;
    final tick = i % kDefaultTicksPerRow;
    out.write(trace.volumeAt(row, tick) > 0 ? '#' : '.');
  }
  return out.toString();
}

void main() {
  test('Impulse Tracker: x on, y off', () {
    expect(
      _gate(ReplayProfile.impulse),
      '###..###..###..###..###..###..###..###..',
    );
  });

  test('ScreamTracker 3: one MORE tick in each phase', () {
    expect(
      _gate(ReplayProfile.screamTracker),
      '####...####...####...####...####...####.',
    );
  });

  test('FastTracker II: no advance on tick 0, and the gate starts suppressed',
      () {
    // The irregular period is real, not a measurement artefact. It is what a
    // five-tick cycle advancing on five of every six ticks looks like.
    expect(
      _gate(ReplayProfile.fastTracker),
      '#####....#####...#####....#####...#####.',
    );
  });

  test('the counter does not restart at the row boundary', () {
    // The bug this file exists for, stated without reference to any format: if
    // the gate were a position within the row it would repeat every 6 ticks,
    // and every model above would show a period of 6.
    for (final profile in [
      ReplayProfile.impulse,
      ReplayProfile.screamTracker,
      ReplayProfile.fastTracker,
    ]) {
      final gate = _gate(profile, ticks: 36);
      final firstRow = gate.substring(0, 6);
      expect(
        gate.substring(6, 12) == firstRow && gate.substring(12, 18) == firstRow,
        isFalse,
        reason: '${profile.name} repeats every row, so the counter is being '
            'restarted instead of free-running: $gate',
      );
    }
  });

  test('I00 — both nibbles zero, which is NOT "no gate"', () {
    // ⚠️ Our trajectory test used to assert that `T00` leaves the note fully
    // on, on the reasonable grounds that a cycle of x+y = 0 has nothing to
    // gate. Wrong: outside FT2 a zero nibble is incremented to ONE, so the
    // note alternates every tick, and FT2's flip-per-advance closes the gate
    // too. Both patterns below are read off libopenmpt's render of
    // `fmt/tremor_I00.{it,s3m,xm}`, which our render matches exactly.
    //
    // ⚠️ I also guessed, before measuring, that FT2's literal zero would mean
    // the gate NEVER closes. It does close — the gate is read AFTER the flip,
    // so a zero-length phase still costs one tick. Worth keeping as a reminder
    // that these state machines do not behave the way their parameters read.
    String gateOf(ReplayProfile profile) {
      final cells = [
        const TrackerCell(midi: 60, instrument: 1),
        for (var i = 0; i < 8; i++) const TrackerCell(fxCmd: kFxTremor),
      ];
      final trace = traceChannel(cells, profile: profile);
      final out = StringBuffer();
      for (var i = 0; i < 24; i++) {
        out.write(
          trace.volumeAt(
                    1 + i ~/ kDefaultTicksPerRow,
                    i % kDefaultTicksPerRow,
                  ) >
                  0
              ? '#'
              : '.',
        );
      }
      return out.toString();
    }

    expect(gateOf(ReplayProfile.impulse), '#.#.#.#.#.#.#.#.#.#.#.#.');
    expect(gateOf(ReplayProfile.screamTracker), '#.#.#.#.#.#.#.#.#.#.#.#.');
    expect(gateOf(ReplayProfile.fastTracker), '##.#.##.#.#..#.#.##.#.#.');
  });

  test('our own authored songs use the Impulse model', () {
    // `native` is not a format and has no quirk to reproduce; it takes the
    // plainest of the three so an authored `Ixy` means what it says.
    expect(ReplayProfile.native.tremor, TremorModel.impulse);
    expect(_gate(ReplayProfile.native), _gate(ReplayProfile.impulse));
  });
}
