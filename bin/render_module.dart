// Render a module (.mod/.s3m/.xm/.it) through OUR import + replay pipeline to a
// WAV — the "mine" side of the libopenmpt oracle comparison. Compare its note
// trajectory (via `dart run bin/listen.dart --wav`) against the reference from
// `openmpt123 --render <module>`. Dev / verification tool (Flutter-free).
//
//   dart run bin/render_module.dart <module> <out.wav>
//
// See docs/ORACLE.md for the full A/B workflow used to verify the S3M/IT
// cross-format effect table against libopenmpt.
import 'dart:io';

import 'package:comet_beat/core/audio/tracker_song_module.dart';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'usage: dart run bin/render_module.dart <module> <out.wav> '
      '[--pattern N]',
    );
    exit(2);
  }
  final bytes = File(args[0]).readAsBytesSync();
  final song = songFromModuleBytes(bytes);
  final patternArg = args.indexOf('--pattern');
  final pattern = patternArg >= 0 && patternArg + 1 < args.length
      ? int.tryParse(args[patternArg + 1])
      : null;
  if (pattern != null && pattern >= 0 && pattern < song.patterns.length) {
    song.selectPattern(pattern);
  }
  final wav =
      pattern == null ? song.renderSongWav() : song.renderCurrentPatternWav();
  File(args[1]).writeAsBytesSync(wav);
  stdout.writeln(
    'wrote ${args[1]}: ${song.channelCount} ch · ${song.patterns.length} pat · '
    'order ${song.order.length} · ${pattern == null ? 'song' : 'pattern $pattern'} · '
    'usesCommands=${song.usesCommands} '
    'usesPan=${song.usesPan}',
  );
}
