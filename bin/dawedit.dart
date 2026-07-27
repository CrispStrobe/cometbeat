// bin/dawedit.dart
//
// Headless Multitrack (DAW) clip EDITOR — run the app's destructive clip
// operations on a real WAV, offline. The sibling of bin/fxproc.dart: that one
// applies effects, this one edits the audio itself (normalize, amplify, invert,
// remove DC, trim silence, crop/silence a range) and generates test signals.
// Flutter-free, like bin/listen.dart.
//
// The maths is NOT reimplemented here — every op calls the same
// `lib/core/audio/daw_edits.dart` functions the app's DawService calls, so a
// result you hear from this CLI is the result the app produces.
//
//   dart run bin/dawedit.dart in.wav --stats
//   dart run bin/dawedit.dart in.wav out.wav --normalize
//   dart run bin/dawedit.dart in.wav out.wav --amplify -6 --remove-dc
//   dart run bin/dawedit.dart in.wav out.wav --trim-silence 0.02 --stats
//   dart run bin/dawedit.dart in.wav out.wav --crop 500:2500
//   dart run bin/dawedit.dart in.wav out.wav --silence 1000:1500
//   dart run bin/dawedit.dart --generate sine:440:2 tone.wav --play
//
// Ops apply in the order given, so they chain. Mono in → mono out; stereo in →
// stereo out (every op is channel-aware). The file's own sample rate is kept.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_edits.dart';
import 'package:comet_beat/core/audio/daw_timeline.dart'
    show Clip, SampleSource;
import 'package:comet_beat/core/audio/spectrogram_png.dart';
import 'package:comet_beat/core/audio/synth.dart' show wavBytes, wavBytesStereo;
import 'package:comet_beat/core/audio/wav_io.dart';

/// The app's split policy (DawService._minSplitMs) — a cut closer than this to
/// a clip edge isn't a split, so the sliver is decided by its midpoint.
const double _minSplitMs = 5;

const _usage = '''
dawedit — headless DAW clip editor (the app's own edit code, on a WAV)

  dart run bin/dawedit.dart <in.wav> [out.wav] [ops...]
  dart run bin/dawedit.dart --generate <shape>[:<freq>[:<sec>]] <out.wav> [ops...]

Ops (applied in the order given):
  --stats                print peak/RMS/duration/clipping at this point
  --normalize [PEAK]     scale so the loudest sample hits PEAK (default 0.98)
  --amplify DB           scale by decibels (e.g. -6, +3)
  --invert               flip phase (x -1)
  --remove-dc            centre the waveform on zero
  --trim-silence [THR]   cut quiet edges (threshold as a fraction, default 0.01)
  --crop A:B             keep only milliseconds A..B
  --silence A:B          cut milliseconds A..B out (surroundings keep their time)
  --pad LEAD[:TAIL]      insert silence before (and after) the audio, in ms
  --repeat N             repeat the whole take N times
  --splice FILE[:MS]     append FILE with an equal-power crossfade (default 20 ms)
  --find-silence [THR]   list the silent gaps (threshold fraction, default 0.01)
  --split-silence [THR]  list the PHRASES between them, as A:B ranges
  --full-stats           peak/RMS plus DC, crest factor, bit depth, crossings
  --spectrogram OUT.png  paint the spectrum over time (see --max-hz, --grey)
  --max-hz HZ            crop the spectrogram's top (music lives low; try 5000)
  --grey                 greyscale spectrogram instead of the heat ramp

Generator: shape = sine | square | saw | triangle | whiteNoise | pinkNoise | silence
  --amp N                generator peak, 0..1 (default 0.5)
  --seed N               noise seed (default 0)

  --play                 play the result when done (afplay/ffplay/aplay)
''';

/// A working buffer: one or two channels at [sampleRate].
class _Audio {
  _Audio(this.left, this.right, this.sampleRate);
  Float64List left;
  Float64List? right;
  final int sampleRate;

  bool get isStereo => right != null;
}

