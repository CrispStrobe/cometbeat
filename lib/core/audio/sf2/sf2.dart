// SoundFont 2 (.sf2) reader — turns a soundfont into tracker instruments.
//
// An SF2 is a RIFF file: raw 16-bit PCM for ALL samples concatenated in
// `sdta/smpl`, plus a `pdta` list of tables. This reader does two things:
//
//   1. SAMPLE extraction — every `shdr` header → an [Sf2Sample] (name, PCM,
//      rate, original MIDI key, loop region). Verified on a real 520-sample
//      soundfont.
//   2. GM PRESET → ZONE mapping — walks phdr/pbag/pgen → inst/ibag/igen → shdr,
//      resolving each preset (bank/program, e.g. GM program 0 = Acoustic Grand)
//      into KEY-SPLIT zones. [Sf2Instrument] renders a preset by picking the
//      zone covering each note's key and resampling that sample from its root
//      key (reusing the engine's sample loop) — a real multi-sample GM voice.
//
// Handles UNCOMPRESSED `.sf2` (raw PCM in `smpl`) directly. For a compressed
// `.sf3` (e.g. MuseScore's FluidR3Mono), each `smpl` byte range `[start,end)` is
// a self-contained OGG-Vorbis stream (verified on the real file: all 1186
// streams begin `OggS`); pass a [VorbisDecode] to `parse(bytes, vorbis: …)` to
// decode them (the app injects a glint-backed decoder — see
// docs/GLINT_VORBIS_HANDOVER.md), else `.sf3` throws a clear error
// ([sf2IsCompressed] pre-checks). Flutter-free, pure Dart.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';

/// Decodes ONE complete Ogg-Vorbis logical stream (the bytes of a single `.sf3`
/// sample) to mono PCM in ±1.0. The app injects a glint-backed implementation
/// (native FFI / web wasm — see docs/GLINT_VORBIS_HANDOVER.md); tests inject a
/// fake. Returning `null` means "couldn't decode this stream" (skipped).
typedef VorbisDecode = Float64List? Function(Uint8List oggStream);

// SF2 generator operators we read.
const _genKeyRange = 43;
const _genVelRange = 44;
const _genInstrument = 41;
const _genSampleId = 53;
const _genRootKeyOverride = 58;
const _genInitialAttenuation = 48; // centibels
const _genCoarseTune = 51; // semitones (signed)
const _genFineTune = 52; // cents (signed)
// Volume-envelope generators (timecents; sustain in centibels of attenuation).
const _genDelayVolEnv = 33;
const _genAttackVolEnv = 34;
const _genHoldVolEnv = 35;
const _genDecayVolEnv = 36;
const _genSustainVolEnv = 37;
const _genReleaseVolEnv = 38;
const _genInitialFilterFc = 8; // low-pass cutoff, absolute cents
const _genInitialFilterQ = 9; // resonance, centibels
const _genPan = 17; // 0.1% units, −500 (left) .. +500 (right)
const _genChorusSend = 15; // 0.1% units, 0..1000 (per-instrument chorus)
const _genReverbSend = 16; // 0.1% units, 0..1000 (per-instrument reverb)
const _genExclusiveClass = 57; // same-class notes cut each other off
const _genSampleModes = 54; // 0 none · 1 loop · 3 loop until release
const _genScaleTuning =
    56; // cents of pitch change per key (100 = normal, 0 = drums)
// LFO generators. modLFO can sweep pitch (gen 5) and volume (gen 13); vibLFO
// sweeps pitch (gen 6). Delays are timecents; freqs are absolute cents.
const _genModLfoToPitch = 5; // cents
const _genVibLfoToPitch = 6; // cents
const _genModLfoToVolume = 13; // centibels
const _genDelayModLfo = 21;
const _genFreqModLfo = 22;
const _genDelayVibLfo = 23;
const _genFreqVibLfo = 24;
// Modulation envelope: a 2nd DAHDSR that can sweep pitch (gen 7) and filter
// cutoff (gen 11) — the attack "bite" of many instruments (a kick's click that
// opens the cutoff then decays back to its body). Times are timecents; sustain
// is in 0.1% of full-scale DECREASE (0 = hold at peak, 1000 = decay to zero).
const _genModEnvToPitch = 7; // cents
const _genModEnvToFilterFc = 11; // cents
const _genDelayModEnv = 25;
const _genAttackModEnv = 26;
const _genHoldModEnv = 27;
const _genDecayModEnv = 28;
const _genSustainModEnv = 29; // 0.1% decrease
const _genReleaseModEnv = 30;
// Sample play start offset (added to the shdr start): gen 0 in samples, gen 4 in
// units of 32768 samples. Skips a lead-in so the attack lands as authored.
const _genStartAddrsOffset = 0;
const _genStartAddrsCoarseOffset = 4;
// Loop-point offsets (added to the shdr loop start/end), in samples.
const _genStartLoopAddrsOffset = 2;
const _genEndLoopAddrsOffset = 3;
// Key→volume-envelope scaling (timecents per key away from 60): higher keys get
// shorter hold/decay — a piano's high notes ring shorter than its low ones.
const _genKeynumToVolEnvHold = 39;
const _genKeynumToVolEnvDecay = 40;

/// One sample from a soundfont: its decoded PCM (−1..1), the rate it was
/// recorded at, the MIDI key it represents ([originalPitch]), and its loop
/// region (sample offsets relative to this sample's start; `loopEnd > loopStart`
/// means it loops).
class Sf2Sample {
  const Sf2Sample({
    required this.name,
    required this.pcm,
    required this.sampleRate,
    required this.originalPitch,
    required this.pitchCorrection,
    required this.loopStart,
    required this.loopEnd,
    this.sampleType = 1,
  });

  final String name;
  final Float64List pcm;
  final int sampleRate;
  final int originalPitch;

  /// Fine tuning of the recording, in cents (SF2 shdr `chPitchCorrection`): the
  /// sample sounds this many cents sharp of [originalPitch]. Baked into the
  /// resample so the instrument plays in tune.
  final int pitchCorrection;

  final int loopStart;
  final int loopEnd;

  /// shdr `sampleType` (ROM flag stripped): 1 mono · 2 right · 4 left · 8 linked.
  final int sampleType;
  bool get isRight => sampleType == 2;
  bool get isLeft => sampleType == 4;

  bool get loops => loopEnd > loopStart && loopEnd <= pcm.length;
}

