// lib/core/audio/mod/xm_module.dart
//
// Model + format contract for the FastTracker 2 `.xm` reader (implemented in
// xm_reader.dart). Pure Dart, read-only (see docs/TRACKER_HANDOVER.md §6).
//
// ─── XM byte layout (little-endian; the authoritative contract) ──────────────
// HEADER:
//   0x00 17  "Extended Module: "
//   0x11 20  module name (NUL-padded)
//   0x25 1   0x1A
//   0x26 20  tracker name
//   0x3A 2   version (0x0104)
//   0x3C 4   header size, measured FROM 0x3C (usually 276). Pattern data starts
//            at 0x3C + headerSize.
//   0x40 2   song length (order entries used)   · 0x42 2 restart position
//   0x44 2   numChannels                        · 0x46 2 numPatterns
//   0x48 2   numInstruments                     · 0x4A 2 flags (bit0 = linear freq)
//   0x4C 2   default tempo (ticks/row)          · 0x4E 2 default BPM
//   0x50 256 order table (pattern index per song position)
//
// PATTERNS (numPatterns, back to back, starting at 0x3C+headerSize):
//   4  pattern header length (=9)  · 1 packing type (0) · 2 numRows · 2 packed size
//   packed data (packed size bytes), then the next pattern.
//   Packed cell: read byte b. If (b & 0x80): b is a mask — bit0 note, bit1
//   instrument, bit2 volume, bit3 effect, bit4 param; read each present field (in
//   that order). Else b IS the note and all five fields follow. A cell not present
//   is empty. Cells are row-major: numChannels cells per row, numRows rows.
//   note: 0 = none, 1..96 = pitch (1 = C-0), 97 = note-off.
//
// INSTRUMENTS (numInstruments, back to back, after the patterns):
//   4  instrument header size · 22 name · 1 type · 2 numSamples
//   (if numSamples>0: 4 sampleHeaderSize, then keymap/envelopes — SKIP by jumping
//    to instrumentStart + instrumentHeaderSize.) Then numSamples × 40-byte sample
//   headers, then all sample data (in order):
//     sample header: 4 length(bytes) · 4 loopStart · 4 loopLength · 1 volume ·
//       1 finetune(signed) · 1 type(bits0-1 loop, bit4 = 16-bit) · 1 panning ·
//       1 relativeNote(signed) · 1 reserved · 22 name
//     sample data is DELTA-encoded: 8-bit → running sum of signed bytes; 16-bit →
//       running sum of signed 16-bit little-endian words. Decode to raw, then
//       normalize (8-bit /128, 16-bit /32768) into [pcm].
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';

/// Thrown when bytes aren't a parseable `.xm` (bad signature, too short…).
class XmFormatException implements Exception {
  const XmFormatException(this.message);
  final String message;
  @override
  String toString() => 'XmFormatException: $message';
}

/// One sample within an instrument. [pcm] is delta-DECODED and NORMALIZED to
/// [-1, 1] (so 8- and 16-bit are uniform and bridge-ready).
class XmSample {
  const XmSample({
    this.name = '',
    this.volume = 64,
    this.finetune = 0,
    this.relativeNote = 0,
    this.pan = 128,
    this.loopStart = 0,
    this.loopLength = 0,
    this.sixteenBit = false,
    this.pingPong = false,
    required this.pcm,
  });

  factory XmSample.empty() => XmSample(pcm: Float64List(0));

  final String name;
  final int volume; // 0..64
  final int finetune; // -128..127
  final int relativeNote; // signed semitone transpose
  final int pan; // 0 hard left … 128 centre … 255 hard right
  final int loopStart, loopLength;
  final bool sixteenBit;
  final bool pingPong; // loop-type 2 (bidirectional)
  final Float64List pcm;

  bool get isEmpty => pcm.isEmpty;
}

/// A volume or panning envelope: `(tick, value)` points (value 0..64), an
/// optional sustain point + loop (indices into [points]), gated by [enabled].
class XmEnvelope {
  const XmEnvelope({
    this.points = const [],
    this.sustain,
    this.loopStart,
    this.loopEnd,
    this.enabled = false,
  });
  final List<(int, int)> points;
  final int? sustain, loopStart, loopEnd;
  final bool enabled;
}

/// An instrument: a name, its samples, and its volume / panning envelopes.
class XmInstrument {
  const XmInstrument({
    this.name = '',
    required this.samples,
    this.volumeEnvelope = const XmEnvelope(),
    this.panEnvelope = const XmEnvelope(),
  });
  final String name;
  final List<XmSample> samples;
  final XmEnvelope volumeEnvelope, panEnvelope;
}

/// One note cell. `note == 0` empty, `note == 97` note-off.
class XmCell {
  const XmCell({
    this.note = 0,
    this.instrument = 0,
    this.volume = 0,
    this.effect = 0,
    this.effectParam = 0,
  });

  static const empty = XmCell();
  static const noteOff = 97;

  final int note; // 0 none, 1..96 pitch, 97 off
  final int instrument;
  final int volume;
  final int effect, effectParam;

  bool get isEmpty =>
      note == 0 &&
      instrument == 0 &&
      volume == 0 &&
      effect == 0 &&
      effectParam == 0;

  @override
  bool operator ==(Object other) =>
      other is XmCell &&
      other.note == note &&
      other.instrument == instrument &&
      other.volume == volume &&
      other.effect == effect &&
      other.effectParam == effectParam;

  @override
  int get hashCode =>
      Object.hash(note, instrument, volume, effect, effectParam);
}

/// A pattern: [numRows] rows × [channelCount] cells.
class XmPattern {
  const XmPattern(this.rows);
  final List<List<XmCell>> rows;
  int get numRows => rows.length;
  int get channelCount => rows.isEmpty ? 0 : rows.first.length;
}

/// A parsed FastTracker 2 module.
class XmModule {
  const XmModule({
    this.name = '',
    this.channelCount = 0,
    this.defaultTempo = 6,
    this.defaultBpm = 125,
    this.restart = 0,
    required this.order,
    required this.patterns,
    required this.instruments,
  });

  final String name;
  final int channelCount;
  final int defaultTempo, defaultBpm, restart;
  final List<int> order; // pattern indices (song length entries)
  final List<XmPattern> patterns;
  final List<XmInstrument> instruments;
}

/// MIDI note for an XM note byte (approximate: note 1 = C-0 → MIDI 12; ignores
/// relativeNote/finetune). Returns -1 for none / note-off.
int xmNoteToMidi(int note) =>
    (note == 0 || note == XmCell.noteOff) ? -1 : note + 11;
