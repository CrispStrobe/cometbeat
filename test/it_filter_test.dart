// Tests for the IT resonant low-pass filter: instrument initial cutoff/
// resonance parsing + bridging, the per-voice biquad applied in the sample-tick
// render (HF attenuation), the Zxx (kFxSetFilter) cell command, and the
// bit-identity guarantee for a voice with NO filter.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/it_reader.dart';
import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/module_instrument_bridge.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replay.dart' show kFxVolumeSlide;
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a minimal single-instrument, single-sample, single-pattern IT with the
/// instrument's initial filter cutoff/resonance set (IMPI bytes 0x3A/0x3B).
Uint8List buildMinimalIt({required int cutoff, required int resonance}) {
  final b = Uint8List(0x600);
  final bd = ByteData.sublistView(b);
  void ascii(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      b[o + i] = s.codeUnitAt(i);
    }
  }

  ascii(0x00, 'IMPM');
  ascii(0x04, 'flt');
  bd.setUint16(0x20, 2, Endian.little); // OrdNum (order + end marker)
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
  // order list @0xC0
  b[0xC0] = 0; // play pattern 0
  b[0xC1] = 0xFF; // end marker

  const insOff = 0x100;
  const smpOff = insOff + 554; // 0x32A
  const smpData = smpOff + 80; // 0x37A
  const patOff = 0x400;

  // offset tables: instrument (0xC2), sample (0xC6), pattern (0xCA)
  bd.setUint32(0xC2, insOff, Endian.little);
  bd.setUint32(0xC6, smpOff, Endian.little);
  bd.setUint32(0xCA, patOff, Endian.little);

  // ── instrument header (IMPI) ──
  ascii(insOff, 'IMPI');
  b[insOff + 0x3A] = 0x80 | (cutoff & 0x7F); // IFC (enabled)
  b[insOff + 0x3B] = 0x80 | (resonance & 0x7F); // IFR (enabled)
  // keyboard table @0x40: every note → sample 1
  for (var n = 0; n < 120; n++) {
    b[insOff + 0x40 + n * 2] = n; // note to play
    b[insOff + 0x40 + n * 2 + 1] = 1; // sample number (1-based)
  }

  // ── sample header (IMPS) ──
  ascii(smpOff, 'IMPS');
  b[smpOff + 0x11] = 64; // global volume
  b[smpOff + 0x12] = 0x01; // Flg: has sample (8-bit, uncompressed)
  b[smpOff + 0x13] = 64; // default volume
  b[smpOff + 0x2E] = 0x01; // Cvt: signed PCM
  bd.setUint32(smpOff + 0x30, 8, Endian.little); // length (samples)
  bd.setUint32(smpOff + 0x3C, 8363, Endian.little); // C5Speed
  bd.setUint32(smpOff + 0x48, smpData, Endian.little); // data pointer
  for (var i = 0; i < 8; i++) {
    b[smpData + i] = (i.isEven ? 60 : -60) & 0xFF; // small square wave
  }

  // ── pattern: 1 row, channel 0 plays note 60 with instrument 1 ──
  // packed: channelvar=0x81 (ch0 + new-mask), mask=0x03 (note+instr), note=60,
  // instr=1, then 0x00 = end of row.
  final packed = [0x81, 0x03, 60, 1, 0x00];
  bd.setUint16(patOff, packed.length, Endian.little); // packed length
  bd.setUint16(patOff + 2, 1, Endian.little); // rows
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

/// A one-channel song playing [inst] with a note at row 0. A benign volume-slide
/// (Axy with param 0, a no-op) forces the per-tick sample voice path where the
/// filter lives, plus [cutoffZxx]/[resZxx] optionally emit a Zxx cell.
TrackerSong filterSong(
  SampleInstrument inst, {
  int? cutoffZxx,
  int? resZxx,
}) {
  const rows = 8;
  const timing = TrackerTiming(rows: rows);
  // Axy (0xA) with the default param 0 → a no-op volume slide, but its presence
  // forces the per-tick sample voice path where the filter lives.
  var note = const TrackerCell(midi: 60, fxCmd: kFxVolumeSlide);
  if (cutoffZxx != null) {
    note = note.copyWith(fxCmd: kFxSetFilter, fxParam: cutoffZxx & 0x7F);
  } else if (resZxx != null) {
    note = note.copyWith(fxCmd: kFxSetFilter, fxParam: 0x80 | (resZxx & 0x7F));
  }
  final col = List<TrackerCell>.filled(rows, TrackerCell.empty, growable: true);
  col[0] = note;
  final channel = TrackerChannel(
    id: 'c0',
    instrument: inst,
    rows: rows,
    gain: 1.0,
  );
  final pattern = TrackerPattern(name: '00', cells: [col]);
  return TrackerSong.fromParts(
    channels: [channel],
    timing: timing,
    patterns: [pattern],
    order: [0],
  );
}

/// A native (non-normalized) sample of a pure [freq] sine at the engine rate.
SampleInstrument sineInstrument(
  double freq, {
  int filterCutoff = -1,
  int filterResonance = 0,
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
  );
}

