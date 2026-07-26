// Generates `test/fixtures/musical.mod` — the A/B's fidelity reference.
//
// WHY THIS EXISTS
//
// The OpenMPT A/B could not judge fidelity, because it had nothing musical to
// judge. The licence-restricted corpus cannot be committed, and the `golden.*`
// fixtures turned out to be a SINGLE NOTE playing a five-sample waveform — on
// that material two engines disagree by 16 dB purely about how to interpolate
// five samples, which says nothing about whether we play the right notes.
//
// So we author one. Because we author it, it is licence-clean and committable.
//
// WHAT IT IS BUILT TO EXERCISE
//   * SUSTAIN — a looped 256-sample wave, so notes ring rather than click. The
//     spectral metric needs frames with steady content; a 5-sample one-shot has
//     none.
//   * PITCH — a melody spanning two octaves, so a tuning error has somewhere to
//     show up. This is the whole point: we map Amiga periods through
//     periodToMidi at A440 rather than from the Paula clock.
//   * POLYPHONY — four channels sounding together, so mixing and per-channel
//     scaling are exercised (the level disagreements were per-channel).
//   * TIME — 2 patterns × 64 rows at speed 6, a few seconds, so lag and
//     envelope correlation have material to lock onto.
//
// Deliberately NOT included: effects. This fixture answers "do we play the
// right notes, at the right pitch, at the right level?" — the narrowest useful
// question. Effect coverage belongs in separate fixtures so a failure localises.
//
// Regenerate with:
//   dart run tool/make_musical_fixture.dart
// It is deterministic: same bytes every run, so a regenerated file that differs
// means the WRITER changed, which is worth knowing.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';

/// A band-limited-ish sawtooth: a few harmonics rather than a hard ramp, so the
/// spectrum has real structure to compare without aliasing into noise at every
/// playback rate. 256 samples, loops seamlessly (period divides the length).
Float64List _wave() {
  const n = 256;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    final phase = 2 * math.pi * i / n;
    // 4 harmonics at 1/k amplitude — a sawtooth's shape, band-limited.
    var v = 0.0;
    for (var k = 1; k <= 4; k++) {
      v += math.sin(phase * k) / k;
    }
    out[i] = v / 2.0834; // normalise the partial sum to ±1
  }
  return out;
}

/// MIDI notes, one per row-step, per channel. Kept inside MOD's 3-octave
/// period table (C-1..B-3 ≈ MIDI 48..83) so every note is representable and
/// nothing is silently clamped — a clamped note would look like a tuning bug.
const _melody = [60, 64, 67, 72, 71, 67, 64, 60]; // arpeggio up and back
const _bass = [36 + 12, 36 + 12, 43 + 12, 43 + 12]; // root/fifth, an octave up
const _pad = [64, 64, 65, 65]; // slow-moving inner voice
const _high = [79, 76, 79, 84 - 12]; // upper line

DocCell _note(int midi) => DocCell(note: midi, instrument: 1);

void main() {
  const rows = 64;
  const channels = 4;
  const patterns = 2;

  final pats = <DocPattern>[];
  for (var p = 0; p < patterns; p++) {
    final rowList = <List<DocCell>>[];
    for (var r = 0; r < rows; r++) {
      final cells = List<DocCell>.filled(channels, DocCell.empty);
      final step = r + p * rows;
      // Melody every 4 rows, bass every 16, pad every 32, high every 8 —
      // different rates so the channels are not merely copies of each other and
      // the mix keeps changing (a static mix makes lag detection meaningless).
      if (r % 4 == 0) cells[0] = _note(_melody[(step ~/ 4) % _melody.length]);
      if (r % 16 == 0) cells[1] = _note(_bass[(step ~/ 16) % _bass.length]);
      if (r % 32 == 0) cells[2] = _note(_pad[(step ~/ 32) % _pad.length]);
      if (r % 8 == 0) cells[3] = _note(_high[(step ~/ 8) % _high.length]);
      rowList.add(cells);
    }
    pats.add(DocPattern(rowList, channels));
  }

  final wave = _wave();
  final doc = ModuleDoc(
    sourceFormat: ModuleFormat.mod,
    title: 'cometbeat ab ref',
    channelCount: channels,
    order: const [0, 1],
    samples: [
      DocSample(
        name: 'saw4',
        pcm: wave,
        // volume 64 and loopStart 0 are the defaults; the LOOP is the point —
        // held notes must sustain rather than click.
        loopLength: wave.length,
      ),
    ],
    patterns: pats,
  );

  final bytes = convertToMod(doc);
  File('test/fixtures/musical.mod').writeAsBytesSync(bytes);
  stdout.writeln('wrote test/fixtures/musical.mod (${bytes.length} bytes): '
      '$channels ch · $patterns patterns × $rows rows · speed 6/125');
}
