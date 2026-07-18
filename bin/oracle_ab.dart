// Oracle A/B — verify our module render against libopenmpt (openmpt123), the
// reference MOD/S3M/XM/IT player. Renders BOTH sides, runs the same pure-Dart
// pitch detector over each, and reports how closely the detected-note
// trajectories agree. This is how we test that our audio output is *correct*
// against another implementation (see docs/ORACLE.md).
//
//   dart run bin/oracle_ab.dart <module> [--openmpt <path>] [--seconds N]
//
// Requires openmpt123 on PATH (brew install libopenmpt) — a DEV tool, not a
// committed test dependency. Our replayer is a musical APPROXIMATION, not a
// bit-exact port, so the yardstick is trajectory/pitch-content agreement, not a
// sample-for-sample match: a rising effect rises in both, a melody's note set
// overlaps, silence lines up. Per-effect isolation modules (one effect each)
// match tightly; full polyphonic modules agree on pitch-class content.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/s3m_module.dart';
import 'package:comet_beat/core/audio/mod/s3m_writer.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/streaming_analyzer.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:comet_beat/core/audio/wav_io.dart';

Future<void> main(List<String> args) async {
  final openmpt = _value(args, '--openmpt') ?? 'openmpt123';
  final maxSeconds = double.tryParse(_value(args, '--seconds') ?? '') ?? 30.0;

  // --selftest: synthesize a known tonal module (a rising C-major scale on a
  // looping sine) and A/B it — a committed, self-contained proof that ours and
  // the reference agree on the note trajectory.
  if (args.contains('--selftest')) {
    final dir = Directory.systemTemp.createTempSync('oracle_selftest');
    final path = '${dir.path}/scale.s3m';
    File(path).writeAsBytesSync(_scaleS3m());
    await _ab(path, openmpt, maxSeconds);
    return;
  }

  if (args.isEmpty || args.first.startsWith('-')) {
    stderr.writeln('usage: dart run bin/oracle_ab.dart <module> '
        '[--openmpt <path>] [--seconds N]\n'
        '       dart run bin/oracle_ab.dart --selftest');
    exit(2);
  }
  await _ab(args.first, openmpt, maxSeconds);
}

Future<void> _ab(String modulePath, String openmpt, double maxSeconds) async {
  final bytes = File(modulePath).readAsBytesSync();

  // ── Our side: import → replay → WAV ─────────────────────────────────────────
  final song = songFromModuleBytes(bytes);
  final ourWav = song.renderSongWav();
  final ours = _trajectory(ourWav, maxSeconds);

  // ── Reference side: openmpt123 --render ─────────────────────────────────────
  // --render writes "<input>.wav" beside the input (no per-file output flag), so
  // copy the module into a temp dir and render there (keeps fixtures clean).
  final tmp = Directory.systemTemp.createTempSync('oracle_ab');
  final tmpModule = '${tmp.path}/${modulePath.split('/').last}';
  File(tmpModule).writeAsBytesSync(bytes);
  final res = await Process.run(openmpt, [
    '--render',
    '--samplerate',
    '44100',
    '--channels',
    '1',
    '--no-float',
    '--output-type',
    'wav',
    '--force',
    '--quiet',
    tmpModule,
  ]);
  if (res.exitCode != 0) {
    stderr.writeln('openmpt123 failed (is it installed? brew install '
        'libopenmpt):\n${res.stderr}');
    exit(1);
  }
  final refWav = File('$tmpModule.wav').readAsBytesSync();
  final ref = _trajectory(refWav, maxSeconds);

  // ── Report ──────────────────────────────────────────────────────────────────
  stdout.writeln('module: $modulePath');
  stdout.writeln('  ours : ${ours.notes.length} voiced frames, '
      'notes ${_compress(ours.notes)}');
  stdout.writeln('  ref  : ${ref.notes.length} voiced frames, '
      'notes ${_compress(ref.notes)}');
  stdout.writeln('  pitch-class overlap (Jaccard): '
      '${_jaccard(ours.pcSet, ref.pcSet).toStringAsFixed(2)}');
  stdout
      .writeln('  voiced-fraction  ours=${ours.voicedFrac.toStringAsFixed(2)} '
          'ref=${ref.voicedFrac.toStringAsFixed(2)}');
  stdout.writeln('  rising?          ours=${ours.rising} ref=${ref.rising}');

  // Verdict: our render agrees with the reference on pitch content + silence
  // structure. (Not a bit-exact test — see the header.)
  final jac = _jaccard(ours.pcSet, ref.pcSet);
  final bothVoiced = ours.voicedFrac > 0.4 && ref.voicedFrac > 0.4;
  final voicedClose = (ours.voicedFrac - ref.voicedFrac).abs() < 0.25;
  final agree =
      jac >= 0.5 && bothVoiced && voicedClose && ours.rising == ref.rising;
  stdout.writeln('  ==> ${agree ? 'PASS' : 'CHECK'} '
      '(pc-overlap ${jac.toStringAsFixed(2)}, voiced-close $voicedClose, '
      'rising-match ${ours.rising == ref.rising})');
}