/// One key-split zone of a preset: the sample (by shdr index) to play for MIDI
/// keys [keyLo]..[keyHi], the MIDI key that sample is tuned to ([rootKey] — a
/// zone override, or -1 meaning "use the sample's own original pitch"), and the
/// zone's level + tuning generators.
class Sf2Zone {
  const Sf2Zone({
    required this.keyLo,
    required this.keyHi,
    required this.sampleIndex,
    required this.rootKey,
    this.velLo = 0,
    this.velHi = 127,
    this.attenuationCb = 0,
    this.coarseTune = 0,
    this.fineTune = 0,
    this.delayVolTc = -12000,
    this.attackVolTc = -12000,
    this.holdVolTc = -12000,
    this.decayVolTc = -12000,
    this.sustainVolCb = 0,
    this.releaseVolTc = -12000,
    this.filterFcCents = 13500,
    this.filterQCb = 0,
    this.modLfoToPitchCents = 0,
    this.vibLfoToPitchCents = 0,
    this.modLfoToVolumeCb = 0,
    this.delayModLfoTc = -12000,
    this.freqModLfoCents = 0,
    this.delayVibLfoTc = -12000,
    this.freqVibLfoCents = 0,
    this.panTenthPct = 0,
    this.exclusiveClass = 0,
    this.sampleModes = 0,
    this.scaleTuning = 100,
    this.velFilterMods = const [],
    this.modEnvToPitchCents = 0,
    this.modEnvToFilterCents = 0,
    this.delayModEnvTc = -12000,
    this.attackModEnvTc = -12000,
    this.holdModEnvTc = -12000,
    this.decayModEnvTc = -12000,
    this.sustainModEnvPermille = 0,
    this.releaseModEnvTc = -12000,
    this.sampleStartOffset = 0,
    this.loopStartOffset = 0,
    this.loopEndOffset = 0,
    this.key2VolEnvHoldTc = 0,
    this.key2VolEnvDecayTc = 0,
    this.reverbSendPermille = 0,
    this.chorusSendPermille = 0,
  });

  final int keyLo;
  final int keyHi;
  final int sampleIndex;
  final int rootKey;

  /// Volume-envelope generators. Times are timecents (seconds = 2^(tc/1200));
  /// the SF2 default −12000 tc ≈ 1 ms (effectively a gate). [sustainVolCb] is
  /// the decay target in centibels of attenuation (0 = full level).
  final int delayVolTc;
  final int attackVolTc;
  final int holdVolTc;
  final int decayVolTc;
  final int sustainVolCb;
  final int releaseVolTc;

  static double _tcSec(int tc) => pow(2, tc / 1200).toDouble();
  double get delayVolSec => _tcSec(delayVolTc);
  double get attackVolSec => _tcSec(attackVolTc);
  double get holdVolSec => _tcSec(holdVolTc);
  double get decayVolSec => _tcSec(decayVolTc);
  double get releaseVolSec => _tcSec(releaseVolTc);

  /// The sustain level as a linear gain (0..1): `10^(−cB/200)`.
  double get sustainGain =>
      pow(10, -sustainVolCb.clamp(0, 1440) / 200).toDouble();

  /// The low-pass filter: `initialFilterFc` (gen 8, absolute cents) and
  /// `initialFilterQ` (gen 9, centibels of resonance). The default 13500 cents
  /// (≈ 20 kHz) + 0 cB is a wide-open, non-resonant filter.
  final int filterFcCents;
  final int filterQCb;

  /// The filter cutoff in Hz: `8.176 · 2^(cents/1200)`.
  double get filterCutoffHz => 8.176 * pow(2, filterFcCents / 1200).toDouble();

  /// A biquad Q from the resonance: `10^((dB − 3.01)/20)`, so 0 cB → ~0.707
  /// (Butterworth, flat) and higher cB peaks.
  double get filterQ => pow(10, (filterQCb / 10 - 3.01) / 20).toDouble();

  /// LFO modulation. modLFO → pitch (gen 5) + volume (gen 13); vibLFO → pitch
  /// (gen 6). Depths default 0 (no effect), so an unset font is unchanged.
  final int modLfoToPitchCents;
  final int vibLfoToPitchCents;
  final int modLfoToVolumeCb;
  final int delayModLfoTc;
  final int freqModLfoCents;
  final int delayVibLfoTc;
  final int freqVibLfoCents;

  double get modLfoHz => 8.176 * pow(2, freqModLfoCents / 1200).toDouble();
  double get vibLfoHz => 8.176 * pow(2, freqVibLfoCents / 1200).toDouble();
  double get delayModLfoSec => _tcSec(delayModLfoTc);
  double get delayVibLfoSec => _tcSec(delayVibLfoTc);

  /// Zone pan (gen 17), −1 (hard left) .. +1 (hard right); 0 = centre.
  final int panTenthPct;
  double get pan => (panTenthPct / 500.0).clamp(-1.0, 1.0);

  /// Exclusive class (gen 57): a new note of the same class on the same channel
  /// cuts off any still-sounding one (open vs closed hi-hat). 0 = none.
  final int exclusiveClass;

  /// sampleModes (gen 54): 0 = no loop, 1 = loop, 3 = loop until note-off then
  /// play to the sample end. (2 is reserved → treated as no loop.)
  final int sampleModes;
  bool get loopEnabled => sampleModes == 1 || sampleModes == 3;
  bool get loopUntilRelease => sampleModes == 3;

  /// scaleTuning (gen 56): cents of pitch change per MIDI key away from the root
  /// (100 = normal chromatic, 0 = untuned — a drum kit's key selects a different
  /// sample, not a transposition). Drives how much [keyLo]..[keyHi] shifts pitch.
  final int scaleTuning;

  /// Velocity→filter-cutoff modulators (SF2 imod), flattened as `[amount, dir,
  /// type, …]` cents triples. Empty → the SF2 default (darken soft notes by up
  /// to 2400 cents). A drum kit adds a positive one so a hard hit opens a low
  /// base cutoff into its bright "click".
  final List<int> velFilterMods;

  /// Modulation envelope (a 2nd DAHDSR) and its targets. [modEnvToFilterCents]
  /// sweeps the filter cutoff and [modEnvToPitchCents] the pitch by the envelope
  /// value (0..1). [sustainModEnvPermille] is the DECREASE in 0.1% units, so the
  /// sustain level is `1 − permille/1000`. Times are timecents.
  final int modEnvToPitchCents;
  final int modEnvToFilterCents;
  final int delayModEnvTc;
  final int attackModEnvTc;
  final int holdModEnvTc;
  final int decayModEnvTc;
  final int sustainModEnvPermille;
  final int releaseModEnvTc;

