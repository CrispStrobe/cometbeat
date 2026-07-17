// lib/core/audio/mod/s3m_module.dart
//
// Model + format contract for the Scream Tracker 3 `.s3m` reader (implemented in
// s3m_reader.dart). Pure Dart. Read-only for now (the module ecosystem has no
// reusable writers — see docs/TRACKER_HANDOVER.md §6).
//
// ─── S3M byte layout (little-endian; the authoritative contract) ─────────────
// HEADER (96 bytes @ 0x00):
//   0x00  28  song title (ASCII, NUL-padded)
//   0x1C  1   0x1A (EOF)
//   0x1D  1   type (16 = ST3 module)
//   0x20  2   ordNum  (order-list length, always even)
//   0x22  2   insNum  (instrument count)
//   0x24  2   patNum  (pattern count)
//   0x26  2   flags
//   0x28  2   created-with-tracker version
//   0x2A  2   sample format (1 = signed PCM, 2 = UNSIGNED PCM)
//   0x2C  4   "SCRM" signature
//   0x30  1   global volume · 0x31 initial speed · 0x32 initial tempo
//   0x33  1   master volume · 0x34 ultra-click · 0x35 default-pan (252 = pan block present)
//   0x40  32  channel settings — one byte per channel; a value < 128 = enabled,
//             255 = disabled. channelCount = number of enabled channels.
// Then, contiguously:
//   ordNum bytes  order list (pattern indices; 254 = "++" skip marker, 255 = end)
//   insNum × 2    instrument PARAPOINTERS (each × 16 = file offset)
//   patNum × 2    pattern  PARAPOINTERS (each × 16 = file offset)
//   [32 bytes default pan, only if default-pan byte == 252]
//
// INSTRUMENT (at its parapointer, 80 bytes):
//   0x00 type (1 = PCM sample) · 0x01 12-byte DOS filename
//   0x0D memseg: byte@0x0D = high, u16@0x0E = low → sample data offset = memseg × 16
//   0x10 u32 length · 0x14 u32 loopBegin · 0x18 u32 loopEnd
//   0x1C volume · 0x1E pack (0 = unpacked) · 0x1F flags (1 loop, 2 stereo, 4 16-bit)
//   0x20 u32 C2 speed · 0x30 28-byte sample name · 0x4C "SCRS"
//   PCM at (memseg × 16), `length` bytes (unsigned if sample-format == 2 → convert
//   to signed by (b - 128)).
//
// PATTERN (at its parapointer): u16 packed length (INCLUDES its own 2 bytes),
//   then packed rows for 64 rows. Each entry starts with a "what" byte:
//     bit5 (0x20) → note byte + instrument byte follow
//     bit6 (0x40) → volume byte follows
//     bit7 (0x80) → command byte + info byte follow
//     low 5 bits  → channel number
//     what == 0x00 → end of the current row
//   Note byte: hi nibble = octave, lo nibble = semitone (0..11); 255 = empty,
//   254 = note-off.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';

/// Thrown when bytes aren't a parseable `.s3m` (bad signature, too short…).
class S3mFormatException implements Exception {
  const S3mFormatException(this.message);
  final String message;
  @override
  String toString() => 'S3mFormatException: $message';
}

/// A PCM sample instrument.
class S3mSample {
  const S3mSample({
    this.name = '',
    this.volume = 64,
    this.c2spd = 8363,
    this.loopStart = 0,
    this.loopEnd = 0,
    this.loop = false,
    required this.pcm,
  });

  factory S3mSample.empty() => S3mSample(pcm: Int8List(0));

  final String name;
  final int volume;
  final int c2spd; // playback rate at C-4/C-2 reference
  final int loopStart, loopEnd;
  final bool loop;

  /// Signed 8-bit PCM (unsigned source is converted on read).
  final Int8List pcm;

  bool get isEmpty => pcm.isEmpty;
}

/// One note cell. `note == emptyNote` is blank; `note == noteOff` is a note-off.
class S3mCell {
  const S3mCell({
    this.note = emptyNote,
    this.instrument = 0,
    this.volume = noVolume,
    this.command = 0,
    this.info = 0,
  });

  static const empty = S3mCell();
  static const emptyNote = 255;
  static const noteOff = 254;
  static const noVolume = 255;

  final int note; // (octave << 4) | semitone, or empty/off
  final int instrument; // 0 = none
  final int volume; // 255 = none
  final int command, info;

  bool get isEmpty =>
      note == emptyNote &&
      instrument == 0 &&
      volume == noVolume &&
      command == 0 &&
      info == 0;

  @override
  bool operator ==(Object other) =>
      other is S3mCell &&
      other.note == note &&
      other.instrument == instrument &&
      other.volume == volume &&
      other.command == command &&
      other.info == info;

  @override
  int get hashCode => Object.hash(note, instrument, volume, command, info);
}

/// A pattern: 64 rows × [channelCount] cells.
class S3mPattern {
  const S3mPattern(this.rows);
  final List<List<S3mCell>> rows;
  int get channelCount => rows.isEmpty ? 0 : rows.first.length;
}

/// A parsed Scream Tracker 3 module.
class S3mModule {
  const S3mModule({
    this.title = '',
    this.channelCount = 0,
    this.globalVolume = 64,
    this.initialSpeed = 6,
    this.initialTempo = 125,
    required this.order,
    required this.samples,
    required this.patterns,
  });

  final String title;
  final int channelCount;
  final int globalVolume, initialSpeed, initialTempo;
  final List<int> order; // pattern indices (254/255 markers removed)
  final List<S3mSample> samples;
  final List<S3mPattern> patterns;
}

/// A MIDI note for an S3M note byte (approximate; octave<<4 | semitone → MIDI).
/// Returns -1 for empty/note-off.
int s3mNoteToMidi(int note) =>
    (note == S3mCell.emptyNote || note == S3mCell.noteOff)
        ? -1
        : (note >> 4) * 12 + (note & 0x0F) + 12;
