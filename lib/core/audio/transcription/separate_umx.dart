// lib/core/audio/transcription/separate_umx.dart
//
// W-SEP (vocals) — Open-Unmix (umxhq vocals, MIT) source separation, the
// spectrogram-domain route (distinct from the waveform HTDemucs shell in
// `separate.dart`, whose model is too large for pure Dart). Isolates the singing
// voice from a full mix so CREPE can follow the LEAD MELODY of a whole song, not
// the loudest instrument. Runs on `onnx_runtime_dart`.
//
// Pipeline: resample→44.1 kHz → STFT (n_fft 4096, hop 1024) → the Open-Unmix
// BiLSTM estimates the vocal magnitude → soft ratio mask → apply to the mix's
// complex STFT → iSTFT → the isolated vocal. See `stft.dart`. Provides a
// vocals-only [Stems] for the `stems.dart` `Separator` seam.
//
// QUALITY NOTE: umxhq is a modest separator (vocals SDR ~5–6 dB) — good enough
// to lift a buried vocal for pitch tracking, not for clean stems. It helps only
// on REAL music; on already-clear or synthetic audio, tracking the raw mix is as
// good (or better).
//
// WEB-SAFE: takes a preloaded [OnnxModel]; the ~36 MB model download (dart:io)
// lives in the native `separate_umx_model_store.dart`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/transcription/stems.dart'
    show Separator, Stems;
import 'package:comet_beat/core/audio/transcription/stft.dart';
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

const int umxSampleRate = 44100;
const int _nFft = 4096;
const int _hop = 1024;
const String _inName = 'spec';
const String _outName = 'mask';

/// Isolate the vocal from [mono] (a full mix) with Open-Unmix. Returns the vocal
/// waveform at 44.1 kHz. [model] is the preloaded umxhq vocals ONNX. Pure /
/// synchronous / web-safe. Feed the result to `crepeF0` for a full-song
/// lead-melody pitch track.
Float64List separateVocal(
  Float64List mono, {
  required OnnxModel model,
  int sampleRate = umxSampleRate,
}) {
  final audio = sampleRate == umxSampleRate
      ? mono
      : resampleLinear(mono, sampleRate / umxSampleRate);
  if (audio.isEmpty) return Float64List(0);

  final st = Stft(_nFft, _hop);
  final (re, im, nFrames) = st.forward(audio);
  final nFreq = st.nFreq;

  // Magnitude, and the model input [1, 2, nFreq, nFrames] (mono duplicated to
  // Open-Unmix's 2 channels; bins then frames).
  final mag = Float32List(nFrames * nFreq);
  for (var i = 0; i < mag.length; i++) {
    mag[i] = math.sqrt(re[i] * re[i] + im[i] * im[i]);
  }
  final input = Float32List(2 * nFreq * nFrames);
  for (var c = 0; c < 2; c++) {
    for (var b = 0; b < nFreq; b++) {
      final dst = (c * nFreq + b) * nFrames;
      for (var t = 0; t < nFrames; t++) {
        input[dst + t] = mag[t * nFreq + b];
      }
    }
  }

  final out = model.run(
    {
      _inName: Tensor.float(input, [1, 2, nFreq, nFrames]),
    },
    const [_outName],
  )[_outName]!;
  final est = out.f ?? out.asFloatList(); // [1,2,nFreq,nFrames] est vocal mag

  // Soft ratio mask (channel 0) applied to the mix's complex STFT.
  final vre = Float64List(nFrames * nFreq), vim = Float64List(nFrames * nFreq);
  for (var b = 0; b < nFreq; b++) {
    final row = b * nFrames; // channel 0
    for (var t = 0; t < nFrames; t++) {
      final idx = t * nFreq + b;
      final m = mag[idx];
      final mask = m > 1e-8 ? (est[row + t] / m).clamp(0.0, 1.0) : 0.0;
      vre[idx] = re[idx] * mask;
      vim[idx] = im[idx] * mask;
    }
  }
  return st.inverse(vre, vim, nFrames, audio.length);
}

/// Open-Unmix as a [Stems] (vocals only; other stems null). Async to match the
/// `stems.dart` [Separator] seam.
Future<Stems> umxSeparate(
  Float64List mono, {
  required OnnxModel model,
  int sampleRate = umxSampleRate,
}) async {
  final vocals = separateVocal(mono, model: model, sampleRate: sampleRate);
  return (vocals: vocals, bass: null, drums: null, other: null);
}

/// Wrap a loaded [model] as the stems.dart [Separator] the pipeline injects —
/// a vocals-only separator (the lead-melody lever).
Separator umxVocalSeparator(OnnxModel model) => (mono, sampleRate) =>
    umxSeparate(mono, model: model, sampleRate: sampleRate);