  double get delayModEnvSec => _tcSec(delayModEnvTc);
  double get attackModEnvSec => _tcSec(attackModEnvTc);
  double get holdModEnvSec => _tcSec(holdModEnvTc);
  double get decayModEnvSec => _tcSec(decayModEnvTc);
  double get releaseModEnvSec => _tcSec(releaseModEnvTc);

  /// The mod-envelope sustain level (0..1): 1 − permille/1000.
  double get modEnvSustain =>
      (1 - sustainModEnvPermille / 1000).clamp(0.0, 1.0);

  /// Whether this zone's mod envelope actually modulates anything.
  bool get hasModEnv => modEnvToFilterCents != 0 || modEnvToPitchCents != 0;

  /// The sample offset (in frames) to start playback at (SF2 gens 0 + 4).
  final int sampleStartOffset;

  /// Loop-point offsets (SF2 gens 2/3), added to the sample's shdr loop points.
  final int loopStartOffset;
  final int loopEndOffset;

  /// Key→volume-envelope scaling (SF2 gens 39/40): timecents added to the hold /
  /// decay time per key ABOVE 60, so a font's high notes ring shorter.
  final int key2VolEnvHoldTc;
  final int key2VolEnvDecayTc;

  /// Per-instrument effects sends (SF2 gens 16/15), in 0.1% units (0..1000) —
  /// the font's authored reverb/chorus amount for this zone.
  final int reverbSendPermille;
  final int chorusSendPermille;
  double get reverbSend => (reverbSendPermille / 1000).clamp(0.0, 1.0);
  double get chorusSend => (chorusSendPermille / 1000).clamp(0.0, 1.0);

  /// The hold / decay time in seconds for MIDI [key], with the SF2 key-scaling
  /// applied (each key above 60 shortens it by [key2VolEnvHoldTc]/[…DecayTc]).
  double volEnvHoldSec(int key) =>
      _tcSec(holdVolTc + key2VolEnvHoldTc * (60 - key));
  double volEnvDecaySec(int key) =>
      _tcSec(decayVolTc + key2VolEnvDecayTc * (60 - key));

  /// The cutoff modulation in cents for MIDI [vel] (0..1), summing this zone's
  /// velocity→filter modulators — or the SF2 default when it has none.
  double velFilterCents(double vel) {
    if (velFilterMods.isEmpty) {
      return -2400 * (1 - vel); // SF2 default modulator
    }
    var sum = 0.0;
    for (var i = 0; i + 2 < velFilterMods.length; i += 3) {
      final amount = velFilterMods[i];
      final dir = velFilterMods[i + 1];
      final type = velFilterMods[i + 2];
      var v = dir == 1 ? 1 - vel : vel; // direction
      if (type == 1) {
        v = v * v; // concave (approx): slow rise
      } else if (type == 2) {
        v = 1 - (1 - v) * (1 - v); // convex (approx): fast rise
      }
      sum += amount * v;
    }
    return sum;
  }

  /// velRange (gen 44): the MIDI velocity window this zone (sample layer) covers,
  /// so a soft vs loud note picks a different recording. Default 0..127 (the
  /// whole range) when the instrument isn't velocity-split.
  final int velLo;
  final int velHi;

  /// initialAttenuation (gen 48), in centibels (0 = full; +cB = quieter).
  final int attenuationCb;

  /// coarseTune (gen 51), in semitones, and fineTune (gen 52), in cents —
  /// applied on top of the sample's own pitch correction.
  final int coarseTune;
  final int fineTune;

  /// The linear gain from [attenuationCb] (dB = cB/10 → gain = 10^(-dB/20)).
  double get gain => pow(10, -attenuationCb / 200).toDouble();

  bool covers(int key) => key >= keyLo && key <= keyHi;

  /// Whether this zone covers both [key] and MIDI [vel] (a velocity-split layer).
  bool coversKeyVel(int key, int vel) =>
      covers(key) && vel >= velLo && vel <= velHi;
}

/// A resolved preset: a General MIDI voice ([bank]/[program], e.g. program 0 =
/// Acoustic Grand Piano) as a list of key-split [zones].
class Sf2Preset {
  const Sf2Preset({
    required this.name,
    required this.bank,
    required this.program,
    required this.zones,
  });

  final String name;
  final int bank;
  final int program;
  final List<Sf2Zone> zones;
}

/// A parsed soundfont: its [samples] (by shdr index) + resolved [presets].
class Sf2SoundFont {
  Sf2SoundFont(this._samplesByShdr, this.presets);

  final List<Sf2Sample?> _samplesByShdr;
  final List<Sf2Preset> presets;

  /// The extracted samples (skipping EOS / empty header records).
  List<Sf2Sample> get samples => _samplesByShdr.whereType<Sf2Sample>().toList();

  /// The sample referenced by shdr index [i], or null if out of range/empty.
  Sf2Sample? sampleAt(int i) =>
      (i >= 0 && i < _samplesByShdr.length) ? _samplesByShdr[i] : null;

