// bin/tabconv.dart
//
// Headless "notation → Guitar Pro (.gp)" converter. Reads any Score-yielding
// format (ABC, MIDI, MusicXML/MXL, MuseScore, MEI, Humdrum kern, Guitar Pro)
// and writes a Guitar Pro 7 (.gp) file — running the cost-based tab arranger so
// the frets are playable, not the greedy per-pitch fallback the writer uses on
// its own. Multi-part inputs export one GP track per part.
//
// Usage:
//   dart run bin/tabconv.dart <in> <out.gp> [options]
//     --tuning <name>   standard | drop-d | dadgad | open-g | 7-string |
//                       8-string | bass | 5-string-bass | banjo | ukulele |
//                       mandolin   (default: standard)
//     --capo <n>        capo fret, folded into the written frets (default 0)
//     --no-arrange      skip the arranger; let the writer fret each pitch
//     --from <fmt>      force the input format (else inferred from extension)
//
// This is Flutter-free (crisp_notation_core codecs + the Flutter-free
// tab_arranger), so it runs under `dart run`. The arranger's per-note string/
// fret choices reach the .gp via GPIF's `frettings` plan (crisp_notation@c5b03bf).
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/features/games/composition/tab_gp_plan.dart'
    show gpFretPlanFor;
import 'package:crisp_notation_core/crisp_notation_core.dart';

void main(List<String> args) {
  final positional = <String>[];
  var arrange = true;
  var tuningName = 'standard';
  var capo = 0;
  String? from;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--no-arrange') {
      arrange = false;
    } else if (a == '--tuning') {
      tuningName = args[++i];
    } else if (a == '--capo') {
      capo = int.parse(args[++i]);
    } else if (a == '--from') {
      from = args[++i];
    } else {
      positional.add(a);
    }
  }
  if (positional.length != 2) {
    stderr.writeln('usage: dart run bin/tabconv.dart <in> <out.gp> '
        '[--tuning <name>] [--capo <n>] [--no-arrange] [--from <fmt>]');
    exit(64);
  }
  final inPath = positional[0], outPath = positional[1];
  final tuning = _tuning(tuningName);

  final parts = _loadParts(inPath, from);
  if (parts.isEmpty) {
    stderr.writeln('no parts found in $inPath');
    exit(1);
  }
  final plans = arrange
      ? [for (final p in parts) gpFretPlanFor(p, tuning, capo: capo)]
      : null;

  final String gpif;
  if (parts.length == 1) {
    gpif = scoreToGpif(parts.single, tuning: tuning, frettings: plans?.single);
  } else {
    gpif = multiPartToGpif(
      MultiPartScore(parts),
      tunings: [for (final _ in parts) tuning],
      names: [
        for (var i = 0; i < parts.length; i++)
          parts[i].metadata.instrument ?? 'Track ${i + 1}',
      ],
      frettings: plans,
    );
  }
  File(outPath).writeAsBytesSync(writeGpFromGpif(gpif));
  stdout.writeln('wrote $outPath — ${parts.length} track(s), '
      '${arrange ? 'arranged on $tuningName' : 'fret-from-pitch'}'
      '${capo > 0 ? ', capo $capo' : ''}');
}

/// Loads [path] to a list of parts. Multi-part formats keep every part; MIDI
/// flattens to one score.
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
    case 'kern':
      return multiPartScoreFromKern(text()).parts;
    case 'midi':
      return [scoreFromMidi(bytes())];
    case 'gpif':
      return multiPartScoreFromGpif(text()).parts;
    case 'gp':
      return multiPartScoreFromGpif(readGpifFromGp(bytes())).parts;
    case 'gpx':
      return multiPartScoreFromGpif(readGpifFromGpx(bytes())).parts;
    case 'gp5':
    case 'gp4':
    case 'gp3':
      return gpToMultiPart(bytes()).parts;
    default:
      stderr.writeln('unknown input format for $path (use --from)');
      exit(64);
  }
}

String _formatOf(String path) {
  final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'xml':
    case 'musicxml':
      return 'musicxml';
    case 'mid':
    case 'midi':
      return 'midi';
    case 'krn':
    case 'kern':
      return 'kern';
    default:
      return ext; // abc, mxl, mscx, mscz, mei, gp3/4/5, gp, gpx, gpif
  }
}

Tuning _tuning(String name) {
  switch (name.toLowerCase()) {
    case 'standard':
    case 'guitar':
      return Tuning.standardGuitar;
    case 'drop-d':
    case 'dropd':
      return Tuning.dropDGuitar;
    case 'dadgad':
      return Tuning.dadgadGuitar;
    case 'open-g':
    case 'openg':
      return Tuning.openGGuitar;
    case '7-string':
    case '7string':
      return Tuning.sevenStringGuitar;
    case '8-string':
    case '8string':
      return Tuning.eightStringGuitar;
    case 'bass':
      return Tuning.standardBass;
    case '5-string-bass':
    case '5stringbass':
      return Tuning.fiveStringBass;
    case 'banjo':
      return Tuning.banjoOpenG;
    case 'ukulele':
      return Tuning.ukulele;
    case 'mandolin':
      return Tuning.mandolin;
    default:
      stderr.writeln('unknown tuning "$name"; using standard guitar');
      return Tuning.standardGuitar;
  }
}
