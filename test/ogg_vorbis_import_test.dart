// O16 — Ogg-Vorbis file import. The DECODE needs glint (native/wasm) and isn't
// available in a headless test, so what's pinned here is everything that is
// pure Dart and can silently go wrong: recognising Vorbis inside an Ogg
// container (Ogg also carries Opus/FLAC/Theora), reading the rate and channel
// count out of the identification header, and declining cleanly — never
// throwing, never guessing — when no decoder is present.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/vorbis_pcm.dart';
import 'package:comet_beat/shared/music_io/audio_import.dart';
import 'package:flutter_test/flutter_test.dart';

/// A first Ogg page carrying a Vorbis identification packet.
/// Layout after `OggS`: version, flags, granule(8), serial(4), seq(4), crc(4),
/// segments(1), segment table, then the packet.
Uint8List _oggVorbis({
  int rate = 44100,
  int channels = 2,
  String codec = 'vorbis',
}) {
  final packet = BytesBuilder()
    ..addByte(0x01) // identification packet
    ..add(codec.codeUnits)
    ..add([0, 0, 0, 0]) // vorbis_version
    ..addByte(channels)
    ..add([
      rate & 0xFF,
      (rate >> 8) & 0xFF,
      (rate >> 16) & 0xFF,
      (rate >> 24) & 0xFF,
    ])
    ..add(List<int>.filled(16, 0)); // bitrate fields + blocksizes + framing
  final body = packet.toBytes();

  return Uint8List.fromList([
    ...'OggS'.codeUnits,
    0, // version
    0x02, // header type: beginning of stream
    ...List<int>.filled(8, 0), // granule position
    ...List<int>.filled(4, 1), // serial
    ...List<int>.filled(4, 0), // page sequence
    ...List<int>.filled(4, 0), // crc (unchecked here)
    1, // one segment
    body.length,
    ...body,
  ]);
}

void main() {
  group('isOggVorbis', () {
    test('accepts an Ogg page carrying Vorbis', () {
      expect(isOggVorbis(_oggVorbis()), isTrue);
    });

    test('rejects Ogg carrying something else — the container is not the codec',
        () {
      // Same Ogg framing, but the packet says "OpusHead"-ish, not Vorbis.
      expect(isOggVorbis(_oggVorbis(codec: 'OpusHe')), isFalse);
    });

    test('rejects non-Ogg and truncated input', () {
      expect(
        isOggVorbis(Uint8List.fromList('RIFFxxxxWAVE'.codeUnits)),
        isFalse,
      );
      expect(isOggVorbis(Uint8List.fromList('OggS'.codeUnits)), isFalse);
      expect(isOggVorbis(Uint8List(0)), isFalse);
    });
  });

  group('identification header', () {
    test('the sample rate is read for the usual rates', () {
      for (final rate in [8000, 22050, 32000, 44100, 48000, 96000]) {
        expect(
          oggVorbisSampleRate(_oggVorbis(rate: rate)),
          rate,
          reason: '$rate Hz',
        );
      }
    });

    test('the channel count is read', () {
      expect(oggVorbisChannels(_oggVorbis(channels: 1)), 1);
      expect(oggVorbisChannels(_oggVorbis()), 2);
    });

    test('a non-Vorbis stream reports 0 rather than a wrong number', () {
      final wav = Uint8List.fromList('RIFFxxxxWAVEfmt '.codeUnits);
      expect(oggVorbisSampleRate(wav), 0);
      expect(oggVorbisChannels(wav), 0);
    });
  });

  group('importAudio', () {
    test('offers .ogg in the picker extensions', () {
      expect(kAudioImportExtensions, containsAll(['ogg', 'oga']));
    });

    test('declines an .ogg with no decoder available, without throwing', () {
      // Headless tests have no glint library, so this must return null — the
      // caller shows "couldn't read that file" rather than crashing.
      expect(importAudio(_oggVorbis()), isNull);
    });

    test('uses an injected decoder, keeping its rate and both channels', () {
      final imported = importAudio(
        _oggVorbis(rate: 48000),
        vorbisDecode: (_) => VorbisPcm(
          left: Float64List.fromList([0.5, -0.5]),
          right: Float64List.fromList([-0.25, 0.25]),
          sampleRate: 48000,
        ),
      );
      expect(imported, isNotNull);
      expect(imported!.sampleRate, 48000);
      expect(imported.pcm, [0.5, -0.5]);
      expect(imported.right, [-0.25, 0.25]);
    });

    test('falls back to the header rate if a decoder reports none', () {
      final imported = importAudio(
        _oggVorbis(rate: 22050),
        vorbisDecode: (_) => VorbisPcm(
          left: Float64List.fromList([0.1]),
          right: null,
          sampleRate: 0, // the web shim doesn't report a rate
        ),
      );
      expect(imported!.sampleRate, 22050);
    });

    test('an empty decode result is declined', () {
      expect(
        importAudio(
          _oggVorbis(),
          vorbisDecode: (_) => VorbisPcm(
            left: Float64List(0),
            right: null,
            sampleRate: 44100,
          ),
        ),
        isNull,
      );
    });

    test('importAudioMono folds an injected stereo ogg down', () {
      final mono = importAudioMono(
        _oggVorbis(),
        vorbisDecode: (_) => VorbisPcm(
          left: Float64List.fromList([1, 1]),
          right: Float64List.fromList([0, 0]),
          sampleRate: 44100,
        ),
      );
      expect(mono!.right, isNull);
      expect(mono.pcm, [0.5, 0.5]);
    });
  });
}
