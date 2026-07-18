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
    stderr.writeln('usage: dart run bin/render_module.dart <module> <out.wav>');
    exit(2);
  }
  final bytes = File(args[0]).readAsBytesSync();
  final song = songFromModuleBytes(bytes);
  File(args[1]).writeAsBytesSync(song.renderSongWav());
  stdout.writeln(
    'wrote ${args[1]}: ${song.channelCount} ch · ${song.patterns.length} pat · '
    'order ${song.order.length} · usesCommands=${song.usesCommands} '
    'usesPan=${song.usesPan}',
  );
}
