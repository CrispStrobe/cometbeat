import 'dart:convert';
import 'dart:io';
// ignore: depend_on_referenced_packages
import 'package:crisp_notation_core/crisp_notation_core.dart';

/// Compare independent encodings of the SAME work, to check we really hold it
/// rather than merely holding rows whose titles match.
///
/// Prints each file's key, meter and melody incipit as MIDI pitches, so two
/// encodings can be lined up by ear-equivalent content even when they differ in
/// transposition, part layout or lyric handling.
///
/// Usage: `dart run tool/music_db_compare_encodings.dart <file>...`
String _text(File f) {
  final bytes = f.readAsBytesSync();
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    final units = <int>[];
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      units.add((bytes[i + 1] << 8) | bytes[i]);
    }
    return String.fromCharCodes(units);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return String.fromCharCodes(bytes);
  }
}

MultiPartScore? _read(File f) {
  final ext = f.path.split('.').last.toLowerCase();
  switch (ext) {
    case 'mxl':
      return multiPartScoreFromMusicXml(
        readMusicXmlFromMxl(f.readAsBytesSync()),
      );
    case 'xml':
    case 'musicxml':
      return multiPartScoreFromMusicXml(_text(f));
    case 'mscz':
      return multiPartScoreFromMscx(
        readMscxFromMscz(f.readAsBytesSync()),
      );
    case 'ly':
      return multiPartFromLilyPond(_text(f));
    case 'abc':
      return multiPartScoreFromAbc(_text(f));
    case 'mid':
    case 'midi':
      return MultiPartScore([scoreFromMidi(f.readAsBytesSync())]);
    default:
      return null;
  }
}

void main(List<String> args) {
  for (final path in args) {
    final f = File(path);
    final name = path.split('/').last;
    MultiPartScore? mp;
    try {
      mp = _read(f);
    } catch (e) {
      stdout.writeln('$name\n  FAIL ${e.toString().split('\n').first}');
      continue;
    }
    if (mp == null) {
      stdout.writeln('$name\n  (unsupported extension)');
      continue;
    }

    // The melody is whichever part carries the most notes in its top voice —
    // enough to line up a piano-plus-voice score against a bare MIDI melody.
    var best = <int>[];
    var bestKey = 0, bestMeter = '?', bestBars = 0;
    for (final part in mp.parts) {
      final pitches = <int>[];
      for (final m in part.measures) {
        for (final e in m.elements) {
          if (e is NoteElement && e.pitches.isNotEmpty) {
            pitches.add(
              e.pitches
                  .map((p) => p.midiNumber)
                  .reduce((a, b) => a > b ? a : b),
            );
          }
        }
      }
      if (pitches.length > best.length) {
        best = pitches;
        bestKey = part.keySignature.fifths;
        bestMeter = part.timeSignature == null
            ? 'none'
            : '${part.timeSignature!.beats}/${part.timeSignature!.beatUnit}';
        bestBars = part.measures.length;
      }
    }

    final incipit = best.take(14).toList();
    // Intervals make the comparison transposition-proof.
    final steps = [
      for (var i = 1; i < incipit.length; i++) incipit[i] - incipit[i - 1],
    ];
    stdout.writeln(name);
    stdout.writeln('  parts=${mp.parts.length} bars=$bestBars '
        'key=$bestKey meter=$bestMeter notes=${best.length}');
    stdout.writeln('  incipit  $incipit');
    stdout.writeln('  intervals $steps');
  }
}
