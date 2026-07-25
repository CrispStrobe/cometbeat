// lib/core/audio/mod/s3m_reader.dart
//
// Scream Tracker 3 `.s3m` IMPORT (reader): raw bytes → [S3mModule]. Pure Dart.
// Implement against the byte-layout contract in s3m_module.dart.
//
// Contract:
//   • Verify "SCRM" at 0x2C (else throw [S3mFormatException]); read the header
//     (title, ordNum/insNum/patNum, sample-format flag, channel settings →
//     channelCount = enabled channels, global volume / speed / tempo).
//   • order = the ordNum order bytes with 254 ("skip") and 255 ("end") removed.
//   • Read insNum instrument PARAPOINTERS (u16 × 16 = offset) and patNum pattern
//     parapointers. For each instrument (type 1 PCM): name, C2 speed, volume,
//     loop, and the PCM at (memseg × 16) for `length` bytes — convert UNSIGNED
//     (sample-format == 2) to signed Int8List via (b - 128); signed passes
//     through. Non-PCM / type 0 → S3mSample.empty().
//   • For each pattern: read the u16 packed length, then unpack 64 rows ×
//     channelCount cells per the "what"-byte scheme (bit5 note+instrument, bit6
//     volume, bit7 command+info, low 5 bits = channel, 0x00 = end of row).
//   • Be robust to truncation (missing PCM / short packed data → empty).
//
// Verify against test/s3m_codec_test.dart (a hand-authored golden oracle +, when
// present, the real test/fixtures/*.s3m).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/s3m_module.dart';

const int _rowsPerPattern = 64;

