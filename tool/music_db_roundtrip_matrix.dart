// Cross-format round-trip PERMUTATION matrix over REAL-WORLD corpus files.
//
//   dart run tool/music_db_roundtrip_matrix.dart <files.json> <root> <report.json>
//                                                [--triples N] [--only X,Y]
//
// Why this exists, on top of roundtrip_property_test.dart:
//   * that test round-trips GENERATED scores through ONE codec (X→X);
//   * this one drives REAL corpus files through CHAINS of codecs —
//     X→Y→X, Y→X→Y, X→Y→Z→X, X→Z→Y→X — so a loss that only appears when two
//     encoders disagree (rather than when one is self-consistent) is visible.
//
// A chain starts from the file's own parsed [Score] and then serializes/reparses
// through each format in turn; the final score is compared to the FIRST parse,
// not to the file, so the source reader's own gaps do not count against the
// chain.
//
// Invariants checked, in increasing strictness:
//   notes    — multiset of (midi pitch, duration fraction) over ALL voices
//   sounding — total sounded duration (catches a tuplet/dot mis-encoding that
//              preserves the note count)
//   state    — the clef/key sequence measure by measure
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:crisp_notation_core/crisp_notation_core.dart';

/// Formats that can both WRITE and READ a [Score] — the round-trippable set.
const _codecs = <String>[
  'musicxml',
  'mei',
  'kern',
  'abc',
  'mscx',
  'ly',
  'midi',
  'gp',
];

String _write(String fmt, Score s) => switch (fmt) {
      'musicxml' => scoreToMusicXml(s),
      'mei' => scoreToMei(s),
      'kern' => scoreToKern(s),
      'abc' => scoreToAbc(s),
      'mscx' => scoreToMscx(s),
      'ly' => scoreToLilyPond(s),
      'gp' => scoreToGpif(s),
      // MIDI is binary; base64 keeps the chain a uniform String pipeline.
      'midi' => base64Encode(scoreToMidi(s)),
      _ => throw FormatException('no writer for $fmt'),
    };

Score _read(String fmt, String data) => switch (fmt) {
      'musicxml' => scoreFromMusicXml(data),
      'mei' => scoreFromMei(data),
      'kern' => scoreFromKern(data),
      'abc' => scoreFromAbc(data),
      'mscx' => scoreFromMscx(data),
      'ly' => scoreFromLilyPond(data),
      'gp' => scoreFromGpif(data),
      'midi' => scoreFromMidi(Uint8List.fromList(base64Decode(data))),
      _ => throw FormatException('no reader for $fmt'),
    };

/// Parses the ORIGINAL corpus file (its on-disk format) into a [Score].
Score _loadSource(String fmt, File f) {
  Uint8List bytes() => Uint8List.fromList(f.readAsBytesSync());
  return switch (fmt) {
    'musicxml' => scoreFromMusicXml(f.readAsStringSync()),
    'mxl' => scoreFromMusicXml(readMusicXmlFromMxl(bytes())),
    'mscx' => scoreFromMscx(f.readAsStringSync()),
    'mscz' => scoreFromMscx(readMscxFromMscz(bytes())),
    'ly' => scoreFromLilyPond(f.readAsStringSync()),
    'krn' => scoreFromKern(f.readAsStringSync()),
    'abc' => scoreFromAbc(f.readAsStringSync()),
    'midi' => scoreFromMidi(bytes()),
    'gabc' => scoreFromGabc(f.readAsStringSync()),
    'gp' => scoreFromGpif(readGpifFromGp(bytes())),
    _ => throw FormatException('unsupported source format $fmt'),
  };
}

List<String> _notes(Score s) {
  final out = <String>[];
  for (final m in s.measures) {
    for (final v in [m.elements, m.voice2, m.voice3, m.voice4]) {
      for (final e in v) {
        if (e is NoteElement) {
          for (final p in e.pitches) {
            final f = e.duration.toFraction();
            out.add('${p.midiNumber}:${f.numerator}/${f.denominator}');
          }
        }
      }
    }
  }
  return out..sort();
}

String _sounding(Score s) {
  var num = 0, den = 1;
  for (final m in s.measures) {
    final f = m.totalDuration;
    num = num * f.denominator + f.numerator * den;
    den = den * f.denominator;
    final g = num.gcd(den == 0 ? 1 : den);
    if (g > 1) {
      num ~/= g;
      den ~/= g;
    }
  }
  return '$num/$den';
}

String _state(Score s) {
  final out = <String>[];
  var clef = s.clef, key = s.keySignature;
  for (final m in s.measures) {
    if (m.clefChange != null) clef = m.clefChange!;
    if (m.keyChange != null) key = m.keyChange!;
    out.add('${clef.name}/${key.fifths}');
  }
  return out.join(',');
}

