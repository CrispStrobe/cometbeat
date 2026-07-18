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
const _genInstrument = 41;
const _genSampleId = 53;
const _genRootKeyOverride = 58;
const _genInitialAttenuation = 48; // centibels
const _genCoarseTune = 51; // semitones (signed)
const _genFineTune = 52; // cents (signed)

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
    this.attenuationCb = 0,
    this.coarseTune = 0,
    this.fineTune = 0,
  });

  final int keyLo;
  final int keyHi;
  final int sampleIndex;
  final int rootKey;

  /// initialAttenuation (gen 48), in centibels (0 = full; +cB = quieter).
  final int attenuationCb;

  /// coarseTune (gen 51), in semitones, and fineTune (gen 52), in cents —
  /// applied on top of the sample's own pitch correction.
  final int coarseTune;
  final int fineTune;

  /// The linear gain from [attenuationCb] (dB = cB/10 → gain = 10^(-dB/20)).
  double get gain => pow(10, -attenuationCb / 200).toDouble();

  bool covers(int key) => key >= keyLo && key <= keyHi;
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

    // Collect the offset/length of every sub-chunk we care about.
    final chunks = <String, (int, int)>{};
    var pos = 12; // past 'RIFF' <size> 'sfbk'
    while (pos + 8 <= bytes.length) {
      final ck = _tag(bytes, pos);
      final size = data.getUint32(pos + 4, Endian.little);
      final body = pos + 8;
      if (ck == 'LIST') {
        var sp = body + 4; // past the list type
        final end = body + size;
        while (sp + 8 <= end) {
          final sck = _tag(bytes, sp);
          final ssize = data.getUint32(sp + 4, Endian.little);
          chunks[sck] = (sp + 8, ssize);
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

  int presetBagNdx(int i) => u16(phdrOff + i * 38 + 24);
  int instBagNdx(int i) => u16(instOff + i * 22 + 20);

  // The zones of instrument [instIndex] (keyRange + sampleID + root override).
  List<Sf2Zone> zonesOfInstrument(int instIndex) {
    if (instIndex < 0 || instIndex + 1 >= instCount) return const [];
    final zones = <Sf2Zone>[];
    final ibStart = instBagNdx(instIndex);
    final ibEnd = instBagNdx(instIndex + 1).clamp(0, ibagCount - 1);
    for (var ib = ibStart; ib < ibEnd; ib++) {
      final gStart = u16(ibagOff + ib * 4);
      final gEnd = u16(ibagOff + (ib + 1) * 4).clamp(0, igenCount);
      var lo = 0, hi = 127;
      var atten = 0, coarse = 0, fine = 0;
      int? sampleId, rootOverride;
      for (var g = gStart; g < gEnd; g++) {
        final oper = u16(igenOff + g * 4);
        final amt = u16(igenOff + g * 4 + 2);
        final samt =
            data.getInt16(igenOff + g * 4 + 2, Endian.little); // signed
        if (oper == _genKeyRange) {
          lo = amt & 0xFF;
          hi = (amt >> 8) & 0xFF;
        } else if (oper == _genRootKeyOverride) {
          rootOverride = amt;
        } else if (oper == _genSampleId) {
          sampleId = amt;
        } else if (oper == _genInitialAttenuation) {
          atten = amt; // centibels (unsigned)
        } else if (oper == _genCoarseTune) {
          coarse = samt; // semitones (signed)
        } else if (oper == _genFineTune) {
          fine = samt; // cents (signed)
        }
      }
      if (sampleId != null && sampleId >= 0 && sampleId < sampleCount) {
        zones.add(
          Sf2Zone(
            keyLo: lo,
            keyHi: hi,
            sampleIndex: sampleId,
            rootKey: (rootOverride != null && rootOverride <= 127)
                ? rootOverride
                : -1, // -1 → resolved to the sample's originalPitch later
            attenuationCb: atten,
            coarseTune: coarse,
            fineTune: fine,
          ),
        );
      }
    }
    return zones;
  }

  final presets = <Sf2Preset>[];
  for (var pi = 0; pi + 1 < phdrCount; pi++) {
    final name = _cstr(bytes, phdrOff + pi * 38, 20);
    if (name == 'EOP') continue;
    final program = u16(phdrOff + pi * 38 + 20);
    final bank = u16(phdrOff + pi * 38 + 22);
    final bagStart = presetBagNdx(pi);
    final bagEnd = presetBagNdx(pi + 1).clamp(0, pbagCount - 1);
    final zones = <Sf2Zone>[];
    for (var b = bagStart; b < bagEnd; b++) {
      final gStart = u16(pbagOff + b * 4);
      final gEnd = u16(pbagOff + (b + 1) * 4).clamp(0, pgenCount);
      int? instIndex;
      for (var g = gStart; g < gEnd; g++) {
        if (u16(pgenOff + g * 4) == _genInstrument) {
          instIndex = u16(pgenOff + g * 4 + 2);
        }
      }
      if (instIndex != null) zones.addAll(zonesOfInstrument(instIndex));
    }
    if (zones.isNotEmpty) {
      presets.add(
        Sf2Preset(name: name, bank: bank, program: program, zones: zones),
      );
    }
  }
  return presets;
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

String _tag(Uint8List b, int o) => String.fromCharCodes(b, o, o + 4);

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

  /// Per zone: key range + a ready [SampleInstrument] (already resampled/looped/
  /// tuned) + the zone's level [gain] (from initialAttenuation).
  final List<({int keyLo, int keyHi, SampleInstrument inst, double gain})>
      _zones;

  ({int keyLo, int keyHi, SampleInstrument inst, double gain})? _zoneFor(
    int key,
  ) {
    for (final z in _zones) {
      if (key >= z.keyLo && key <= z.keyHi) return z;
    }
    return _zones.isEmpty ? null : _zones.first; // fall back to the first zone
  }

  @override
  Float64List renderChannel(List<TrackerCell> cells, TrackerTiming timing) {
    final out = Float64List(timing.totalSamples);
    if (_zones.isEmpty) return out;
    var startStep = 0;
    for (final (midi, steps) in cellRuns(cells)) {
      if (midi != null) {
        final zone = _zoneFor(midi);
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
            final g = zone.gain;
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
  final zones =
      <({int keyLo, int keyHi, SampleInstrument inst, double gain})>[];
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
        gain: z.gain,
        inst: SampleInstrument(
          '$id.${z.sampleIndex}',
          pcm,
          baseMidi: z.rootKey >= 0 ? z.rootKey : s.originalPitch,
          loopStart: loopStart,
          loopLength: loopLen,
        ),
      ),
    );
  }
  return Sf2Instrument(id, zones);
}
