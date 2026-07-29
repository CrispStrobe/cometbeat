import 'dart:convert';
import 'dart:io';
// ignore: depend_on_referenced_packages
import 'package:crisp_notation_core/crisp_notation_core.dart';

/// Parse-sweep a directory of newly harvested corpus files through the
/// crisp_notation readers.
///
/// Reports note counts across ALL voices, not just `measure.elements` — a
/// voice-1-only count is blind to `\\`/voice-2 material and silently
/// under-reports (the trap that made an earlier CPDL sweep read "0 gains").
///
/// Usage: `dart run tool/music_db_new_source_sweep.dart <dir> [report.json]`

/// Reads an XML file as text, honouring a UTF-16 byte-order mark.
///
/// MusicXML permits `encoding="UTF-16"` and Finale 2003-era exports (e.g. the
/// Project Gutenberg quartets) use it. A plain `readAsStringSync` throws on
/// those, which looks like a reader bug but is only a decoding gap.
String _readXmlText(File f) {
  final bytes = f.readAsBytesSync();
  if (bytes.length >= 2) {
    if (bytes[0] == 0xFF && bytes[1] == 0xFE) return _utf16(bytes, 2, false);
    if (bytes[0] == 0xFE && bytes[1] == 0xFF) return _utf16(bytes, 2, true);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// Reads a plain-text source file as UTF-8, falling back to Latin-1.
///
/// ABC carries no encoding declaration, and pre-Unicode archives are routinely
/// ISO-8859-1 — the Dahlhoff transcriptions are, wherever a German umlaut
/// appears in a title. A bare `readAsStringSync` throws on those.
String _readText(File f) {
  final bytes = f.readAsBytesSync();
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return String.fromCharCodes(bytes);
  }
}

String _utf16(List<int> bytes, int start, bool bigEndian) {
  final units = <int>[];
  for (var i = start; i + 1 < bytes.length; i += 2) {
    units.add(
      bigEndian
          ? (bytes[i] << 8) | bytes[i + 1]
          : (bytes[i + 1] << 8) | bytes[i],
    );
  }
  return String.fromCharCodes(units);
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: music_db_new_source_sweep.dart <dir> [report.json]');
    exitCode = 64;
    return;
  }
  final dir = Directory(args[0]);
  if (!dir.existsSync()) {
    stderr.writeln('No such directory: ${args[0]}');
    exitCode = 66;
    return;
  }

  final rows = <Map<String, Object?>>[];
  var ok = 0, noNotes = 0, failed = 0, skipped = 0;

  final files = dir.listSync(recursive: true).whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final f in files) {
    final ext = f.path.split('.').last.toLowerCase();
    final rel = f.path.substring(dir.path.length + 1);
    MultiPartScore? mp;
    Score? single;
    String? error;

    try {
      switch (ext) {
        case 'abc':
          mp = multiPartScoreFromAbc(_readText(f));
        case 'xml':
        case 'musicxml':
          mp = multiPartScoreFromMusicXml(_readXmlText(f));
        case 'ly':
          mp = multiPartFromLilyPond(f.readAsStringSync());
        case 'mid':
        case 'midi':
          single = scoreFromMidi(f.readAsBytesSync());
        default:
          skipped++;
          continue;
      }
    } catch (e) {
      error = e.toString().replaceAll('\n', ' ');
      if (error.length > 160) error = error.substring(0, 160);
    }

    if (error != null) {
      failed++;
      rows.add({'file': rel, 'status': 'fail', 'error': error});
      continue;
    }

    final parts = mp?.parts ?? [single!];
    var notes = 0, rests = 0, measures = 0;
    for (final p in parts) {
      for (final m in p.measures) {
        measures++;
        for (final voice in m.voices) {
          for (final e in voice) {
            if (e is NoteElement) {
              notes++;
            } else if (e is RestElement) {
              rests++;
            }
          }
        }
      }
    }

    if (notes == 0) {
      noNotes++;
      rows.add({
        'file': rel,
        'status': 'no_notes',
        'parts': parts.length,
        'measures': measures,
        'rests': rests,
      });
    } else {
      ok++;
      rows.add({
        'file': rel,
        'status': 'ok',
        'parts': parts.length,
        'measures': measures,
        'notes': notes,
        'rests': rests,
      });
    }
  }

  final total = ok + noNotes + failed;
  final pct = total == 0 ? 0.0 : ok * 100.0 / total;
  stdout.writeln('files=$total ok=$ok no_notes=$noNotes fail=$failed '
      'skipped=$skipped (${pct.toStringAsFixed(1)}%)');
  final totalNotes =
      rows.fold<int>(0, (s, r) => s + ((r['notes'] as int?) ?? 0));
  stdout.writeln('total notes read: $totalNotes');

  if (args.length > 1) {
    File(args[1])
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
    stdout.writeln('report -> ${args[1]}');
  }

  for (final r in rows.where((r) => r['status'] != 'ok').take(15)) {
    stdout.writeln('  ! ${r['file']}: ${r['status']} ${r['error'] ?? ''}');
  }
}
