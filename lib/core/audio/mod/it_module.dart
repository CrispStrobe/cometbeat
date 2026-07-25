// lib/core/audio/mod/it_module.dart
//
// Model + format contract for the Impulse Tracker `.it` reader (implemented in
// it_reader.dart). Pure Dart, read-only (see docs/TRACKER_HANDOVER.md §6).
//
// ─── IT byte layout (little-endian; the authoritative contract) ──────────────
// HEADER (@0x00):
//   0x00 4   "IMPM"
//   0x04 26  song name (NUL-padded)
//   0x1E 2   pattern row-highlight (ignored)
//   0x20 2   OrdNum   · 0x22 2 InsNum · 0x24 2 SmpNum · 0x26 2 PatNum
//   0x28 2   Cwt/v (created-with tracker version; >= 0x0215 selects IT215 sample
//            decompression, else IT214) · 0x2A 2 Cmwt (compatible-with)
//   0x2C 2   Flags · 0x2E 2 Special
//   0x30 1   global volume · 0x31 1 mix volume · 0x32 1 initial speed ·
//   0x33 1   initial tempo · 0x34 1 pan separation · 0x35 1 pitch-wheel depth
//   0x36 2   message length · 0x38 4 message offset · 0x3C 4 reserved
//   0x40 64  channel pan · 0x80 64 channel volume
//   0xC0 OrdNum bytes  order list (0xFF = end marker "---", 0xFE = skip "+++")
//   then InsNum × u32 instrument-header offsets
//   then SmpNum × u32 sample-header offsets
//   then PatNum × u32 pattern offsets  (an offset of 0 = empty/absent)
//
// SAMPLE HEADER (80 bytes, at each sample offset):
//   0x00 4  "IMPS" · 0x04 12 DOS filename · 0x10 1 (00)
//   0x11 1  global volume · 0x12 1 Flg · 0x13 1 default volume
//   0x14 26 sample name · 0x2E 1 Cvt · 0x2F 1 default pan
//   0x30 4  length (in SAMPLES, not bytes) · 0x34 4 loop begin · 0x38 4 loop end
//   0x3C 4  C5Speed · 0x40 4 sustain-loop begin · 0x44 4 sustain-loop end
//   0x48 4  sample-data pointer (file offset) · 0x4C 4 vibrato s/d/r/type
//   Flg bits: 0x01 has-sample · 0x02 16-bit · 0x04 stereo · 0x08 COMPRESSED
//             0x10 loop · 0x20 sustain-loop · 0x40/0x80 ping-pong
//   Cvt bits: 0x01 signed PCM (else unsigned) · 0x02 big-endian 16-bit ·
//             0x04 delta-encoded (running sum) · 0x08 byte-delta (rare)
//
// SAMPLE DATA (at the sample-data pointer):
//   • Uncompressed: `length` samples. 8-bit = 1 byte each, 16-bit = 2 bytes LE
//     (BE if Cvt 0x02). Unsigned → subtract midpoint (128 / 32768). Cvt 0x04 →
//     values are deltas, running-sum before use. Normalize (8-bit /128, 16-bit
//     /32768) into [ItSample.pcm].
//   • Compressed (Flg 0x08): IT214/IT215 variable-bit-width delta bitstream —
//     decoded by the separate, unit-tested decoder (see it_reader.dart / the
//     it214 decode section of the contract). IT215 (double delta) when
//     Cwt/v >= 0x0215, else IT214 (single delta).
//
// PATTERN (at each non-zero pattern offset):
//   0x00 2 packed length (bytes) · 0x02 2 rows · 0x04 4 reserved · 0x08 packed…
//   Unpack (per-channel "last" caches, channels 0..63):
//     read u8 channelvar; 0 ⇒ end of this row. channel = (channelvar-1) & 63.
//     if (channelvar & 0x80): read u8 mask, cache it for this channel; else reuse
//       the cached mask. Then, in order:
//       mask&0x01 → read note byte (cache)   · mask&0x02 → read instrument (cache)
//       mask&0x04 → read vol/pan byte (cache) · mask&0x08 → read command + value
//       mask&0x10 → reuse cached note · 0x20 reuse instrument · 0x40 reuse vol ·
//       0x80 reuse command+value.
//     note byte: 0..119 pitch (60 = middle C-5), 254 = note cut, 255 = note off.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';

/// Thrown when bytes aren't a parseable `.it` (bad signature, too short…).
class ItFormatException implements Exception {
  const ItFormatException(this.message);
  final String message;
  @override
  String toString() => 'ItFormatException: $message';
}

/// One sample. [pcm] is fully decoded (uncompressed OR IT214/215) and NORMALIZED
/// to [-1, 1], so it's uniform and bridge-ready.
class ItSample {
  const ItSample({
    this.name = '',
    this.filename = '',
    this.globalVolume = 64,
    this.defaultVolume = 64,
    this.sixteenBit = false,
    this.stereo = false,
    this.compressed = false,
    this.length = 0,
    this.loopStart = 0,
    this.loopEnd = 0,
    this.loop = false,
    this.c5speed = 8363,
    this.pan = 128,
    this.pingPong = false,
    required this.pcm,
    this.pcmRight,
  });

  factory ItSample.empty() => ItSample(pcm: Float64List(0));

  final String name, filename;
  final int globalVolume, defaultVolume; // 0..64
  final bool sixteenBit;
  final bool stereo;
  final bool compressed; // whether the SOURCE was IT214/215 compressed
  final int length; // declared length in samples
  final int loopStart, loopEnd;
  final bool loop;
  final int c5speed; // playback rate at C-5