void main(List<String> args) {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    stdout.write(_usage);
    return;
  }

  final positional = <String>[];
  final ops = <(String, String?)>[]; // (op, argument)
  String? generate;
  var amp = 0.5;
  var seed = 0;
  var play = false;
  double? maxHz;
  var grey = false;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    // The value ops take an argument; the optional-argument ones only consume
    // the next token when it isn't another flag or the output path.
    String? maybeValue() {
      if (i + 1 >= args.length) return null;
      final next = args[i + 1];
      if (next.startsWith('-') || next.toLowerCase().endsWith('.wav')) {
        return null;
      }
      return args[++i];
    }

    String requireValue(String flag) {
      if (i + 1 >= args.length) _fail('$flag needs a value');
      return args[++i];
    }

    switch (a) {
      case '--generate':
        generate = requireValue(a);
      case '--amp':
        amp = double.tryParse(requireValue(a)) ?? amp;
      case '--seed':
        seed = int.tryParse(requireValue(a)) ?? seed;
      case '--play':
        play = true;
      case '--stats':
      case '--invert':
      case '--remove-dc':
        ops.add((a, null));
      case '--normalize':
      case '--trim-silence':
      case '--find-silence':
      case '--split-silence':
        ops.add((a, maybeValue()));
      case '--full-stats':
        ops.add((a, null));
      case '--spectrogram':
        ops.add((a, requireValue(a)));
      case '--max-hz':
        maxHz = double.tryParse(requireValue(a));
      case '--grey':
      case '--gray':
        grey = true;
      case '--amplify':
      case '--crop':
      case '--silence':
      case '--pad':
      case '--repeat':
      case '--splice':
        ops.add((a, requireValue(a)));
      default:
        if (a.startsWith('-')) _fail('Unknown option: $a');
        positional.add(a);
    }
  }

  final _Audio audio;
  String? outPath;

  if (generate != null) {
    if (positional.isEmpty) _fail('--generate needs an output .wav path');
    outPath = positional.first;
    audio = _generate(generate, amp: amp, seed: seed);
    stdout.writeln(
      'Generated $generate '
      '(${audio.left.length} samples @ ${audio.sampleRate} Hz)',
    );
  } else {
    if (positional.isEmpty) _fail('Need an input .wav');
    audio = _read(positional.first);
    outPath = positional.length > 1 ? positional[1] : null;
    stdout.writeln(
      'Read ${positional.first} — ${audio.isStereo ? 'stereo' : 'mono'}, '
      '${audio.sampleRate} Hz, '
      '${(audio.left.length * 1000 / audio.sampleRate).toStringAsFixed(1)} ms',
    );
  }

  for (final (op, value) in ops) {
    _apply(audio, op, value, maxHz: maxHz, grey: grey);
  }

  if (outPath == null) {
    if (ops.any((o) => o.$1 != '--stats')) {
      stderr.writeln('(no output path given — edits were not written)');
    }
    return;
  }

  File(outPath).writeAsBytesSync(_wav(audio));
  stdout.writeln(
    'Wrote $outPath — ${audio.isStereo ? 'stereo' : 'mono'}, '
    '${(audio.left.length * 1000 / audio.sampleRate).toStringAsFixed(1)} ms',
  );
  if (play) _play(outPath);
}

