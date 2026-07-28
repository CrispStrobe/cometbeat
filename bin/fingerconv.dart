// bin/fingerconv.dart
//
// Headless "score → fingered score" for BOWED strings: reads any Score-yielding
// format and writes it back with a cellist's markup — a fingering digit on every
// note, a Roman string numeral where the string is not inferable from the digit
// alone, and a bow direction on each stroke.
//
// This is the CLI twin of what the Song Book screen does on one score at a time
// (`song_screen.dart` → `scoreWithBowedFingerings`). It exists because the app path
// cannot be run over a corpus: our music DB holds ~2,650 scores with a cello part
// and NOT ONE of them carries a fingering, which is the single largest gap a
// fingering engine could fill.
//
// Usage:
//   dart run bin/fingerconv.dart <in> [<out>] [options]
//     --skill <name>    first | neck | advanced       (default: neck)
//                       first    = first position only, no extensions — a beginner
//                       neck     = positions 1–4 with extensions — the app default
//                       advanced = the whole neck + thumb, shifts freely
//     --instrument <n>  cello | bass                  (default: cello)
//     --part <n|name>   which part: an INDEX, or an instrument name to match
//                       (e.g. `--part cello`). Default: the first part whose
//                       instrument looks bowed, else part 0.
//     --list-parts      print the parts with their instrument names and exit
//     --no-strings      omit the Roman string numerals
//     --no-bowing       omit the bow directions
//     --to <fmt>        musicxml | lilypond | kern | abc  (default: from <out>,
//                       else musicxml)
//     --from <fmt>      force the input format (else inferred from the extension)
//     --stats           print agreement-relevant counts to stderr and write nothing
//
// Flutter-free: the arranger and `bowed_score_fingering` depend only on
// crisp_notation_core, deliberately so this could exist. Run with `dart run`.
//
// ⚠ What the numbers mean, so output is not over-trusted: measured agreement with
// printed editions is ~95% on pedagogical music (a beginner duet in first position),
// ~54% on expressive chamber repertoire, and ~56% on scale tables. A fingering is
// ONE valid answer among several — professionals agree on the string (~92%) and
// disagree on the position (literature: F1 .24–.31 across ten annotators). Treat the
// output as a good first draft for a teacher to correct, never as ground truth.
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/notation/bowed_arranger.dart';
import 'package:comet_beat/core/notation/bowed_score_fingering.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';

void main(List<String> args) {
  final positional = <String>[];
  var skillName = 'neck';
  var instrumentName = 'cello';
  String? partSpec;
  var listParts = false;
  var strings = true;
  var bowing = true;
  var stats = false;
  String? from;
  String? to;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '--no-strings':
        strings = false;
      case '--no-bowing':
        bowing = false;
      case '--stats':
        stats = true;
      case '--skill':
        skillName = args[++i];
      case '--instrument':
        instrumentName = args[++i];
      case '--part':
        partSpec = args[++i];
      case '--list-parts':
        listParts = true;
      case '--from':
        from = args[++i];
      case '--to':
        to = args[++i];
      default:
        if (a.startsWith('-')) {
          stderr.writeln('unknown option: $a');
          exit(64);
        }
        positional.add(a);
    }
  }
  if (positional.isEmpty) {
    stderr
        .writeln('usage: dart run bin/fingerconv.dart <in> [<out>] [options]');
    exit(64);
  }

  final skill = switch (skillName) {
    'first' => BowedSkill.firstPosition,
    'neck' => BowedSkill.neckPositions,
    'advanced' => BowedSkill.advanced,
    _ => _bail('unknown skill "$skillName" (first | neck | advanced)'),
  };
  final instrument = switch (instrumentName) {
    'cello' => BowedInstrument.cello,
    'bass' => BowedInstrument.doubleBass,
    _ => _bail('unknown instrument "$instrumentName" (cello | bass)'),
  };

  final parts = _loadParts(positional.first, from);
  if (listParts) {
    for (var i = 0; i < parts.length; i++) {
      stdout.writeln('$i\t${parts[i].metadata.instrument ?? "(unnamed)"}');
    }
    return;
  }
  final part = _choosePart(parts, partSpec);
  final score = parts[part];

  final fingered = scoreWithBowedFingerings(
    score,
    skill: skill,
    instrument: instrument,
    markStrings: strings,
    markBowing: bowing,
  );

  // Report what actually happened. A fingering engine that silently leaves notes
  // unfingered is worse than one that says so.
  final assigned =
      fingerBowedScore(score, skill: skill, instrument: instrument);
  final total = score.measures
      .expand((m) => m.elements)
      .whereType<NoteElement>()
      .where((n) => n.pitches.isNotEmpty)
      .length;
  stderr.writeln('${positional.first}: part $part of ${parts.length} · '
      '$total notes · ${assigned.length} fingered · '
      'skill=$skillName instrument=$instrumentName');
  if (assigned.length < total) {
    stderr.writeln('  ⚠ ${total - assigned.length} note(s) got no fingering — '
        'they are out of range for this instrument, or the passage needs a '
        'technique this skill profile forbids (try --skill advanced)');
  }
  if (stats) return;

  final outPath = positional.length > 1 ? positional[1] : null;
  final fmt = to ?? (outPath == null ? 'musicxml' : _formatOf(outPath));
  final text = switch (fmt) {
    'musicxml' || 'xml' => scoreToMusicXml(fingered),
    'lilypond' || 'ly' => scoreToLilyPond(fingered),
    'kern' || 'krn' => scoreToKern(fingered),
    'abc' => scoreToAbc(fingered),
    _ => _bail('unknown output format "$fmt" '
        '(musicxml | lilypond | kern | abc)'),
  };

  if (outPath == null) {
    stdout.write(text);
  } else {
    File(outPath).writeAsStringSync(text);
    stderr.writeln('  wrote $outPath ($fmt)');
  }
}

