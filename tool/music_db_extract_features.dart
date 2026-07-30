import 'dart:convert';
import 'dart:io';
// ignore: depend_on_referenced_packages
import 'package:crisp_notation_core/crisp_notation_core.dart';

/// Extract the MUSICAL features of corpus files, for indexing in `db.json`.
///
/// `db.json` records provenance and licensing exhaustively but is musically
/// opaque: nothing in a row says what key a piece is in, what metre it uses, or
/// whether a child could actually sing it. This computes that, so the catalog
/// can be browsed and filtered by content rather than only by title.
///
/// What each field is FOR, since that drove the choices:
///   * `key`      — inferred with Krumhansl–Schmuckler, so it distinguishes
///                  D major from B minor rather than reporting a bare
///                  signature that is ambiguous between the two.
///   * `ambitus`  — lowest/highest sounding pitch. The single most useful
///                  filter for teaching: "is this within my group's range?"
///   * `incipit`  — the opening melody, plus its INTERVALS. Intervals are
///                  transposition-proof, which makes them a same-tune
///                  detector: the German cross-source dedup was done by an
///                  ad-hoc fingerprinting pass, and this generalises it.
///
/// Emits `{path: {…}}` JSON so a merge step can attach it to rows by `path`.
///
/// Usage:
/// `dart run tool/music_db_extract_features.dart <dir> <out.json> [list.txt]`
///
/// With a path list, only those paths (relative to the directory) are read,
/// which is how the full-corpus backfill processes just the rows that still
/// lack features.
String _text(File f) {
  final bytes = f.readAsBytesSync();
  if (bytes.length >= 2) {
    if (bytes[0] == 0xFF && bytes[1] == 0xFE) return _utf16(bytes, false);
    if (bytes[0] == 0xFE && bytes[1] == 0xFF) return _utf16(bytes, true);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return String.fromCharCodes(bytes);
  }
}

String _utf16(List<int> b, bool big) {
  final u = <int>[];
  for (var i = 2; i + 1 < b.length; i += 2) {
    u.add(big ? (b[i] << 8) | b[i + 1] : (b[i + 1] << 8) | b[i]);
  }
  return String.fromCharCodes(u);
}

MultiPartScore? _read(File f) {
  switch (f.path.split('.').last.toLowerCase()) {
    case 'mxl':
      return multiPartScoreFromMusicXml(
        readMusicXmlFromMxl(f.readAsBytesSync()),
      );
    case 'xml':
    case 'musicxml':
      return multiPartScoreFromMusicXml(_text(f));
    case 'mscz':
      return multiPartScoreFromMscx(readMscxFromMscz(f.readAsBytesSync()));
    case 'mscx':
      return multiPartScoreFromMscx(_text(f));
    case 'ly':
      return multiPartFromLilyPond(_text(f));
    case 'abc':
      return multiPartScoreFromAbc(_text(f));
    case 'krn':
      return multiPartScoreFromKern(_text(f));
    case 'mei':
      return multiPartScoreFromMei(_text(f));
    case 'gabc':
      // The largest format in the corpus by far (18,684 chants). Single-voice
      // by nature, so there is no multi-part reader.
      return MultiPartScore([scoreFromGabc(_text(f))]);
    case 'gp':
      return MultiPartScore([
        scoreFromGpif(readGpifFromGp(f.readAsBytesSync())),
      ]);
    case 'mid':
    case 'midi':
      return MultiPartScore([scoreFromMidi(f.readAsBytesSync())]);
    default:
      return null;
  }
}

/// Whether a key estimate is meaningful for this file.
///
/// Krumhansl–Schmuckler matches duration-weighted pitch classes against
/// MAJOR and MINOR profiles, so it always returns one of those — which is
/// actively wrong for Gregorian chant, where the organising concept is the
/// church mode and the corpus already records it in a `mode` field. Reporting
/// "D major" for a Mode 1 antiphon would be worse than reporting nothing.
bool _keyIsMeaningful(String path) => !path.toLowerCase().endsWith('.gabc');

const _stepNames = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];

String _keyName(Key k) {
  final t = k.tonic;
  final alter = t.alter > 0
      ? '#' * t.alter
      : t.alter < 0
          ? 'b' * -t.alter
          : '';
  return '${_stepNames[t.step.index]}$alter ${k.isMajor ? 'major' : 'minor'}';
}