/// Parses Scream Tracker 3 `.s3m` [bytes] into an [S3mModule].
S3mModule parseS3m(Uint8List bytes) {
  if (bytes.length < 96) {
    throw const S3mFormatException('too short for an S3M header');
  }
  final data = ByteData.sublistView(bytes);
  // "SCRM" signature at 0x2C.
  if (bytes[0x2C] != 0x53 ||
      bytes[0x2D] != 0x43 ||
      bytes[0x2E] != 0x52 ||
      bytes[0x2F] != 0x4D) {
    throw const S3mFormatException('missing "SCRM" signature at 0x2C');
  }

  final title = _readAsciiz(bytes, 0x00, 28);
  final ordNum = data.getUint16(0x20, Endian.little);
  final insNum = data.getUint16(0x22, Endian.little);
  final patNum = data.getUint16(0x24, Endian.little);
  final flags = data.getUint16(0x26, Endian.little);
  final createdWith = data.getUint16(0x28, Endian.little);
  final sampleFormat = data.getUint16(0x2A, Endian.little);
  final globalVolume = bytes[0x30];
  final initialSpeed = bytes[0x31];
  final initialTempo = bytes[0x32];
  final masterVolume = bytes[0x33];
  final ultraClick = bytes[0x34];
  final defaultPan = bytes[0x35];

  // Channel settings: 32 bytes @ 0x40, value < 128 = enabled.
  var channelCount = 0;
  final logicalChannel = List<int>.filled(32, -1);
  final channelSettings = <int>[];
  for (var i = 0; i < 32; i++) {
    channelSettings.add(bytes[0x40 + i]);
    if (bytes[0x40 + i] < 128) logicalChannel[i] = channelCount++;
  }
  if (channelCount == 0) {
    channelCount = 1; // defensive; must be > 0.
    logicalChannel[0] = 0;
  }

  // Order list: ordNum bytes @ 0x60, with 254/255 markers removed.
  const orderStart = 0x60;
  final order = <int>[];
  final rawOrder = <int>[];
  for (var i = 0; i < ordNum; i++) {
    final off = orderStart + i;
    if (off >= bytes.length) break;
    final v = bytes[off];
    rawOrder.add(v);
    if (v == 254 || v == 255) continue;
    order.add(v);
  }

  // Parapointer tables follow the order list. The pointer-table offsets use the
  // real declared counts (that's the on-disk layout), but the build loops below
  // are clamped: pattern and sample references in the order list and cells are
  // single bytes (0-255), so a module can address at most 256 of each. A header
  // declaring more (up to the u16 max, 65535) is malformed — and without this
  // clamp a 96-byte file with patNum=65535 drives ~65535 × 64 × channelCount
  // cell allocations, a multi-second hang / OOM decode-bomb. Clamping is
  // lossless for every real S3M (the extra, unaddressable entries are dropped).
  const maxAddressable = 256;
  final insPtrStart = orderStart + ordNum;
  final patPtrStart = insPtrStart + insNum * 2;
  final panStart = patPtrStart + patNum * 2;
  final defaultPans = defaultPan == 252 && panStart + 32 <= bytes.length
      ? List<int>.from(bytes.sublist(panStart, panStart + 32))
      : const <int>[];
  final insCount = insNum > maxAddressable ? maxAddressable : insNum;
  final patCount = patNum > maxAddressable ? maxAddressable : patNum;

  final samples = <S3mSample>[];
  for (var i = 0; i < insCount; i++) {
    final ptrOff = insPtrStart + i * 2;
    if (ptrOff + 2 > bytes.length) {
      samples.add(S3mSample.empty());
      continue;
    }
    final para = data.getUint16(ptrOff, Endian.little);
    samples.add(_readInstrument(bytes, data, para * 16, sampleFormat));
  }

  final patterns = <S3mPattern>[];
  for (var i = 0; i < patCount; i++) {
    final ptrOff = patPtrStart + i * 2;
    if (ptrOff + 2 > bytes.length) {
      patterns.add(_emptyPattern(channelCount));
      continue;
    }
    final para = data.getUint16(ptrOff, Endian.little);
    patterns.add(
      _readPattern(bytes, data, para * 16, channelCount, logicalChannel),
    );
  }

  return S3mModule(
    title: title,
    channelCount: channelCount,
    globalVolume: globalVolume,
    masterVolume: masterVolume,
    ultraClick: ultraClick,
    defaultPan: defaultPan,
    channelSettings: channelSettings,
    sampleFormat: sampleFormat,
    flags: flags,
    createdWith: createdWith,
    defaultPans: defaultPans,
    rawOrder: rawOrder,
    initialSpeed: initialSpeed,
    initialTempo: initialTempo,
    order: order,
    samples: samples,
    patterns: patterns,
  );
}