  /// Parse a SoundFont byte buffer. An uncompressed `.sf2` reads raw PCM; a
  /// compressed `.sf3` (OGG-Vorbis samples) is decoded via [vorbis] — pass a
  /// glint-backed decoder to support `.sf3`, else a `.sf3` throws a clear error
  /// (see [sf2IsCompressed]). Throws [FormatException] if the RIFF/sfbk structure
  /// or required chunks are missing.
  factory Sf2SoundFont.parse(Uint8List bytes, {VorbisDecode? vorbis}) {
    final data = ByteData.sublistView(bytes);
    if (_tag(bytes, 0) != 'RIFF' || _tag(bytes, 8) != 'sfbk') {
      throw const FormatException('not a RIFF/sfbk SoundFont');
    }

    // Collect the offset/length of every sub-chunk we care about. Chunk sizes
    // are attacker-controlled, so every `end`/recorded size is clamped to the
    // real buffer — a corrupt font can only ever yield a clean FormatException
    // downstream, never an out-of-bounds read. Valid fonts are unaffected (the
    // clamps are no-ops when sizes fit).
    final chunks = <String, (int, int)>{};
    var pos = 12; // past 'RIFF' <size> 'sfbk'
    while (pos + 8 <= bytes.length) {
      final ck = _tag(bytes, pos);
      final size = data.getUint32(pos + 4, Endian.little);
      final body = pos + 8;
      if (ck == 'LIST') {
        var sp = body + 4; // past the list type
        final end = min(body + size, bytes.length);
        while (sp + 8 <= end) {
          final sck = _tag(bytes, sp);
          final ssize = data.getUint32(sp + 4, Endian.little);
          // Bound the recorded size so every later read of this chunk stays
          // inside the buffer even if the header lies about its length.
          final avail = bytes.length - (sp + 8);
          chunks[sck] = (sp + 8, ssize < avail ? ssize : avail);
          sp = sp + 8 + ssize + (ssize.isOdd ? 1 : 0);
        }
      }
      pos = body + size + (size.isOdd ? 1 : 0);
    }

    final smpl = chunks['smpl'];
    final shdr = chunks['shdr'];
    if (smpl == null || shdr == null) {
      throw const FormatException('SoundFont missing smpl/shdr chunks');
    }
    // `.sf3` stores each sample as an OGG-Vorbis stream in `smpl` (starts with
    // the "OggS" magic) instead of raw PCM. With a [vorbis] decoder we decode
    // each stream; without one, fail with a clear, catchable message rather than
    // reading the compressed bytes as garbage PCM.
    final compressed = smpl.$2 >= 4 && _tag(bytes, smpl.$1) == 'OggS';
    if (compressed && vorbis == null) {
      throw const FormatException(
        'compressed .sf3 (OGG-Vorbis samples) needs a Vorbis decoder — '
        'pass Sf2SoundFont.parse(bytes, vorbis: …) or use an uncompressed .sf2',
      );
    }

    // Raw-PCM pool (uncompressed .sf2 only; .sf3 decodes per stream instead).
    final pool = compressed ? Int16List(0) : Int16List(smpl.$2 ~/ 2);
    if (!compressed) {
      for (var i = 0; i < pool.length; i++) {
        pool[i] = data.getInt16(smpl.$1 + i * 2, Endian.little);
      }
    }

    // shdr: 46-byte records → samples indexed by record number.
    const rec = 46;
    final shdrCount = shdr.$2 ~/ rec;
    final samplesByShdr = List<Sf2Sample?>.filled(shdrCount, null);
    for (var i = 0; i < shdrCount; i++) {
      final o = shdr.$1 + i * rec;
      final name = _cstr(bytes, o, 20);
      final start = data.getUint32(o + 20, Endian.little);
      final endS = data.getUint32(o + 24, Endian.little);
      final startLoop = data.getUint32(o + 28, Endian.little);
      final endLoop = data.getUint32(o + 32, Endian.little);
      final sr = data.getUint32(o + 36, Endian.little);
      final pitch = bytes[o + 40];
      final correction =
          data.getInt8(o + 41); // chPitchCorrection, signed cents
      final sampleType =
          data.getUint16(o + 44, Endian.little) & 0x7fff; // strip ROM flag
      if (name == 'EOS' || endS <= start) continue;

      final Float64List pcm;
      final int lStart;
      final int lEnd;
      if (compressed) {
        // .sf3: start/end are BYTE offsets into smpl delimiting this sample's
        // self-contained Ogg-Vorbis stream; loop points are absolute DECODED
        // sample-frame positions (0-based in the decoded PCM).
        if (smpl.$1 + endS > bytes.length) continue;
        final ogg =
            Uint8List.sublistView(bytes, smpl.$1 + start, smpl.$1 + endS);
        final decoded = vorbis!(ogg);
        if (decoded == null || decoded.isEmpty) continue;
        pcm = decoded;
        lStart = startLoop;
        lEnd = endLoop;
      } else {
        // .sf2: start/end are sample-frame offsets into the shared PCM pool;
        // loop points are absolute pool positions (→ relative to `start`).
        if (endS > pool.length) continue;
        final n = endS - start;
        pcm = Float64List(n);
        for (var j = 0; j < n; j++) {
          pcm[j] = pool[start + j] / 32768.0;
        }
        lStart = startLoop > start ? startLoop - start : 0;
        lEnd = endLoop > start ? endLoop - start : 0;
      }
      samplesByShdr[i] = Sf2Sample(
        name: name,
        pcm: pcm,
        sampleRate: sr == 0 ? kSampleRate : sr,
        originalPitch: pitch > 127 ? 60 : pitch,
        pitchCorrection: correction,
        loopStart: lStart,
        loopEnd: lEnd,
        sampleType: sampleType,
      );
    }

    final presets = _parsePresets(data, bytes, chunks, samplesByShdr.length);
    return Sf2SoundFont(samplesByShdr, presets);
  }
}

