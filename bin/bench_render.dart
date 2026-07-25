// Benchmark the module render pipeline (import + replay → WAV). Flutter-free
// dev tool — the "how slow / how heavy" companion to bin/render_module.dart.
//
//   dart run bin/bench_render.dart <module> [<module> ...]
//   dart run bin/bench_render.dart --json <module> ...
//
// For a CLEAN per-file peak-memory reading, invoke it once per file (a fresh
// process resets ProcessInfo.maxRss):
//
//   for f in test/fixtures/*.{mod,xm,s3m,it}; do
//     dart run bin/bench_render.dart "$f"; done
//
// Reports, per module: import time, render time, WAV bytes, channels/patterns,
// output seconds (@ kSampleRate mono/stereo), and process peak RSS (maxRss).
// Used to track the streaming-renderer memory/throughput work in mod_pending.md.
import 'dart:convert';
import 'dart:io';

import 'package:comet_beat/core/audio/tracker_song_module.dart';

const int _kSampleRate = 44100;

class _Row {
  _Row(this.file);
  final String file;
  String format = '?';
  int channels = 0;
  int patterns = 0;
  int order = 0;
  bool usesCommands = false;
  bool usesPan = false;
  int importUs = 0;
  int renderUs = 0;
  int wavBytes = 0;
  int maxRssBytes = 0;
  String? error;

  double get outSeconds {
    if (wavBytes <= 44) return 0;
    final bytesPerFrame = usesPan ? 4 : 2; // stereo interleaved vs mono PCM16
    return (wavBytes - 44) / bytesPerFrame / _kSampleRate;
  }

  Map<String, Object?> toJson() => {
        'file': file,
        'format': format,
        'channels': channels,
        'patterns': patterns,
        'order': order,
        'usesCommands': usesCommands,
        'usesPan': usesPan,
        'importMs': importUs / 1000.0,
        'renderMs': renderUs / 1000.0,
        'wavBytes': wavBytes,
        'outSeconds': outSeconds,
        'maxRssMB': maxRssBytes / (1024 * 1024),
        if (error != null) 'error': error,
      };
}

_Row _benchOne(String path) {
  final row = _Row(path);
  final dot = path.lastIndexOf('.');
  row.format = dot >= 0 ? path.substring(dot + 1).toLowerCase() : '?';
  final bytes = File(path).readAsBytesSync();
  try {
    final sw = Stopwatch()..start();
    final song = songFromModuleBytes(bytes);
    row.importUs = sw.elapsedMicroseconds;
    row.channels = song.channelCount;
    row.patterns = song.patterns.length;
    row.order = song.order.length;
    row.usesCommands = song.usesCommands;
    row.usesPan = song.usesPan;

    sw
      ..reset()
      ..start();
    final wav = song.renderSongWav();
    row.renderUs = sw.elapsedMicroseconds;
    row.wavBytes = wav.length;
  } catch (e) {
    row.error = e.toString();
  }
  row.maxRssBytes = ProcessInfo.maxRss;
  return row;
}

void main(List<String> args) {
  final json = args.contains('--json');
  final files = args.where((a) => !a.startsWith('--')).toList();
  if (files.isEmpty) {
    stderr
        .writeln('usage: dart run bin/bench_render.dart [--json] <module> ...');
    exit(2);
  }

  final rows = <_Row>[];
  for (final f in files) {
    if (!File(f).existsSync()) {
      stderr.writeln('skip (missing): $f');
      continue;
    }
    rows.add(_benchOne(f));
  }

  if (json) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ')
          .convert(rows.map((r) => r.toJson()).toList()),
    );
    return;
  }

  // Human table.
  stdout.writeln(
      'file                          fmt  ch  pat  ord  cmd pan   import   render'
      '     out(s)   maxRSS');
  for (final r in rows) {
    final name = r.file.split('/').last;
    if (r.error != null) {
      stdout.writeln('${name.padRight(28)}  ERROR: ${r.error}');
      continue;
    }
    stdout.writeln(
      '${name.padRight(28)}  '
      '${r.format.padRight(3)} '
      '${r.channels.toString().padLeft(3)} '
      '${r.patterns.toString().padLeft(4)} '
      '${r.order.toString().padLeft(4)} '
      '${(r.usesCommands ? 'y' : '.').padLeft(3)} '
      '${(r.usesPan ? 'y' : '.').padLeft(3)} '
      '${_ms(r.importUs).padLeft(8)} '
      '${_ms(r.renderUs).padLeft(8)} '
      '${r.outSeconds.toStringAsFixed(1).padLeft(9)} '
      '${(r.maxRssBytes / (1024 * 1024)).toStringAsFixed(0).padLeft(6)}M',
    );
  }
}

String _ms(int us) => '${(us / 1000.0).toStringAsFixed(1)}ms';
