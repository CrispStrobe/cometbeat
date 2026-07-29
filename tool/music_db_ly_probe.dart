// Probe a LilyPond file through crisp_notation and report what the reader
// actually found — used to bisect why some CPDL .ly files yield zero notes.
//
// Usage: dart run tool/music_db_ly_probe.dart <file.ly> [file2.ly ...]
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:crisp_notation_core/crisp_notation_core.dart';

void main(List<String> a) {
  for (final path in a) {
    final f = File(path);
    if (!f.existsSync()) {
      stdout.writeln('MISSING $path');
      continue;
    }
    try {
      final mp = multiPartFromLilyPond(f.readAsStringSync());
      var notes = 0, rests = 0, measures = 0;
      for (final p in mp.parts) {
        measures += p.measures.length;
        for (final m in p.measures) {
          for (final e in m.elements) {
            if (e is NoteElement) {
              notes++;
            } else if (e is RestElement) {
              rests++;
            }
          }
        }
      }
      stdout.writeln('parts=${mp.parts.length} measures=$measures '
          'notes=$notes rests=$rests  ${path.split('/').last}');
    } catch (e) {
      var msg = e.toString().replaceAll('\n', ' ');
      if (msg.length > 140) msg = msg.substring(0, 140);
      stdout.writeln('THREW $msg  ${path.split('/').last}');
    }
  }
}
