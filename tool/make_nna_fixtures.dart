// PLAN.md §6 — IT New-Note Actions, the last unmeasured item on the ladder.
//
// NNA decides what happens to the voice ALREADY sounding on a channel when a
// new note arrives: cut it (0), let it continue (1), release it (2), or fade it
// (3). It is the one part of the IT model that makes a channel polyphonic, and
// our replayer implements all four plus the `S7[3-6]` per-channel override and
// DCT/DCA duplicate checks — none of it ever measured against a reference.
//
// **The notes ascend rather than repeat.** With one repeated pitch, "continue"
// and "cut" differ only in level, which the spectral gate is blind to by
// construction (it is amplitude-invariant — that is what hid tremolo's 4x
// depth). Ascending notes make overlapping voices a CHORD, so the difference is
// spectral as well as loud, and both metrics can see it.
//
// IT only: XM has no NNA, and MOD/S3M have no instruments at all. That leaves
// libopenmpt and libxmp as the two references — IT is the format with the
// fewest oracles and the most features, which is exactly why it was left last.
//
// Regenerate:  dart run tool/make_nna_fixtures.dart

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';

const _rows = 32;
const _channels = 4;

/// A steady tone with harmonics, so overlapping voices beat audibly instead of
/// summing into something a spectral comparison could shrug off.
Float64List _wave() {
  const n = 256;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    final phase = 2 * math.pi * i / n;
    var v = 0.0;
    for (var k = 1; k <= 4; k++) {
      v += math.sin(phase * k) / k;
    }
    out[i] = v / 2.0834;
  }
  return out;
}

/// A volume envelope that HOLDS at full while the note is held and ramps to
/// silence once it is released.
///
/// `noteOff` (NNA 2) releases the old voice rather than cutting or keeping it,
/// and without an envelope there is nothing for a release to DO — the voice
/// just carries on, so `nna_off` rendered byte-for-byte like `nna_continue` in
/// both references and the fixture proved nothing about it. The sustain point
/// is what gives "released" a meaning: held, the envelope sits at 64; released,
/// it walks down to 0.
DocEnvelope _sustainThenRelease() => const DocEnvelope(
      points: [(0, 64), (12, 64), (60, 0)],
      sustain: 1,
      enabled: true,
    );

/// One channel, a new note every [every] rows, ascending — so a channel that
/// keeps its old voices builds a chord and one that cuts them does not.
///
/// [fadeout] matters for `noteFade` (3): with no fadeout an IT fade never
/// completes, so the fixture would measure "continue" under another name.
/// [sustainEnvelope] is what gives `noteOff` something to release.
ModuleDoc _doc(
  int nna, {
  int every = 4,
  int fadeout = 0,
  bool sustainEnvelope = false,
}) {
  final wave = _wave();
  return ModuleDoc(
    sourceFormat: ModuleFormat.mod,
    title: 'nna $nna',
    channelCount: _channels,
    order: const [0],
    samples: [
      DocSample(
        name: 'saw4',
        pcm: wave,
        loopLength: wave.length,
        volumeEnvelope:
            sustainEnvelope ? _sustainThenRelease() : const DocEnvelope(),
      ),
    ],
    itInstruments: [
      DocInstrument(
        name: 'saw4',
        nna: nna,
        fadeout: fadeout,
        volumeEnvelope:
            sustainEnvelope ? _sustainThenRelease() : const DocEnvelope(),
        // 1-BASED sample numbers. Filling this with 0 means "no sample" and the
        // whole module renders silent — which the envelope pass learned the
        // hard way, and only caught because the REFERENCE render was checked
        // against arithmetic before anything was compared to us.
        keymap: List<int>.filled(120, 1),
      ),
    ],
    patterns: [
      DocPattern(
        [
          for (var r = 0; r < _rows; r++)
            [
              if (r % every == 0 && r < 20)
                DocCell(note: 55 + (r ~/ every) * 4, instrument: 1, volume: 64)
              else
                DocCell.empty,
              DocCell.empty,
              DocCell.empty,
              DocCell.empty,
            ],
        ],
        _channels,
      ),
    ],
  );
}

void _emit(String name, ModuleDoc doc) {
  final bytes = convertToIt(doc);
  File('test/fixtures/nna/$name.it').writeAsBytesSync(bytes);
  stdout.writeln('  $name.it  ${bytes.length} bytes');
}

void main() {
  Directory('test/fixtures/nna').createSync(recursive: true);
  stdout.writeln('IT new-note-action fixtures:');

  // CUT is the CONTROL. It is what a channel does without NNA at all, so if
  // this one diverges the fault is not in the NNA model — it is in something
  // the other three would inherit anyway.
  _emit('nna_cut', _doc(0));

  // CONTINUE: every voice keeps ringing, so five ascending notes become a
  // five-note chord. The loudest possible difference from `cut`, and the
  // fixture that says whether channel polyphony happens at all.
  _emit('nna_continue', _doc(1));

  // NOTE OFF: the old voice is RELEASED — not cut, not held.
  //
  // ⚠️ This needs the sustain envelope, and finding that out is the reason the
  // reference render gets checked before ours. Without an envelope there is
  // nothing for a release to do, so the voice simply carries on and BOTH
  // references rendered `nna_off` identically to `nna_continue` — a fixture
  // that would have "passed" while testing nothing. With a sustain point, held
  // means 64 and released means a walk down to 0, so the two separate.
  _emit('nna_off', _doc(2, sustainEnvelope: true));

  // NOTE FADE, with a fadeout that actually completes. Without the fadeout this
  // is indistinguishable from `continue`, which would make a passing result
  // meaningless.
  _emit('nna_fade', _doc(3, fadeout: 512));

  // CONTINUE again, with the same sustain envelope as `nna_off`. This is the
  // CONTROL for that comparison: same envelope, same notes, only the action
  // differs, so whatever separates them is the action and not the shaping.
  _emit('nna_continue_env', _doc(1, sustainEnvelope: true));

  stdout.writeln('done — one channel, ascending notes every 4 rows');
}
