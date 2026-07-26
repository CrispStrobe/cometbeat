// bin/fxproc.dart
//
// Headless audio-FX processor — run the app's ENTIRE effect rack on a WAV,
// offline. Flutter-free, like bin/listen.dart; the sibling of bin/dawedit.dart,
// which edits the audio itself while this one processes it.
//
//   dart run bin/fxproc.dart in.wav out.wav --chain "highpass freq=120 | reverb mix=0.25"
//   dart run bin/fxproc.dart in.wav out.wav --chain "compressor ratio=4 | gain gainDb=-1" --stats
//   dart run bin/fxproc.dart --list                  # every effect
//   dart run bin/fxproc.dart --list compressor       # one effect, every param + range
//
// The rack is NOT re-listed here. The chain string is parsed by
// `fx/fx_chain_codec.dart` straight out of the FX registry, and the audio is
// processed by `applyFxChainStereo` — the same code path the app's clip, track,
// bus and master chains use. So every effect the app has is available the day it
// is added, with the same params and the same sound, and a chain tuned by ear in
// the app can be pasted here (and back) verbatim.
//
// Stereo in → stereo out, per channel (the previous version downmixed every
// input to mono, discarding half of a stereo recording before processing it).
//
// The pre-registry `--effect <name>` flags still work, unchanged and mono, so
// anything already scripted against them keeps its exact behaviour.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/distortion.dart';
import 'package:comet_beat/core/audio/crisp_dsp/modulated_delay.dart';
import 'package:comet_beat/core/audio/crisp_dsp/reverb.dart';
import 'package:comet_beat/core/audio/crisp_dsp/ring_mod.dart';
import 'package:comet_beat/core/audio/crisp_dsp/time_stretch.dart';
import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart';
import 'package:comet_beat/core/audio/daw_edits.dart' show clipStatsOf;
import 'package:comet_beat/core/audio/fx/fx_chain.dart' show applyFxChainStereo;
import 'package:comet_beat/core/audio/fx/fx_chain_codec.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/core/audio/synth.dart' show wavBytes, wavBytesStereo;
import 'package:comet_beat/core/audio/wav_io.dart';

const _usage = '''
fxproc — the app's whole FX rack, on a WAV

  dart run bin/fxproc.dart <in.wav> <out.wav> --chain "<chain>"
  dart run bin/fxproc.dart --list [effect]

A chain is effects separated by "|", each "name key=value key=value":

  "highpass freq=120 | compressor ratio=4 thresholdDb=-22 | reverb mix=20%"

  * unnamed params keep their defaults        * "!name" bypasses a stage
  * names ignore case and punctuation         * a choice takes its label
    (peakingEq = peaking-eq = Peaking EQ)       (distortion kind=fuzz)
  * 0..1 params take a percentage             * out-of-range values clamp
    (mix=20%)                                   and say so

Options:
  --chain "<chain>"   the effect chain (repeatable; stages concatenate)
  --list [effect]     print the rack, or one effect's params and ranges
  --stats             peak/RMS before and after
  --mono              downmix to mono before processing
  --dry-run           parse and print the chain; touch no audio
  --play              play the result (afplay/ffplay/aplay)

Legacy (mono, unchanged): --effect <name> [--mix M] [--drive D] [--carrier Hz]
  [--factor F] [--kind hardClip|softClip|fuzz|waveFold]
''';

