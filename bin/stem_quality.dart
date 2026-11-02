// bin/stem_quality.dart
//
// How well does each CrispASR source separator recover KNOWN stems? Ground
// truth comes from the Loop Mixer: every groove track (drums, bass, chords,
// melody) renders ALONE, so the stems are exact and their sum is the mix. The
// separators then split that mix and each stem is scored by SDR — the
// MUSDB/MDX "new SDR", 10·log10(‖s‖² / ‖s − ŝ‖²), in dB, higher is better.
//
// Scored stems: drums, bass, and other+vocals against chords+melody — the
// groove has no singer, so a model is right to file the synth lead under
// `other` and leave `vocals` near-silent; scoring melody against `vocals`
// alone would measure that silence (it reads ~0 dB) and nothing else.
// mel-band-roformer splits only vocals / the rest; with no voice in the mix
// its "rest" should be the whole mix, which is what it is scored against.
//
// --voice adds a recorded voice (any PCM WAV; repeated to the groove's length)
// as a real `vocals` stem — e.g. `say -o v.aiff "…" && afconvert -f WAVE
// -d LEI16@44100 v.aiff v.wav` — which is what makes the vocal split, and so
// mel-band-roformer, measurable at all.
//
// ⚠ Synthetic material: these voices are our own synths, not recorded
// instruments and not a human voice. The numbers RANK the models on clean,
// well-separated parts; they are not MUSDB scores and must not be quoted as
// such. A recorded multitrack would be the next check.
//
//   COMET_CRISPASR_LIB=~/.cache/crispasr/libcrispasr.dylib \
//     dart run bin/stem_quality.dart [--models htdemucs,mini-bs-roformer] \
//                                    [--seconds 24] [--download] [--consistent]
//                                    [--voice speech.wav]
//                                    [--json out.json]

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/practice/practice_mix.dart'
    show mixtureConsistent;
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_separate_io.dart';
import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:comet_beat/core/audio/wav_io.dart';

const _tracks = ['drums', 'bass', 'chords', 'melody'];

Future<void> main(List<String> args) async {
  String? opt(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final seconds = int.tryParse(opt('--seconds') ?? '') ?? 24;
  final download = args.contains('--download');
  // Score the stems after the practice player's mixture-consistency step.
  final consistent = args.contains('--consistent');
  final wanted =
      (opt('--models') ?? 'htdemucs,mini-bs-roformer,mel-band-roformer')
          .split(',');
  final models = [
    for (final m in CrispasrSeparatorModel.values)
      if (m != CrispasrSeparatorModel.auto &&
          wanted.contains(m.registryBackend))
        m,
  ];

  final voicePath = opt('--voice');
  final voice = voicePath == null ? null : _readVoice(voicePath);

  final report = <String, Object>{};
  for (final style in kGrooveStyles) {
    final truth = _renderTruth(style.id, seconds);
    if (voice != null) truth['voice'] = _fit(voice, truth['drums']!.length);
    final mix = _sum(truth.values);
    // Leave headroom: scale the mix AND every reference by the same factor so
    // the mixture stays an exact sum.
    final peak = mix.fold<double>(0, (m, v) => math.max(m, v.abs()));
    final g = peak > 0 ? 0.9 / peak : 1.0;
    for (final v in [...truth.values, mix]) {
      for (var i = 0; i < v.length; i++) {
        v[i] *= g;
      }
    }
    stdout.writeln('\n== style "${style.id}" (${style.tempoBpm} BPM, '
        '${(mix.length / kSampleRate).toStringAsFixed(1)} s)');

    for (final model in models) {
      if (!await crispasrSeparatorAvailable(model, download: download)) {
        stdout.writeln('  ${model.registryBackend}: unavailable (lib or model '
            'missing; --download fetches the model)');
        continue;
      }
      final sw = Stopwatch()..start();
      final stems =
          await separateStereoCrispasr(mix, mix, kSampleRate, model: model);
      sw.stop();
      if (stems == null) {
        stdout.writeln('  ${model.registryBackend}: separation failed');
        continue;
      }
      final est = {
        for (final s in consistent ? mixtureConsistent(stems, mix, mix) : stems)
          s.name: s,
      };
      final scores = <String, double>{};
      // The groove has no singer, so a separator is right to leave its
      // `vocals` stem near-silent and file the synth lead under `other`. The
      // fair harmonic score is therefore other+vocals against chords+melody.
      final harmonic = _sum([truth['chords']!, truth['melody']!]);
      final v = truth['voice'];
      if (v != null) {
        // A real voice in the mix: `vocals` is scored against it.
        final rest = est['instrumental'] ?? est['other'];
        if (model == CrispasrSeparatorModel.melBandRoformer) {
          scores['vocals'] = _sdr(v, est['vocals']);
          scores['accompaniment'] = _sdr(
            _sum([truth['drums']!, truth['bass']!, harmonic]),
            rest,
          );
        } else {
          scores['vocals'] = _sdr(v, est['vocals']);
          scores['drums'] = _sdr(truth['drums']!, est['drums']);
          scores['bass'] = _sdr(truth['bass']!, est['bass']);
          scores['other'] = _sdr(harmonic, rest);
        }
      } else if (model == CrispasrSeparatorModel.melBandRoformer) {
        // Two stems: vocals and the rest (named `other` or `instrumental`
        // depending on the GGUF). Here everything is "the rest".
        scores['accompaniment'] =
            _sdr(mix, est['instrumental'] ?? est['other']);
      } else {
        scores['drums'] = _sdr(truth['drums']!, est['drums']);
        scores['bass'] = _sdr(truth['bass']!, est['bass']);
        scores['other+vocals'] =
            _sdr(harmonic, _add(est['other'], est['vocals']));
      }
      final rtf = sw.elapsedMilliseconds / 1000 / (mix.length / kSampleRate);
      stdout.writeln('  ${model.registryBackend.padRight(18)} '
          '${scores.entries.map((e) => '${e.key} ${e.value.toStringAsFixed(1)}').join(' · ')}'
          '  (${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s, '
          '${rtf.toStringAsFixed(2)}× real time)');
      report['${style.id}/${model.registryBackend}'] = {
        'sdr': scores,
        'seconds': sw.elapsedMilliseconds / 1000,
        'rtf': rtf,
      };
    }
  }
  final out = opt('--json');
  if (out != null) {
    File(out).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report),
    );
  }
}