void _apply(
  _Audio a,
  String op,
  String? value, {
  double? maxHz,
  bool grey = false,
}) {
  switch (op) {
    case '--stats':
      _printStats(a);
    case '--normalize':
      final peak = value == null ? 0.98 : double.parse(value);
      _take(a, normalizeTake(a.left, a.right, targetPeak: peak));
      stdout.writeln('normalize → peak $peak');
    case '--amplify':
      final db = double.parse(value!);
      _take(a, amplifyTake(a.left, a.right, db));
      stdout.writeln('amplify → ${db > 0 ? '+' : ''}$db dB');
    case '--invert':
      _take(a, invertTake(a.left, a.right));
      stdout.writeln('invert phase');
    case '--remove-dc':
      _take(a, removeDcTake(a.left, a.right));
      stdout.writeln('remove DC offset');
    case '--trim-silence':
      final threshold = value == null ? 0.01 : double.parse(value);
      final take = trimSilenceTake(
        a.left,
        a.right,
        threshold: threshold,
        sampleRate: a.sampleRate,
      );
      if (take.left.isEmpty) {
        stdout.writeln('trim silence → nothing audible above $threshold, kept');
        return;
      }
      _take(a, take);
      final leftMs = a.left.length * 1000 / a.sampleRate;
      stdout.writeln(
        'trim silence → cut ${take.startShiftMs.toStringAsFixed(1)} ms off the '
        'front, ${leftMs.toStringAsFixed(1)} ms left',
      );
    case '--crop':
    case '--silence':
      final (start, end) = _range(value!);
      _rangeEdit(a, start, end, removeInside: op == '--silence');
      stdout.writeln(
        '${op == '--silence' ? 'silence' : 'crop'} → $start..$end ms',
      );
    case '--pad':
      final parts = value!.split(':');
      final lead = double.tryParse(parts.first) ?? 0;
      final tail = parts.length > 1 ? double.tryParse(parts[1]) ?? 0 : 0.0;
      _take(
        a,
        padTake(
          a.left,
          a.right,
          leadMs: lead,
          tailMs: tail,
          sampleRate: a.sampleRate,
        ),
      );
      stdout.writeln('pad → $lead ms before, $tail ms after');
    case '--repeat':
      final times = int.tryParse(value!);
      if (times == null || times < 0) {
        _fail('--repeat needs a count, got "$value"');
      }
      _take(a, repeatTake(a.left, a.right, times));
      stdout.writeln('repeat → ×$times, ${_msOf(a)} ms');
    case '--splice':
      final parts = value!.split(':');
      final other = _read(parts.first);
      final fade = parts.length > 1 ? double.tryParse(parts[1]) ?? 20 : 20.0;
      if (other.sampleRate != a.sampleRate) {
        _fail(
          'splice needs matching sample rates: ${a.sampleRate} vs '
          '${other.sampleRate} Hz',
        );
      }
      _take(
        a,
        spliceTakes(
          a.left,
          a.right,
          other.left,
          other.right,
          crossfadeMs: fade,
          sampleRate: a.sampleRate,
        ),
      );
      stdout.writeln(
        'splice → +${parts.first} with a $fade ms crossfade, ${_msOf(a)} ms',
      );
    case '--find-silence':
    case '--split-silence':
      final threshold = value == null ? 0.01 : double.parse(value);
      final phrases = op == '--split-silence';
      final ranges = phrases
          ? findPhrases(
              a.left,
              a.right,
              threshold: threshold,
              sampleRate: a.sampleRate,
            )
          : findSilences(
              a.left,
              a.right,
              threshold: threshold,
              sampleRate: a.sampleRate,
            );
      stdout.writeln(
        '${phrases ? 'phrases' : 'silences'} (threshold $threshold): '
        '${ranges.length}',
      );
      for (final r in ranges) {
        stdout.writeln(
          '  ${r.startMs.toStringAsFixed(1)}:${r.endMs.toStringAsFixed(1)}',
        );
      }
    case '--full-stats':
      _printFullStats(a);
    case '--spectrogram':
      // Painted from the MONO fold: a spectrogram of one channel would answer
      // a question nobody asked, and two stacked pictures need a layout
      // decision that belongs in the app, not here.
      final mono = a.right == null
          ? a.left
          : Float64List.fromList([
              for (var i = 0; i < a.left.length; i++)
                (a.left[i] + (i < a.right!.length ? a.right![i] : 0)) / 2,
            ]);
      final png = pcmToSpectrogramPng(
        mono,
        sampleRate: a.sampleRate,
        maxHz: maxHz,
        height: 480,
        palette: grey ? SpectrogramPalette.grey : SpectrogramPalette.heat,
      );
      File(value!).writeAsBytesSync(png);
      stdout.writeln(
        'spectrogram → $value'
        '${maxHz == null ? '' : ' (up to ${maxHz.round()} Hz)'}',
      );
  }
}

String _msOf(_Audio a) =>
    (a.left.length * 1000 / a.sampleRate).toStringAsFixed(1);

void _printFullStats(_Audio a) {
  final s = fullStatsOf(a.left, a.right, sampleRate: a.sampleRate);
  _printStats(a);
  stdout.writeln(
    '  health: DC ${s.dcOffset.toStringAsFixed(5)} · '
    'crest ${s.crestFactorDb.toStringAsFixed(1)} dB · '
    '${s.effectiveBits}-bit effective · '
    '${s.zeroCrossings} zero crossings',
  );
}

/// Adopt a baked take. The CLI has no timeline to slide, so a front-trim's
/// `startShiftMs` is reported by the caller rather than applied.
void _take(_Audio a, BakedTake take) {
  if (take.left.isEmpty) return;
  a.left = take.left;
  a.right = take.right;
}