void main(List<String> args) {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    stdout.write(_usage);
    return;
  }

  final positional = <String>[];
  final chainParts = <String>[];
  var listing = false;
  String? listOnly;
  var stats = false;
  var mono = false;
  var dryRun = false;
  var play = false;

  // Legacy flags.
  var effect = '';
  var mix = 0.4;
  var drive = 4.0;
  var carrier = 220.0;
  var factor = 1.5;
  var kind = DistortionKind.softClip;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String require(String flag) {
      if (i + 1 >= args.length) _fail('$flag needs a value');
      return args[++i];
    }

    switch (a) {
      case '--chain':
        chainParts.add(require(a));
      case '--list':
        listing = true;
        // The effect name is optional, so only consume a following token when
        // it is not another flag.
        if (i + 1 < args.length && !args[i + 1].startsWith('-')) {
          listOnly = args[++i];
        }
      case '--stats':
        stats = true;
      case '--mono':
        mono = true;
      case '--dry-run':
        dryRun = true;
      case '--play':
        play = true;
      case '--effect':
        effect = require(a);
      case '--mix':
        mix = double.tryParse(require(a)) ?? mix;
      case '--drive':
        drive = double.tryParse(require(a)) ?? drive;
      case '--carrier':
        carrier = double.tryParse(require(a)) ?? carrier;
      case '--factor':
        factor = double.tryParse(require(a)) ?? factor;
      case '--kind':
        final k = require(a);
        kind = DistortionKind.values.firstWhere(
          (d) => d.name == k,
          orElse: () => kind,
        );
      default:
        if (a.startsWith('-')) _fail('Unknown option: $a');
        positional.add(a);
    }
  }

  if (listing) {
    _list(listOnly);
    return;
  }

  if (chainParts.isEmpty && effect.isEmpty) {
    _fail('Need --chain "<chain>" (or the legacy --effect). Try --help.');
  }

  // --- the chain path ------------------------------------------------------
  if (chainParts.isNotEmpty) {
    final parsed = parseFxChain(chainParts.join(' | '));
    for (final warning in parsed.warnings) {
      stderr.writeln('fxproc: $warning');
    }
    if (!parsed.ok) {
      for (final error in parsed.errors) {
        stderr.writeln('fxproc: $error');
      }
      stderr.writeln('fxproc: nothing written. `--list` shows every effect.');
      exit(2);
    }
    if (parsed.isEmpty) _fail('The chain is empty.');

    stdout.writeln('Chain: ${formatFxChain(parsed.chain)}');
    if (dryRun) {
      for (final fx in parsed.chain) {
        stdout.write(fxCatalogText(only: fx.type));
      }
      return;
    }

    if (positional.length < 2) _fail('Need <in.wav> and <out.wav>');
    final audio = _read(positional[0], forceMono: mono);
    stdout.writeln(
      'Read ${positional[0]} — ${audio.right == null ? 'mono' : 'stereo'}, '
      '${audio.sampleRate} Hz, ${_ms(audio)} ms',
    );
    if (stats) _printStats('  in ', audio);

    // A mono file is processed as a dual-mono PAIR, so it takes the identical
    // code path as a stereo one — no second dispatch to drift out of step.
    // Length-changing effects (time-stretch) are why the result is measured
    // afterwards rather than assumed.
    final right = audio.right ?? audio.left;
    final out = applyFxChainStereo(
      audio.left,
      right,
      parsed.chain,
      audio.sampleRate,
    );

    // Whether mono-in stays mono-out is decided by the AUDIO, not by the input:
    // a chain containing `pan`, a delay `spread` or a stereo chorus genuinely
    // moves the channels apart, and folding that back to one channel would
    // discard the very effect that was asked for. So the output keeps two
    // channels exactly when the two channels differ.
    final widened = audio.right == null && !_identical(out.left, out.right);
    final result = _Audio(
      out.left,
      audio.right == null && !widened ? null : out.right,
      audio.sampleRate,
    );
    if (stats) _printStats('  out', result);

    File(positional[1]).writeAsBytesSync(_wav(result));
    stdout.writeln(
      'Wrote ${positional[1]} — '
      '${result.right == null ? 'mono' : 'stereo'}, ${_ms(result)} ms'
      '${widened ? ' (the chain moved the channels apart)' : ''}',
    );
    if (play) _play(positional[1]);
    return;
  }

  // --- the legacy path (mono, byte-identical to the pre-registry CLI) -------
  if (positional.length < 2) _fail('Need <in.wav> and <out.wav>');
  final inFile = File(positional[0]);
  if (!inFile.existsSync()) _fail('no such file: ${positional[0]}');
  final WavData wav;
  try {
    wav = readWavPcm16(inFile.readAsBytesSync());
  } catch (e) {
    stderr.writeln('fxproc: not a readable PCM16 WAV: $e');
    exit(1);
  }
  final sr = wav.sampleRate < 1 ? 44100 : wav.sampleRate;
  final input = wavToMonoFloat(wav);
  final out =
      _applyLegacy(effect, input, sr, mix, drive, carrier, factor, kind);
  if (out == null) {
    stderr.writeln(
      'fxproc: unknown effect "$effect". The legacy flag knows reverb, delay, '
      'chorus, flanger, distortion, ringmod, stretch and the voice presets '
      '(${VoiceEffect.values.map((v) => v.name).join('/')}).\n'
      'fxproc: --chain reaches the whole rack — see --list.',
    );
    exit(2);
  }
  final pcm = Int16List(out.length);
  for (var i = 0; i < out.length; i++) {
    pcm[i] = (out[i] * 32767).round().clamp(-32768, 32767);
  }
  File(positional[1]).writeAsBytesSync(wavBytes(pcm, sampleRate: sr));
  stdout.writeln(
    'fxproc: $effect  ${positional[0]} -> ${positional[1]}  '
    '(${input.length} -> ${out.length} frames @ ${sr}Hz)',
  );
  if (play) _play(positional[1]);
}

