// Parse-validate the CPDL symbolic harvest through crisp_notation.
//
// Runs LOCALLY, never on the VPS — dart/flutter refuse to run as root there.
//
// Usage:
//   dart run tool/music_db_cpdl_parse_sweep.dart <candidates.json> <files-root> <report.json>
//
// Unlike the Jukebox sweep (plain .musicxml only) CPDL is mostly ZIPPED: .mxl
// and .mscz are both ZIP containers, unwrapped here with the pure-Dart
// readMusicXmlFromMxl / readMscxFromMscz so no external tooling is needed.
//
// Reads the candidate list rather than walking the tree, because only the
// licence-cleared editions are worth validating — the extracted tree holds the
// whole 60k-file corpus including CPDL-licensed and NC editions we never ship.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:crisp_notation_core/crisp_notation_core.dart';

({int notes, int rests, int parts, int measures}) _stats(MultiPartScore mp) {
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
  return (
    notes: notes,
    rests: rests,
    parts: mp.parts.length,
    measures: measures
  );
}

MultiPartScore _read(String fmt, File f) {
  switch (fmt) {
    case 'mxl':
      return multiPartScoreFromMusicXml(
        readMusicXmlFromMxl(Uint8List.fromList(f.readAsBytesSync())),
      );
    case 'musicxml':
      return multiPartScoreFromMusicXml(f.readAsStringSync());
    case 'mscz':
      return multiPartScoreFromMscx(
        readMscxFromMscz(Uint8List.fromList(f.readAsBytesSync())),
      );
    case 'ly':
      return multiPartFromLilyPond(f.readAsStringSync());
    case 'midi':
      final s = scoreFromMidi(Uint8List.fromList(f.readAsBytesSync()));
      return MultiPartScore([s]);
    default:
      throw FormatException('unsupported format $fmt');
  }
}

void main(List<String> a) {
  if (a.length < 3) {
    stderr.writeln(
      'usage: cpdl_parse_sweep <candidates.json> <files-root> <report.json>',
    );
    exit(64);
  }
  final rows = (jsonDecode(File(a[0]).readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final root = a[1];

  final out = <Map<String, dynamic>>[];
  final okByFmt = <String, int>{};
  final failByFmt = <String, int>{};
  var ok = 0, fail = 0, empty = 0, missing = 0;

  for (final r in rows) {
    final fmt = r['format'] as String?;
    final files = (r['files'] as Map).cast<String, dynamic>();
    final rel = fmt == null ? null : files[fmt] as String?;
    if (fmt == null || rel == null) {
      missing++;
      continue;
    }
    final f = File('$root/$rel');
    if (!f.existsSync()) {
      missing++;
      out.add({'id': r['id'], 'format': fmt, 'status': 'missing', 'file': rel});
      continue;
    }
    try {
      final st = _stats(_read(fmt, f));
      final status = st.notes > 0 ? 'ok' : 'no_notes';
      if (st.notes > 0) {
        ok++;
        okByFmt[fmt] = (okByFmt[fmt] ?? 0) + 1;
      } else {
        empty++;
      }
      out.add({
        'id': r['id'],
        'format': fmt,
        'status': status,
        'file': rel,
        'parts': st.parts,
        'measures': st.measures,
        'notes': st.notes,
        'rests': st.rests,
      });
    } catch (e) {
      fail++;
      failByFmt[fmt] = (failByFmt[fmt] ?? 0) + 1;
      var msg = e.toString().replaceAll('\n', ' ');
      if (msg.length > 180) msg = msg.substring(0, 180);
      out.add({
        'id': r['id'],
        'format': fmt,
        'status': 'fail',
        'file': rel,
        'error': msg,
      });
    }
  }

  File(a[2]).writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert({
      'total': rows.length,
      'ok': ok,
      'no_notes': empty,
      'fail': fail,
      'missing': missing,
      'rows': out,
    }),
  );

  stdout.writeln('editions=${rows.length} parseable=$ok no_notes=$empty '
      'fail=$fail missing=$missing');
  stdout.writeln('  ok by format:   $okByFmt');
  stdout.writeln('  fail by format: $failByFmt');
  final withNotes = out
      .where((r) => r['status'] == 'ok')
      .map((r) => r['notes'] as int)
      .toList()
    ..sort();
  if (withNotes.isNotEmpty) {
    stdout.writeln('  notes min=${withNotes.first} '
        'median=${withNotes[withNotes.length ~/ 2]} max=${withNotes.last}');
  }
  for (final r in out.where((r) => r['status'] == 'fail').take(15)) {
    stdout.writeln('  FAIL ${r['format']} ${r['file']}: ${r['error']}');
  }
}