/// Crop/silence through the app's real clip surgery: wrap the audio in a
/// one-clip lane, let [editClipsAroundRange] split and drop segments, then lay
/// the survivors back down at their own start times (a hole stays a hole).
void _rangeEdit(
  _Audio a,
  double startMs,
  double endMs, {
  required bool removeInside,
}) {
  final rate = a.sampleRate;
  // Snapshot the source length: `a.left` is replaced at the end, and the right
  // channel is laid out afterwards — both passes must measure the ORIGINAL.
  final sourceSamples = a.left.length;
  final totalMs = sourceSamples * 1000 / rate;

  double durationOf(Clip c) {
    final to = c.trimEndMs == 0 ? totalMs : c.trimEndMs;
    return (to - c.trimStartMs).clamp(0, totalMs).toDouble();
  }

  int sampleAt(double ms) =>
      (ms * rate / 1000).round().clamp(0, sourceSamples).toInt();

  final clips = [Clip(source: SampleSource(a.left))];
  editClipsAroundRange(
    clips,
    startMs,
    endMs,
    removeInside: removeInside,
    durationOf: durationOf,
    minSplitMs: _minSplitMs,
  );

  if (clips.isEmpty) {
    a.left = Float64List(0);
    a.right = a.right == null ? null : Float64List(0);
    return;
  }

  // Lay the surviving windows onto a fresh buffer. A CROP moves what survives
  // to the top of the file (that's the point of cropping); a SILENCE keeps the
  // original timeline origin, so blanking the head leaves real silence there
  // instead of sliding the rest of the file left.
  final originMs = removeInside ? 0.0 : clips.first.startMs;
  var lengthSamples = 0;
  for (final c in clips) {
    final end = sampleAt(c.startMs - originMs) + sampleAt(durationOf(c));
    if (end > lengthSamples) lengthSamples = end;
  }

  Float64List lay(Float64List source) {
    final out = Float64List(lengthSamples);
    for (final c in clips) {
      final from = sampleAt(c.trimStartMs);
      final to = sampleAt(c.trimStartMs + durationOf(c));
      final at = sampleAt(c.startMs - originMs);
      for (var i = from; i < to; i++) {
        final j = at + (i - from);
        if (j >= out.length) break;
        if (i < source.length) out[j] = source[i];
      }
    }
    return out;
  }

  final right = a.right;
  a.left = lay(a.left);
  a.right = right == null ? null : lay(right);
}

void _printStats(_Audio a) {
  final s = clipStatsOf(a.left, a.right, sampleRate: a.sampleRate);
  stdout.writeln(
    '  stats: ${s.durationMs.toStringAsFixed(1)} ms · '
    '${s.channels == 2 ? 'stereo' : 'mono'} · '
    'peak ${s.peak.toStringAsFixed(4)} (${s.peakDb.toStringAsFixed(1)} dBFS) · '
    'RMS ${s.rms.toStringAsFixed(4)} (${s.rmsDb.toStringAsFixed(1)} dBFS) · '
    'clipped ${s.clippedSamples}',
  );
}

_Audio _generate(String spec, {required double amp, required int seed}) {
  final parts = spec.split(':');
  final shape = GeneratorShape.values.firstWhere(
    (s) => s.name.toLowerCase() == parts.first.toLowerCase(),
    orElse: () => _fail(
      'Unknown shape "${parts.first}". '
      'Try: ${GeneratorShape.values.map((s) => s.name).join(' | ')}',
    ),
  );
  final freq = parts.length > 1 ? double.tryParse(parts[1]) ?? 440 : 440.0;
  final seconds = parts.length > 2 ? double.tryParse(parts[2]) ?? 2 : 2.0;
  const rate = kCliSampleRate;
  return _Audio(
    generateWave(
      shape: shape,
      samples: (seconds * rate).round(),
      sampleRate: rate,
      freq: freq,
      amp: amp,
      seed: seed,
    ),
    null,
    rate,
  );
}

/// The rate generated files are written at (the app's timeline rate).
const int kCliSampleRate = 44100;

_Audio _read(String path) {
  final file = File(path);
  if (!file.existsSync()) _fail('No such file: $path');
  final wav = readWavPcm16(file.readAsBytesSync());
  final frames = wav.samples.length ~/ wav.channels;
  final left = Float64List(frames);
  final right = wav.channels >= 2 ? Float64List(frames) : null;
  for (var i = 0; i < frames; i++) {
    left[i] = wav.samples[i * wav.channels] / 32768;
    if (right != null) right[i] = wav.samples[i * wav.channels + 1] / 32768;
  }
  return _Audio(left, right, wav.sampleRate);
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

(double, double) _range(String spec) {
  final parts = spec.split(':');
  if (parts.length != 2) _fail('Range must be START:END in ms, e.g. 500:2500');
  final a = double.tryParse(parts[0]);
  final b = double.tryParse(parts[1]);
  if (a == null || b == null) _fail('Range must be numbers, got "$spec"');
  return a <= b ? (a, b) : (b, a);
}

void _play(String path) {
  for (final player in ['afplay', 'ffplay', 'aplay']) {
    final args =
        player == 'ffplay' ? ['-autoexit', '-nodisp', path] : <String>[path];
    try {
      final r = Process.runSync(player, args);
      if (r.exitCode == 0) return;
    } on ProcessException {
      continue;
    }
  }
  stderr.writeln('(no audio player found — tried afplay/ffplay/aplay)');
}

Never _fail(String message) {
  stderr.writeln('dawedit: $message');
  exit(2);
}
