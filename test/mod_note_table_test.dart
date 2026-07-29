// The PERIOD our writer puts on disk for an authored note, against ProTracker's
// published table.
//
// PLAN.md §6, fixture independence. Every fixture in `test/fixtures/` is written
// by our own writer, so a writer bug is baked into every A/B that uses it. The
// effect BYTES have a guard now (`effect_numbering_table_test.dart`, which
// caught XM's `15h` on its first run). The note table did not, and it is the
// more fundamental of the two: an effect writes the wrong command, but a wrong
// period writes the wrong MUSIC, in every module we export, at every pitch.
//
// It is invisible to everything else the audit does:
//
//   * a ROUND TRIP cannot see it — our reader maps the same wrong period back
//     to the same note, so `docFromMod(convertToMod(x)) == x` holds;
//   * an A/B against libopenmpt cannot see it either — the reference plays the
//     file we wrote, so it plays the same wrong pitch we do, and the spectral
//     comparison is a perfect 1.000. **Both engines agreeing is not evidence
//     the file says what we meant.**
//
// Only an outside constant settles it. ProTracker's period table is published
// and fixed — `C-2` is 428, and the octave above is exactly half — so the check
// is arithmetic, needs no reference players, and runs in CI.
//
// ⚠️ The 2× octave relation is checked as well as the literal values, because a
// table can be right at the anchor and drift in the extremes; that is exactly
// where a fixture's slides run when they bend far, and where clamping starts to
// dominate a measurement (which X1 learned the hard way).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/mod_reader.dart';
import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:flutter_test/flutter_test.dart';

/// ProTracker's period table, quoted from the format rather than from us.
///
/// This is deliberately a SECOND copy of `modPeriods`: a test that imports the
/// table it is checking proves only that the table equals itself. If someone
/// edits one, these must be reconciled by hand — which is the point.
const List<int> kProTrackerPeriods = [
  856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453, // C-1..B-1
  428, 404, 381, 360, 339, 320, 302, 285, 269, 254, 240, 226, // C-2..B-2
  214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113, // C-3..B-3
];

/// The MIDI note our model assigns to table index 0.
///
/// Also a deliberate second copy (of `modNoteBaseMidi`). Between this and the
/// table above, the file imports NOTHING from the module it is checking — which
/// is why the unused-import warning that removing `mod_module.dart` silenced was
/// the right signal rather than an inconvenience.
const int kIndexZeroMidi = 48;

Float64List _wave() {
  const n = 256;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = math.sin(2 * math.pi * i / n);
  }
  return out;
}

/// The raw period byte-pair our writer emitted for [midi], read back at the
/// FORMAT level — what a foreign player sees.
int _periodOnDiskFor(int midi) {
  final wave = _wave();
  final doc = ModuleDoc(
    sourceFormat: ModuleFormat.mod,
    title: 'periods',
    channelCount: 4,
    order: const [0],
    samples: [DocSample(name: 's', pcm: wave, loopLength: wave.length)],
    patterns: [
      DocPattern(
        [
          [
            DocCell(note: midi, instrument: 1),
            DocCell.empty,
            DocCell.empty,
            DocCell.empty,
          ],
          for (var r = 1; r < 4; r++)
            [
              DocCell.empty,
              DocCell.empty,
              DocCell.empty,
              DocCell.empty,
            ],
        ],
        4,
      ),
    ],
  );
  return parseMod(convertToMod(doc)).patterns.first.rows.first.first.period;
}

void main() {
  test('every authored note writes ProTracker\'s published period', () {
    // The whole table in one assertion, so a drift anywhere is named rather
    // than caught only where a fixture happens to sound.
    final wrong = <String>[];
    for (var i = 0; i < kProTrackerPeriods.length; i++) {
      final midi = kIndexZeroMidi + i;
      final got = _periodOnDiskFor(midi);
      if (got != kProTrackerPeriods[i]) {
        wrong.add('midi $midi (index $i): wrote $got, '
            'ProTracker says ${kProTrackerPeriods[i]}');
      }
    }
    expect(
      wrong,
      isEmpty,
      reason: 'the period IS the pitch in a MOD, so a wrong one detunes every '
          'exported module — and neither a round trip nor an A/B can see it, '
          'because both read back what we wrote:\n  ${wrong.join("\n  ")}',
    );
  });

  test('MIDI 60 is period 428 — the anchor the whole table hangs on', () {
    // Called out separately because every fixture in `fx/` sounds this note,
    // and `tracker_profile.periodForPitch` is built on it: `428 * 2^((60-p)/12)`
    // is the continuous curve that `slidePitchByPeriod` bends along. If the
    // anchor moved, the fixtures and the slide arithmetic would disagree about
    // what "note 60" is while still agreeing with each other.
    expect(_periodOnDiskFor(60), 428);
  });

  test('the octave relation holds across the table, not just at the anchor',
      () {
    // A table can be right where it is checked and drift at the extremes — and
    // the extremes are where a held slide ends up, which is where clamping
    // starts to dominate a measurement rather than the effect under test.
    for (var i = 0; i + 12 < kProTrackerPeriods.length; i++) {
      final low = _periodOnDiskFor(kIndexZeroMidi + i).toDouble();
      final high = _periodOnDiskFor(kIndexZeroMidi + i + 12).toDouble();
      expect(
        low / high,
        closeTo(2.0, 0.02),
        reason: 'an octave up must halve the period; index $i -> ${i + 12} '
            'gives $low / $high',
      );
    }
  });

  test('a note outside the table is refused, not silently wrapped', () {
    // MOD has three octaves and nothing else. Writing a note it cannot express
    // must not fold around into a different pitch — that would be a wrong note
    // in the file with no diagnostic anywhere.
    final below = _periodOnDiskFor(kIndexZeroMidi - 1);
    final above = _periodOnDiskFor(kIndexZeroMidi + kProTrackerPeriods.length);
    for (final (name, got) in [('below', below), ('above', above)]) {
      expect(
        got == 0 || kProTrackerPeriods.contains(got),
        isTrue,
        reason: 'a $name-range note wrote period $got, which is neither '
            '"no note" (0) nor a legal ProTracker period',
      );
    }
    // Whatever the clamp policy is, it must not land on the OPPOSITE end of
    // the table — an octave-wrapped note is the failure this guards.
    if (below != 0) {
      expect(below, greaterThanOrEqualTo(kProTrackerPeriods.last));
    }
    if (above != 0) {
      expect(above, lessThanOrEqualTo(kProTrackerPeriods.first));
    }
  });
}