/// Walk phdr/pbag/pgen → inst/ibag/igen and resolve each preset into key-split
/// [Sf2Zone]s. A preset zone names an instrument (gen 41); the instrument's own
/// zones carry the key range (gen 43), sample (gen 53) and optional root-key
/// override (gen 58). Missing preset/instrument tables → no presets (samples
/// still extract).
List<Sf2Preset> _parsePresets(
  ByteData data,
  Uint8List bytes,
  Map<String, (int, int)> chunks,
  int sampleCount,
) {
  final phdr = chunks['phdr'];
  final pbag = chunks['pbag'];
  final pgen = chunks['pgen'];
  final inst = chunks['inst'];
  final ibag = chunks['ibag'];
  final igen = chunks['igen'];
  if ([phdr, pbag, pgen, inst, ibag, igen].contains(null)) return const [];

  int u16(int o) => data.getUint16(o, Endian.little);
  final phdrOff = phdr!.$1, instOff = inst!.$1;
  final pbagOff = pbag!.$1, ibagOff = ibag!.$1;
  final pgenOff = pgen!.$1, igenOff = igen!.$1;
  final phdrCount = phdr.$2 ~/ 38;
  final instCount = inst.$2 ~/ 22;
  final pbagCount = pbag.$2 ~/ 4, ibagCount = ibag.$2 ~/ 4;
  final pgenCount = pgen.$2 ~/ 4, igenCount = igen.$2 ~/ 4;
  // Instrument modulators (imod): each ibag record's 2nd u16 is its imod index.
  // We read only the velocity→filter-cutoff modulator (10-byte records) — the
  // one that gives a drum kit its high-velocity "click" (a low base cutoff that
  // opens wide on a hard hit). Absent imod → no mods → the SF2 default applies.
  final imod = chunks['imod'];
  final imodOff = imod?.$1 ?? 0;
  final imodCount = (imod?.$2 ?? 0) ~/ 10;
  // Preset modulators (pmod): a GM drum kit puts the high-velocity filter-open
  // at the PRESET level (its instrument zone zeroes the default darkening), so
  // these ADD to the instrument's velocity→filter modulation.
  final pmod = chunks['pmod'];
  final pmodOff = pmod?.$1 ?? 0;
  final pmodCount = (pmod?.$2 ?? 0) ~/ 10;

  int presetBagNdx(int i) => u16(phdrOff + i * 38 + 24);
  int instBagNdx(int i) => u16(instOff + i * 22 + 20);

  // Every zone's generators for one instrument, in ibag order. A leading zone
  // with no sampleID is the instrument's GLOBAL zone (defaults for the rest).
  List<_Gen> instZoneGens(int instIndex) {
    if (instIndex < 0 || instIndex + 1 >= instCount) return const [];
    final out = <_Gen>[];
    final ibStart = instBagNdx(instIndex);
    final ibEnd = instBagNdx(instIndex + 1).clamp(0, ibagCount - 1);
    for (var ib = ibStart; ib < ibEnd; ib++) {
      final g = _readGens(
        data,
        igenOff,
        u16(ibagOff + ib * 4),
        u16(ibagOff + (ib + 1) * 4),
        igenCount,
      );
      g.velFilterMods = _readVelFilterMods(
        data,
        imodOff,
        u16(ibagOff + ib * 4 + 2),
        u16(ibagOff + (ib + 1) * 4 + 2),
        imodCount,
      );
      out.add(g);
    }
    return out;
  }

  // Resolve one instrument zone [z] (falling back to the instrument GLOBAL zone
  // [ig], then SF2 defaults) and ADD the preset's generator offsets [p] — which
  // is how a GM font's preset-level attenuation/pan/tune balance its instruments
  // (SF2 §9.4: preset generators are relative and add to the instrument's). Key
  // and velocity windows INTERSECT with the preset's (they narrow, never widen).
  Sf2Zone? buildZone(_Gen z, _Gen? ig, _Gen p) {
    final sampleId = z.sampleId;
    if (sampleId == null || sampleId < 0 || sampleId >= sampleCount) {
      return null;
    }
    int iv(int? Function(_Gen) f, int dflt) =>
        f(z) ?? (ig == null ? null : f(ig)) ?? dflt; // instrument absolute
    int po(int? Function(_Gen) f) => f(p) ?? 0; // preset offset (absent → 0)
    final root = z.rootOverride ?? ig?.rootOverride;
    return Sf2Zone(
      keyLo: max(iv((g) => g.keyLo, 0), p.keyLo ?? 0),
      keyHi: min(iv((g) => g.keyHi, 127), p.keyHi ?? 127),
      velLo: max(iv((g) => g.velLo, 0), p.velLo ?? 0),
      velHi: min(iv((g) => g.velHi, 127), p.velHi ?? 127),
      sampleIndex: sampleId,
      rootKey: (root != null && root <= 127) ? root : -1,
      attenuationCb: iv((g) => g.atten, 0) + po((g) => g.atten),
      coarseTune: iv((g) => g.coarse, 0) + po((g) => g.coarse),
      fineTune: iv((g) => g.fine, 0) + po((g) => g.fine),
      delayVolTc: iv((g) => g.delayVol, -12000) + po((g) => g.delayVol),
      attackVolTc: iv((g) => g.attackVol, -12000) + po((g) => g.attackVol),
      holdVolTc: iv((g) => g.holdVol, -12000) + po((g) => g.holdVol),
      decayVolTc: iv((g) => g.decayVol, -12000) + po((g) => g.decayVol),
      sustainVolCb: iv((g) => g.sustainVol, 0) + po((g) => g.sustainVol),
      releaseVolTc: iv((g) => g.releaseVol, -12000) + po((g) => g.releaseVol),
      filterFcCents: iv((g) => g.filterFc, 13500) + po((g) => g.filterFc),
      filterQCb: iv((g) => g.filterQ, 0) + po((g) => g.filterQ),
      modLfoToPitchCents:
          iv((g) => g.modLfoPitch, 0) + po((g) => g.modLfoPitch),
      vibLfoToPitchCents:
          iv((g) => g.vibLfoPitch, 0) + po((g) => g.vibLfoPitch),
      modLfoToVolumeCb: iv((g) => g.modLfoVol, 0) + po((g) => g.modLfoVol),
      delayModLfoTc:
          iv((g) => g.delayModLfo, -12000) + po((g) => g.delayModLfo),
      freqModLfoCents: iv((g) => g.freqModLfo, 0) + po((g) => g.freqModLfo),
      delayVibLfoTc:
          iv((g) => g.delayVibLfo, -12000) + po((g) => g.delayVibLfo),
      freqVibLfoCents: iv((g) => g.freqVibLfo, 0) + po((g) => g.freqVibLfo),
      panTenthPct: iv((g) => g.pan, 0) + po((g) => g.pan),
      // Not additive from a preset (instrument-only per spec).
      exclusiveClass: iv((g) => g.exclusiveClass, 0),
      sampleModes: iv((g) => g.sampleModes, 0),
      scaleTuning: iv((g) => g.scaleTuning, 100),
      // Modulation envelope + its pitch/filter targets (additive, like the vol
      // env); and the sample play-start offset (gen 0 + gen 4×32768).
      modEnvToPitchCents:
          iv((g) => g.modEnvToPitch, 0) + po((g) => g.modEnvToPitch),
      modEnvToFilterCents:
          iv((g) => g.modEnvToFilter, 0) + po((g) => g.modEnvToFilter),
      delayModEnvTc:
          iv((g) => g.delayModEnv, -12000) + po((g) => g.delayModEnv),
      attackModEnvTc:
          iv((g) => g.attackModEnv, -12000) + po((g) => g.attackModEnv),
      holdModEnvTc: iv((g) => g.holdModEnv, -12000) + po((g) => g.holdModEnv),
      decayModEnvTc:
          iv((g) => g.decayModEnv, -12000) + po((g) => g.decayModEnv),
      sustainModEnvPermille:
          iv((g) => g.sustainModEnv, 0) + po((g) => g.sustainModEnv),
      releaseModEnvTc:
          iv((g) => g.releaseModEnv, -12000) + po((g) => g.releaseModEnv),
      sampleStartOffset:
          iv((g) => g.startOff, 0) + 32768 * iv((g) => g.startCoarse, 0),
      loopStartOffset: iv((g) => g.loopStartOff, 0) + po((g) => g.loopStartOff),
      loopEndOffset: iv((g) => g.loopEndOff, 0) + po((g) => g.loopEndOff),
      key2VolEnvHoldTc: iv((g) => g.key2VolHold, 0) + po((g) => g.key2VolHold),
      key2VolEnvDecayTc:
          iv((g) => g.key2VolDecay, 0) + po((g) => g.key2VolDecay),
      reverbSendPermille: iv((g) => g.reverbSend, 0) + po((g) => g.reverbSend),
      chorusSendPermille: iv((g) => g.chorusSend, 0) + po((g) => g.chorusSend),
      // Velocity→filter modulators: the instrument zone's (or the instrument
      // global zone's) PLUS the preset's (they add — a drum kit's high-velocity
      // filter-open lives at the preset level). Empty → SF2 default at play time.
      velFilterMods: [
        ...((z.velFilterMods?.isNotEmpty ?? false)
            ? z.velFilterMods!
            : (ig?.velFilterMods ?? const [])),
        ...?p.velFilterMods,
      ],
    );
  }

  final presets = <Sf2Preset>[];
  for (var pi = 0; pi + 1 < phdrCount; pi++) {
    final name = _cstr(bytes, phdrOff + pi * 38, 20);
    if (name == 'EOP') continue;
    final program = u16(phdrOff + pi * 38 + 20);
    final bank = u16(phdrOff + pi * 38 + 22);
    final bagStart = presetBagNdx(pi);
    final bagEnd = presetBagNdx(pi + 1).clamp(0, pbagCount - 1);
    // Parse every preset zone's generators. A leading zone naming no instrument
    // is the preset's GLOBAL zone — its offsets apply to all the other zones.
    final pZones = <_Gen>[];
    for (var b = bagStart; b < bagEnd; b++) {
      final g = _readGens(
        data,
        pgenOff,
        u16(pbagOff + b * 4),
        u16(pbagOff + (b + 1) * 4),
        pgenCount,
      );
      g.velFilterMods = _readVelFilterMods(
        data,
        pmodOff,
        u16(pbagOff + b * 4 + 2),
        u16(pbagOff + (b + 1) * 4 + 2),
        pmodCount,
      );
      pZones.add(g);
    }
    final pGlobal = (pZones.isNotEmpty && pZones.first.instIndex == null)
        ? pZones.first
        : null;
    final zones = <Sf2Zone>[];
    for (final pz in pZones) {
      final instIndex = pz.instIndex;
      if (instIndex == null) continue; // the global zone is not a voice itself
      final offsets = _mergePreset(pGlobal, pz); // local preset over global
      final iz = instZoneGens(instIndex);
      final ig = (iz.isNotEmpty && iz.first.sampleId == null) ? iz.first : null;
      for (final z in iz) {
        if (z.sampleId == null) continue; // instrument global zone, not a voice
        final built = buildZone(z, ig, offsets);
        if (built != null) zones.add(built);
      }
    }
    if (zones.isNotEmpty) {
      presets.add(
        Sf2Preset(name: name, bank: bank, program: program, zones: zones),
      );
    }
  }
  return presets;
}