List<double> renderMono(TrackerSong song) {
  final pcm = replaySong(song).pcm;
  return [for (final v in pcm) v / 32768.0];
}

void main() {
  group('IT initial filter cutoff/resonance parse + bridge', () {
    test('(a) values land on the model and on SampleInstrument', () {
      final module = parseIt(buildMinimalIt(cutoff: 40, resonance: 20));
      expect(module.instruments, isNotEmpty);
      expect(module.instruments.first.initialFilterCutoff, 40);
      expect(module.instruments.first.initialFilterResonance, 20);

      // Bridge → neutral DocInstrument.
      final doc = docFromIt(module);
      expect(doc.itInstruments.first.filterCutoff, 40);
      expect(doc.itInstruments.first.filterResonance, 20);

      // Bridge → SampleInstrument carries the filter onto the played voice.
      final si = sampleInstrumentFromDoc(
        'y',
        DocSample(
          pcm: Float64List(16),
          c5speed: kSampleRate,
          filterCutoff: 55,
          filterResonance: 12,
        ),
      );
      expect(si.filterCutoff, 55);
      expect(si.filterResonance, 12);
      expect(si.hasFilter, isTrue);
    });

    test('disabled IFC/IFR parse as none (-1 / 0)', () {
      final b = buildMinimalIt(cutoff: 40, resonance: 20);
      b[0x100 + 0x3A] = 40; // high bit clear → disabled
      b[0x100 + 0x3B] = 20;
      final module = parseIt(b);
      expect(module.instruments.first.initialFilterCutoff, -1);
      expect(module.instruments.first.initialFilterResonance, 0);
    });
  });

  group('IT resonant low-pass render', () {
    test('(b) a filtered voice attenuates high-frequency content', () {
      const hf = 8000.0;
      final open = renderMono(filterSong(sineInstrument(hf)));
      final filtered =
          renderMono(filterSong(sineInstrument(hf, filterCutoff: 20)));

      // Skip the attack + filter settling transient.
      const skip = 2000;
      final openTail = open.sublist(min(skip, open.length));
      final filteredTail = filtered.sublist(min(skip, filtered.length));

      final openMag = goertzel(openTail, hf);
      final filteredMag = goertzel(filteredTail, hf);

      expect(openMag, greaterThan(0));
      // The 8 kHz tone through a ~230 Hz 2-pole low-pass collapses.
      expect(
        filteredMag,
        lessThan(openMag * 0.25),
        reason: 'filtered HF ($filteredMag) vs open ($openMag)',
      );
    });

    test('(c) a Zxx cell sets cutoff (Z00..Z7F) and resonance (Z80..ZFF)', () {
      // Unit: ReplayVoice decodes Zxx.
      final v = ReplayVoice();
      v.armRow(const TrackerCell(fxCmd: kFxSetFilter, fxParam: 40));
      expect(v.filterCutoff, 40);
      v.armRow(const TrackerCell(fxCmd: kFxSetFilter, fxParam: 0x80 | 30));
      expect(v.filterResonance, 30);

      // End-to-end: a Zxx cutoff cell attenuates the HF tone in the render.
      const hf = 8000.0;
      final open = renderMono(filterSong(sineInstrument(hf)));
      final zxx = renderMono(filterSong(sineInstrument(hf), cutoffZxx: 20));
      const skip = 2000;
      final openMag = goertzel(open.sublist(min(skip, open.length)), hf);
      final zxxMag = goertzel(zxx.sublist(min(skip, zxx.length)), hf);
      expect(zxxMag, lessThan(openMag * 0.25));
    });

    test('(d) a no-filter voice is byte-identical to a filterless render', () {
      // Unit: filterOut is an exact pass-through for an unfiltered voice.
      final v = ReplayVoice();
      v.armFilterOnTrigger(-1, 0); // no instrument filter
      for (final x in [0.0, 0.5, -0.5, 0.123456789, -0.999, 1.0]) {
        expect(v.filterOut(x), x);
        expect(v.filterOutRight(x), x);
      }

      // Integration: an open instrument (cutoff 127 = no filter) renders exactly
      // the same PCM whether or not the filter machinery is present.
      const hf = 8000.0;
      final a = replaySong(filterSong(sineInstrument(hf))).pcm;
      final b =
          replaySong(filterSong(sineInstrument(hf, filterCutoff: 127))).pcm;
      expect(a, b);
    });
  });

  group('IT filter cutoff/resonance mapping', () {
    test('cutoff → Hz is monotonic and clamped to Nyquist', () {
      expect(itFilterCutoffHz(0), lessThan(itFilterCutoffHz(64)));
      expect(itFilterCutoffHz(64), lessThan(itFilterCutoffHz(127)));
      expect(itFilterCutoffHz(127), lessThan(kSampleRate / 2));
      expect(itFilterCutoffHz(0), greaterThanOrEqualTo(120.0));
    });

    test('resonance → Q rises from Butterworth', () {
      expect(itFilterResonanceQ(0), closeTo(0.707, 0.01));
      expect(itFilterResonanceQ(127), greaterThan(itFilterResonanceQ(0)));
    });
  });
}
