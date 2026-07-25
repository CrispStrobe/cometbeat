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
    this.cvt = 1,
    this.rawData,
    this.length = 0,
    this.loopStart = 0,
    this.loopEnd = 0,
    this.loop = false,
    this.sustainStart = 0,
    this.sustainEnd = 0,
    this.sustain = false,
    this.sustainPingPong = false,
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
  final int cvt; // original sample conversion flags
  final Uint8List? rawData; // original compressed blocks, when retained
  final int length; // declared length in samples
  final int loopStart, loopEnd, sustainStart, sustainEnd;
  final bool loop;
  final bool sustain;
  final bool sustainPingPong;
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
    this.loopEnabled = false,
    this.sustainEnabled = false,
    this.loopStart,
    this.loopEnd,
    this.sustainStart,
    this.sustainEnd,
  });

  final List<(int, int)> points; // (tick, value)
  final bool enabled;
  final bool loopEnabled;
  final bool sustainEnabled;
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
    this.initialFilterCutoff = -1,
    this.initialFilterResonance = 0,
    this.filterEnvelope = false,
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

  /// IT initial filter cutoff (IMPI byte 0x3A). The high bit is the "enabled"
  /// flag; the low 7 bits are the 0..127 cutoff. -1 = absent/disabled (no
  /// filter). 127 = enabled but fully open (also effectively no filter).
  final int initialFilterCutoff;

  /// IT initial filter resonance (IMPI byte 0x3B), 0..127. 0 = none.
  final int initialFilterResonance;

  /// Whether the pitch envelope is flagged as a FILTER envelope (IMPI pitch-env
  /// flag bit 0x80). Parsed for completeness; applying it is a documented
  /// follow-up (see it_reader.dart / the renderer).
  final bool filterEnvelope;
  final ItEnvelope volumeEnvelope, panEnvelope, pitchEnvelope;

  /// Original 554-byte IMPI header, when available. This preserves IT
  /// envelopes and instrument behavior for same-format roundtrips.
  final List<int> rawHeader;

  factory ItInstrument.identity() => ItInstrument(
        keymap: List<int>.filled(120, 0),
        noteMap: [for (var i = 0; i < 120; i++) i],
      );
}

/// The IT embedded MIDI-macro configuration (the "MidiCfg" block), present when
/// the header Special word has bit 0x08 set. It is laid out as 9 global "MIDI
/// out" macros, then 16 parametric SFx macros (SF0..SFF), then 128 fixed Zxx
/// macros — each a NUL-padded 32-byte ASCII string of hex nibbles plus the
/// parameter placeholder `z`.
///
/// A `Zxx` pattern effect resolves through this table: values 0x00..0x7F run the
/// channel's active parametric macro (SFx) with the low 7 bits substituted for
/// `z`; values 0x80..0xFF run fixed macro (value & 0x7F). Of all the macro forms,
/// only the resonant-filter macros are renderable here — `F0F000` sets cutoff and
/// `F0F001` sets resonance (the canonical IT filter macros). Every other macro is
/// a MIDI event to external gear with no audible target in this offline renderer;
/// it is parsed and ignored.
///
/// DEFERRED: per-channel active-macro selection (`\SFx`). The active parametric
/// macro is assumed to be 0 (the IT default), which is what all real modules that
/// do not explicitly switch macros use. Full `z`-parameter arithmetic beyond the
/// direct substitution is likewise a follow-up.
class ItMidiMacros {
  const ItMidiMacros({
    required this.global,
    required this.sfx,
    required this.zxx,
  });

  /// Bytes per macro slot in the on-disk MidiCfg block.
  static const int macroLength = 32;

  /// Slot counts: 9 global, 16 parametric (SF0..SFF), 128 fixed (Zxx). The total
  /// on-disk block is (9 + 16 + 128) × 32 = 4896 bytes.
  static const int globalCount = 9;
  static const int sfxCount = 16;
  static const int zxxCount = 128;
  static const int blockBytes =
      (globalCount + sfxCount + zxxCount) * macroLength;