/// Which part to finger.
///
/// ⚠ This exists because the naive `--part 0` is actively WRONG on real corpus
/// files: a NIFC choral score has soprano, two violins, viola and cello, and
/// index 0 is none of them. Fingering a soprano line as though it were a cello
/// produces confident nonsense, and a bulk run would produce it 2,650 times.
/// So: match by instrument name, and when nothing is specified prefer a part
/// that LOOKS bowed rather than blindly taking the first.
int _choosePart(List<Score> parts, String? spec) {
  // ⚠ Normalise historical orthography before matching. A NIFC score names its
  // cello part "Baſso." with a LONG S (U+017F), which `contains('basso')` never
  // matches — 11 of 25 corpus files silently found "no bowed part" until this was
  // added. Old prints also use ligatures and accents freely.
  String nameOf(int i) => (parts[i].metadata.instrument ?? '')
      .toLowerCase()
      .replaceAll('\u017f', 's') // ſ long s
      .replaceAll('\u00df', 'ss') // ß
      .replaceAll('\u0153', 'oe') // œ
      .replaceAll('\u00e6', 'ae'); // æ

  if (spec != null) {
    final asIndex = int.tryParse(spec);
    if (asIndex != null) {
      if (asIndex < 0 || asIndex >= parts.length) {
        stderr.writeln('score has ${parts.length} part(s); '
            '--part $asIndex is out of range');
        exit(1);
      }
      return asIndex;
    }
    final want = spec.toLowerCase();
    for (var i = 0; i < parts.length; i++) {
      if (nameOf(i).contains(want)) return i;
    }
    stderr.writeln('no part matching "$spec". Parts:');
    for (var i = 0; i < parts.length; i++) {
      stderr.writeln('  $i  ${parts[i].metadata.instrument ?? "(unnamed)"}');
    }
    exit(1);
  }

  // No preference given: prefer something plausibly bowed, and SAY which was
  // chosen, because silently fingering the wrong part is the failure mode here.
  const bowed = [
    'cello',
    'violoncell',
    'vlc',
    'basso',
    'contrabass',
    'double bass',
  ];
  for (var i = 0; i < parts.length; i++) {
    if (bowed.any(nameOf(i).contains)) {
      stderr.writeln('  (auto-selected part $i '
          '"${parts[i].metadata.instrument}" — pass --part to override)');
      return i;
    }
  }
  if (parts.length > 1) {
    stderr.writeln('  ⚠ no part looks bowed; using part 0 '
        '"${parts[0].metadata.instrument ?? "(unnamed)"}" of ${parts.length}. '
        'Use --list-parts to see them, --part <name|n> to choose.');
  }
  return 0;
}

Never _bail(String message) {
  stderr.writeln(message);
  exit(64);
}

String _formatOf(String path) {
  final dot = path.lastIndexOf('.');
  return dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
}

/// Loads [path] to a list of parts. Mirrors `tabconv.dart`'s dispatch so the two
/// CLIs accept exactly the same inputs.
List<Score> _loadParts(String path, String? from) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('no such file: $path');
    exit(1);
  }
  final fmt = from ?? _formatOf(path);
  Uint8List bytes() => file.readAsBytesSync();
  String text() => file.readAsStringSync();
  switch (fmt) {
    case 'abc':
      return multiPartScoreFromAbc(text()).parts;
    case 'xml':
    case 'musicxml':
      return multiPartScoreFromMusicXml(text()).parts;
    case 'mxl':
      return multiPartScoreFromMusicXml(readMusicXmlFromMxl(bytes())).parts;
    case 'mscx':
      return multiPartScoreFromMscx(text()).parts;
    case 'mscz':
      return multiPartScoreFromMscx(readMscxFromMscz(bytes())).parts;
    case 'mei':
      return multiPartScoreFromMei(text()).parts;
    case 'krn':
    case 'kern':
      return multiPartScoreFromKern(text()).parts;
    case 'ly':
    case 'lilypond':
      return multiPartFromLilyPond(text()).parts;
    case 'mid':
    case 'midi':
      return [scoreFromMidi(bytes())];
    default:
      stderr.writeln('unknown input format for $path (use --from)');
      exit(64);
  }
}
