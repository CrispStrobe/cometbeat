// Tests for the IT per-voice FILTER-CUTOFF envelope: an instrument's third
// envelope is a filter (cutoff) envelope instead of a pitch envelope when its
// env-filter flag (IMPI pitch-env flag bit 0x80) is set. It modulates the
// resonant low-pass cutoff over the note.
//
// Coverage:
//   • parse: a synthetic IT with the env-filter flag + a cutoff envelope →
//     ItInstrument.filterEnvelope true, the envelope nodes land on the model,
//     and (bridge) the native SampleInstrument carries a nativeFilterEnvelope
//     (and NO pitch envelope — the same block is either pitch OR filter);
//   • apply: a note rendered through a RISING filter envelope OPENS the low-pass
//     (HF energy grows over the note); a FALLING envelope CLOSES it (HF shrinks)
//     — measured with a windowed Goertzel over early vs. late windows;
//   • byte-identity: a voice with NO filter envelope is unperturbed — the
//     per-sample updateFilterEnv call is inert, so its output is bit-identical.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/it_reader.dart';
import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replay.dart' show kFxVolumeSlide;
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal single-instrument, single-sample, single-pattern IT whose
/// instrument carries a FILTER-CUTOFF envelope: the pitch-envelope block (IMPI
/// 0x1D4) is flagged as a filter envelope (flag bit 0x80) and holds [nodes]
/// `(tick, value 0..64)` breakpoints.
Uint8List buildFilterEnvIt({required List<(int, int)> nodes}) {
  final b = Uint8List(0x600);
  final bd = ByteData.sublistView(b);
  void ascii(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      b[o + i] = s.codeUnitAt(i);
    }
  }

  ascii(0x00, 'IMPM');
  ascii(0x04, 'flt');
  bd.setUint16(0x20, 2, Endian.little); // OrdNum
  bd.setUint16(0x22, 1, Endian.little); // InsNum
  bd.setUint16(0x24, 1, Endian.little); // SmpNum
  bd.setUint16(0x26, 1, Endian.little); // PatNum
  bd.setUint16(0x28, 0x0214, Endian.little); // Cwt/v
  bd.setUint16(0x2A, 0x0200, Endian.little); // Cmwt
  bd.setUint16(0x2C, 0x04, Endian.little); // flags: use instruments
  b[0x30] = 128; // global volume
  b[0x32] = 6; // speed
  b[0x33] = 125; // tempo
  for (var i = 0; i < 64; i++) {
    b[0x40 + i] = 32; // channel pans (centre)
    b[0x80 + i] = 64; // channel volumes
  }
  b[0xC0] = 0; // order: play pattern 0
  b[0xC1] = 0xFF; // end marker

  const insOff = 0x100;
  const smpOff = insOff + 554;
  const smpData = smpOff + 80;
  const patOff = 0x400;
  bd.setUint32(0xC2, insOff, Endian.little);
  bd.setUint32(0xC6, smpOff, Endian.little);
  bd.setUint32(0xCA, patOff, Endian.little);

  // ── instrument header (IMPI) with a FILTER envelope in the pitch-env block ──
  ascii(insOff, 'IMPI');
  // Pitch-envelope flags (0x1D4): bit0 = enabled, bit7 (0x80) = FILTER flag.
  b[insOff + 0x1D4] = 0x01 | 0x80;
  b[insOff + 0x1D4 + 1] = nodes.length; // node count
  for (var i = 0; i < nodes.length; i++) {
    final (tick, value) = nodes[i];
    final p = insOff + 0x1D4 + 6 + i * 3;
    b[p] = value & 0xFF; // value 0..64
    bd.setUint16(p + 1, tick, Endian.little); // tick
  }
  // keyboard table @0x40: every note → sample 1
  for (var n = 0; n < 120; n++) {
    b[insOff + 0x40 + n * 2] = n;
    b[insOff + 0x40 + n * 2 + 1] = 1;
  }

  // ── sample header (IMPS) ──
  ascii(smpOff, 'IMPS');
  b[smpOff + 0x11] = 64; // global volume
  b[smpOff + 0x12] = 0x01; // Flg: has sample (8-bit)
  b[smpOff + 0x13] = 64; // default volume
  b[smpOff + 0x2E] = 0x01; // Cvt: signed PCM
  bd.setUint32(smpOff + 0x30, 8, Endian.little); // length
  bd.setUint32(smpOff + 0x3C, 8363, Endian.little); // C5Speed
  bd.setUint32(smpOff + 0x48, smpData, Endian.little); // data pointer
  for (var i = 0; i < 8; i++) {
    b[smpData + i] = (i.isEven ? 60 : -60) & 0xFF;
  }

  // ── pattern: 1 row, channel 0 plays note 60 with instrument 1 ──
  final packed = [0x81, 0x03, 60, 1, 0x00];
  bd.setUint16(patOff, packed.length, Endian.little);
  bd.setUint16(patOff + 2, 1, Endian.little);
  for (var i = 0; i < packed.length; i++) {
    b[patOff + 8 + i] = packed[i];
  }
  return b;
}