/// A voice recording as mono float at [kSampleRate].
Float32List _readVoice(String path) {
  final wav = readWavPcm16(File(path).readAsBytesSync());
  final ch = wav.channels;
  final n = wav.samples.length ~/ ch;
  final mono = Float64List(n);
  for (var i = 0; i < n; i++) {
    mono[i] = wav.samples[i * ch] / 32768;
  }
  final at = wav.sampleRate == kSampleRate
      ? mono
      : resampleLinear(mono, wav.sampleRate / kSampleRate);
  return Float32List.fromList(at);
}

/// [x] repeated (with a one-second rest between repeats, as a singer breathes)
/// and cut to exactly [n] frames.
Float32List _fit(Float32List x, int n) {
  final out = Float32List(n);
  final period = x.length + kSampleRate;
  for (var i = 0; i < n; i++) {
    final k = i % period;
    if (k < x.length) out[i] = x[k];
  }
  return out;
}

/// Each groove track rendered alone, tiled to at least [seconds].
Map<String, Float32List> _renderTruth(String styleId, int seconds) {
  final engine = LoopEngine()
    ..styleId = styleId
    ..progression = kProgressions.first;
  final out = <String, Float32List>{};
  for (final t in _tracks) {
    engine.enabled
      ..clear()
      ..add(t);
    final wav = readWavPcm16(engine.renderLoop());
    final ch = wav.channels;
    final frames = wav.samples.length ~/ ch;
    final loop = Float32List(frames);
    for (var i = 0; i < frames; i++) {
      var s = 0.0;
      for (var c = 0; c < ch; c++) {
        s += wav.samples[i * ch + c];
      }
      loop[i] = s / ch / 32768;
    }
    final reps = math.max(1, (seconds * kSampleRate / frames).ceil());
    final tiled = Float32List(frames * reps);
    for (var r = 0; r < reps; r++) {
      tiled.setAll(r * frames, loop);
    }
    out[t] = tiled;
  }
  return out;
}

Float32List _sum(Iterable<Float32List> xs) {
  final n = xs.map((x) => x.length).reduce(math.max);
  final out = Float32List(n);
  for (final x in xs) {
    for (var i = 0; i < x.length; i++) {
      out[i] += x[i];
    }
  }
  return out;
}

/// The sum of two stems (either may be missing).
SeparatedStem? _add(SeparatedStem? a, SeparatedStem? b) {
  if (a == null || b == null) return a ?? b;
  final n = math.min(a.frames, b.frames);
  final l = Float32List(n), r = Float32List(n);
  for (var i = 0; i < n; i++) {
    l[i] = a.left[i] + b.left[i];
    r[i] = a.right[i] + b.right[i];
  }
  return SeparatedStem(a.name, l, r, a.sampleRate);
}

/// SDR of an estimate against [ref] (both channels of the stem, which carry
/// the same mono reference here). A missing stem scores −∞ → reported as −99.
double _sdr(Float32List ref, SeparatedStem? est) {
  if (est == null) return -99;
  var sig = 0.0, err = 0.0;
  final n = math.min(ref.length, est.frames);
  for (var i = 0; i < n; i++) {
    for (final e in [est.left[i], est.right[i]]) {
      sig += ref[i] * ref[i];
      final d = ref[i] - e;
      err += d * d;
    }
  }
  if (sig == 0) return -99;
  return 10 * math.log(sig / math.max(err, 1e-12)) / math.ln10;
}
