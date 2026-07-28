// Parse-validate the Internet Jukebox MusicXML harvest through crisp_notation.
//
// Runs LOCALLY, never on the VPS — flutter/dart refuse to run as root there.
//
// Usage:
//   dart run tool/music_db_jukebox_parse_sweep.dart <harvest-dir> <report.json>
//
// Every music-db format gets this treatment before ingest (midi/kern/gp/mscx/
// mxl were swept the same way). Beyond "does it throw", it records part/measure/
// note counts, because these files are OMR OUTPUT: a file that parses but holds
// two notes is a recognition failure, not a reader failure, and only the counts
// tell them apart.
import 'dart:convert';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:crisp_notation_core/crisp_notation_core.dart';

void main(List<String> a) {
  if (a.length < 2) {
    stderr.writeln('usage: parse_sweep <harvest-dir> <report.json>');
    exit(64);
  }
  final dir = Directory(a[0]);
  final rows = <Map<String, dynamic>>[];
  var ok = 0, fail = 0, empty = 0;

  final files = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.musicxml'))
      .toList()
    ..sort((x, y) => x.path.compareTo(y.path));

  for (final f in files) {
    final rel = f.path.replaceFirst('${dir.path}/', '');
    try {
      final mp = multiPartScoreFromMusicXml(f.readAsStringSync());
      var notes = 0, measures = 0, rests = 0;
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
      final row = <String, dynamic>{
        'file': rel,
        'status': notes > 0 ? 'ok' : 'no_notes',
        'parts': mp.parts.length,
        'measures': measures,
        'notes': notes,
        'rests': rests,
        'bytes': f.lengthSync(),
      };
      if (notes > 0) {
        ok++;
      } else {
        empty++;
      }
      rows.add(row);
    } catch (e) {
      fail++;
      var msg = e.toString().replaceAll('\n', ' ');
      if (msg.length > 200) msg = msg.substring(0, 200);
      rows.add({'file': rel, 'status': 'fail', 'error': msg});
    }
  }

  File(a[1]).writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
    'total': files.length,
    'ok': ok,
    'no_notes': empty,
    'fail': fail,
    'rows': rows,
  }));

  stdout.writeln('musicxml files=${files.length} '
      'parseable=$ok no_notes=$empty fail=$fail');
  if (ok > 0) {
    final withNotes = rows.where((r) => r['status'] == 'ok').toList();
    final noteCounts = withNotes.map((r) => r['notes'] as int).toList()..sort();
    final partCounts = withNotes.map((r) => r['parts'] as int).toList()..sort();
    stdout.writeln('notes  min=${noteCounts.first} '
        'median=${noteCounts[noteCounts.length ~/ 2]} max=${noteCounts.last}');
    stdout.writeln('parts  min=${partCounts.first} '
        'median=${partCounts[partCounts.length ~/ 2]} max=${partCounts.last}');
  }
  for (final r in rows.where((r) => r['status'] != 'ok').take(20)) {
    stdout.writeln('  ${r['status']}: ${r['file']} ${r['error'] ?? ''}');
  }
}
