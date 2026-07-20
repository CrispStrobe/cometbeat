// lib/core/audio/mod/module_doc.dart
//
// ModuleDoc — a common, format-neutral module model that all four readers map
// INTO and (eventually) all writers map OUT of. It is the hub for cross-format
// conversion (MOD/S3M/XM/IT): any A→B is `parseAnyModule` (→ ModuleDoc) then a
// writer. See module_convert.dart for the adapters, and docs/TRACKER_IDEAS.md §A.
//
// Design notes / deliberate lossiness (v1):
//   • Pitch is carried as MIDI note numbers, so a note keeps its PITCH across
//     formats even though each format numbers octaves differently.
//   • Sample PCM is normalized to [-1, 1] (Float64List) — the common currency
//     (MOD/S3M Int8List /128, XM/IT already normalized).
//   • Per-cell EFFECTS are dropped on the neutral model for now: command
//     semantics differ per format (MOD nibble vs S3M/IT letters vs XM), so a
//     faithful mapping needs a cross-format effect table (a documented follow-up).
//     Notes + instrument + volume-column + samples + song structure convert
//     cleanly, which is what "convert & play the tune" needs.
//   • Instruments are 1-based (matching the tracker cell convention); instrument
//     k refers to samples[k-1]. Multi-sample XM/IT instruments collapse to their
//     first sample in v1.

import 'dart:typed_data';

/// The source container format a [ModuleDoc] was read from.
enum ModuleFormat { mod, s3m, xm, it }

/// A volume or panning envelope in the neutral model — the shape XM and IT
/// share: [points] are `(tick, value)` breakpoints (value 0..64; pan is centred
/// at 32), with an optional [sustain] point and a [loopStart]..[loopEnd] loop
/// (all indices into [points]), gated by [enabled]. A disabled/empty envelope
/// means the sample has none.
class DocEnvelope {
  const DocEnvelope({
    this.points = const [],
    this.sustain,
    this.loopStart,
    this.loopEnd,
    this.enabled = false,
  });

  final List<(int, int)> points; // (x in ticks, y 0..64)
  final int? sustain; // sustain-point index, or null
  final int? loopStart, loopEnd; // loop-point indices, or null
  final bool enabled;

  bool get isEmpty => !enabled || points.isEmpty;
}

/// A sample in the neutral model. [pcm] is normalized to [-1, 1].
class DocSample {
  const DocSample({
    this.name = '',
    this.volume = 64,
    this.loopStart = 0,
    this.loopLength = 0,
    this.c5speed = 8363,
    this.pan = 128,
    this.pingPong = false,
    this.sixteenBit = false,
    this.volumeEnvelope = const DocEnvelope(),
    this.panEnvelope = const DocEnvelope(),
    required this.pcm,
  });

  factory DocSample.empty() => DocSample(pcm: Float64List(0));

  final String name;
  final int volume; // 0..64 default volume
  final int loopStart; // in samples
  final int loopLength; // in samples (0 = no loop)
  final int c5speed; // playback rate (Hz) at the C-5 reference

  /// Default stereo position, 0 = hard left … 128 = centre … 255 = hard right.
  /// XM carries this per sample; MOD/S3M default to centre here.
  final int pan;

  final bool pingPong; // bidirectional ("ping-pong") loop (IT/XM flag)

  /// Store the sample at 16-bit depth where the container supports it (XM/IT).
  /// Default false = the classic 8-bit sample (byte-identical export). MOD/S3M
  /// ignore this (MOD is 8-bit only); the XM/IT writers honour it.
  final bool sixteenBit;

  /// The instrument's volume / panning envelopes (XM/IT carry these on the
  /// instrument; MOD/S3M have none, so these stay empty there).
  final DocEnvelope volumeEnvelope, panEnvelope;

  final Float64List pcm;

  bool get isEmpty => pcm.isEmpty;
}

/// One cell in the neutral model. Absent fields use sentinels.
class DocCell {
  const DocCell({
    this.note = -1,
    this.instrument = 0,
    this.volume = -1,
    this.noteOff = false,
    this.effect = 0,
    this.effectParam = 0,
  });

  /// A key-off cell: stops the ringing note (the formats' note-off / note-cut).
  /// Distinct from an empty cell, which lets the note ring on. Readers don't
  /// emit these yet; the Score→ModuleDoc bridge uses them so a rest survives the
  /// round-trip (an empty cell would be absorbed into the held note).
  const DocCell.off()
      : note = -1,
        instrument = 0,
        volume = -1,
        noteOff = true,
        effect = 0,
        effectParam = 0;

  static const empty = DocCell();

  final int note; // -1 = none, else MIDI note 0..127
  final int instrument; // 0 = none, else 1-based
  final int volume; // -1 = none, else 0..64 (volume column)
  final bool noteOff; // true = key-off (stop the ringing note)

  /// The effect column, in the ORIGINAL format's encoding. For MOD this is the
  /// 4-bit command nibble (0..15) + the 8-bit param, which map 1:1 onto the
  /// tracker replayer's `fxCmd`/`fxParam`. Only MOD import populates these so
  /// far; S3M/XM/IT use different command numbering and stay 0 until a
  /// cross-format effect table lands (see the module_doc header notes).
  final int effect; // 0 = none (0/0), else the format's effect command
  final int effectParam; // 0..255

  bool get isEmpty =>
      note == -1 &&
      instrument == 0 &&
      volume == -1 &&
      !noteOff &&
      effect == 0 &&
      effectParam == 0;

  @override
  bool operator ==(Object other) =>
      other is DocCell &&
      other.note == note &&
      other.instrument == instrument &&
      other.volume == volume &&
      other.noteOff == noteOff &&
      other.effect == effect &&
      other.effectParam == effectParam;

  @override
  int get hashCode =>
      Object.hash(note, instrument, volume, noteOff, effect, effectParam);
}

/// A pattern: [numRows] rows × [channelCount] cells.
class DocPattern {
  const DocPattern(this.rows, this.channelCount);
  final List<List<DocCell>> rows;
  final int channelCount;
  int get numRows => rows.length;
}

/// A format-neutral module.
class ModuleDoc {
  const ModuleDoc({
    this.title = '',
    this.channelCount = 0,
    this.initialSpeed = 6,
    this.initialTempo = 125,
    required this.sourceFormat,
    required this.order,
    required this.patterns,
    required this.samples,
  });

  final String title;
  final int channelCount;
  final int initialSpeed, initialTempo;
  final ModuleFormat sourceFormat;
  final List<int> order; // pattern indices
  final List<DocPattern> patterns;
  final List<DocSample> samples; // index k-1 for instrument k

  /// Non-empty samples only (convenience for "borrow a sample" pickers).
  Iterable<DocSample> get usedSamples => samples.where((s) => !s.isEmpty);
}