S3mSample _readInstrument(
  Uint8List bytes,
  ByteData data,
  int base,
  int sampleFormat,
) {
  // Need the whole 80-byte instrument header to trust it.
  if (base < 0 || base + 0x50 > bytes.length) return S3mSample.empty();

  final type = bytes[base];
  final rawHeader = List<int>.from(bytes.sublist(base, base + 0x50));

  // type 2 = AdLib/OPL (melodic or percussion). We do NOT emulate the OPL chip;
  // instead we render a short, loopable APPROXIMATION of the 2-operator FM
  // timbre to PCM (see [synthesizeAdlibWaveform]) so the ordinary sample path
  // can sound it. The 12 OPL register bytes (header 0x10..0x1B) and the full
  // header are still preserved so the instrument survives a read/write cycle
  // and re-exports byte-identically (the writer never emits the synth PCM).
  if (type == 2) {
    final adlibData = List<int>.from(bytes.sublist(base + 0x10, base + 0x1C));
    final wave = synthesizeAdlibWaveform(adlibData);
    return S3mSample(
      name: _readAsciiz(bytes, base + 0x30, 28),
      volume: bytes[base + 0x1C],
      c2spd: () {
        final c = data.getUint32(base + 0x20, Endian.little);
        return c == 0 ? 8363 : c;
      }(),
      pcm: wave,
      // Loop the whole synthesized waveform so a held note sustains the tone.
      loop: wave.isNotEmpty,
      // loopStart defaults to 0 (start of the buffer).
      loopEnd: wave.length,
      adlib: true,
      adlibData: adlibData,
      rawHeader: rawHeader,
    );
  }
  if (type != 1) return S3mSample.empty(); // 0 = empty; other = unsupported.

  // memseg: high byte @ 0x0D, low u16 @ 0x0E.
  final memsegHi = bytes[base + 0x0D];
  final memsegLo = data.getUint16(base + 0x0E, Endian.little);
  final memseg = (memsegHi << 16) | memsegLo;
  final pcmOffset = memseg * 16;

  final length = data.getUint32(base + 0x10, Endian.little);
  final loopBegin = data.getUint32(base + 0x14, Endian.little);
  final loopEnd = data.getUint32(base + 0x18, Endian.little);
  final volume = bytes[base + 0x1C];
  final pack = bytes[base + 0x1E]; // 0 = unpacked, 1 = DP30 ADPCM.
  final flags = bytes[base + 0x1F];
  final loop = (flags & 0x01) != 0;
  final stereo = (flags & 0x02) != 0;
  final sixteenBit = (flags & 0x04) != 0;
  final unsigned = sampleFormat == 2;
  final c2spd = data.getUint32(base + 0x20, Endian.little);
  final name = _readAsciiz(bytes, base + 0x30, 28);
  final bytesPerSample = sixteenBit ? 2 : 1;

  // pack==1 → DP30 4-bit ADPCM (see [decodeDp30Adpcm]). Decode to PCM, but keep
  // the raw packed block regardless for byte-identical same-format re-export.
  if (pack == 1) {
    // DP30 block = 16-byte delta table + one nibble per sample (two per byte).
    // Capture the raw block for preservation, clamped to what's present.
    var packedLen = 16 + (length + 1) ~/ 2;
    if (pcmOffset < 0 || pcmOffset >= bytes.length) {
      packedLen = 0;
    } else if (pcmOffset + packedLen > bytes.length) {
      packedLen = bytes.length - pcmOffset;
    }
    final rawData = packedLen > 0
        ? Uint8List.fromList(bytes.sublist(pcmOffset, pcmOffset + packedLen))
        : null;
    // Decode the ADPCM stream. If the result is degenerate (empty or all-zero)
    // fall back to preserve-only (pcm empty) rather than emitting garbage.
    var pcm = Float64List(0);
    if (rawData != null) {
      final decoded = decodeDp30Adpcm(rawData, length);
      if (decoded.isNotEmpty && decoded.any((v) => v != 0.0)) {
        pcm = decoded;
      }
    }
    return S3mSample(
      name: name,
      volume: volume,
      c2spd: c2spd == 0 ? 8363 : c2spd,
      loopStart: loopBegin,
      loopEnd: loopEnd,
      loop: loop,
      sixteenBit: sixteenBit,
      pcm: pcm,
      packed: true,
      rawHeader: rawHeader,
      rawData: rawData,
    );
  }

  // PCM window — robust to truncation: clamp to what's actually present.
  // [length] is in SAMPLES per channel; a 16-bit sample is 2 bytes each. A
  // STEREO sample stores the LEFT channel (`length` samples) immediately
  // followed by the RIGHT channel (`length` samples) at the same depth.
  // Normalize to [-1, 1] float (unified with the XM/IT readers): 8-bit /128,
  // 16-bit /32768.
  final channels = stereo ? 2 : 1;
  var availTotal = length * channels;
  if (pcmOffset < 0 || pcmOffset >= bytes.length) {
    availTotal = 0;
  } else {
    final maxSamples = (bytes.length - pcmOffset) ~/ bytesPerSample;
    if (maxSamples < availTotal) availTotal = maxSamples;
  }
  final leftAvail = availTotal < length ? availTotal : length;
  var rightAvail = 0;
  if (stereo) {
    final rem = availTotal - length; // samples after the full left channel
    rightAvail = rem <= 0 ? 0 : (rem > length ? length : rem);
  }

  double decode(int sampleIndex) {
    if (sixteenBit) {
      final o = pcmOffset + sampleIndex * 2;
      final w = bytes[o] | (bytes[o + 1] << 8);
      final s = unsigned ? w - 32768 : (w >= 32768 ? w - 65536 : w);
      return s / 32768.0;
    }
    final b = bytes[pcmOffset + sampleIndex];
    final s = unsigned ? b - 128 : (b >= 128 ? b - 256 : b);
    return s / 128.0;
  }

  final pcm = Float64List(leftAvail);
  for (var i = 0; i < leftAvail; i++) {
    pcm[i] = decode(i);
  }
  Float64List? pcmRight;
  if (stereo && rightAvail > 0) {
    pcmRight = Float64List(rightAvail);
    for (var i = 0; i < rightAvail; i++) {
      pcmRight[i] = decode(length + i); // right channel starts after `length`
    }
  }

  final rawBytes = (leftAvail + rightAvail) * bytesPerSample;
  return S3mSample(
    name: name,
    volume: volume,
    c2spd: c2spd == 0 ? 8363 : c2spd,
    loopStart: loopBegin,
    loopEnd: loopEnd,
    loop: loop,
    sixteenBit: sixteenBit,
    pcm: pcm,
    pcmRight: pcmRight,
    rawHeader: rawHeader,
    rawData: pcmOffset >= 0 && pcmOffset + rawBytes <= bytes.length
        ? Uint8List.fromList(bytes.sublist(pcmOffset, pcmOffset + rawBytes))
        : null,
  );
}