class _Traj {
  _Traj(this.notes, this.pcSet, this.voicedFrac, this.rising);
  final List<int> notes; // nearestMidi per voiced frame, in order
  final Set<int> pcSet; // pitch classes (midi % 12) seen
  final double voicedFrac; // fraction of frames that were voiced
  final bool rising; // more zero-content later than earlier (glide check)
}

_Traj _trajectory(Uint8List wavBytes, double maxSeconds) {
  final wav = readWavPcm16(wavBytes);
  var mono = wavToMonoFloat(wav);
  final cap = (maxSeconds * wav.sampleRate).round();
  if (mono.length > cap) mono = mono.sublist(0, cap);
  final analyzer = StreamingAudioAnalyzer(
    detector: PitchDetector(sampleRate: wav.sampleRate),
  );
  final notes = <int>[];
  final pc = <int>{};
  var total = 0;
  var voiced = 0;
  const chunk = 1024;
  for (var i = 0; i < mono.length; i += chunk) {
    final end = (i + chunk < mono.length) ? i + chunk : mono.length;
    for (final f in analyzer.addSamples(mono.sublist(i, end))) {
      total++;
      if (f.pitch.hasPitch) {
        voiced++;
        notes.add(f.pitch.nearestMidi);
        pc.add(f.pitch.nearestMidi % 12);
      }
    }
  }
  // "Rising": the mean note of the second half exceeds the first (a glide check).
  var rising = false;
  if (notes.length >= 4) {
    final h = notes.length ~/ 2;
    final a = notes.sublist(0, h).fold(0, (s, v) => s + v) / h;
    final b = notes.sublist(h).fold(0, (s, v) => s + v) / (notes.length - h);
    rising = b > a + 0.5;
  }
  return _Traj(notes, pc, total == 0 ? 0 : voiced / total, rising);
}

/// Collapse consecutive equal notes into a compact run list (first 24 shown).
String _compress(List<int> notes) {
  final out = <String>[];
  int? last;
  for (final n in notes) {
    if (n != last) {
      out.add(_name(n));
      last = n;
    }
    if (out.length >= 24) {
      out.add('…');
      break;
    }
  }
  return '[${out.join(' ')}]';
}

double _jaccard(Set<int> a, Set<int> b) {
  if (a.isEmpty && b.isEmpty) return 1;
  final inter = a.intersection(b).length;
  final union = a.union(b).length;
  return union == 0 ? 0 : inter / union;
}

const _names = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];
String _name(int midi) => '${_names[midi % 12]}${(midi ~/ 12) - 1}';

String? _value(List<String> args, String key) {
  final i = args.indexOf(key);
  return (i >= 0 && i + 1 < args.length) ? args[i + 1] : null;
}

/// A 1-channel S3M playing a rising C-major scale (C-4 … C-5) on a looping sine
/// sample — a deterministic tonal fixture for [--selftest]. S3M note byte =
/// (octave << 4) | semitone; instrument 2 is the sine (slot 1 is the empty
/// reserved sample).
Uint8List _scaleS3m() {
  const n = 2000;
  final sine = Int8List(n);
  for (var i = 0; i < n; i++) {
    sine[i] = (100 * sin(2 * pi * 8 * i / n)).round();
  }
  const semis = [0, 2, 4, 5, 7, 9, 11, 12]; // C D E F G A B C (major scale)
  final rows = <List<S3mCell>>[
    for (final s in semis)
      [
        S3mCell(
          note: ((4 + s ~/ 12) << 4) | (s % 12),
          instrument: 2,
          volume: 64,
        ),
      ],
  ];
  final m = S3mModule(
    title: 'scale',
    channelCount: 1,
    order: [0],
    samples: [
      S3mSample.empty(),
      S3mSample(pcm: sine, loopEnd: n, loop: true),
    ],
    patterns: [S3mPattern(rows)],
  );
  return writeS3m(m);
}