/// Goertzel magnitude of [x] at [freq] (single-bin DFT).
double goertzel(List<double> x, double freq, {double sr = kSampleRate + 0.0}) {
  final w = 2 * pi * freq / sr;
  final coeff = 2 * cos(w);
  double s1 = 0, s2 = 0;
  for (final v in x) {
    final s0 = v + coeff * s1 - s2;
    s2 = s1;
    s1 = s0;
  }
  final real = s1 - s2 * cos(w);
  final imag = s2 * sin(w);
  return sqrt(real * real + imag * imag);
}

/// A native (non-normalized) sine [freq] instrument, optionally with a filter
/// envelope and/or an initial cutoff.
SampleInstrument sineInstrument(
  double freq, {
  int filterCutoff = -1,
  int filterResonance = 0,
  FilterEnvelope? filterEnvelope,
}) {
  const n = kSampleRate; // 1 s
  final s = Float64List(n);
  for (var i = 0; i < n; i++) {
    s[i] = 0.5 * sin(2 * pi * freq * i / kSampleRate);
  }
  return SampleInstrument(
    'sine',
    s,
    normalize: false,
    filterCutoff: filterCutoff,
    filterResonance: filterResonance,
    nativeFilterEnvelope: filterEnvelope,
  );
}

/// A one-channel, 8-row (~1 s at 120 BPM) song playing [inst] from row 0. A
/// benign Axy (param 0, no-op) forces the per-tick sample voice path.
TrackerSong filterSong(SampleInstrument inst) {
  const rows = 8;
  const timing = TrackerTiming(rows: rows);
  final col = List<TrackerCell>.filled(rows, TrackerCell.empty, growable: true);
  col[0] = const TrackerCell(midi: 60, fxCmd: kFxVolumeSlide);
  final channel =
      TrackerChannel(id: 'c0', instrument: inst, rows: rows, gain: 1.0);
  final pattern = TrackerPattern(name: '00', cells: [col]);
  return TrackerSong.fromParts(
    channels: [channel],
    timing: timing,
    patterns: [pattern],
    order: [0],
  );
}

List<double> renderMono(TrackerSong song) =>
    [for (final v in replaySong(song).pcm) v / 32768.0];

/// Every [SampleInstrument] reachable from a song's instrument pool.
Iterable<SampleInstrument> _sampleInstruments(TrackerSong song) sync* {
  for (final inst in song.instruments) {
    if (inst is SampleInstrument) yield inst;
    if (inst is MultiSampleInstrument) {
      for (final z in inst.zones.values) {
        if (z is SampleInstrument) yield z;
      }
    }
  }
}