  /// The 9 global MIDI-out event macros (start/stop/tick/note-on/off/volume/pan/
  /// bank/program). Parsed for completeness; none are renderable here.
  final List<String> global;

  /// The 16 parametric SFx macros (SF0..SFF), triggered by `Zxx` values
  /// 0x00..0x7F through the channel's active macro (assumed 0).
  final List<String> sfx;

  /// The 128 fixed Zxx macros, triggered by `Zxx` values 0x80..0xFF (index =
  /// value & 0x7F).
  final List<String> zxx;

  /// Resolve a `Zxx` effect [value] to the kFxSetFilter param (a cutoff 0..0x7F,
  /// or `0x80 | resonance`) for the renderer, honoring these macros. Returns null
  /// when the resolved macro is NOT a recognized filter macro (a MIDI-out macro
  /// with no audible target — parse-and-ignore).
  ///
  /// For the DEFAULT filter macro set (SF0 = `F0F000z` cutoff, fixed Zxx[n] =
  /// `F0F001nn` resonance) this returns [value] unchanged, i.e. it is identical to
  /// the direct `Zxx→filter` mapping (Z00..Z7F cutoff, Z80..ZFF resonance).
  int? resolveZxxFilterParam(int value) {
    final String macro;
    final int? param;
    if (value < 0x80) {
      // Parametric: active macro assumed 0 (see class doc). `z` ← low 7 bits.
      macro = sfx.isNotEmpty ? sfx[0] : '';
      param = value & 0x7F;
    } else {
      final idx = value & 0x7F;
      macro = idx < zxx.length ? zxx[idx] : '';
      param = null; // a fixed macro carries its own value
    }
    return _recognizeFilterParam(macro, param);
  }

  /// True when the table is the IT DEFAULT filter set — i.e.
  /// [resolveZxxFilterParam] reproduces the direct mapping for every `Zxx` value.
  bool get isDefaultFilterSet {
    for (var v = 0; v < 256; v++) {
      if (resolveZxxFilterParam(v) != v) return false;
    }
    return true;
  }

  static String _clean(String macro) =>
      macro.replaceAll(RegExp(r'\s+'), '').toUpperCase();

  /// Recognize a filter macro string: `F0F000`→cutoff, `F0F001`→resonance,
  /// followed by either the `z` placeholder (→[param]) or two hex digits (a fixed
  /// value). Returns the kFxSetFilter param, or null if not a filter macro.
  static int? _recognizeFilterParam(String macro, int? param) {
    final s = _clean(macro);
    final bool cutoff;
    if (s.startsWith('F0F000')) {
      cutoff = true;
    } else if (s.startsWith('F0F001')) {
      cutoff = false;
    } else {
      return null;
    }
    final rest = s.substring(6);
    int? val;
    if (rest.startsWith('Z')) {
      val = param; // parameter substitution
    } else if (rest.length >= 2) {
      val = int.tryParse(rest.substring(0, 2), radix: 16);
    } else if (rest.isEmpty) {
      val = param; // "F0F000"/"F0F001" alone → take the parameter
    }
    if (val == null) return null;
    val &= 0x7F;
    return cutoff ? val : (0x80 | val);
  }
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
    this.midiMacros,
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

  /// The embedded MIDI-macro configuration, or null when the header Special word
  /// has no MidiCfg (bit 0x08 clear). Null ⇒ the implicit IT default macro set,
  /// i.e. the direct `Zxx→filter` mapping (see [ItMidiMacros]).
  final ItMidiMacros? midiMacros;

  bool get usesInstruments => instruments.isNotEmpty;
}

/// MIDI note for an IT note byte (IT note 60 = middle C-5 = MIDI 60; they align).
/// Returns -1 for absent / cut / off / out-of-range.
int itNoteToMidi(int note) => (note >= 0 && note < 120) ? note : -1;
