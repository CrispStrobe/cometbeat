// bin/fxproc.dart
//
// Headless audio-FX processor — apply any of the app's pure-Dart crisp_dsp effects
// to a WAV, offline. Chipmunk/robot/alien a recording, add reverb or echo, crunch
// it, ring-mod it, or slow it down without changing pitch — no app, no device.
// Flutter-free, like bin/listen.dart.
//
//   dart run bin/fxproc.dart in.wav out.wav --effect reverb
//   dart run bin/fxproc.dart voice.wav out.wav --effect robot
//   dart run bin/fxproc.dart in.wav out.wav --effect distortion --kind fuzz --drive 6
//   dart run bin/fxproc.dart in.wav out.wav --effect ringmod --carrier 180 --mix 0.7
//   dart run bin/fxproc.dart in.wav out.wav --effect stretch --factor 1.5
//
// Effects: reverb · delay · chorus · flanger · distortion · ringmod · stretch,
// plus the voice presets normal/chipmunk/monster/deep/robot/alien/cyborg/radio/demon.
// Stereo input is downmixed to mono; output is mono at the input's sample rate.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/distortion.dart';
import 'package:comet_beat/core/audio/crisp_dsp/modulated_delay.dart';
import 'package:comet_beat/core/audio/crisp_dsp/reverb.dart';
import 'package:comet_beat/core/audio/crisp_dsp/ring_mod.dart';
import 'package:comet_beat/core/audio/crisp_dsp/time_stretch.dart';
import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart';
import 'package:comet_beat/core/audio/synth.dart' show wavBytes;
import 'package:comet_beat/core/audio/wav_io.dart';

void main(List<String> args) {
  final positional = <String>[];
  var effect = '';
  var mix = 0.4;
  var drive = 4.0;
  var carrier = 220.0;
  var factor = 1.5;
  var kind = DistortionKind.softClip;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String next() => i + 1 < args.length ? args[++i] : '';
    switch (a) {
      case '--effect':
        effect = next();
      case '--mix':
        mix = double.tryParse(next()) ?? mix;
      case '--drive':
        drive = double.tryParse(next()) ?? drive;
      case '--carrier':
        carrier = double.tryParse(next()) ?? carrier;
      case '--factor':
        factor = double.tryParse(next()) ?? factor;
      case '--kind':
        final k = next();
        kind = DistortionKind.values.firstWhere(
          (d) => d.name == k,
          orElse: () => kind,
        );
      default:
        if (a.startsWith('-')) {
          stderr.writeln('fxproc: unknown option $a');
          exitCode = 2;
          return;
        }
        positional.add(a);
    }
  }

  if (positional.length < 2 || effect.isEmpty) {
    stderr.writeln('usage: dart run bin/fxproc.dart <in.wav> <out.wav> '
        '--effect <name> [--mix M] [--drive D] [--carrier Hz] [--factor F] '
        '[--kind hardClip|softClip|fuzz|waveFold]');
    exitCode = 2;
    return;
  }

  final inFile = File(positional[0]);
  if (!inFile.existsSync()) {
    stderr.writeln('fxproc: no such file: ${positional[0]}');
    exitCode = 2;
    return;
  }

  final WavData wav;
  try {
    wav = readWavPcm16(inFile.readAsBytesSync());
  } catch (e) {
    stderr.writeln('fxproc: not a readable PCM16 WAV: $e');
    exitCode = 1;
    return;
  }
  final sr = wav.sampleRate < 1 ? 44100 : wav.sampleRate;

  // Downmix to mono, normalized.
  final ch = wav.channels < 1 ? 1 : wav.channels;
  final frames = wav.samples.length ~/ ch;
  final mono = Float64List(frames);
  for (var f = 0; f < frames; f++) {
    var sum = 0.0;
    for (var c = 0; c < ch; c++) {
      sum += wav.samples[f * ch + c];
    }
    mono[f] = sum / ch / 32768.0;
  }

  final Float64List? out =
      _apply(effect, mono, sr, mix, drive, carrier, factor, kind);
  if (out == null) {
    stderr.writeln('fxproc: unknown effect "$effect". One of: reverb, delay, '
        'chorus, flanger, distortion, ringmod, stretch, or a voice preset '
        '(${VoiceEffect.values.map((v) => v.name).join('/')}).');
    exitCode = 2;
    return;
  }

  final pcm = Int16List(out.length);
  for (var i = 0; i < out.length; i++) {
    pcm[i] = (out[i] * 32767).round().clamp(-32768, 32767);
  }
  File(positional[1]).writeAsBytesSync(wavBytes(pcm, sampleRate: sr));
  stdout.writeln('fxproc: $effect  ${positional[0]} -> ${positional[1]}  '
      '($frames -> ${out.length} frames @ ${sr}Hz)');
}

Float64List? _apply(
  String effect,
  Float64List mono,
  int sr,
  double mix,
  double drive,
  double carrier,
  double factor,
  DistortionKind kind,
) {
  // A voice preset?
  for (final v in VoiceEffect.values) {
    if (v.name == effect) return applyVoiceEffect(mono, v, sampleRate: sr);
  }
  switch (effect) {
    case 'reverb':
      return reverbFx(mono, mix: mix, sampleRate: sr);
    case 'delay':
      return delayFx(mono, mix: mix, sampleRate: sr);
    case 'chorus':
      return chorusFx(mono, mix: mix, sampleRate: sr);
    case 'flanger':
      return flangerFx(mono, mix: mix, sampleRate: sr);
    case 'distortion':
      return distortionFx(mono, kind: kind, drive: drive, mix: mix);
    case 'ringmod':
      return ringModFx(mono, carrierHz: carrier, mix: mix, sampleRate: sr);
    case 'stretch':
      return timeStretch(mono, factor, sampleRate: sr);
    default:
      return null;
  }
}
