// Parse-validate the ENTIRE music-db score corpus through crisp_notation.
//
// Runs LOCALLY — dart/flutter refuse to run as root on the VPS.
//
// Usage:
//   dart run tool/music_db_corpus_sweep.dart <rows.json> <files-root> <report.json>
//
// `rows.json` is a list of {id, source, format, path} exported from db.json.
//
// Covers every format the corpus holds: gabc · midi · krn · musicxml · mxl ·
// mscx · mscz · ly · abc · gp. The two ZIP containers (.mxl/.mscz) and the .gp
// container are unwrapped with the pure-Dart readers, so no external tooling is
// involved anywhere.
//
// ⚠️ Counts notes across ALL FOUR VOICES. Counting `elements` only made an
// earlier sweep blind to the LilyPond parallel-voice bug — it reported "no
// change" from the very fix it was validating.
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
      for (final e in [...m.elements, ...m.voice2, ...m.voice3, ...m.voice4]) {
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
    measures: measures,
  );
}

MultiPartScore _read(String fmt, File f) {
  Uint8List bytes() => Uint8List.fromList(f.readAsBytesSync());
  switch (fmt) {
    case 'musicxml':
      return multiPartScoreFromMusicXml(f.readAsStringSync());
    case 'mxl':
      return multiPartScoreFromMusicXml(readMusicXmlFromMxl(bytes()));
    case 'mscx':
      return multiPartScoreFromMscx(f.readAsStringSync());
    case 'mscz':
      return multiPartScoreFromMscx(readMscxFromMscz(bytes()));
    case 'ly':
      return multiPartFromLilyPond(f.readAsStringSync());
    case 'krn':
      return multiPartScoreFromKern(f.readAsStringSync());
    case 'abc':
      return multiPartScoreFromAbc(f.readAsStringSync());
    case 'midi':
      return MultiPartScore([scoreFromMidi(bytes())]);
    case 'gabc':
      return MultiPartScore([scoreFromGabc(f.readAsStringSync())]);
    case 'gp':
      return MultiPartScore([scoreFromGpif(readGpifFromGp(bytes()))]);
    default:
      throw FormatException('unsupported format $fmt');
  }
}

Future<void> main(List<String> a) async {
  if (a.length < 3) {
    stderr
        .writeln('usage: corpus_sweep <rows.json> <files-root> <report.json>');
    exit(64);
  }
  final rows = (jsonDecode(File(a[0]).readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final root = a[1];

  // Stream each result to a JSONL sink rather than accumulating 44k maps: the
  // first run of this tool held every row in memory and buffered stdout, so
  // when it was killed there was NOTHING to show for the work. Now partial
  // progress survives.
  final sink = File('${a[2]}.jsonl').openWrite();
  final okBy = <String, int>{};
  final failBy = <String, int>{};
  final emptyBy = <String, int>{};
  final notesBy = <String, int>{};
  final errors = <String, int>{};
  var ok = 0, fail = 0, empty = 0, missing = 0, done = 0;

  for (final r in rows) {
    final fmt = r['format'] as String?;
    final rel = r['path'] as String?;
    if (fmt == null || rel == null) {
      missing++;
      continue;
    }
    final f = File('$root/$rel');
    if (!f.existsSync()) {
      missing++;
      sink.writeln(
        jsonEncode(
          {'id': r['id'], 'format': fmt, 'status': 'missing', 'file': rel},
        ),
      );
      continue;
    }
    try {
      final st = _stats(_read(fmt, f));
      final status = st.notes > 0 ? 'ok' : 'no_notes';
      if (st.notes > 0) {
        ok++;
        okBy[fmt] = (okBy[fmt] ?? 0) + 1;
        notesBy[fmt] = (notesBy[fmt] ?? 0) + st.notes;
      } else {
        empty++;
        emptyBy[fmt] = (emptyBy[fmt] ?? 0) + 1;
      }
      sink.writeln(
        jsonEncode({
          'id': r['id'],
          'source': r['source'],
          'format': fmt,
          'status': status,
          'file': rel,
          'parts': st.parts,
          'measures': st.measures,
          'notes': st.notes,
          'rests': st.rests,
        }),
      );
    } catch (e) {
      fail++;
      failBy[fmt] = (failBy[fmt] ?? 0) + 1;
      var msg = e.toString().replaceAll('\n', ' ');
      if (msg.length > 160) msg = msg.substring(0, 160);
      // Bucket by the error shape so the report shows WHICH gaps dominate.
      final key = '$fmt: ${msg.split(RegExp(r'[:(]')).first.trim()}';
      errors[key] = (errors[key] ?? 0) + 1;
      sink.writeln(
        jsonEncode({
          'id': r['id'],
          'source': r['source'],
          'format': fmt,
          'status': 'fail',
          'file': rel,
          'error': msg,
        }),
      );
    }
    if (++done % 1000 == 0) {
      stdout
          .writeln('  … $done/${rows.length}  ok=$ok fail=$fail empty=$empty');
      // NB: do NOT call stdout.flush() here — flushing without awaiting
      // leaves the sink bound and the next writeln throws
      // "StreamSink is bound to a stream". Dart flushes progress on its own.
    }
  }

  // Close the JSONL sink BEFORE writing the summary — an unclosed IOSink loses
  // its tail, which would silently truncate the per-row report.
  await sink.flush();
  await sink.close();

  File(a[2]).writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert({
      'total': rows.length,
      'ok': ok,
      'no_notes': empty,
      'fail': fail,
      'missing': missing,
      'okByFormat': okBy,
      'failByFormat': failBy,
      'emptyByFormat': emptyBy,
      'notesByFormat': notesBy,
      'errorBuckets': errors,
      'rowsFile': '${a[2]}.jsonl',
    }),
  );

  stdout.writeln('\n=== corpus sweep ===');
  stdout.writeln('rows=${rows.length} ok=$ok no_notes=$empty fail=$fail '
      'missing=$missing');
  final fmts = {...okBy.keys, ...failBy.keys, ...emptyBy.keys}.toList()..sort();
  stdout.writeln('${'format'.padRight(10)}${'ok'.padLeft(7)}'
      '${'empty'.padLeft(7)}${'fail'.padLeft(7)}${'notes'.padLeft(11)}');
  for (final f in fmts) {
    stdout.writeln('  ${f.padRight(10)}${(okBy[f] ?? 0).toString().padLeft(5)}'
        '${(emptyBy[f] ?? 0).toString().padLeft(7)}'
        '${(failBy[f] ?? 0).toString().padLeft(7)}'
        '${(notesBy[f] ?? 0).toString().padLeft(11)}');
  }
  if (errors.isNotEmpty) {
    stdout.writeln('\ntop error buckets:');
    final sorted = errors.entries.toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    for (final e in sorted.take(15)) {
      stdout.writeln('  ${e.value.toString().padLeft(5)}  ${e.key}');
    }
  }
}
