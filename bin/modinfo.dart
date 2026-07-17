// bin/modinfo.dart
//
// Headless module inspector — sniffs and dumps any tracker module
// (.mod/.s3m/.xm/.it) using the SAME pure-Dart codecs the app uses. The Dart
// counterpart of the Python fixture inspectors; doubles as a fixture verifier.
//
//   dart run bin/modinfo.dart path/to/song.it
//   dart run bin/modinfo.dart song.xm --patterns   # also list per-pattern rows
//
// Prints format, title, channels, speed/tempo, order, patterns and per-sample
// metadata. Flutter-free (like bin/listen.dart) — runs under plain `dart run`.

import 'dart:io';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';

const _fmtName = {
  ModuleFormat.mod: 'ProTracker MOD',
  ModuleFormat.s3m: 'Scream Tracker 3 S3M',
  ModuleFormat.xm: 'FastTracker 2 XM',
  ModuleFormat.it: 'Impulse Tracker IT',
};

void main(List<String> args) {
  final paths = args.where((a) => !a.startsWith('-')).toList();
  final showPatterns = args.contains('--patterns');
  if (paths.isEmpty) {
    stderr.writeln('usage: dart run bin/modinfo.dart <module> [--patterns]');
    exitCode = 2;
    return;
  }

  final path = paths.first;
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('modinfo: no such file: $path');
    exitCode = 2;
    return;
  }

  final bytes = file.readAsBytesSync();
  final fmt = sniffModuleFormat(bytes);
  if (fmt == null) {
    stderr.writeln('modinfo: $path is not a recognized module '
        '(.mod/.s3m/.xm/.it)');
    exitCode = 1;
    return;
  }

  final ModuleDoc m;
  try {
    m = parseAnyModule(bytes);
  } catch (e) {
    stderr.writeln('modinfo: failed to parse $path: $e');
    exitCode = 1;
    return;
  }

  final used = m.usedSamples.length;
  stdout.writeln('$path  (${_fmtName[fmt]})');
  stdout.writeln('  title        : ${m.title}');
  stdout.writeln('  channels     : ${m.channelCount}');
  stdout.writeln('  speed/tempo  : ${m.initialSpeed} / ${m.initialTempo}');
  stdout.writeln('  order        : ${m.order.length} entries');
  stdout.writeln('  patterns     : ${m.patterns.length}');
  stdout.writeln('  samples      : ${m.samples.length} ($used used)');

  if (m.samples.isNotEmpty) {
    stdout
        .writeln('  #   name                    length   loop          c5spd');
    for (var i = 0; i < m.samples.length; i++) {
      final s = m.samples[i];
      if (s.isEmpty) continue;
      final loop = s.loopLength > 0
          ? '${s.loopStart}..${s.loopStart + s.loopLength}'
          : '-';
      stdout.writeln('  ${_pad('${i + 1}', 3)} '
          '${_pad(s.name, 22)} '
          '${_padL('${s.pcm.length}', 8)} '
          '${_pad(loop, 13)} '
          '${_padL('${s.c5speed}', 6)}');
    }
  }

  if (showPatterns) {
    stdout.writeln('  pattern rows :');
    for (var i = 0; i < m.patterns.length; i++) {
      final p = m.patterns[i];
      stdout.writeln('    #${_pad('$i', 3)} '
          '${_padL('${p.numRows}', 4)} rows × ${p.channelCount} ch');
    }
  }
}

String _pad(String s, int w) =>
    s.length >= w ? s.substring(0, w) : s + ' ' * (w - s.length);
String _padL(String s, int w) => s.length >= w ? s : ' ' * (w - s.length) + s;