Map<String, Object?>? _features(MultiPartScore mp, {bool withKey = true}) {
  final all = <Pitch>[];
  final weights = <double>[];
  var notes = 0, bars = 0;
  int? lo, hi;

  for (final part in mp.parts) {
    bars = bars > part.measures.length ? bars : part.measures.length;
    for (final m in part.measures) {
      for (final voice in m.voices) {
        for (final e in voice) {
          if (e is! NoteElement) continue;
          notes++;
          final w = e.duration.toFraction().toDouble();
          for (final p in e.pitches) {
            all.add(p);
            weights.add(w);
            final n = p.midiNumber;
            if (lo == null || n < lo) lo = n;
            if (hi == null || n > hi) hi = n;
          }
        }
      }
    }
  }
  if (notes == 0) return null;

  // Pick the melody by REGISTER, not by note count. Counting notes picks the
  // accompaniment on any voice-plus-piano score — Mozart's KV 596 has 117
  // notes of broken-chord left hand against 90 in the vocal line, so a
  // count-based rule fingerprints the arpeggio instead of the tune. The melody
  // is the part sitting on top, so rank by mean pitch and use note count only
  // to break ties.
  var incipit = <int>[];
  var bestMean = -1.0;
  for (final part in mp.parts) {
    final line = <int>[];
    for (final m in part.measures) {
      for (final e in m.elements) {
        if (e is NoteElement && e.pitches.isNotEmpty) {
          line.add(
            e.pitches.map((p) => p.midiNumber).reduce((a, b) => a > b ? a : b),
          );
        }
      }
      if (line.length >= 32) break;
    }
    if (line.isEmpty) continue;
    final mean = line.reduce((a, b) => a + b) / line.length;
    if (mean > bestMean || (mean == bestMean && line.length > incipit.length)) {
      bestMean = mean;
      incipit = line;
    }
  }
  incipit = incipit.take(16).toList();

  final key = withKey ? keyOf(all, durations: weights) : null;
  final meter = mp.parts.first.timeSignature;

  return {
    'key': key == null ? null : _keyName(key),
    'keyFifths': key?.signature.fifths,
    'mode': key == null
        ? null
        : key.isMajor
            ? 'major'
            : 'minor',
    'meter': meter == null ? null : '${meter.beats}/${meter.beatUnit}',
    'bars': bars,
    'parts': mp.parts.length,
    'notes': notes,
    'ambitus': [lo, hi],
    'incipit': incipit,
    'incipitIntervals': [
      for (var i = 1; i < incipit.length; i++) incipit[i] - incipit[i - 1],
    ],
  };
}

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('Usage: music_db_extract_features.dart <dir> <out.json>');
    exitCode = 64;
    return;
  }
  final dir = Directory(args[0]);
  if (!dir.existsSync()) {
    stderr.writeln('No such directory: ${args[0]}');
    exitCode = 66;
    return;
  }

  final out = <String, Object?>{};
  var ok = 0, empty = 0, failed = 0, skipped = 0, missing = 0;

  // With a path list, do exactly those files. A full-corpus backfill wants to
  // process only the rows that still lack features, and walking the tree would
  // also drag in the sample/soundfont payloads.
  final List<File> files;
  if (args.length > 2) {
    files = [];
    for (final line in File(args[2]).readAsLinesSync()) {
      final rel = line.trim();
      if (rel.isEmpty) continue;
      final f = File('${dir.path}/$rel');
      if (f.existsSync()) {
        files.add(f);
      } else {
        missing++;
      }
    }
  } else {
    files = dir.listSync(recursive: true).whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  final total = files.length;
  var done = 0;

  for (final f in files) {
    final rel = f.path.substring(dir.path.length + 1);
    if (++done % 2000 == 0) {
      stdout.writeln('  $done/$total  ok=$ok fail=$failed empty=$empty');
    }
    MultiPartScore? mp;
    try {
      mp = _read(f);
    } catch (_) {
      failed++;
      continue;
    }
    if (mp == null) {
      skipped++;
      continue;
    }
    final feat = _features(mp, withKey: _keyIsMeaningful(f.path));
    if (feat == null) {
      empty++;
      continue;
    }
    out[rel] = feat;
    ok++;
  }

  File(args[1])
      .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
  stdout.writeln('DONE features=$ok empty=$empty fail=$failed '
      'skipped=$skipped missing=$missing -> ${args[1]}');
}