void _list(String? only) {
  if (only == null) {
    stdout.writeln('The FX rack — ${FxType.values.length} effects.');
    stdout.write(fxCatalogText());
    stdout.writeln(
      '\n`--list <effect>` shows one effect\'s params, defaults and ranges.',
    );
    return;
  }
  final type = fxTypeFromName(only);
  if (type == null) {
    stderr.writeln('fxproc: unknown effect "$only". `--list` shows them all.');
    exit(2);
  }
  stdout.write(fxCatalogText(only: type));
}

/// Whether two channels carry the same audio, sample for sample.
bool _identical(Float64List a, Float64List b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One or two channels at a sample rate.
class _Audio {
  _Audio(this.left, this.right, this.sampleRate);
  final Float64List left;
  final Float64List? right;
  final int sampleRate;
}

String _ms(_Audio a) =>
    (a.left.length * 1000 / a.sampleRate).toStringAsFixed(1);

_Audio _read(String path, {required bool forceMono}) {
  final file = File(path);
  if (!file.existsSync()) _fail('no such file: $path');
  final WavData wav;
  try {
    wav = readWavPcm16(file.readAsBytesSync());
  } catch (e) {
    stderr.writeln('fxproc: not a readable PCM16 WAV: $e');
    exit(1);
  }
  final rate = wav.sampleRate < 1 ? 44100 : wav.sampleRate;
  if (forceMono) return _Audio(wavToMonoFloat(wav), null, rate);
  final channels = wavToChannels(wav);
  return _Audio(channels.left, channels.right, rate);
}

Uint8List _wav(_Audio a) {
  int pcm16(double v) => (v.clamp(-1.0, 1.0) * 32767).round();
  final right = a.right;
  if (right == null) {
    final out = Int16List(a.left.length);
    for (var i = 0; i < a.left.length; i++) {
      out[i] = pcm16(a.left[i]);
    }
    return wavBytes(out, sampleRate: a.sampleRate);
  }
  final frames = a.left.length;
  final out = Int16List(frames * 2);
  for (var i = 0; i < frames; i++) {
    out[i * 2] = pcm16(a.left[i]);
    out[i * 2 + 1] = pcm16(i < right.length ? right[i] : 0);
  }
  return wavBytesStereo(out, sampleRate: a.sampleRate);
}

void _printStats(String label, _Audio a) {
  final s = clipStatsOf(a.left, a.right, sampleRate: a.sampleRate);
  stdout.writeln(
    '$label ${s.durationMs.toStringAsFixed(1)} ms · '
    'peak ${s.peak.toStringAsFixed(4)} (${s.peakDb.toStringAsFixed(1)} dBFS) · '
    'RMS ${s.rms.toStringAsFixed(4)} (${s.rmsDb.toStringAsFixed(1)} dBFS)'
    '${s.clippedSamples > 0 ? ' · CLIPPED ${s.clippedSamples}' : ''}',
  );
}

/// The pre-registry effect dispatch, kept exactly as it was so scripts written
/// against `--effect` keep their behaviour to the sample.
Float64List? _applyLegacy(
  String effect,
  Float64List mono,
  int sr,
  double mix,
  double drive,
  double carrier,
  double factor,
  DistortionKind kind,
) {
  for (final v in VoiceEffect.values) {
    if (v.name == effect) return applyVoiceEffect(mono, v, sampleRate: sr);
  }
  return switch (effect) {
    'reverb' => reverbFx(mono, mix: mix, sampleRate: sr),
    'delay' => delayFx(mono, mix: mix, sampleRate: sr),
    'chorus' => chorusFx(mono, mix: mix, sampleRate: sr),
    'flanger' => flangerFx(mono, mix: mix, sampleRate: sr),
    'distortion' => distortionFx(mono, kind: kind, drive: drive, mix: mix),
    'ringmod' => ringModFx(mono, carrierHz: carrier, mix: mix, sampleRate: sr),
    'stretch' => timeStretch(mono, factor, sampleRate: sr),
    _ => null,
  };
}

void _play(String path) {
  for (final player in ['afplay', 'ffplay', 'aplay']) {
    final args =
        player == 'ffplay' ? ['-autoexit', '-nodisp', path] : <String>[path];
    try {
      if (Process.runSync(player, args).exitCode == 0) return;
    } on ProcessException {
      continue;
    }
  }
  stderr.writeln('(no audio player found — tried afplay/ffplay/aplay)');
}

Never _fail(String message) {
  stderr.writeln('fxproc: $message');
  exit(2);
}