/// Describes what musical features a file actually exercises.
String _shape(Score s) {
  final voices = [
    for (final m in s.measures)
      [m.voice2, m.voice3, m.voice4].where((v) => v.isNotEmpty).length,
  ].fold<int>(0, (a, b) => a > b ? a : b);
  final clefChanges = s.measures.where((m) => m.clefChange != null).length;
  final keyChanges = s.measures.where((m) => m.keyChange != null).length;
  return 'voices=${voices + 1} clefChanges=$clefChanges keyChanges=$keyChanges';
}

void main(List<String> a) {
  if (a.length < 3) {
    stderr.writeln('usage: roundtrip_matrix <files.json> <root> <report.json> '
        '[--triples N]');
    exit(64);
  }
  final files = (jsonDecode(File(a[0]).readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final root = a[1];
  var triples = 0;
  for (var i = 3; i < a.length - 1; i++) {
    if (a[i] == '--triples') triples = int.parse(a[i + 1]);
  }

  // Chains: every ordered pair X→Y→X, plus a deterministic sample of triples.
  final chains = <List<String>>[];
  for (final x in _codecs) {
    for (final y in _codecs) {
      if (x != y) chains.add([x, y, x]);
    }
  }
  if (triples > 0) {
    final all = <List<String>>[];
    for (final x in _codecs) {
      for (final y in _codecs) {
        for (final z in _codecs) {
          if (x != y && y != z && x != z) all.add([x, y, z, x]);
        }
      }
    }
    // Deterministic stride so the sample is reproducible without a RNG.
    final stride = (all.length / triples).ceil().clamp(1, all.length);
    for (var i = 0;
        i < all.length && chains.length < 56 + triples;
        i += stride) {
      chains.add(all[i]);
    }
  }

  final results = <Map<String, dynamic>>[];
  final chainFail = <String, int>{};
  final chainRun = <String, int>{};
  final pairLoss = <String, Set<String>>{};

  for (final fRow in files) {
    final path = fRow['path'] as String;
    final srcFmt = fRow['format'] as String;
    final f = File('$root/$path');
    if (!f.existsSync()) continue;
    Score base;
    try {
      base = _loadSource(srcFmt, f);
    } catch (e) {
      results.add({'file': path, 'status': 'source-unreadable', 'error': '$e'});
      continue;
    }
    final wantNotes = _notes(base);
    if (wantNotes.isEmpty) continue;
    final wantSound = _sounding(base);
    final wantState = _state(base);

    for (final chain in chains) {
      final name = chain.join('→');
      chainRun[name] = (chainRun[name] ?? 0) + 1;
      var cur = base;
      String? threw;
      try {
        for (final fmt in chain) {
          cur = _read(fmt, _write(fmt, cur));
        }
      } catch (e) {
        threw = e.toString().replaceAll('\n', ' ');
        if (threw.length > 120) threw = threw.substring(0, 120);
      }
      final gotNotes = threw == null ? _notes(cur) : const <String>[];
      final notesOk =
          threw == null && gotNotes.join('|') == wantNotes.join('|');
      final soundOk = threw == null && _sounding(cur) == wantSound;
      final stateOk = threw == null && _state(cur) == wantState;
      if (!notesOk || !soundOk) {
        chainFail[name] = (chainFail[name] ?? 0) + 1;
        // Attribute the loss to the format that is not the anchor.
        for (final fmt in chain.toSet()) {
          if (fmt != chain.first) {
            (pairLoss[fmt] ??= <String>{}).add(chain.first);
          }
        }
      }
      results.add({
        'file': path,
        'sourceFormat': srcFmt,
        'shape': _shape(base),
        'chain': name,
        'threw': threw,
        'notesOk': notesOk,
        'soundingOk': soundOk,
        'stateOk': stateOk,
        'wantNotes': wantNotes.length,
        'gotNotes': gotNotes.length,
      });
    }
    stdout.writeln('  ${path.split('/').last.padRight(42).substring(0, 42)}'
        '  ${_shape(base)}  chains=${chains.length}');
  }

  File(a[2]).writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert({
      'files': files.length,
      'chains': chains.length,
      'results': results,
    }),
  );

  final failedChains = chainFail.entries.toList()
    ..sort((x, y) => y.value.compareTo(x.value));
  final clean = chainRun.keys.where((k) => !chainFail.containsKey(k)).length;
  stdout.writeln('\n=== round-trip permutation matrix ===');
  stdout.writeln('files=${files.length} chains=${chains.length} '
      'runs=${results.length}');
  stdout.writeln('chains clean on EVERY file: $clean / ${chainRun.length}');
  stdout.writeln('\nchains with losses (fails / runs):');
  for (final e in failedChains.take(28)) {
    stdout.writeln('  ${e.key.padRight(26)} ${e.value}/${chainRun[e.key]}');
  }
}
