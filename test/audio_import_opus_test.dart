// The export -> import round trip for Ogg-Opus, and the container-detection
// rules around it.
//
// The gap this pins shut: `.ogg`/`.oga` was in kAudioImportExtensions and the
// export sheet could WRITE Opus, but importAudio only recognised Ogg-VORBIS.
// An Opus file therefore passed the picker's extension filter, missed every
// branch, and came back null — indistinguishable from a corrupt file. Users
// could export a mix and not re-open it.
//
// Runs headless with an INJECTED decoder, so it tests the routing (detection,
// ordering, channel de-interleaving) rather than the codec. The real codec
// round trip is integration_test/glint_encoder_test.dart and the native
// ctest harness.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/encoded_audio.dart';
import 'package:comet_beat/core/audio/sf2/vorbis_pcm.dart' show isOggVorbis;
import 'package:comet_beat/shared/music_io/audio_import.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal but structurally honest Ogg page carrying an `OpusHead` packet.
/// Real enough for detection: "OggS", the 27-byte header, a segment table, then
/// the packet.
Uint8List _oggOpusHeader({int channels = 2}) {
  final head = <int>[
    0x4F, 0x70, 0x75, 0x73, 0x48, 0x65, 0x61, 0x64, // "OpusHead"
    1, // version
    channels,
    0x38, 0x01, // pre-skip 312
    0x80, 0xBB, 0x00, 0x00, // 48000 input rate
    0, 0, // output gain
    0, // mapping family
  ];
  final page = <int>[
    0x4F, 0x67, 0x67, 0x53, // "OggS"
    0, // version
    0x02, // header type: beginning of stream
    ...List<int>.filled(8, 0), // granule
    1, 0, 0, 0, // serial
    0, 0, 0, 0, // page sequence
    0, 0, 0, 0, // CRC (not validated by the detector)
    1, // one segment
    head.length,
    ...head,
  ];
  return Uint8List.fromList(page);
}

/// The same page shape but carrying a Vorbis identity packet.
Uint8List _oggVorbisHeader() {
  final ident = <int>[
    0x01, 0x76, 0x6F, 0x72, 0x62, 0x69, 0x73, // \x01vorbis
    0, 0, 0, 0, // version
    2, // channels
    0x44, 0xAC, 0x00, 0x00, // 44100
    ...List<int>.filled(16, 0),
  ];
  return Uint8List.fromList(<int>[
    0x4F,
    0x67,
    0x67,
    0x53,
    0,
    0x02,
    ...List<int>.filled(8, 0),
    1,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1,
    ident.length,
    ...ident,
  ]);
}

DecodedAudio _stereo({int frames = 400, int sampleRate = 48000}) {
  final pcm = Float64List(frames * 2);
  for (var i = 0; i < frames; i++) {
    pcm[i * 2] = 0.5; // left rail
    pcm[i * 2 + 1] = -0.25; // right rail
  }
  return DecodedAudio(pcm: pcm, channels: 2, sampleRate: sampleRate);
}

void main() {
  group('Ogg container detection', () {
    test('an Opus stream is Opus and NOT Vorbis', () {
      final opus = _oggOpusHeader();
      expect(isOggOpus(opus), isTrue);
      expect(
        isOggVorbis(opus),
        isFalse,
        reason: 'must not reach the Vorbis path',
      );
    });

    test('a Vorbis stream is Vorbis and NOT Opus', () {
      final vorbis = _oggVorbisHeader();
      expect(isOggVorbis(vorbis), isTrue);
      expect(isOggOpus(vorbis), isFalse);
    });

    test('non-Ogg bytes are neither', () {
      final wav = Uint8List.fromList('RIFF....WAVE'.codeUnits);
      expect(isOggOpus(wav), isFalse);
      expect(isOggVorbis(wav), isFalse);
      expect(isOggOpus(Uint8List(0)), isFalse);
      expect(isOggOpus(Uint8List(8)), isFalse);
    });

    test('OpusHead is found past a variable-length segment table', () {
      // The magic does not sit at a fixed offset — the Ogg page header's
      // segment table varies — so the locator must scan.
      final b = _oggOpusHeader();
      expect(b.indexOf(0x4F, 4), greaterThan(20));
      expect(isOggOpus(b), isTrue);
    });

    test('channel count is read from OpusHead', () {
      expect(oggOpusChannels(_oggOpusHeader(channels: 1)), 1);
      expect(oggOpusChannels(_oggOpusHeader()), 2, reason: 'default is stereo');
      expect(
        oggOpusChannels(_oggVorbisHeader()),
        0,
        reason: 'not an Opus head',
      );
    });
  });

  group('importAudio routes Ogg-Opus', () {
    test('an Opus file reaches the Opus decoder and de-interleaves', () {
      var calls = 0;
      final imported = importAudio(
        _oggOpusHeader(),
        opusDecode: (bytes) {
          calls++;
          return _stereo();
        },
      );

      expect(calls, 1, reason: 'the Opus decoder must be the one consulted');
      expect(imported, isNotNull);
      expect(imported!.sampleRate, 48000);
      expect(imported.pcm.length, 400);
      expect(imported.right, isNotNull);
      expect(imported.pcm[0], 0.5, reason: 'left channel');
      expect(imported.right![0], -0.25, reason: 'right channel');
    });

    test('an Opus file never reaches the Vorbis decoder', () {
      var vorbisCalls = 0;
      importAudio(
        _oggOpusHeader(),
        opusDecode: (_) => _stereo(),
        vorbisDecode: (_) {
          vorbisCalls++;
          return null;
        },
      );
      expect(vorbisCalls, 0);
    });

    test('mono Opus imports without a right channel', () {
      final imported = importAudio(
        _oggOpusHeader(channels: 1),
        opusDecode: (_) => DecodedAudio(
          pcm: Float64List.fromList(List<double>.filled(256, 0.3)),
          channels: 1,
          sampleRate: 48000,
        ),
      );
      expect(imported, isNotNull);
      expect(imported!.right, isNull);
      expect(imported.pcm.length, 256);
    });

    test('importAudioMono folds Opus stereo down', () {
      final mono = importAudioMono(
        _oggOpusHeader(),
        opusDecode: (_) => _stereo(),
      );
      expect(mono, isNotNull);
      expect(mono!.right, isNull);
      // (0.5 + -0.25) / 2
      expect(mono.pcm[0], closeTo(0.125, 1e-12));
    });

    test('no decoder available degrades to null, it does not throw', () {
      // Web without the wasm shim, or a native build without the plugin.
      expect(importAudio(_oggOpusHeader(), opusDecode: (_) => null), isNull);
    });

    test('a decoder returning zero frames degrades to null', () {
      final empty = DecodedAudio(
        pcm: Float64List(0),
        channels: 2,
        sampleRate: 48000,
      );
      expect(importAudio(_oggOpusHeader(), opusDecode: (_) => empty), isNull);
    });
  });

  test('.opus is offered by the picker', () {
    // Without this the file dialog filters out the very files we can now read.
    expect(kAudioImportExtensions, contains('opus'));
    expect(kAudioImportExtensions, contains('ogg'));
  });
}
