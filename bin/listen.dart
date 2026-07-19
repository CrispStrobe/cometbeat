// bin/listen.dart
//
// Command-line harness for the play-along detectors — runs the SAME pure-Dart
// pitch/chord analysis the app uses, headlessly, over real audio. Three inputs:
//
//   Analyze a recording:
//     dart run bin/listen.dart --wav path/to/cello.wav --chords
//
//   Live from the mic (pipe raw PCM16 mono in on stdin):
//     sox -d -t raw -b 16 -e signed -c 1 -r 44100 - | \
//       dart run bin/listen.dart --stdin --rate 44100
//     # or with ffmpeg (macOS avfoundation, mic is usually ":0"):
//     ffmpeg -f avfoundation -i ":0" -ac 1 -ar 44100 -f s16le - 2>/dev/null | \
//       dart run bin/listen.dart --stdin
//
//   Self-test (synth a note/chord, no audio device needed):
//     dart run bin/listen.dart --selftest
//
// This is the "real live test" path the app can't easily give you: deterministic
// over files for CI, and truly live over stdin for hands-on validation.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/aec_offline.dart';
import 'package:comet_beat/core/audio/chroma_analysis.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/recording_analysis.dart';
import 'package:comet_beat/core/audio/streaming_analyzer.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/audio/wav_io.dart';

const _usage = '''
Play-along detector CLI.

Usage:
  dart run bin/listen.dart --wav <file> [options]
  dart run bin/listen.dart --stdin [options]      # raw PCM16 mono on stdin
  dart run bin/listen.dart --selftest [options]

Options:
  --wav <file>    Analyze a PCM16 WAV recording.
  --stdin         Read raw PCM16 little-endian mono from stdin (live).
  --selftest      Synthesize test tones/chords and analyze them.
  --aec           Echo-cancel two WAVs: --mic <captured.wav> --ref <played.wav>,
                  reports the delay + ERLE and (with --out) writes the cleaned
                  WAV. For streaming/pipes and --detect, use bin/aec.dart.
  --rate <hz>     Sample rate for --stdin (default 44100).
  --a4 <hz>       Tuning reference (default 440).
  --chords        Also run chord recognition.
  --all           Print silent frames too (default: only frames with a result).
  --melody        With --wav: print the smoothed melody transcription, not frames.
  -h, --help      Show this help.
''';

Future<void> main(List<String> argv) async {
  final args = _Args(argv);
  if (args.flag('help') || args.flag('h') || argv.isEmpty) {
    stdout.write(_usage);
    return;
  }

  final rate = int.tryParse(args.value('rate') ?? '') ?? 44100;
  final a4 = double.tryParse(args.value('a4') ?? '') ?? kDefaultA4;
  final withChords = args.flag('chords');
  final printAll = args.flag('all');
  final melodyOnly = args.flag('melody');

  StreamingAudioAnalyzer analyzerFor(int sr) => StreamingAudioAnalyzer(
        detector: PitchDetector(sampleRate: sr, a4: a4),
        chordDetector:
            withChords ? ChordDetector(sampleRate: sr, a4: a4) : null,
      );

  if (args.flag('selftest')) {
    _selftest(analyzerFor, withChords);
    return;
  }

  if (args.flag('aec')) {
    _runAec(args);
    return;
  }

  final wavPath = args.value('wav');
  if (wavPath != null) {
    final file = File(wavPath);
    if (!file.existsSync()) {
      stderr.writeln('No such file: $wavPath');
      exitCode = 2;
      return;
    }
    // Shared with the app: one tested file-analysis path (recording_analysis).
    final result = analyzeRecording(
      file.readAsBytesSync(),
      a4: a4,
      detectChords: withChords,
    );
    stderr.writeln(
      'Loaded @ ${result.sampleRate} Hz, ${result.channels}ch  '
      '(${result.durationSeconds.toStringAsFixed(2)}s)',
    );
    if (melodyOnly) {
      const names = [
        'C', 'C#', 'D', 'D#', 'E', 'F', //
        'F#', 'G', 'G#', 'A', 'A#', 'B',
      ];
      stdout.writeln(
        result.melody().map((m) => '${names[m % 12]}${m ~/ 12 - 1}').join(' '),
      );
      return;
    }
    for (final f in result.frames) {
      _printFrame(f, printAll);
    }
    return;
  }

  if (args.flag('stdin')) {
    stderr
        .writeln('Listening on stdin: PCM16 mono @ $rate Hz. Ctrl-C to stop.');
    final analyzer = analyzerFor(rate);
    var leftover = <int>[];
    await for (final data in stdin) {
      final bytes = <int>[...leftover, ...data];
      final usable = bytes.length - (bytes.length & 1); // whole samples only
      leftover = bytes.sublist(usable);
      if (usable == 0) continue;
      for (final f
          in analyzer.addPcm16(Uint8List.fromList(bytes.sublist(0, usable)))) {
        _printFrame(f, printAll);
      }
    }
    return;
  }

  stdout.write(_usage);
}

