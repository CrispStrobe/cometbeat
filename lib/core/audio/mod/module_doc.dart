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
//   • Per-cell EFFECTS ARE carried and mapped cross-format: [DocCell] holds a
//     neutral MOD-numbered `effect`/`effectParam` PLUS the raw
//     `nativeEffect`/`nativeEffectParam`, and module_convert.dart maps between
//     each format's command set (MOD nibble ↔ S3M/IT letters ↔ XM) — every
//     `Sxy` with an audible target now survives A→B. The residual drops (e.g.
//     `SF`/`Z` external MIDI, native-only provenance) are reported honestly by
//     module_export_report.dart, not silently lost.
//   • Instruments are 1-based (matching the tracker cell convention). Generic
//     cross-format conversions flatten XM/IT keymaps, while the Advanced
//     Tracker song export path reconstructs native XM/IT instruments.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/it_module.dart';
import 'package:comet_beat/core/audio/mod/s3m_module.dart';
import 'package:comet_beat/core/audio/mod/xm_module.dart';

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
    // 128 is neutral in the cross-format model; IT sample global volume is
    // normalized from its native 0..64 field when present.
    this.globalVolume = 128,
    this.volume = 64,
    this.loopStart = 0,
    this.loopLength = 0,
    this.sustainLoopStart = 0,
    this.sustainLoopLength = 0,
    this.sustainPingPong = false,
    this.c5speed = 8363,
    this.pan = 128,
    this.pingPong = false,
    this.sixteenBit = false,
    this.filterCutoff = -1,
    this.filterResonance = 0,
    this.volumeEnvelope = const DocEnvelope(),
    this.panEnvelope = const DocEnvelope(),
    this.adlibData,
    required this.pcm,
    this.pcmRight,
  });

  factory DocSample.empty() => DocSample(pcm: Float64List(0));

  final String name;

  /// Native per-sample gain where supported. 128 is neutral; IT contributes
  /// its native 0..64 value.
  final int globalVolume;
  final int volume; // 0..64 default volume
  final int loopStart; // in samples
  final int loopLength; // in samples (0 = no loop)
  final int sustainLoopStart; // IT sustain-loop start, in samples
  final int sustainLoopLength; // IT sustain-loop length (0 = none)
  final int c5speed; // playback rate (Hz) at the C-5 reference

  /// Default stereo position, 0 = hard left … 128 = centre … 255 = hard right.
  /// XM carries this per sample; MOD/S3M default to centre here.
  final int pan;

  final bool pingPong; // bidirectional ("ping-pong") loop (IT/XM flag)
  final bool sustainPingPong; // IT sustain-loop direction

  /// Store the sample at 16-bit depth where the container supports it (XM/IT).
  /// Default false = the classic 8-bit sample (byte-identical export). MOD/S3M
  /// ignore this (MOD is 8-bit only); the XM/IT writers honour it.
  final bool sixteenBit;

  /// IT initial filter cutoff (0..127; -1 = none/disabled) and resonance
  /// (0..127; 0 = none), carried from the owning IT instrument so a single
  /// SampleInstrument voice can apply the resonant low-pass. Non-IT formats
  /// leave these at their neutral defaults.
  final int filterCutoff;
  final int filterResonance;

  /// The instrument's volume / panning envelopes (XM/IT carry these on the
  /// instrument; MOD/S3M have none, so these stay empty there).
  final DocEnvelope volumeEnvelope, panEnvelope;

  /// For an S3M AdLib (type-2) instrument, the 12-byte OPL register block
  /// (header 0x10..0x1B). Non-null marks this sample as a dynamic OPL voice
  /// rather than PCM; the import builds an `OplInstrument` from it. Null for
  /// every ordinary PCM sample.
  final List<int>? adlibData;

  final Float64List pcm;
  final Float64List? pcmRight;

  bool get isEmpty => pcm.isEmpty;
}

/// A tracker instrument independent of its sample storage. IT's NNA/DCT/DCA,
/// fadeout, tuning, gain, randomization, and keymap live here rather than on
/// a flattened sample. Envelopes use the shared [DocEnvelope] representation.
class DocInstrument {
  const DocInstrument({
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
    this.filterCutoff = -1,
    this.filterResonance = 0,
    this.filterEnvelope = false,
    this.keymap = const [],
    this.noteMap = const [],
    this.volumeEnvelope = const DocEnvelope(),
    this.panEnvelope = const DocEnvelope(),
    this.pitchEnvelope = const DocEnvelope(),
    this.rawHeader = const [],
  });

  final String name;
  final int nna, dct, dca, fadeout, pps, ppc;
  final int globalVolume, defaultPan, randomVolume, randomPan;

  /// IT initial filter cutoff (0..127; -1 = none) / resonance (0..127; 0 = none)
  /// and whether the pitch envelope is a filter envelope (deferred).
  final int filterCutoff, filterResonance;
  final bool filterEnvelope;
  final List<int> keymap, noteMap;
  final DocEnvelope volumeEnvelope, panEnvelope, pitchEnvelope;