S3mPattern _readPattern(
  Uint8List bytes,
  ByteData data,
  int base,
  int channelCount,
  List<int> logicalChannel,
) {
  final rows = List.generate(
    _rowsPerPattern,
    (_) => List<S3mCell>.filled(channelCount, S3mCell.empty),
    growable: false,
  );

  // Guard the 2-byte packed-length prefix.
  if (base < 0 || base + 2 > bytes.length) {
    return S3mPattern(rows);
  }
  final packedLen = data.getUint16(base, Endian.little);
  if (packedLen == 0) {
    return S3mPattern(rows, rawData: Uint8List(0));
  }
  // Data body starts after the length word; end is bounded by both the declared
  // length and the actual file size.
  var end = base + packedLen;
  if (packedLen < 2 || end > bytes.length) end = bytes.length;

  var pos = base + 2;
  var row = 0;
  while (row < _rowsPerPattern && pos < end) {
    final what = bytes[pos++];
    if (what == 0x00) {
      row++;
      continue;
    }
    final channel = what & 0x1F;

    int? note, instrument, volume, command, info;
    if ((what & 0x20) != 0) {
      if (pos + 2 > end) break;
      note = bytes[pos++];
      instrument = bytes[pos++];
    }
    if ((what & 0x40) != 0) {
      if (pos + 1 > end) break;
      volume = bytes[pos++];
    }
    if ((what & 0x80) != 0) {
      if (pos + 2 > end) break;
      command = bytes[pos++];
      info = bytes[pos++];
    }

    final logical =
        channel < logicalChannel.length ? logicalChannel[channel] : -1;
    if (logical >= 0 && logical < channelCount) {
      rows[row][logical] = S3mCell(
        note: note ?? S3mCell.emptyNote,
        instrument: instrument ?? 0,
        volume: volume ?? S3mCell.noVolume,
        command: command ?? 0,
        info: info ?? 0,
      );
    }
  }

  return S3mPattern(
    rows,
    rawData: base >= 0 && base + packedLen <= bytes.length
        ? Uint8List.fromList(bytes.sublist(base, base + packedLen))
        : null,
  );
}

S3mPattern _emptyPattern(int channelCount) => S3mPattern(
      List.generate(
        _rowsPerPattern,
        (_) => List<S3mCell>.filled(channelCount, S3mCell.empty),
        growable: false,
      ),
    );

