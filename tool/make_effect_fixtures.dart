// PLAN.md §6 task X1 — one MOD effect per fixture.
//
// `effects.mod` runs four effect families on four channels at once, so when a
// listener heard our sweeps drift from libopenmpt/libxmp/micromod, the audit
// could only say "effects are off" — not WHICH command. These fixtures each
// exercise exactly one effect on exactly one sounding channel, so a measured
// deviation names the bug.
//
// Shape of every fixture, deliberately uniform so numbers are comparable:
//   * 4 channels (a real M.K. MOD), but only channel 0 ever sounds.
//   * 32 rows, speed 6 / tempo 125 → 0.12 s per row, 3.84 s total.
//   * one looped 256-sample band-limited saw, so notes SUSTAIN and an effect
//     has something to act on for its whole run.
//   * a note on row 0, then the effect held on rows 1..31 — effects that work
//     per TICK need a long run before they diverge visibly.
//
// Regenerate:  dart run tool/make_effect_fixtures.dart

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';

const _rows = 32;
const _channels = 4;
const _note = 60; // C, mid-table: room to bend both ways without clamping

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

/// One fixture: [cellFor] supplies channel 0's cell for each row.
void _emit(
  String name,
  Float64List wave,
  DocCell Function(int row) cellFor,
) {
  final doc = ModuleDoc(
    sourceFormat: ModuleFormat.mod,
    title: 'fx $name',
    channelCount: _channels,
    order: const [0],
    samples: [DocSample(name: 'saw4', pcm: wave, loopLength: wave.length)],
    patterns: [
      DocPattern(
        [
          for (var r = 0; r < _rows; r++)
            [cellFor(r), DocCell.empty, DocCell.empty, DocCell.empty],
        ],
        _channels,
      ),
    ],
  );
  final bytes = convertToMod(doc);
  File('test/fixtures/fx/$name.mod').writeAsBytesSync(bytes);
  stdout.writeln('  $name.mod  ${bytes.length} bytes');
}

/// Note on row 0, the effect for rows 1..8, then silence-free hold. Keeps a
/// pitch bend inside the period table so clamp behaviour does not dominate.
DocCell Function(int) _bend(int effect, int param) => (r) => r == 0
    ? const DocCell(note: _note, instrument: 1)
    : (r <= 8 ? DocCell(effect: effect, effectParam: param) : DocCell.empty);

/// Note on row 0, then [effect]/[param] every row after it.
DocCell Function(int) _hold(int effect, int param) => (r) => r == 0
    ? const DocCell(note: _note, instrument: 1)
    : DocCell(effect: effect, effectParam: param);