/// One zone's generators, each null when that zone doesn't specify it — so an
/// instrument zone can fall back to its global zone / SF2 defaults, and a preset
/// zone's set values act as offsets (unset = 0, i.e. no change).
class _Gen {
  int? keyLo, keyHi, velLo, velHi, atten, coarse, fine;
  int? delayVol, attackVol, holdVol, decayVol, sustainVol, releaseVol;
  int? filterFc, filterQ;
  int? modLfoPitch, vibLfoPitch, modLfoVol;
  int? delayModLfo, freqModLfo, delayVibLfo, freqVibLfo;
  int? pan, exclusiveClass, sampleModes, scaleTuning, sampleId;
  int? rootOverride, instIndex;
  // Modulation envelope (2nd DAHDSR) + its pitch/filter targets, and the sample
  // play-start offset.
  int? modEnvToPitch, modEnvToFilter;
  int? delayModEnv, attackModEnv, holdModEnv, decayModEnv, sustainModEnv;
  int? releaseModEnv, startOff, startCoarse;
  int? loopStartOff, loopEndOff, key2VolHold, key2VolDecay;
  int? reverbSend, chorusSend; // gen 16 / 15, 0.1% units
  // velocity→filterFc modulators, flattened as [amount, dir, type, …] triples.
  List<int>? velFilterMods;
}

/// Read the generators in [gStart, gEnd) of a pgen/igen chunk into a [_Gen].
_Gen _readGens(ByteData data, int genOff, int gStart, int gEnd, int genCount) {
  final g = _Gen();
  final end = gEnd.clamp(0, genCount);
  for (var i = gStart.clamp(0, genCount); i < end; i++) {
    final oper = data.getUint16(genOff + i * 4, Endian.little);
    final amt = data.getUint16(genOff + i * 4 + 2, Endian.little); // unsigned
    final samt = data.getInt16(genOff + i * 4 + 2, Endian.little); // signed
    switch (oper) {
      case _genKeyRange:
        g.keyLo = amt & 0xFF;
        g.keyHi = (amt >> 8) & 0xFF;
      case _genVelRange:
        g.velLo = amt & 0xFF;
        g.velHi = (amt >> 8) & 0xFF;
      case _genRootKeyOverride:
        g.rootOverride = amt;
      case _genSampleId:
        g.sampleId = amt;
      case _genInstrument:
        g.instIndex = amt;
      case _genInitialAttenuation:
        g.atten = amt;
      case _genCoarseTune:
        g.coarse = samt;
      case _genFineTune:
        g.fine = samt;
      case _genDelayVolEnv:
        g.delayVol = samt;
      case _genAttackVolEnv:
        g.attackVol = samt;
      case _genHoldVolEnv:
        g.holdVol = samt;
      case _genDecayVolEnv:
        g.decayVol = samt;
      case _genSustainVolEnv:
        g.sustainVol = amt;
      case _genReleaseVolEnv:
        g.releaseVol = samt;
      case _genInitialFilterFc:
        g.filterFc = samt;
      case _genInitialFilterQ:
        g.filterQ = amt;
      case _genModLfoToPitch:
        g.modLfoPitch = samt;
      case _genVibLfoToPitch:
        g.vibLfoPitch = samt;
      case _genModLfoToVolume:
        g.modLfoVol = samt;
      case _genDelayModLfo:
        g.delayModLfo = samt;
      case _genFreqModLfo:
        g.freqModLfo = samt;
      case _genDelayVibLfo:
        g.delayVibLfo = samt;
      case _genFreqVibLfo:
        g.freqVibLfo = samt;
      case _genModEnvToPitch:
        g.modEnvToPitch = samt;
      case _genModEnvToFilterFc:
        g.modEnvToFilter = samt;
      case _genDelayModEnv:
        g.delayModEnv = samt;
      case _genAttackModEnv:
        g.attackModEnv = samt;
      case _genHoldModEnv:
        g.holdModEnv = samt;
      case _genDecayModEnv:
        g.decayModEnv = samt;
      case _genSustainModEnv:
        g.sustainModEnv = amt;
      case _genReleaseModEnv:
        g.releaseModEnv = samt;
      case _genStartAddrsOffset:
        g.startOff = amt;
      case _genStartAddrsCoarseOffset:
        g.startCoarse = amt;
      case _genStartLoopAddrsOffset:
        g.loopStartOff = samt;
      case _genEndLoopAddrsOffset:
        g.loopEndOff = samt;
      case _genKeynumToVolEnvHold:
        g.key2VolHold = samt;
      case _genKeynumToVolEnvDecay:
        g.key2VolDecay = samt;
      case _genReverbSend:
        g.reverbSend = amt;
      case _genChorusSend:
        g.chorusSend = amt;
      case _genPan:
        g.pan = samt;
      case _genExclusiveClass:
        g.exclusiveClass = amt;
      case _genSampleModes:
        g.sampleModes = amt;
      case _genScaleTuning:
        g.scaleTuning = amt;
    }
  }
  return g;
}