/// OPL frequency-multiplication factor per the 4-bit `MULT` field (registers
/// 0x20/0x23). Index 11 and 13 alias 10 and 12; 14/15 both mean 15.
const List<double> _oplMultTable = <double>[
  0.5, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 12, 12, 15, 15, //
];

/// The synthesized buffer spans this many cycles of the base (unit) frequency.
/// It is even so that a 0.5× OPL multiple still yields a whole number of
/// oscillator cycles across the buffer, guaranteeing a seamless loop.
const int _adlibBaseCycles = 2;

/// Maximum FM modulation index (radians of carrier-phase deviation) reached
/// when the modulator operator is at full level (total-level attenuation 0).
const double _adlibMaxModIndex = 4.0;

/// Renders a short, seamlessly loopable APPROXIMATION of an AdLib/OPL 2-operator
/// FM instrument to normalized PCM in [-1, 1], so the ordinary S3M sample path
/// can sound a type-2 instrument.
///
/// This is NOT a cycle-exact OPL2/OPL3 emulator. It captures only the static
/// FM timbre: a carrier phase-modulated by a single modulator,
///
///   carrier(t) = sin(2π·fc·t + I·sin(2π·fm·t + fb·prev))
///
/// where `fc`/`fm` are the carrier/modulator OPL frequency multiples, `I` is a
/// modulation index derived from the modulator's total-level attenuation, and
/// `fb` is a small feedback term applied to the modulator when the patch's
/// feedback field is non-zero. Envelopes (attack/decay/sustain/release),
/// key-scaling, vibrato/tremolo, the waveform-select registers, and the
/// additive (connection=1) topology are all ignored — the result is a single
/// sustained FM tone, not the chip's actual output.
///
/// [adlibData] is the standard 12-byte SBI-style register block (header
/// 0x10..0x1B): modulator/carrier characteristic (MULT in the low nibble) at
/// 0/1, KSL+total-level at 2/3, attack/decay 4/5, sustain/release 6/7, waveform
/// 8/9, and feedback/connection at 10.
///
/// Tuning: the buffer holds [_adlibBaseCycles] cycles of the base frequency, so
/// looping it produces a tone at the base frequency and PITCH TRACKS THE PLAYED
/// NOTE through the existing resampler (the carrier sits at `carrierMult ×` the
/// base). Returns [samples] frames, normalized so the peak magnitude is 1.
///
/// A degenerate patch (fewer than 11 bytes, or all-zero registers) returns an
/// empty list so nothing garbage is played.
Float64List synthesizeAdlibWaveform(List<int> adlibData, {int samples = 2048}) {
  if (samples <= 0 || adlibData.length < 11) return Float64List(0);
  // All-zero register block = no real patch → play nothing.
  if (!adlibData.any((b) => (b & 0xFF) != 0)) return Float64List(0);

  final modMult = _oplMultTable[adlibData[0] & 0x0F];
  final carMult = _oplMultTable[adlibData[1] & 0x0F];
  final modTotalLevel = adlibData[2] & 0x3F; // 0 = loudest .. 63 = silent
  final feedbackField = (adlibData[10] >> 1) & 0x07; // 0..7

  // Modulator amplitude (linear) from its total-level attenuation. OPL total
  // level is 0.75 dB per step; 0 → unity, 63 → ~ -47 dB (effectively silent).
  final modAmp = math.pow(10.0, -0.75 * modTotalLevel / 20.0).toDouble();
  final modIndex = modAmp * _adlibMaxModIndex;

  // Feedback → a bounded self-modulation term on the modulator phase (0..π/2).
  final feedback =
      feedbackField == 0 ? 0.0 : (feedbackField / 7.0) * (math.pi / 2);

  // Whole cycle counts across the buffer (integers because base cycles is even
  // and the multiples are integers or 0.5) → the waveform loops seamlessly.
  final carCycles = carMult * _adlibBaseCycles;
  final modCycles = modMult * _adlibBaseCycles;

  const twoPi = 2 * math.pi;

  // Warm up the feedback so the loop point is seamless: run the (periodic)
  // modulator to a steady state before rendering the carrier.
  var modPrev = 0.0;
  if (feedback != 0.0) {
    for (var pass = 0; pass < 2; pass++) {
      for (var i = 0; i < samples; i++) {
        final phase = twoPi * modCycles * i / samples + feedback * modPrev;
        modPrev = math.sin(phase);
      }
    }
  }

  final out = Float64List(samples);
  var peak = 0.0;
  for (var i = 0; i < samples; i++) {
    final ph = i / samples;
    final modPhase = twoPi * modCycles * ph + feedback * modPrev;
    final mod = math.sin(modPhase);
    modPrev = mod;
    final car = math.sin(twoPi * carCycles * ph + modIndex * mod);
    out[i] = car;
    final a = car.abs();
    if (a > peak) peak = a;
  }

  if (peak <= 0.0 || !peak.isFinite) return Float64List(0);
  final inv = 1.0 / peak;
  for (var i = 0; i < samples; i++) {
    out[i] *= inv;
  }
  return out;
}

