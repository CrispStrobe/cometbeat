// The practice-stems pipeline AS IT WAS before the memory work (origin/main
// 1328361c), kept verbatim so real_song_probe_test.dart can measure before
// and after on the same machine, song and metric. Not used by the app.

import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/crisp_dsp/time_stretch.dart';
import 'package:comet_beat/core/audio/practice/song_audio.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_separate_io.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_session_io.dart';
import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:crispasr/crispasr.dart' show CrispasrSession;

/// Old separateStereoCrispasr: the whole song in one separate() call.
Future<List<SeparatedStem>?> legacySeparate(
  Float32List left,
  Float32List right,
  int sampleRate,
  CrispasrSeparatorModel model,
) async {
  final backend = model.registryBackend;
  final modelPath = crispasrModelPath(backend);
  if (modelPath == null) return null;
  final libPath = crispasrLibPath();
  final cpuOnly = model.cpuOnly;
  return Isolate.run(() {
    CrispasrSession? session;
    try {
      session =
          openCrispasrSeparator(modelPath, libPath, backend, cpuOnly: cpuOnly);
      final sr = session.separateSampleRate;
      if (sr <= 0) return null;
      final l = _toRate(left, sampleRate, sr);
      final r = _toRate(right, sampleRate, sr);
      final n = l.length < r.length ? l.length : r.length;
      final inter = Float32List(n * 2);
      for (var i = 0; i < n; i++) {
        inter[2 * i] = l[i];
        inter[2 * i + 1] = r[i];
      }
      return [
        for (final s in session.separate(inter))
          SeparatedStem.fromInterleaved(s.name, s.pcm, sr),
      ];
    } catch (_) {
      return null;
    } finally {
      session?.close();
    }
  });
}

Float32List _toRate(Float32List x, int from, int to) {
  if (from == to) return x;
  final f64 = Float64List(x.length);
  for (var i = 0; i < x.length; i++) {
    f64[i] = x[i];
  }
  final y = resampleLinear(f64, from / to);
  return Float32List.fromList(y);
}

/// Old _consistentInIsolate + mixtureConsistent (boxed list comprehensions).
Future<List<SeparatedStem>> legacyConsistent(
  List<SeparatedStem> stems,
  SongAudio song,
) {
  final rate = stems.first.sampleRate;
  final left = song.left, right = song.right, from = song.sampleRate;
  return Isolate.run(
    () => _legacyMixtureConsistent(
      stems,
      _atRate(left, from, rate),
      _atRate(right, from, rate),
    ),
  );
}

Float32List _atRate(Float32List x, int from, int to) {
  if (from == to) return x;
  final y = resampleLinear(Float64List.fromList(x), from / to);
  return Float32List.fromList(y);
}

List<SeparatedStem> _legacyMixtureConsistent(
  List<SeparatedStem> stems,
  Float32List left,
  Float32List right,
) {
  if (stems.isEmpty) return stems;
  final n = stems.map((s) => s.frames).fold(
        math.min(left.length, right.length),
        math.min,
      );
  final share = 1 / stems.length;
  final rl = Float32List(n), rr = Float32List(n);
  for (var i = 0; i < n; i++) {
    var sl = 0.0, sr = 0.0;
    for (final s in stems) {
      sl += s.left[i];
      sr += s.right[i];
    }
    rl[i] = (left[i] - sl) * share;
    rr[i] = (right[i] - sr) * share;
  }
  return [
    for (final s in stems)
      SeparatedStem(
        s.name,
        Float32List.fromList([
          for (var i = 0; i < n; i++) s.left[i] + rl[i],
        ]),
        Float32List.fromList([
          for (var i = 0; i < n; i++) s.right[i] + rr[i],
        ]),
        s.sampleRate,
      ),
  ];
}

/// Old _slowInIsolate + slowStems: the whole slowed song rendered at once.
Future<List<SeparatedStem>> legacySlow(
  List<SeparatedStem> stems,
  double speed,
) =>
    Isolate.run(() {
      final channels = <Float64List>[
        for (final s in stems) ...[
          Float64List.fromList(s.left),
          Float64List.fromList(s.right),
        ],
      ];
      final out = timeStretchLinked(
        channels,
        1 / speed,
        quality: StretchQuality.deep,
      );
      return [
        for (var i = 0; i < stems.length; i++)
          SeparatedStem(
            stems[i].name,
            Float32List.fromList(out[2 * i]),
            Float32List.fromList(out[2 * i + 1]),
            stems[i].sampleRate,
          ),
      ];
    });