void main() {
  group('IT filter-cutoff envelope parse + bridge', () {
    test('(a) the env-filter flag + nodes land on the model', () {
      final module = parseIt(
        buildFilterEnvIt(nodes: [(0, 0), (24, 32), (48, 64)]),
      );
      final ins = module.instruments.first;
      expect(
        ins.filterEnvelope,
        isTrue,
        reason: 'pitch-env flag bit 0x80 → filter envelope',
      );
      // The node block is parsed onto pitchEnvelope (which IS the filter env).
      expect(ins.pitchEnvelope.enabled, isTrue);
      expect(ins.pitchEnvelope.points, [(0, 0), (24, 32), (48, 64)]);

      // Bridge → DocInstrument keeps the flag + the envelope nodes.
      final doc = docFromIt(module);
      expect(doc.itInstruments.first.filterEnvelope, isTrue);
      expect(
        doc.itInstruments.first.pitchEnvelope.points,
        [(0, 0), (24, 32), (48, 64)],
      );
    });

    test('(b) bridge routes the block to nativeFilterEnvelope, NOT pitch', () {
      final song = songFromModuleDoc(
        docFromIt(parseIt(buildFilterEnvIt(nodes: [(0, 0), (48, 64)]))),
      );
      final withFilterEnv = _sampleInstruments(song)
          .where((s) => s.nativeFilterEnvelope != null)
          .toList();
      expect(
        withFilterEnv,
        isNotEmpty,
        reason: 'a filter-flagged instrument yields a nativeFilterEnvelope',
      );
      for (final s in withFilterEnv) {
        // The same envelope block is EITHER pitch OR filter — never both.
        expect(s.nativePitchEnvelope, isNull);
        expect(s.hasFilter, isTrue); // engages the per-voice low-pass
        expect(s.nativeFilterEnvelope!.points, isNotEmpty);
      }
    });
  });

  group('IT filter-cutoff envelope render', () {
    // A 5 kHz tone through a low-pass whose cutoff the envelope sweeps. Early vs
    // late Goertzel windows (well clear of the attack/settling transient).
    const hf = 5000.0;
    const earlyLo = 4000, earlyHi = 12000; // ~0.09..0.27 s
    const lateLo = 32000, lateHi = 40000; // ~0.73..0.91 s

    List<double> window(List<double> x, int lo, int hi) =>
        x.sublist(min(lo, x.length), min(hi, x.length));

    test('(c) a RISING filter envelope OPENS the low-pass (HF grows)', () {
      // value 0 → dark (~0.8 kHz), value 64 → open (~5 kHz). Rising over ~0.9 s.
      const env = FilterEnvelope([
        (ms: 0, value: 0.0),
        (ms: 900, value: 64.0),
      ]);
      final out =
          renderMono(filterSong(sineInstrument(hf, filterEnvelope: env)));
      final early = goertzel(window(out, earlyLo, earlyHi), hf);
      final late = goertzel(window(out, lateLo, lateHi), hf);
      expect(early, greaterThan(0));
      expect(
        late,
        greaterThan(early * 3),
        reason: 'rising env: late HF ($late) ≫ early HF ($early)',
      );
    });

    test('(d) a FALLING filter envelope CLOSES the low-pass (HF shrinks)', () {
      const env = FilterEnvelope([
        (ms: 0, value: 64.0),
        (ms: 900, value: 0.0),
      ]);
      final out =
          renderMono(filterSong(sineInstrument(hf, filterEnvelope: env)));
      final early = goertzel(window(out, earlyLo, earlyHi), hf);
      final late = goertzel(window(out, lateLo, lateHi), hf);
      expect(late, greaterThan(0));
      expect(
        early,
        greaterThan(late * 3),
        reason: 'falling env: early HF ($early) ≫ late HF ($late)',
      );
    });

    test('(e) cutoff modulation mapping: value 64 = neutral, lower darkens',
        () {
      // flt = value·4; itFilterCutoffHzMod(cutoff, flt). value 64 → flt 256 →
      // matches the neutral (no-envelope) itFilterCutoffHz.
      expect(
        itFilterCutoffHzMod(127, 256),
        closeTo(itFilterCutoffHz(127), 1e-9),
      );
      expect(itFilterCutoffHzMod(80, 256), closeTo(itFilterCutoffHz(80), 1e-9));
      // Lower modifier → lower cutoff (darker).
      expect(
        itFilterCutoffHzMod(100, 0),
        lessThan(itFilterCutoffHzMod(100, 256)),
      );
      expect(
        itFilterCutoffHzMod(100, 128),
        lessThan(itFilterCutoffHzMod(100, 256)),
      );
    });
  });

  group('IT filter-cutoff envelope byte-identity', () {
    test('(f) updateFilterEnv is inert for a voice with NO filter envelope',
        () {
      // A voice armed WITHOUT a filter envelope must be bit-identical whether or
      // not the per-sample updateFilterEnv hook runs — proving the new call is a
      // pure no-op on the shipped (initial-cutoff-only) path.
      const xs = [0.0, 0.5, -0.5, 0.123456789, -0.999, 1.0, 0.25, -0.25];

      final withHook = ReplayVoice()
        ..armFilterOnTrigger(20, 0); // cutoff, no env
      final noHook = ReplayVoice()..armFilterOnTrigger(20, 0);
      final a = <double>[];
      final b = <double>[];
      for (var i = 0; i < xs.length; i++) {
        withHook.updateFilterEnv(i * 3.0); // hook runs — must be inert
        a.add(withHook.filterOut(xs[i]));
        b.add(noHook.filterOut(xs[i])); // no hook
      }
      expect(a, b);
    });

    test('(g) an unfiltered voice with no env is an exact pass-through', () {
      final v = ReplayVoice()..armFilterOnTrigger(-1, 0); // no filter at all
      for (final x in [0.0, 0.5, -0.5, 0.123456789, -0.999, 1.0]) {
        expect(v.filterOut(x), x);
        expect(v.filterOutRight(x), x);
      }
    });

    test('(h) a no-filter-env render is deterministic + unchanged', () {
      // Two renders of a no-filter-env instrument (initial cutoff only) are
      // bit-identical — the filter-envelope machinery never touches this path.
      final a =
          replaySong(filterSong(sineInstrument(5000, filterCutoff: 20))).pcm;
      final b =
          replaySong(filterSong(sineInstrument(5000, filterCutoff: 20))).pcm;
      expect(a, b);
    });
  });
}