/// Decodes an ST3 "DP30ADPCM" packed sample block into normalized PCM in
/// [-1, 1]. Implements the well-known ST3 4-bit ADPCM (a.k.a. delta-PCM)
/// variant, exactly as libopenmpt's S3M ADPCM reader (`SampleIO` ADPCM path):
///
///   • [packed] begins with a 16-byte signed-int8 delta table.
///   • The remaining bytes are a nibble stream — two nibbles per byte, the LOW
///     nibble first (even sample index), then the HIGH nibble (odd index).
///   • An 8-bit accumulator starts at 0; for each sample it is advanced by
///     `table[nibble]` modulo 256, and the running value, reinterpreted as a
///     signed int8, is the output sample (÷128 to normalize to [-1, 1]).
///
/// Returns up to [lengthSamples] samples, stopping early on a truncated stream;
/// returns an empty list when there is no table (fewer than 16 bytes present).
///
/// Verification basis: proven by an internal roundtrip + a hand-computed
/// reference vector in test/s3m_dp30_test.dart against this algorithm spec —
/// NOT validated against a real packed `.s3m` (the corpus contains none). The
/// caller ([_readInstrument]) applies a degenerate-result fallback: an empty or
/// all-zero decode is discarded (pcm left empty, raw block preserved).
Float64List decodeDp30Adpcm(Uint8List packed, int lengthSamples) {
  if (lengthSamples <= 0 || packed.length < 16) return Float64List(0);
  // First 16 bytes = signed delta table.
  final table = Int8List(16);
  for (var i = 0; i < 16; i++) {
    final b = packed[i];
    table[i] = b >= 128 ? b - 256 : b;
  }
  const nibbleBase = 16;
  final availableNibbles = (packed.length - nibbleBase) * 2;
  var count = lengthSamples;
  if (count > availableNibbles) count = availableNibbles; // truncated stream
  if (count <= 0) return Float64List(0);

  final out = Float64List(count);
  var delta = 0; // 8-bit accumulator (wraps modulo 256)
  for (var i = 0; i < count; i++) {
    final byte = packed[nibbleBase + (i >> 1)];
    final nibble = (i & 1) == 0 ? (byte & 0x0F) : (byte >> 4);
    delta = (delta + table[nibble]) & 0xFF;
    final signed = delta >= 128 ? delta - 256 : delta;
    out[i] = signed / 128.0;
  }
  return out;
}

/// Reads an ASCII string from [bytes] at [start], up to [maxLen] bytes, stopping
/// at the first NUL. Non-printable trailing bytes are trimmed.
String _readAsciiz(Uint8List bytes, int start, int maxLen) {
  final sb = StringBuffer();
  for (var i = 0; i < maxLen; i++) {
    final off = start + i;
    if (off >= bytes.length) break;
    final b = bytes[off];
    if (b == 0) break;
    sb.writeCharCode(b);
  }
  return sb.toString().trimRight();
}