void main() {
  Directory('test/fixtures/fx').createSync(recursive: true);
  final wave = _wave();
  stdout.writeln('X1 per-effect fixtures:');

  // 0xy — arpeggio. Cycles base/+4/+7 every tick: a fast chord shimmer.
  _emit('arpeggio', wave, _hold(0x0, 0x47));

  // 1xx / 2xx — portamento up/down, a steady per-tick period slide.
  //
  // Bend for only 8 rows, then hold. Held for all 31 the note slides off the
  // end of the period table and CLAMPING dominates — the three references then
  // disagree with each other (0.555 spectral), so the fixture would be
  // measuring their clamp policies rather than our slide.
  _emit('porta_up', wave, _bend(0x1, 0x04));
  _emit('porta_down', wave, _bend(0x2, 0x04));

  // 3xx — TONE portamento: slides from the sounding note toward a NEW target
  // note, then must STOP there. Overshoot and target-snapping are the usual
  // bugs, and neither shows up without a real target.
  _emit('tone_porta', wave, (r) {
    if (r == 0) return const DocCell(note: _note, instrument: 1);
    if (r == 8) {
      return const DocCell(note: _note + 7, effect: 0x3, effectParam: 0x04);
    }
    return const DocCell(effect: 0x3, effectParam: 0x04);
  });

  // 4xy — vibrato (pitch LFO). The one the listening test flagged.
  _emit('vibrato', wave, _hold(0x4, 0x35));

  // 7xy — tremolo (volume LFO). Same LFO machinery, different destination, so
  // a shared waveform/rate bug shows in both and a wiring bug in only one.
  _emit('tremolo', wave, _hold(0x7, 0x35));

  // Axy — volume slide. x slides up, y slides down; per TICK, not per row.
  _emit('volslide_down', wave, _hold(0xA, 0x01));
  _emit('volslide_up', wave, (r) {
    if (r == 0) {
      return const DocCell(
        note: _note,
        instrument: 1,
        effect: 0xC,
        effectParam: 0x10,
      );
    }
    return const DocCell(effect: 0xA, effectParam: 0x10);
  });

  // 5xy / 6xy — porta+volslide and vibrato+volslide. These CONTINUE the
  // previous porta/vibrato from memory while sliding volume, so they fail
  // whenever effect memory is wrong even though 3xx/4xy alone look fine.
  _emit('tonevol_5xy', wave, (r) {
    if (r == 0) return const DocCell(note: _note, instrument: 1);
    if (r == 4) {
      return const DocCell(note: _note + 7, effect: 0x3, effectParam: 0x04);
    }
    return const DocCell(effect: 0x5, effectParam: 0x01);
  });
  _emit('vibvol_6xy', wave, (r) {
    if (r == 0) return const DocCell(note: _note, instrument: 1);
    if (r == 1) return const DocCell(effect: 0x4, effectParam: 0x35);
    return const DocCell(effect: 0x6, effectParam: 0x01);
  });

  // 9xx — sample offset. Restarts the note partway into the waveform.
  _emit('offset_9xx', wave, (r) {
    if (r % 8 != 0) return DocCell.empty;
    return const DocCell(
      note: _note,
      instrument: 1,
      effect: 0x9,
      effectParam: 0x02,
    );
  });

  // 9xx again, but landing INSIDE the sample — the ordinary case. Without
  // this, the only offset evidence is the out-of-range edge above.
  _emit('offset_9xx_inrange', _longWave(), (r) {
    if (r % 8 != 0) return DocCell.empty;
    return const DocCell(
      note: _note,
      instrument: 1,
      effect: 0x9,
      effectParam: 0x02,
    );
  });

  // ECx / EDx — note cut and note delay, sub-row TIMING rather than pitch.
  _emit('notecut_ECx', wave, (r) {
    if (r % 4 != 0) return DocCell.empty;
    return const DocCell(
      note: _note,
      instrument: 1,
      effect: 0xE,
      effectParam: 0xC3,
    );
  });
  _emit('notedelay_EDx', wave, (r) {
    if (r % 4 != 0) return DocCell.empty;
    return const DocCell(
      note: _note,
      instrument: 1,
      effect: 0xE,
      effectParam: 0xD3,
    );
  });

  // --- X3/X4: effect MEMORY -------------------------------------------------
  //
  // Every fixture above restates its parameter on every row, so none of them
  // can see a memory bug at all. These state the parameter ONCE and then send
  // the bare zero-parameter form, which is where ProTracker's rules diverge
  // sharply from FastTracker's — and our replayer serves all four formats from
  // one implementation, so it can only match one of them.
  //
  // ProTracker (`pt2_replayer.c`):
  //   * `1xx`/`2xx` portaUp/portaDown read `ch->n_cmd` DIRECTLY. No memory at
  //     all: a bare `100` slides by zero.
  //   * `Axy` volumeSlide likewise — a bare `A00` changes nothing.
  //   * `3xx` tonePortamento DOES latch (`if (param > 0) n_toneportspeed = …`).
  //   * `4xy` vibrato latches each nibble separately.
  // So the memory is per-command, not a blanket rule, and the two that latch
  // are exactly the two we would expect to.

  // 1xx with the parameter given ONCE. Under ProTracker rows 2..8 do nothing;
  // under a blanket-memory model they keep sliding, and the note ends up a long
  // way from where the hardware leaves it.
  _emit('mem_porta_up', wave, (r) {
    if (r == 0) return const DocCell(note: _note, instrument: 1);
    if (r == 1) return const DocCell(effect: 0x1, effectParam: 0x04);
    return r <= 8 ? const DocCell(effect: 0x1) : DocCell.empty;
  });

  _emit('mem_porta_down', wave, (r) {
    if (r == 0) return const DocCell(note: _note, instrument: 1);
    if (r == 1) return const DocCell(effect: 0x2, effectParam: 0x04);
    return r <= 8 ? const DocCell(effect: 0x2) : DocCell.empty;
  });

  // Axy the same way. Volume is a level effect, so the spectral metric is
  // nearly blind to it (it is amplitude-invariant) — read the sweep's duration
  // and level columns, or the envelope correlation, not the spectral number.
  _emit('mem_volslide', wave, (r) {
    if (r == 0) {
      return const DocCell(
        note: _note,
        instrument: 1,
        effect: 0xC,
        effectParam: 0x30,
      );
    }
    if (r == 1) return const DocCell(effect: 0xA, effectParam: 0x02);
    return r <= 12 ? const DocCell(effect: 0xA) : DocCell.empty;
  });

  // 3xx, the one that SHOULD latch. It is the control: if the two above are
  // wrong and this one is right, the fault is a blanket memory rule rather than
  // a broken memory mechanism.
  _emit('mem_tone_porta', wave, (r) {
    if (r == 0) return const DocCell(note: _note, instrument: 1);
    if (r == 4) {
      return const DocCell(note: _note + 7, effect: 0x3, effectParam: 0x04);
    }
    return r <= 20 ? const DocCell(effect: 0x3) : DocCell.empty;
  });

  stdout.writeln('done — one sounding channel each, 32 rows, speed 6/125');
}

/// A longer wave, so a `9xx` offset can land INSIDE the sample.
///
/// `9xx` counts in units of 256 samples, so `9x02` is 512 in — past the end of
/// the 256-sample wave every other fixture uses. That makes the default offset
/// fixture an OUT-OF-RANGE test, which is a legitimate edge but tells you
/// nothing about whether ordinary offsets work. This one is 2048 samples so
/// `9x02` lands a quarter of the way through with plenty left to play.
Float64List _longWave() {
  const n = 2048;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    // Four cycles across the buffer, so an offset lands at an audibly
    // different phase rather than somewhere indistinguishable.
    final phase = 2 * math.pi * 4 * i / n;
    var v = 0.0;
    for (var k = 1; k <= 4; k++) {
      v += math.sin(phase * k) / k;
    }
    out[i] = v / 2.0834;
  }
  return out;
}
