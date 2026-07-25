// lib/core/audio/mod/mod_module.dart
//
// The data model + format contract for the ProTracker `.mod` codec (the reader
// lives in mod_reader.dart, the writer in mod_writer.dart). Pure Dart
// (dart:typed_data only) so it's testable Flutter-free and reusable.
//
// ─────────────────────────────────────────────────────────────────────────────
// ProTracker `.mod` byte layout (4-channel "M.K." and friends). All multi-byte
// integers are BIG-ENDIAN. This block is the authoritative contract the
// reader/writer implement against.
//
//   offset  size  field
//   0       20    module title (ASCII, NUL-padded)
//   20      31×30 sample descriptors, each 30 bytes:
//                   0   22  sample name (ASCII, NUL-padded)
//                   22  2   sample length in WORDS (×2 = bytes)
//                   24  1   finetune — low nibble, signed −8..+7 (two's comp of 4 bits)
//                   25  1   volume 0..64
//                   26  2   repeat point in WORDS
//                   28  2   repeat length in WORDS
//   950     1     song length (number of order positions used, 1..128)
//   951     1     restart position (historically 127; preserved, not interpreted)
//   952     128   order table (pattern number per song position)
//   1080    4     signature: "M.K."/"M!K!"/"FLT4"/"4CHN" → 4ch, "6CHN" → 6,
//                   "8CHN"/"OCTA"/"FLT8" → 8, "%dCH"/"%dCHN" → that many
//   1084    …     pattern data: [maxPatternRef+1] patterns, each
//                   64 rows × channelCount × 4 bytes. A 4-byte cell decodes as:
//                     sample = (b0 & 0xF0) | (b2 >> 4)
//                     period = ((b0 & 0x0F) << 8) | b1        (0 = no note)
//                     effect = b2 & 0x0F
//                     param  = b3
//   …       …     sample PCM: signed 8-bit, concatenated in sample order,
//                   each `length_words × 2` bytes.
//
// A repeat length of 1 word means "no loop". Sample/repeat lengths are stored in
// words; this model exposes them in SAMPLES (bytes), converting on read/write.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';

/// Thrown when bytes are not a parseable `.mod` (too short, unknown signature…).
class ModFormatException implements Exception {
  const ModFormatException(this.message);
  final String message;
  @override
  String toString() => 'ModFormatException: $message';
}

/// One of a module's (always 31) instrument slots. An unused slot has an empty
/// [pcm] and length 0.
class ModSample {
  const ModSample({
    this.name = '',
    this.volume = 64,
    this.finetune = 0,
    this.repeatPoint = 0,
    this.repeatLength = 0,
    required this.pcm,
  });

  /// Silent, zero-length slot (for the unused samples in a sparse module).
  factory ModSample.empty() => ModSample(pcm: Int8List(0));

  final String name; // ≤ 22 chars
  final int volume; // 0..64
  final int finetune; // −8..+7
  final int repeatPoint; // in samples
  final int repeatLength; // in samples (≤ 1 → no loop)

  /// Signed 8-bit PCM (length is authoritative; the descriptor's word-length is
  /// derived as `(pcm.length + 1) ~/ 2` on write).
  final Int8List pcm;

  bool get isEmpty => pcm.isEmpty;
}

/// One note cell for one channel on one row. All-zero = empty cell.
class ModCell {
  const ModCell({
    this.sample = 0,
    this.period = 0,
    this.effect = 0,
    this.effectParam = 0,
  });

  static const empty = ModCell();

  final int sample; // 0 = none, else 1..31
  final int period; // 0 = no note, else Amiga period
  final int effect; // 0..15
  final int effectParam; // 0..255

  bool get isEmpty =>
      sample == 0 && period == 0 && effect == 0 && effectParam == 0;

  @override
  bool operator ==(Object other) =>
      other is ModCell &&
      other.sample == sample &&
      other.period == period &&
      other.effect == effect &&
      other.effectParam == effectParam;

  @override
  int get hashCode => Object.hash(sample, period, effect, effectParam);
}

/// A pattern: 64 rows × [channelCount] cells.
class ModPattern {
  const ModPattern(this.rows);

  /// `rows[0..63][0..channelCount-1]`.
  final List<List<ModCell>> rows;

  int get channelCount => rows.isEmpty ? 0 : rows.first.length;
}

/// A parsed ProTracker module.
class ModModule {
  const ModModule({
    this.title = '',
    this.channelCount = 4,
    this.restart = 127,
    this.signature = '',
    required this.samples, // exactly 31
    required this.order, // length = song length (1..128)
    required this.patterns,
  });

  final String title; // ≤ 20 chars
  final int channelCount;
  final int restart;

  /// The original 4-byte signature tag read from offset 0x438 (e.g. "OCTA",
  /// "FLT8", "CD81", "M!K!"). Empty on a synthetically-built module, in which
  /// case the writer computes a canonical tag from the channel/pattern count.
  /// When non-empty the writer emits these bytes verbatim, so a same-format
  /// read→write roundtrip reproduces the source tag byte-for-byte.
  final String signature;

  final List<ModSample> samples; // exactly 31
  final List<int> order; // song positions → pattern index
  final List<ModPattern> patterns;

  int get songLength => order.length;
}

// ─────────────────────────────────────────────────────────────────────────────
// Period ↔ note helpers (finetune 0). The bridge (mod ↔ Tracker) uses these to
// map Amiga periods to MIDI notes and back.
// ─────────────────────────────────────────────────────────────────────────────

/// ProTracker finetune-0 periods, 36 notes C-1..B-3 (3 octaves), index 0 = C-1.
const List<int> modPeriods = [
  856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453, // C-1..B-1
  428, 404, 381, 360, 339, 320, 302, 285, 269, 254, 240, 226, // C-2..B-2
  214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113, // C-3..B-3
];

/// MIDI note for [modPeriods] index 0 (C-1). ProTracker's "C-2" (period 428,
/// index 12) is treated as middle-ish C4 = 60, so index 0 → 48.
const int modNoteBaseMidi = 48;

/// Nearest note index (0..35) for a raw [period]; -1 for a 0 (no-note) period.
int periodToNoteIndex(int period) {
  if (period <= 0) return -1;
  var best = 0;
  var bestDist = (modPeriods[0] - period).abs();
  for (var i = 1; i < modPeriods.length; i++) {
    final d = (modPeriods[i] - period).abs();
    if (d < bestDist) {
      bestDist = d;
      best = i;
    }
  }
  return best;
}

/// MIDI note nearest to [period] (−1 for a no-note period).
int periodToMidi(int period) {
  final i = periodToNoteIndex(period);
  return i < 0 ? -1 : modNoteBaseMidi + i;
}

/// The finetune-0 period nearest to [midi] (clamped into the 36-note table).
int midiToPeriod(int midi) {
  final i = (midi - modNoteBaseMidi).clamp(0, modPeriods.length - 1);
  return modPeriods[i];
}