/// Read the velocity→filter-cutoff modulators in a zone's imod range, flattened
/// as `[amount, dir, type, …]` triples. A modulator qualifies when its
/// destination is initialFilterFc (gen 8) and its source is note-on velocity (a
/// general controller, index 2). `dir` (1 = max→min) and `type` (0 linear /
/// 1 concave / 2 convex) shape the velocity curve; the amount is in cents. GM
/// drum kits use these to open a low base cutoff on a hard hit (the "click").
List<int> _readVelFilterMods(
  ByteData data,
  int modOff,
  int mStart,
  int mEnd,
  int modCount,
) {
  final out = <int>[];
  final end = mEnd.clamp(0, modCount);
  for (var i = mStart.clamp(0, modCount); i < end; i++) {
    final o = modOff + i * 10;
    final src = data.getUint16(o, Endian.little);
    final dest = data.getUint16(o + 2, Endian.little);
    final amount = data.getInt16(o + 4, Endian.little);
    // dest 8 = initialFilterFc; source: CC flag clear (bit 7) and index 2 = vel.
    if (dest == 8 && (src & 0x80) == 0 && (src & 0x7f) == 2) {
      out
        ..add(amount)
        ..add((src >> 8) & 1) // direction
        ..add((src >> 10) & 0x3f); // curve type
    }
  }
  return out;
}

/// Merge a preset's global-zone offsets [glob] under a local preset zone [loc]
/// (local wins). Used so a preset's global attenuation/pan applies to each of
/// its instrument zones unless that zone overrides it.
_Gen _mergePreset(_Gen? glob, _Gen loc) {
  if (glob == null) return loc;
  return _Gen()
    ..keyLo = loc.keyLo ?? glob.keyLo
    ..keyHi = loc.keyHi ?? glob.keyHi
    ..velLo = loc.velLo ?? glob.velLo
    ..velHi = loc.velHi ?? glob.velHi
    ..atten = loc.atten ?? glob.atten
    ..coarse = loc.coarse ?? glob.coarse
    ..fine = loc.fine ?? glob.fine
    ..delayVol = loc.delayVol ?? glob.delayVol
    ..attackVol = loc.attackVol ?? glob.attackVol
    ..holdVol = loc.holdVol ?? glob.holdVol
    ..decayVol = loc.decayVol ?? glob.decayVol
    ..sustainVol = loc.sustainVol ?? glob.sustainVol
    ..releaseVol = loc.releaseVol ?? glob.releaseVol
    ..filterFc = loc.filterFc ?? glob.filterFc
    ..filterQ = loc.filterQ ?? glob.filterQ
    ..modLfoPitch = loc.modLfoPitch ?? glob.modLfoPitch
    ..vibLfoPitch = loc.vibLfoPitch ?? glob.vibLfoPitch
    ..modLfoVol = loc.modLfoVol ?? glob.modLfoVol
    ..delayModLfo = loc.delayModLfo ?? glob.delayModLfo
    ..freqModLfo = loc.freqModLfo ?? glob.freqModLfo
    ..delayVibLfo = loc.delayVibLfo ?? glob.delayVibLfo
    ..freqVibLfo = loc.freqVibLfo ?? glob.freqVibLfo
    ..pan = loc.pan ?? glob.pan
    ..instIndex = loc.instIndex
    ..velFilterMods = [...?glob.velFilterMods, ...?loc.velFilterMods];
}

/// Whether [bytes] is a compressed `.sf3` soundfont (OGG-Vorbis samples), which
/// [Sf2SoundFont.parse] can't decode. Lets the app check + show a friendly
/// "please use a .sf2" message instead of catching a [FormatException]. Returns
/// false for a normal `.sf2` or anything that isn't a RIFF/sfbk soundfont.
bool sf2IsCompressed(Uint8List bytes) {
  if (bytes.length < 12 ||
      _tag(bytes, 0) != 'RIFF' ||
      _tag(bytes, 8) != 'sfbk') {
    return false;
  }
  final data = ByteData.sublistView(bytes);
  var pos = 12;
  while (pos + 8 <= bytes.length) {
    final ck = _tag(bytes, pos);
    final size = data.getUint32(pos + 4, Endian.little);
    if (ck == 'LIST') {
      var sp = pos + 12; // past 'LIST' <size> <listType>
      final end = pos + 8 + size;
      while (sp + 8 <= end) {
        final ssize = data.getUint32(sp + 4, Endian.little);
        if (_tag(bytes, sp) == 'smpl') {
          return ssize >= 4 && _tag(bytes, sp + 8) == 'OggS';
        }
        sp = sp + 8 + ssize + (ssize.isOdd ? 1 : 0);
      }
    }
    pos = pos + 8 + size + (size.isOdd ? 1 : 0);
  }
  return false;
}

/// A 4-char RIFF tag at [o], or '' if [o]..[o]+4 runs past the buffer (so a
/// short/truncated file fails the RIFF/sfbk check cleanly instead of throwing).
String _tag(Uint8List b, int o) =>
    (o >= 0 && o + 4 <= b.length) ? String.fromCharCodes(b, o, o + 4) : '';

String _cstr(Uint8List b, int o, int max) {
  var n = 0;
  while (n < max && b[o + n] != 0) {
    n++;
  }
  return String.fromCharCodes(b, o, o + n);
}

