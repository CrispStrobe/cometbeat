// SoundFont 2 (.sf2) sample extraction — the reusable core of the "render GM
// instruments from a bundled/downloaded soundfont" path (FluidR3Mono is MIT).
// An SF2 is a RIFF file: raw 16-bit PCM for ALL samples concatenated in the
// `sdta/smpl` chunk, plus a `pdta/shdr` table describing each sample (name,
// start/end into the pool, loop points, sample rate, the MIDI key it was
// recorded at). That's exactly what a tracker SampleInstrument needs — a pitched
// buffer with a loop — so this parser turns each SF2 sample into one.
//
// This first cut extracts SAMPLES (the payload) from an UNCOMPRESSED `.sf2`
// (raw PCM in `smpl`) — verified against a real 520-sample soundfont. Two
// documented follow-ups: (1) the preset→instrument→zone generator graph (GM
// program → key-split sample selection); (2) `.sf3` support (MuseScore's
// FluidR3Mono ships as `.sf3` with OGG-Vorbis-compressed samples, which need an
// OGG decoder — the MIT FluidR3_GM `.sf2` is uncompressed and works today).
// Extracting named samples already lets a soundfont feed the sound library.
// Flutter-free, pure Dart.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';

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
    required this.loopStart,
    required this.loopEnd,
  });

  final String name;
  final Float64List pcm;
  final int sampleRate;
  final int originalPitch;
  final int loopStart;
  final int loopEnd;

  bool get loops => loopEnd > loopStart && loopEnd <= pcm.length;
}

/// A parsed soundfont — for now, just its list of [samples].
class Sf2SoundFont {
  const Sf2SoundFont(this.samples);

  final List<Sf2Sample> samples;

  /// Parse an `.sf2` byte buffer, extracting every sample. Throws [FormatException]
  /// if the RIFF/sfbk structure or required chunks are missing.
  factory Sf2SoundFont.parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (_tag(bytes, 0) != 'RIFF' || _tag(bytes, 8) != 'sfbk') {
      throw const FormatException('not a RIFF/sfbk SoundFont');
    }

    // Walk the top-level LIST chunks to find sdta (sample data) + pdta (headers).
    int? smplOff, smplLen, shdrOff, shdrLen;
    var pos = 12; // past 'RIFF' <size> 'sfbk'
    while (pos + 8 <= bytes.length) {
      final ck = _tag(bytes, pos);
      final size = data.getUint32(pos + 4, Endian.little);
      final body = pos + 8;
      if (ck == 'LIST') {
        final listType = _tag(bytes, body);
        // Scan sub-chunks within this LIST.
        var sp = body + 4;
        final end = body + size;
        while (sp + 8 <= end) {
          final sck = _tag(bytes, sp);
          final ssize = data.getUint32(sp + 4, Endian.little);
          final sbody = sp + 8;
          if (listType == 'sdta' && sck == 'smpl') {
            smplOff = sbody;
            smplLen = ssize;
          } else if (listType == 'pdta' && sck == 'shdr') {
            shdrOff = sbody;
            shdrLen = ssize;
          }
          sp = sbody + ssize + (ssize.isOdd ? 1 : 0); // chunks are word-aligned
        }
      }
      pos = body + size + (size.isOdd ? 1 : 0);
    }

    if (smplOff == null || shdrOff == null) {
      throw const FormatException('SoundFont missing smpl/shdr chunks');
    }

    // The whole sample pool as signed 16-bit words.
    final pool = Int16List(smplLen! ~/ 2);
    for (var i = 0; i < pool.length; i++) {
      pool[i] = data.getInt16(smplOff + i * 2, Endian.little);
    }

    // shdr: 46-byte records; the final "EOS" terminal record is skipped.
    const rec = 46;
    final count = shdrLen! ~/ rec;
    final samples = <Sf2Sample>[];
    for (var i = 0; i < count; i++) {
      final o = shdrOff + i * rec;
      final name = _cstr(bytes, o, 20);
      final start = data.getUint32(o + 20, Endian.little);
      final end = data.getUint32(o + 24, Endian.little);
      final startLoop = data.getUint32(o + 28, Endian.little);
      final endLoop = data.getUint32(o + 32, Endian.little);
      final sampleRate = data.getUint32(o + 36, Endian.little);
      final originalPitch = bytes[o + 40];
      if (name == 'EOS' || end <= start || end > pool.length) continue;

      final n = end - start;
      final pcm = Float64List(n);
      for (var j = 0; j < n; j++) {
        pcm[j] = pool[start + j] / 32768.0;
      }
      samples.add(
        Sf2Sample(
          name: name,
          pcm: pcm,
          sampleRate: sampleRate == 0 ? kSampleRate : sampleRate,
          originalPitch: originalPitch > 127 ? 60 : originalPitch,
          loopStart: startLoop > start ? startLoop - start : 0,
          loopEnd: endLoop > start ? endLoop - start : 0,
        ),
      );
    }
    return Sf2SoundFont(samples);
  }
}

/// Turn an [Sf2Sample] into a tracker [SampleInstrument]: resample to the engine
/// rate, using the soundfont's original pitch as the base note and its loop
/// region (scaled to the engine rate) so held notes sustain. Reuses the engine's
/// existing sample-loop support.
SampleInstrument sampleInstrumentFromSf2(Sf2Sample s, {required String id}) {
  var pcm = s.pcm;
  var loopStart = s.loopStart;
  var loopLen = s.loops ? s.loopEnd - s.loopStart : 0;
  if (s.sampleRate != kSampleRate) {
    final ratio = s.sampleRate / kSampleRate;
    pcm = resampleCubic(pcm, ratio);
    loopStart = (loopStart / ratio).round();
    loopLen = (loopLen / ratio).round();
  }
  return SampleInstrument(
    id,
    pcm,
    baseMidi: s.originalPitch,
    loopStart: loopStart,
    loopLength: loopLen,
  );
}

String _tag(Uint8List b, int o) => String.fromCharCodes(b, o, o + 4);

String _cstr(Uint8List b, int o, int max) {
  var n = 0;
  while (n < max && b[o + n] != 0) {
    n++;
  }
  return String.fromCharCodes(b, o, o + n);
}
