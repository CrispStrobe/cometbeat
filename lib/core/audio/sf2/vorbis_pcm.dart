// The shape a decoded `.ogg` FILE comes back in. Kept in its own dart:ffi-free
// file so the import layer (and web) can name the type without pulling in the
// native decoder.
//
// This is deliberately NOT the `.sf3` [VorbisDecode] seam: an SF3 sample is
// always mono and gets its rate from the SF2 header, so that path throws both
// away. A user's .ogg needs them.

import 'dart:typed_data';

/// Decoded Ogg-Vorbis PCM: per-channel float samples (±1.0) plus the file's own
/// rate. [right] is null for mono. Mirrors `FlacPcm`.
class VorbisPcm {
  const VorbisPcm({
    required this.left,
    required this.right,
    required this.sampleRate,
  });

  final Float64List left;
  final Float64List? right;
  final int sampleRate;
}

/// Decode one complete Ogg-Vorbis file, or null on error / not Vorbis.
typedef VorbisFileDecode = VorbisPcm? Function(Uint8List ogg);

/// True if [b] is an Ogg stream carrying Vorbis (`OggS` + the Vorbis identity
/// packet). Ogg is only a container — it can hold Opus, FLAC or Theora — so
/// checking `OggS` alone would let files through that the decoder can't read.
bool isOggVorbis(Uint8List b) {
  if (b.length < 35) return false;
  if (b[0] != 0x4F || b[1] != 0x67 || b[2] != 0x67 || b[3] != 0x53) {
    return false; // "OggS"
  }
  return _vorbisIdentityAt(b) >= 0;
}

/// The sample rate declared in the Vorbis identification header, or 0 if this
/// isn't a readable Ogg-Vorbis stream. Parsing it here means the rate survives
/// even where the decoder itself doesn't report one (the web wasm shim).
int oggVorbisSampleRate(Uint8List b) {
  final at = _vorbisIdentityAt(b);
  if (at < 0 || at + 16 > b.length) return 0;
  // packet: type(1) "vorbis"(6) version(4) channels(1) rate(4, LE) …
  final rateAt = at + 12;
  return b[rateAt] |
      (b[rateAt + 1] << 8) |
      (b[rateAt + 2] << 16) |
      (b[rateAt + 3] << 24);
}

/// Channel count from the Vorbis identification header, or 0 if unreadable.
int oggVorbisChannels(Uint8List b) {
  final at = _vorbisIdentityAt(b);
  if (at < 0 || at + 12 > b.length) return 0;
  return b[at + 11];
}

/// Offset of the `\x01vorbis` identification packet within the first page, or
/// -1. The packet follows the Ogg page header + its segment table, whose length
/// varies, so scan the start of the file rather than assuming a fixed offset.
int _vorbisIdentityAt(Uint8List b) {
  final limit = b.length < 512 ? b.length - 7 : 505;
  for (var i = 0; i < limit; i++) {
    if (b[i] == 0x01 &&
        b[i + 1] == 0x76 && // v
        b[i + 2] == 0x6F && // o
        b[i + 3] == 0x72 && // r
        b[i + 4] == 0x62 && // b
        b[i + 5] == 0x69 && // i
        b[i + 6] == 0x73) {
      return i;
    }
  }
  return -1;
}