/// Turn an [Sf2Sample] into a single tracker [SampleInstrument]: resample to the
/// engine rate, using the soundfont's original pitch as the base note and its
/// loop region (scaled to the engine rate) so held notes sustain.
SampleInstrument sampleInstrumentFromSf2(Sf2Sample s, {required String id}) {
  final (pcm, loopStart, loopLen) = _resampleWithLoop(s);
  return SampleInstrument(
    id,
    pcm,
    baseMidi: s.originalPitch,
    loopStart: loopStart,
    loopLength: loopLen,
  );
}

/// Resample a soundfont sample to the engine rate AND bake in its tuning (so the
/// integer-rooted [SampleInstrument] plays in tune), scaling the loop points by
/// the same factor. Total detune = the sample's own `chPitchCorrection` plus any
/// per-zone [extraCents] (coarse/fine tune); a sample that sounds `c` cents sharp
/// is stretched by 2^(c/1200) to lower it back onto its root key.
(Float64List, int, int) _resampleWithLoop(Sf2Sample s, {int extraCents = 0}) {
  var pcm = s.pcm;
  var loopStart = s.loopStart;
  var loopLen = s.loops ? s.loopEnd - s.loopStart : 0;
  final cents = s.pitchCorrection + extraCents;
  final ratio = (s.sampleRate / kSampleRate) * pow(2, cents / 1200.0);
  if ((ratio - 1.0).abs() > 1e-9) {
    pcm = resampleCubic(pcm, ratio.toDouble());
    loopStart = (loopStart / ratio).round();
    loopLen = (loopLen / ratio).round();
  }
  return (pcm, loopStart, loopLen);
}

/// A key-split soundfont instrument: renders each note with the [Sf2Preset] zone
/// covering its key, resampled from that zone's root key (with the sample loop),
/// so one instrument spans the keyboard like a real GM voice. Built by
/// [sf2InstrumentFromPreset]. Deterministic → stable stem cache.
class Sf2Instrument implements TrackerInstrument {
  Sf2Instrument(this.id, this._zones);

  @override
  final String id;

  /// Per zone: key range + velocity range (the sample layer) + a ready
  /// [SampleInstrument] (already resampled/looped/tuned) + the zone's level
  /// [gain] (from initialAttenuation).
  final List<
      ({
        int keyLo,
        int keyHi,
        int velLo,
        int velHi,
        SampleInstrument inst,
        double gain,
      })> _zones;

  ({
    int keyLo,
    int keyHi,
    int velLo,
    int velHi,
    SampleInstrument inst,
    double gain,
  })? _zoneFor(int key, int vel) {
    // Prefer the layer covering BOTH key and velocity (velocity-split voices);
    // then any zone covering the key (non-split, or vel outside every layer);
    // then the first zone as a last resort.
    for (final z in _zones) {
      if (key >= z.keyLo &&
          key <= z.keyHi &&
          vel >= z.velLo &&
          vel <= z.velHi) {
        return z;
      }
    }
    for (final z in _zones) {
      if (key >= z.keyLo && key <= z.keyHi) return z;
    }
    return _zones.isEmpty ? null : _zones.first;
  }

  @override
  Float64List renderChannel(List<TrackerCell> cells, TrackerTiming timing) {
    final out = Float64List(timing.totalSamples);
    if (_zones.isEmpty) return out;
    // The tracker's per-cell volume column (0..1, null = full) is the note's
    // MIDI velocity → it selects the velocity layer AND scales the level.
    final velByStep = <int, int>{};
    {
      var s = 0;
      for (final c in cells) {
        velByStep[s] = ((c.volume ?? 1.0) * 127).round().clamp(0, 127);
        s++;
      }
    }
    var startStep = 0;
    for (final (midi, steps) in cellRuns(cells)) {
      if (midi != null) {
        final vel = velByStep[startStep] ?? 127;
        final zone = _zoneFor(midi, vel);
        if (zone != null) {
          final start = timing.stepStartSample(startStep);
          final end = timing.stepStartSample(startStep + steps);
          final runSamples = end - start;
          if (runSamples > 0) {
            // Render the single note over its own span, reusing the zone's
            // SampleInstrument (resample + loop are handled there).
            final runMs = (runSamples * 1000 / kSampleRate).round();
            final tempo =
                (runMs <= 0 ? 240 : (60000 / runMs).round()).clamp(1, 1 << 20);
            final noteTiming =
                TrackerTiming(tempoBpm: tempo, rows: 1, stepsPerBeat: 1);
            final buf =
                zone.inst.renderChannel([TrackerCell(midi: midi)], noteTiming);
            final n = [buf.length, runSamples, out.length - start]
                .reduce((a, b) => a < b ? a : b);
            // Zone attenuation × the note's velocity level (linear, like the
            // tracker's volume column elsewhere; full velocity = ×1, unchanged).
            final g = zone.gain * (vel / 127.0);
            for (var i = 0; i < n; i++) {
              out[start + i] = buf[i] * g;
            }
          }
        }
      }
      startStep += steps;
    }
    return out;
  }
}

/// Build a key-split [Sf2Instrument] from a resolved [preset] of [sf], resampling
/// each zone's sample to the engine rate once.
Sf2Instrument sf2InstrumentFromPreset(
  Sf2SoundFont sf,
  Sf2Preset preset, {
  required String id,
}) {
  final zones = <({
    int keyLo,
    int keyHi,
    int velLo,
    int velHi,
    SampleInstrument inst,
    double gain,
  })>[];
  for (final z in preset.zones) {
    final s = sf.sampleAt(z.sampleIndex);
    if (s == null) continue;
    // Per-zone coarse+fine tune baked in on top of the sample's own correction.
    final (pcm, loopStart, loopLen) =
        _resampleWithLoop(s, extraCents: z.coarseTune * 100 + z.fineTune);
    zones.add(
      (
        keyLo: z.keyLo,
        keyHi: z.keyHi,
        velLo: z.velLo,
        velHi: z.velHi,
        gain: z.gain,
        inst: SampleInstrument(
          '$id.${z.sampleIndex}',
          pcm,
          // scaleTuning 0 = an untuned drum zone: the key selects the sample and
          // must not transpose it. Zones are single-key, so basing the sample at
          // the zone's own key means key−base = 0 (no shift). Else use the root.
          baseMidi: z.scaleTuning == 0
              ? z.keyLo
              : (z.rootKey >= 0 ? z.rootKey : s.originalPitch),
          loopStart: loopStart,
          loopLength: loopLen,
        ),
      ),
    );
  }
  return Sf2Instrument(id, zones);
}
