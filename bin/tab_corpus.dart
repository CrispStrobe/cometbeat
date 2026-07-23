// Symbolic tab-fingering CORPUS extractor: a directory of GuitarPro / MusicXML
// files (that carry human string/fret) → the JSON the labeler trainer consumes,
// so any licence-clean GP/MusicXML collection (or the VPS music-db, once
// reachable) becomes training data for cstr/tab-labeler-onnx in one command.
//
//   dart run bin/tab_corpus.dart <in-dir-or-file> <out.json> [--from gp5|gpif|musicxml]
//
// Output = [{id, columns:[[midi,...],...], human:[[[string,fret],...],...]}],
// the same shape as tool/tab_labeler/export_acceptance.py — feed it to
// tool/tab_labeler/symbolic_to_npz.py to window/encode into the .npz.
//
// Each NoteElement is one column; its (string,fret) come from Score.tabVoicings
// (exactly as TabDocument.fromScore reads them). Standard tuning is assumed (the
// GP Score doesn't retain per-track tuning, like tabconv); notes whose fret
// falls outside [0,19] under standard tuning are dropped, which naturally filters
// out non-standard-tuning / bass / out-of-range content. String index 0 = high e
// (Tuning.standardGuitar order — the model's convention).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_notation_core/crisp_notation_core.dart';

const int _maxFret = 19;

List<Score> _loadParts(String path, String? from) {
  final bytes = File(path).readAsBytesSync();
  Uint8List b() => bytes;
  String t() => utf8.decode(bytes, allowMalformed: true);
  final fmt = from ?? path.toLowerCase().split('.').last;
  switch (fmt) {
    case 'gpif':
      return multiPartScoreFromGpif(t()).parts;
    case 'gp':
      return multiPartScoreFromGpif(readGpifFromGp(b())).parts;
    case 'gpx':
      return multiPartScoreFromGpif(readGpifFromGpx(b())).parts;
    case 'gp5':
    case 'gp4':
    case 'gp3':
      return gpToMultiPart(b()).parts;
    case 'musicxml':
    case 'xml':
      return multiPartScoreFromMusicXml(t()).parts;
    case 'mxl':
      return multiPartScoreFromMusicXml(readMusicXmlFromMxl(b())).parts;
    default:
      return const [];
  }
}

/// The column sequence for one part: each NoteElement → {string: fret} from the
/// explicit voicing; Rest → {}. Returns null if the part isn't a standard-tuning
/// 6-string guitar with enough voiced, in-range notes (skip bass / weird tunings).
({List<List<int>> columns, List<List<List<int>>> human})? _extract(
  Score score,
) {
  final tuning = Tuning.standardGuitar;
  final voiced = {for (final v in score.tabVoicings) v.noteId: v.strings};
  final columns = <List<int>>[];
  final human = <List<List<int>>>[];
  var voicedNotes = 0, inRange = 0;
  for (final measure in score.measures) {
    for (final el in measure.elements) {
      if (el is! NoteElement) continue;
      final midis = [for (final p in el.pitches) p.midiNumber];
      final strings = voiced[el.id];
      final placed = <List<int>>[];
      if (strings != null && strings.length == midis.length) {
        voicedNotes += midis.length;
        for (var i = 0; i < midis.length; i++) {
          final s = strings[i];
          if (s < 0 || s >= 6) continue;
          final fret = midis[i] - tuning.strings[s].midiNumber;
          if (fret >= 0 && fret <= _maxFret) {
            placed.add([s, fret]);
            inRange++;
          }
        }
      }
      if (placed.isEmpty) continue; // skip unvoiced / out-of-range columns
      columns.add(
        [for (final p in placed) tuning.strings[p[0]].midiNumber + p[1]],
      );
      human.add(placed);
    }
  }
  // Require a real guitar part: enough voiced notes, and most in standard range.
  // Thresholds are env-tunable (CORPUS_MIN_COLS / CORPUS_MIN_NOTES) — the
  // defaults suit full songs; lower them to accept short clips.
  final minCols = int.parse(Platform.environment['CORPUS_MIN_COLS'] ?? '8');
  final minNotes = int.parse(Platform.environment['CORPUS_MIN_NOTES'] ?? '16');
  if (columns.length < minCols ||
      voicedNotes < minNotes ||
      inRange < voicedNotes * 0.6) {
    return null;
  }
  return (columns: columns, human: human);
}

void main(List<String> args) {
  final pos = args.where((a) => !a.startsWith('--')).toList();
  String? from;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--from' && i + 1 < args.length) from = args[i + 1];
  }
  if (pos.length != 2) {
    stderr.writeln('usage: dart run bin/tab_corpus.dart <in-dir-or-file> '
        '<out.json> [--from gp5|gpif|musicxml]');
    exit(64);
  }
  final inPath = pos[0], outPath = pos[1];
  final exts = {
    'gp',
    'gpx',
    'gp5',
    'gp4',
    'gp3',
    'gpif',
    'musicxml',
    'xml',
    'mxl',
  };
  final files = <String>[];
  final ent = FileSystemEntity.typeSync(inPath);
  if (ent == FileSystemEntityType.directory) {
    for (final f in Directory(inPath).listSync(recursive: true)) {
      if (f is File && exts.contains(f.path.toLowerCase().split('.').last)) {
        files.add(f.path);
      }
    }
  } else {
    files.add(inPath);
  }
  files.sort();

  final out = <Map<String, dynamic>>[];
  var parts = 0, kept = 0, failed = 0, cols = 0;
  for (final f in files) {
    List<Score> ps;
    try {
      ps = _loadParts(f, from);
    } catch (_) {
      failed++;
      continue;
    }
    for (var i = 0; i < ps.length; i++) {
      parts++;
      final ex = _extract(ps[i]);
      if (ex == null) continue;
      kept++;
      cols += ex.columns.length;
      out.add({
        'id': '${f.split('/').last}#$i',
        'columns': ex.columns,
        'human': ex.human,
      });
    }
  }
  File(outPath).writeAsStringSync(jsonEncode(out));
  stderr
      .writeln('${files.length} files, $parts parts → kept $kept guitar parts '
          '($cols columns), $failed files unparseable → $outPath');
}
