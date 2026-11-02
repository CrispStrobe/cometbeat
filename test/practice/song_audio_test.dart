import 'dart:typed_data';

import 'package:comet_beat/core/audio/practice/song_audio.dart';
import 'package:comet_beat/core/audio/synth.dart' show wavBytes, wavBytesStereo;
import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a stereo WAV keeps both channels and its own rate', () async {
    final bytes = wavBytesStereo(
      Int16List.fromList([16384, -16384, 8192, -8192]),
      sampleRate: 22050,
    );
    final song = (await decodeSongBytes(bytes))!;
    expect(song.sampleRate, 22050);
    expect(song.frames, 2);
    expect(song.left, [0.5, 0.25]);
    expect(song.right, [-0.5, -0.25]);
    expect(song.mono(), [0, 0]);
  });

  test('a mono WAV fills both channels', () async {
    final song = (await decodeSongBytes(
      wavBytes(Int16List.fromList([16384, 0])),
    ))!;
    expect(song.left, song.right);
    expect(song.left.first, 0.5);
  });

  test('bytes that are neither WAV nor MP3 are refused, not misread', () async {
    expect(
      await decodeSongBytes(Uint8List.fromList('fLaC....'.codeUnits)),
      isNull,
    );
    expect(await decodeSongBytes(Uint8List(0)), isNull);
  });

  test('a truncated WAV is refused rather than thrown', () async {
    final bytes = wavBytes(Int16List.fromList([1, 2, 3]));
    expect(await decodeSongBytes(Uint8List.sublistView(bytes, 0, 20)), isNull);
  });

  group('separator model in the persisted config', () {
    test('round-trips', () {
      for (final m in CrispasrSeparatorModel.values) {
        final c = const TranscriptionEngineConfig()
            .copyWith(crispasrSeparatorModel: m);
        expect(
          TranscriptionEngineConfig.fromJson(c.toJson()).crispasrSeparatorModel,
          m,
        );
      }
    });

    test('a config written before the choice existed reads as auto', () {
      expect(
        TranscriptionEngineConfig.fromJson(const {'quality': 'balanced'})
            .crispasrSeparatorModel,
        CrispasrSeparatorModel.auto,
      );
    });

    test('auto loads htdemucs, the model the harness ranked first on drums',
        () {
      expect(CrispasrSeparatorModel.auto.registryBackend, 'htdemucs');
      expect(
        CrispasrSeparatorModel.miniBsRoformer.registryBackend,
        'mini-bs-roformer',
      );
      expect(
        CrispasrSeparatorModel.melBandRoformer.registryBackend,
        'mel-band-roformer',
      );
    });
  });

  test('only mini-bs-roformer is pinned to the CPU (CrispASR #568)', () {
    expect(
      [
        for (final m in CrispasrSeparatorModel.values)
          if (m.cpuOnly) m,
      ],
      [CrispasrSeparatorModel.miniBsRoformer],
    );
  });
}