  /// Default stereo position 0 left … 128 centre … 255 right, from the sample
  /// header's default-pan byte (128 = no explicit default pan).
  final int pan;

  final bool pingPong; // Flg 0x40 — bidirectional loop
  final Float64List pcm;
  final Float64List? pcmRight;

  bool get isEmpty => pcm.isEmpty;
}

/// One note cell. Absent fields use sentinels: [note] and [volpan] are -1 when
/// not present; [instrument] and [command] are 0.
class ItCell {
  const ItCell({
    this.note = -1,
    this.instrument = 0,
    this.volpan = -1,
    this.command = 0,
    this.commandValue = 0,
  });

  static const empty = ItCell();
  static const noteCut = 254;
  static const noteOff = 255;

  final int note; // -1 absent, 0..119 pitch, 254 cut, 255 off
  final int instrument; // 0 absent, else 1..99 (sample/instrument number)
  final int volpan; // -1 absent, else 0..212 volume/pan column
  final int command, commandValue;

  bool get isEmpty =>
      note == -1 &&
      instrument == 0 &&
      volpan == -1 &&
      command == 0 &&
      commandValue == 0;

  @override
  bool operator ==(Object other) =>
      other is ItCell &&
      other.note == note &&
      other.instrument == instrument &&
      other.volpan == volpan &&
      other.command == command &&
      other.commandValue == commandValue;

  @override
  int get hashCode =>
      Object.hash(note, instrument, volpan, command, commandValue);
}

class ItEnvelope {
  const ItEnvelope({
    this.points = const [],
    this.enabled = false,
    this.loopStart,
    this.loopEnd,
    this.sustainStart,
    this.sustainEnd,
  });

  final List<(int, int)> points; // (tick, value)
  final bool enabled;
  final int? loopStart, loopEnd, sustainStart, sustainEnd;
}

/// A pattern: [numRows] rows × [channelCount] cells (padded to the highest
/// channel index actually used, +1).
class ItPattern {
  const ItPattern(this.rows, this.channelCount);
  final List<List<ItCell>> rows;
  final int channelCount;
  int get numRows => rows.length;
}

/// An IT instrument: the note→sample keyboard map (offset 0x40 in the IMPI
/// header). In instrument mode a cell's `instrument` number selects one of
/// these, and the PLAYED note indexes [keymap] to pick the actual sample (and
/// [noteMap] the note to sound). Sample-mode files have none.
class ItInstrument {
  const ItInstrument({
    required this.keymap,
    required this.noteMap,
    this.name = '',
    this.nna = 0,
    this.dct = 0,
    this.dca = 0,
    this.fadeout = 0,
    this.pps = 0,
    this.ppc = 0,
    this.globalVolume = 128,
    this.defaultPan = 32,
    this.randomVolume = 0,
    this.randomPan = 0,
    this.volumeEnvelope = const ItEnvelope(),
    this.panEnvelope = const ItEnvelope(),
    this.pitchEnvelope = const ItEnvelope(),
    this.rawHeader = const [],
  });

  /// 120 entries: the 1-based sample number for each input note (0 = no sample).
  final List<int> keymap;

  /// 120 entries: the note actually played for each input note (usually 1:1).
  final List<int> noteMap;
  final String name;
  final int nna, dct, dca, fadeout, pps, ppc;
  final int globalVolume, defaultPan, randomVolume, randomPan;
  final ItEnvelope volumeEnvelope, panEnvelope, pitchEnvelope;

  /// Original 554-byte IMPI header, when available. This preserves IT
  /// envelopes and instrument behavior for same-format roundtrips.
  final List<int> rawHeader;

  factory ItInstrument.identity() => ItInstrument(
        keymap: List<int>.filled(120, 0),
        noteMap: [for (var i = 0; i < 120; i++) i],
      );
}

/// A parsed Impulse Tracker module.
class ItModule {
  const ItModule({
    this.name = '',
    this.channelCount = 0,
    this.instrumentCount = 0,
    this.initialSpeed = 6,
    this.initialTempo = 125,
    this.globalVolume = 128,
    this.createdWith = 0x0214,
    this.compatibleWith = 0x0200,
    this.special = 0,
    this.rowHighlight = 0,
    this.flags = 9,
    this.mixVolume = 48,
    this.panSeparation = 128,
    this.pitchWheelDepth = 0,
    this.channelPans = const [],
    this.channelVolumes = const [],
    required this.order,
    required this.patterns,
    required this.samples,
    this.instruments = const [],
  });

  final String name;
  final int channelCount; // max used across patterns
  final int instrumentCount; // InsNum
  final int initialSpeed, initialTempo, globalVolume, flags, createdWith;
  final int compatibleWith, special, rowHighlight;
  final int mixVolume, panSeparation, pitchWheelDepth;

  /// IT header channel state, indexed by channel (pan 0..64, volume 0..64).
  final List<int> channelPans, channelVolumes;
  final List<int> order; // OrdNum entries (0xFF end, 0xFE skip)
  final List<ItPattern> patterns;
  final List<ItSample> samples;

  /// Parsed instrument headers (empty for sample-mode files). Indexed 0-based;
  /// a cell's 1-based instrument number is `instruments[n - 1]`.
  final List<ItInstrument> instruments;

  bool get usesInstruments => instruments.isNotEmpty;
}

/// MIDI note for an IT note byte (IT note 60 = middle C-5 = MIDI 60; they align).
/// Returns -1 for absent / cut / off / out-of-range.
int itNoteToMidi(int note) => (note >= 0 && note < 120) ? note : -1;
