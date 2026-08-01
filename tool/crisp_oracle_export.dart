import 'dart:convert';
import 'dart:io';
// ignore: depend_on_referenced_packages
import 'package:crisp_notation_core/crisp_notation_core.dart';

/// Emits the cases a THIRD-PARTY oracle checks (see `tool/oracle.py`).
///
/// Every test in this repo so far compares our codecs against each other or
/// against themselves. That can only ever prove SELF-CONSISTENCY: a writer and
/// a reader sharing the same misconception round-trip perfectly, and no amount
/// of chaining or permuting our own formats will show it. The only way to see
/// that class is to ask somebody else to read what we wrote.
///
/// For each corpus file this writes the score out in each format an oracle can
/// read, plus OUR OWN MIDI of the same score as the reference. The oracle
/// renders its copy to MIDI too, and the two note sets are compared. LilyPond
/// 2.24 is the reference implementation of its own format, so a disagreement
/// there is close to definitive; music21 and verovio are independent readers of
/// MusicXML/ABC/kern/MEI.
void main(List<String> args) {
  if (args.length < 3) {
    stderr.writeln('usage: crisp_oracle_export.dart <dir> <outDir> <cases.json>'
        ' [perExt]');
    exitCode = 64;
    return;
  }
  final outDir = Directory(args[1])..createSync(recursive: true);
  final perExt = args.length > 3 ? int.tryParse(args[3]) : null;

  final all = Directory(args[0])
      .listSync(recursive: true)
      .whereType<File>()
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final byExt = <String, List<File>>{};
  for (final f in all) {
    byExt.putIfAbsent(f.path.split('.').last.toLowerCase(), () => []).add(f);
  }
  final files = <File>[];
  for (final e in byExt.entries) {
    final l = e.value;
    if (perExt == null || l.length <= perExt) {
      files.addAll(l);
    } else {
      final step = l.length / perExt;
      for (var i = 0; i < perExt; i++) {
        files.add(l[(i * step).floor()]);
      }
    }
  }

  // (format, oracle) pairs. MusicXML is checked TWICE, by two independent
  // readers — when they disagree with each other the fault is not necessarily
  // ours, and knowing that saves chasing a phantom.
  const targets = [
    ('lilypond', 'lilypond'),
    ('musicxml', 'music21'),
    ('abc', 'music21'),
    ('kern', 'music21'),
    ('musicxml', 'verovio'),
    ('mei', 'verovio'),
  ];

  final cases = <Map<String, Object?>>[];
  var n = 0;
  for (final f in files) {
    Score? src;
    try {
      src = _load(f);
    } catch (_) {
      continue;
    }
    if (src == null) continue;
    if (!src.measures
        .any((m) => m.elements.whereType<NoteElement>().isNotEmpty)) {
      continue;
    }
    // Our own MIDI is the reference. It is written once per file and shared by
    // every oracle, so a disagreement is between us and THEM, never between two
    // of our own renderings.
    final midiPath = '${outDir.path}/ref_$n.mid';
    try {
      File(midiPath).writeAsBytesSync(scoreToMidi(src));
    } catch (_) {
      continue;
    }
    for (final (fmt, oracle) in targets) {
      String text;
      try {
        text = switch (fmt) {
          'lilypond' => scoreToLilyPond(src),
          'musicxml' => scoreToMusicXml(src),
          'abc' => scoreToAbc(src),
          'kern' => scoreToKern(src),
          'mei' => scoreToMei(src),
          _ => throw ArgumentError(fmt),
        };
      } catch (_) {
        continue;
      }
      cases.add({
        'name': f.path.split('/').last,
        'format': fmt,
        'oracle': oracle,
        'text': text,
        'our_midi': midiPath,
      });
    }
    n++;
  }
  File(args[2]).writeAsStringSync(jsonEncode(cases));
  stdout.writeln('${cases.length} cases from $n files');
}

Score? _load(File f) {
  String text() {
    final b = f.readAsBytesSync();
    try {
      return utf8.decode(b);
    } on FormatException {
      return String.fromCharCodes(b);
    }
  }

  switch (f.path.split('.').last.toLowerCase()) {
    case 'mei':
      return scoreFromMei(text());
    case 'krn':
      return scoreFromKern(text());
    case 'xml':
    case 'musicxml':
      return scoreFromMusicXml(text());
    case 'mxl':
      return scoreFromMusicXml(readMusicXmlFromMxl(f.readAsBytesSync()));
    case 'abc':
      return scoreFromAbc(text());
    case 'ly':
      return scoreFromLilyPond(text());
    case 'mscx':
      return scoreFromMscx(text());
    case 'mscz':
      return scoreFromMscx(readMscxFromMscz(f.readAsBytesSync()));
    default:
      return null;
  }
}
