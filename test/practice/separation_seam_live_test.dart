// Live: does separating in windows (practice_split.dart) sound like separating
// the whole song? On a clip of a real song, compare the windowed stems with a
// single whole-clip separation — overall, and in the second around each seam,
// where a windowing artefact would be. Skips unless PROBE_SONG names an audio
// file and the separator model is here (see real_song_probe_test.dart).
//
//   COMET_GLINT_LIB=../glint/build/libglint.dylib \
//   PROBE_SONG="$HOME/Downloads/04 Carpet Crawlers.mp3" \
//   flutter test test/practice/separation_seam_live_test.dart
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/practice/practice_split.dart';
import 'package:comet_beat/core/audio/practice/song_audio_file.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_separate_io.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_session_io.dart';
import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// 10·log10(‖ref‖² / ‖est − ref‖²) over frames [a, b) of both channels.
double _sdr(SeparatedStem ref, SeparatedStem est, int a, int b) {
  var sig = 0.0, err = 0.0;
  for (var t = a; t < b; t++) {
    final dl = est.left[t] - ref.left[t], dr = est.right[t] - ref.right[t];
    sig += ref.left[t] * ref.left[t] + ref.right[t] * ref.right[t];
    err += dl * dl + dr * dr;
  }
  return 10 * math.log(sig / math.max(err, 1e-20)) / math.ln10;
}

void main() {
  final path = Platform.environment['PROBE_SONG'];
  final modelName = Platform.environment['PROBE_MODEL'] ?? 'mini-bs-roformer';
  final clipSeconds =
      int.tryParse(Platform.environment['PROBE_CLIP'] ?? '') ?? 100;
  final model = CrispasrSeparatorModel.values.firstWhere(
    (m) => m != CrispasrSeparatorModel.auto && m.registryBackend == modelName,
    orElse: () => CrispasrSeparatorModel.miniBsRoformer,
  );

  test(
    'windowed vs whole-clip separation (${model.registryBackend})',
    () async {
      if (path == null || !File(path).existsSync()) {
        markTestSkipped('set PROBE_SONG to an audio file');
        return;
      }
      final modelPath = crispasrModelPath(model.registryBackend);
      if (modelPath == null) {
        markTestSkipped('${model.registryBackend} not available here');
        return;
      }
      final song = await decodeSongFile(path, File(path).readAsBytesSync());
      expect(song, isNotNull);
      final sr = song!.sampleRate;
      // From a minute in: past any intro, into the full arrangement.
      final a = math.min(60 * sr, song.frames ~/ 4);
      final b = math.min(song.frames, a + clipSeconds * sr);
      final l = Float32List.sublistView(song.left, a, b);
      final r = Float32List.sublistView(song.right, a, b);
      final session = openCrispasrSeparator(
        modelPath,
        crispasrLibPath(),
        model.registryBackend,
        cpuOnly: model.cpuOnly,
      );
      try {
        expect(session.separateSampleRate, sr);
        final n = b - a;
        List<SeparatedStem> whole() =>
            separateInWindows(l, r, sr, session.separate, windowFrames: n + 1);
        final ref = whole();
        final again = whole();
        // As the app does it: on the model's own chunk grid.
        final grid = crispasrSeparatorGrid(model.registryBackend, sr);
        expect(grid, isNotNull);
        final windowed =
            separateInWindows(l, r, sr, session.separate, grid: grid);
        final seams = [
          for (final w in alignedSeparationWindows(
            n,
            grid!,
            window: (kSeparationWindowSeconds * sr).round(),
          ).skip(1))
            w.fadeInStart,
        ];
        // ignore: avoid_print
        print('seam: clip ${n / sr} s, seams at '
            '${seams.map((s) => (s / sr).toStringAsFixed(2)).join(', ')} s');
        var worst = double.infinity;
        for (var k = 0; k < ref.length; k++) {
          final name = ref[k].name;
          final w = windowed.firstWhere((s) => s.name == name);
          final rerun = _sdr(ref[k], again[k], 0, n);
          final overall = _sdr(ref[k], w, 0, n);
          final near = [
            for (final s in seams)
              _sdr(ref[k], w, math.max(0, s - sr), math.min(n, s + 2 * sr)),
          ];
          worst = math.min(worst, overall);
          // ignore: avoid_print
          print('seam: ${name.padRight(7)} whole-vs-whole '
              '${rerun.toStringAsFixed(1)} dB · windowed-vs-whole '
              '${overall.toStringAsFixed(1)} dB · at seams '
              '${near.map((d) => d.toStringAsFixed(1)).join(' / ')} dB');
        }
        // On the grid the windows see the very chunks the whole-clip call
        // does: agreement to float rounding, not merely below audibility.
        expect(worst, greaterThan(100));
      } finally {
        session.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