void _selftest(
  StreamingAudioAnalyzer Function(int) analyzerFor,
  bool withChords,
) {
  stderr.writeln('Self-test: synthesizing tones/chords…');
  final segments = <({List<double> freqs, int ms, String label})>[
    (freqs: [_midi(36)], ms: 700, label: 'C2 (cello low C)'),
    (freqs: [_midi(43)], ms: 700, label: 'G2'),
    (freqs: [_midi(57)], ms: 700, label: 'A3 = 220 Hz'),
    (freqs: [_midi(69)], ms: 700, label: 'A4 = 440 Hz'),
    if (withChords)
      (freqs: [_midi(60), _midi(64), _midi(67)], ms: 900, label: 'C major'),
    if (withChords)
      (freqs: [_midi(57), _midi(60), _midi(64)], ms: 900, label: 'A minor'),
    if (withChords)
      (
        freqs: [_midi(55), _midi(59), _midi(62), _midi(65)],
        ms: 900,
        label: 'G7'
      ),
  ];
  for (final s in segments) {
    stdout.writeln('--- expect: ${s.label} ---');
    final pcm = renderSegments([(freqs: s.freqs, ms: s.ms)]);
    final mono = Float64List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      mono[i] = pcm[i] / 32768.0;
    }
    final analyzer = analyzerFor(kSampleRate);
    for (final f in analyzer.addSamples(mono)) {
      _printFrame(f, false);
    }
  }
}

double _midi(int m) => midiToFrequency(m);

/// Echo-cancel a captured mic recording using the reference that was played.
// The AEC file path is now the shared offline core (lib/core/audio/
// aec_offline.dart), which bin/aec.dart also uses (and adds streaming/pipes).
void _runAec(_Args args) {
  final micPath = args.value('mic');
  final refPath = args.value('ref');
  if (micPath == null || refPath == null) {
    stderr.writeln('--aec needs --mic <captured.wav> and --ref <played.wav>');
    stderr.writeln('(for streaming/pipes and --detect, use bin/aec.dart)');
    exitCode = 2;
    return;
  }
  final micWav = readWavPcm16(File(micPath).readAsBytesSync());
  final refWav = readWavPcm16(File(refPath).readAsBytesSync());
  if (micWav.sampleRate != refWav.sampleRate) {
    stderr.writeln('mic and ref sample rates differ '
        '(${micWav.sampleRate} vs ${refWav.sampleRate})');
    exitCode = 2;
    return;
  }
  final sr = micWav.sampleRate;
  final result = cancelEcho(wavToMonoFloat(micWav), wavToMonoFloat(refWav));
  stderr.writeln('estimated delay: ${result.delay} samples '
      '(${(result.delay * 1000 / sr).toStringAsFixed(1)} ms)  →  '
      'ERLE ${result.erleDb.toStringAsFixed(1)} dB');

  final outPath = args.value('out');
  if (outPath != null) {
    final pcm = Int16List(result.cleaned.length);
    for (var i = 0; i < pcm.length; i++) {
      pcm[i] = (result.cleaned[i].clamp(-1.0, 1.0) * 32767).round();
    }
    File(outPath).writeAsBytesSync(wavBytes(pcm, sampleRate: sr));
    stderr.writeln('wrote cleaned WAV: $outPath');
  }
}

void _printFrame(AnalyzerFrame f, bool printAll) {
  final p = f.pitch;
  final chord = f.chord;
  final hasSomething = p.hasPitch || (chord?.hasChord ?? false);
  if (!hasSomething && !printAll) return;

  final t = 't=${f.timeSeconds.toStringAsFixed(2)}s';
  final pitchStr = p.hasPitch
      ? '${p.noteName.padRight(3)} '
          '${p.cents >= 0 ? '+' : ''}${p.cents.toStringAsFixed(0).padLeft(3)}c  '
          '${p.frequency.toStringAsFixed(1).padLeft(7)}Hz  '
          'clarity ${p.clarity.toStringAsFixed(2)}'
      : '(no pitch)'.padRight(34);

  final buf = StringBuffer('$t  $pitchStr');
  if (chord != null) {
    buf.write('  | ');
    buf.write(
      chord.hasChord ? chord.candidates.take(3).join(', ') : '(no chord)',
    );
  }
  stdout.writeln(buf.toString());
}

/// Tiny zero-dependency flag/value parser: `--flag`, `--key value`, `--key=value`.
class _Args {
  _Args(List<String> argv) {
    for (var i = 0; i < argv.length; i++) {
      var a = argv[i];
      if (!a.startsWith('-')) continue;
      a = a.replaceFirst(RegExp(r'^-+'), '');
      if (a.contains('=')) {
        final k = a.substring(0, a.indexOf('='));
        _values[k] = a.substring(a.indexOf('=') + 1);
      } else if (i + 1 < argv.length && !argv[i + 1].startsWith('-')) {
        _values[a] = argv[i + 1];
        _flags.add(a); // also usable as a presence flag
      } else {
        _flags.add(a);
      }
    }
  }
  final Set<String> _flags = {};
  final Map<String, String> _values = {};
  bool flag(String name) => _flags.contains(name) || _values.containsKey(name);
  String? value(String name) => _values[name];
}