  /// Compatibility bytes for fields not yet interpreted by the neutral model.
  final List<int> rawHeader;
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
    this.nativeEffect = -1,
    this.nativeEffectParam = 0,
    this.nativeInstrument = 0,
    this.nativeInstrumentSet = false,
    this.nativeNote = -1,
    this.nativeVolpan = -1,
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
        effectParam = 0,
        nativeEffect = -1,
        nativeEffectParam = 0,
        nativeInstrument = 0,
        nativeInstrumentSet = false,
        nativeNote = -1,
        nativeVolpan = -1;

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

  /// Original command encoding for lossless same-format writes. [effect] is
  /// the mapped neutral command; this retains commands without a common
  /// equivalent, such as IT Q/V/W/Y commands.
  final int nativeEffect; // -1 when unavailable
  final int nativeEffectParam;
  final int nativeInstrument; // original IT instrument number, or 0
  final bool nativeInstrumentSet;
  final int nativeNote; // original IT note byte, or -1
  final int nativeVolpan; // original IT volume/pan byte, or -1

  bool get isEmpty =>
      note == -1 &&
      instrument == 0 &&
      volume == -1 &&
      !noteOff &&
      effect == 0 &&
      effectParam == 0 &&
      nativeEffect == -1 &&
      nativeInstrument == 0 &&
      nativeNote == -1 &&
      nativeVolpan == -1;

  @override
  bool operator ==(Object other) =>
      other is DocCell &&
      other.note == note &&
      other.instrument == instrument &&
      other.volume == volume &&
      other.noteOff == noteOff &&
      other.effect == effect &&
      other.effectParam == effectParam &&
      other.nativeEffect == nativeEffect &&
      other.nativeEffectParam == nativeEffectParam &&
      other.nativeInstrument == nativeInstrument &&
      other.nativeInstrumentSet == nativeInstrumentSet &&
      other.nativeNote == nativeNote &&
      other.nativeVolpan == nativeVolpan;

  @override
  int get hashCode => Object.hash(
        note,
        instrument,
        volume,
        noteOff,
        effect,
        effectParam,
        nativeEffect,
        nativeEffectParam,
        nativeInstrument,
        nativeInstrumentSet,
        nativeNote,
        nativeVolpan,
      );
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
    this.xmTrackerName = '',
    this.xmVersion = 0x0104,
    this.xmRestart = 0,
    this.xmRawHeader = const [],
    this.channelCount = 0,
    this.initialSpeed = 6,
    this.initialTempo = 125,
    this.globalVolume = 128,
    this.itCreatedWith = 0x0214,
    this.itCompatibleWith = 0x0200,
    this.itSpecial = 0,
    this.itRowHighlight = 0,
    this.s3mMasterVolume = 48,
    this.s3mUltraClick = 0,
    this.s3mDefaultPan = 0,
    this.s3mChannelSettings = const [],
    this.s3mSampleFormat = 1,
    this.s3mFlags = 0,
    this.s3mCreatedWith = 0x1320,
    this.s3mDefaultPans = const [],
    this.s3mRawOrder = const [],
    this.s3mPatterns = const [],
    this.s3mSamples = const [],
    this.itFlags = 9,
    this.itMixVolume = 48,
    this.itPanSeparation = 128,
    this.itPitchWheelDepth = 0,
    this.linearFrequency = false,
    this.channelPans = const [],
    this.channelVolumes = const [],
    this.itInstrumentHeaders = const [],
    this.itInstruments = const [],
    this.itSamples = const [],
    this.xmInstruments = const [],
    this.xmPatterns = const [],
    required this.sourceFormat,
    required this.order,
    required this.patterns,
    required this.samples,
  });

  final String title;
  final String xmTrackerName;
  final int xmVersion;
  final int xmRestart;
  final List<int> xmRawHeader;
  final int channelCount;
  final int initialSpeed, initialTempo;

  /// Container global volume normalized to the IT 0..128 scale.
  final int globalVolume;
  final int itCreatedWith;
  final int itCompatibleWith, itSpecial, itRowHighlight;
  final int s3mMasterVolume, s3mUltraClick, s3mDefaultPan;
  final List<int> s3mChannelSettings;
  final int s3mSampleFormat;
  final int s3mFlags, s3mCreatedWith;
  final List<int> s3mDefaultPans;
  final List<int> s3mRawOrder;
  final List<S3mPattern> s3mPatterns;
  final List<S3mSample> s3mSamples;

  /// Original IT header flags, including instrument mode and slide mode.
  final int itFlags;
  final int itMixVolume, itPanSeparation, itPitchWheelDepth;
  final bool linearFrequency;

  /// Optional native channel state. IT uses pan 0..64 and volume 0..64.
  final List<int> channelPans, channelVolumes;

  /// Original IT instrument headers for lossless IT -> IT conversion.
  final List<List<int>> itInstrumentHeaders;
  final List<DocInstrument> itInstruments;
  final List<ItSample> itSamples;

  /// Native XM instruments retained for lossless XM -> XM conversion. The
  /// neutral sample list remains available for cross-format conversion.
  final List<XmInstrument> xmInstruments;
  final List<XmPattern> xmPatterns;
  final ModuleFormat sourceFormat;
  final List<int> order; // pattern indices
  final List<DocPattern> patterns;
  final List<DocSample> samples; // index k-1 for instrument k

  /// Non-empty samples only (convenience for "borrow a sample" pickers).
  Iterable<DocSample> get usedSamples => samples.where((s) => !s.isEmpty);
}
