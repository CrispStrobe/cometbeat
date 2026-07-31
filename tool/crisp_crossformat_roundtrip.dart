import 'dart:convert';
import 'dart:io';
// ignore: depend_on_referenced_packages
import 'package:crisp_notation_core/crisp_notation_core.dart';

/// CROSS-format round-trips over real files: read A, write B, read B, compare.
///
/// The existing property matrix only does `read(write(x)) == x` on scores WE
/// generated, so it exercises exactly the subset our own writers emit. That is
/// structurally blind to anything only third-party files contain — the gap that
/// hid the LilyPond `\<` truncation and the UTF-16 MusicXML rejection.
///
/// This drives real corpus files through every writer/reader pair instead, so a
/// disagreement is a bug in one of OUR codecs rather than a property of the
/// music. The comparison is the note content — pitch and duration in order —
/// because that is what every format shares; layout, beaming and text
/// legitimately differ between them.
///
/// Usage:
/// `dart run tool/crisp_crossformat_roundtrip.dart <dir> [out.json] [perExt]`
///
/// `perExt` caps how many source files of each extension are used, so a
/// 45,000-file corpus can be sampled without waiting hours for a signal.
typedef Writer = String Function(Score);
typedef Reader = Score Function(String);

/// The formats that can express a single-staff score in text and read it back.
const _formats = ['musicxml', 'mei', 'kern', 'abc', 'lilypond', 'musescore'];

Writer _writerFor(String f) => switch (f) {
      'musicxml' => scoreToMusicXml,
      'mei' => scoreToMei,
      'kern' => scoreToKern,
      'abc' => scoreToAbc,
      'lilypond' => scoreToLilyPond,
      'musescore' => scoreToMscx,
      _ => throw ArgumentError(f),
    };

Reader _readerFor(String f) => switch (f) {
      'musicxml' => scoreFromMusicXml,
      'mei' => scoreFromMei,
      'kern' => scoreFromKern,
      'abc' => scoreFromAbc,
      'lilypond' => scoreFromLilyPond,
      'musescore' => scoreFromMscx,
      _ => throw ArgumentError(f),
    };

String _text(File f) {
  final b = f.readAsBytesSync();
  if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
    final u = <int>[];
    for (var i = 2; i + 1 < b.length; i += 2) {
      u.add((b[i + 1] << 8) | b[i]);
    }
    return String.fromCharCodes(u);
  }
  try {
    return utf8.decode(b);
  } on FormatException {
    return String.fromCharCodes(b);
  }
}

/// The source score for a corpus file, or null if the extension is not one we
/// read.
Score? _load(File f) {
  final ext = f.path.split('.').last.toLowerCase();
  switch (ext) {
    case 'mei':
      return scoreFromMei(_text(f));
    case 'krn':
      return scoreFromKern(_text(f));
    case 'xml':
    case 'musicxml':
      return scoreFromMusicXml(_text(f));
    case 'mxl':
      return scoreFromMusicXml(readMusicXmlFromMxl(f.readAsBytesSync()));
    case 'abc':
      return scoreFromAbc(_text(f));
    case 'ly':
      return scoreFromLilyPond(_text(f));
    case 'mscx':
      return scoreFromMscx(_text(f));
    case 'mscz':
      return scoreFromMscx(readMscxFromMscz(f.readAsBytesSync()));
    default:
      return null;
  }
}

/// Pitch+duration of every note, in order — the content all formats share.
///
/// A chord's pitches are SORTED: their order within the chord is not musical
/// information, and formats legitimately serialise it differently (low-to-high
/// vs high-to-low). Comparing it raw reports a reordering as data loss and
/// buries the real failures.
///
/// The duration compared is the SOUNDING one — the notated value scaled by any
/// tuplet the note is under. Comparing the notated value instead is wrong in
/// both directions. It reports a false failure whenever a format cannot record
/// the tuplet BRACKET and the reader has to respell it: `**kern` writes only a
/// reciprocal, so a septuplet of eighths in the time of 8 comes back as the
/// conventional 7:4 of quarters — a different spelling of an identical sound,
/// and the only spelling kern can express. And it is blind in the other
/// direction, because a genuinely wrong ratio leaves the notated value intact:
/// reading 3:2 back as 5:4 changes what you hear and nothing this function used
/// to look at. Sounding duration catches that and ignores the respelling.
///
/// Voices 2-4 are compared only under `--voices`.
///
/// NOT because any format here is limited to one voice — that was an assumption
/// and it is FALSE. Measured: a 4-voice bar round-trips with all four voices
/// intact through every one of musicxml, mei, kern, abc, lilypond and musescore.
/// The flag exists so the inner-voice result can be read separately from the
/// voice-1 one, since a codec can be exact on voice 1 while mangling the rest —
/// which is precisely what five of them were doing with inner-voice tuplets.
bool _allVoices = false;

List<String> _content(Score s) {
  final out = <String>[];
  for (final m in s.measures) {
    for (var v = 0; v < (_allVoices ? m.voices.length : 1); v++) {
      // Ratio per element index, so a note can be scaled without searching the
      // spans again for every one.
      final scale = <int, Fraction>{};
      for (final t in m.tuplets) {
        if (t.voice != v) continue;
        for (var i = t.startIndex; i <= t.endIndex; i++) {
          scale[i] = Fraction(t.normal, t.actual);
        }
      }
      final elements = m.voices[v];
      for (var i = 0; i < elements.length; i++) {
        final e = elements[i];
        if (e is! NoteElement) continue;
        final sounding = e.duration.toFraction() * (scale[i] ?? Fraction(1, 1));
        final pitches = e.pitches.map((p) => p.midiNumber).toList()..sort();
        out.add('${v == 0 ? '' : 'v$v:'}${pitches.join('.')}@$sounding');
      }
    }
  }
  return out;
}

void main(List<String> rawArgs) {
  _allVoices = rawArgs.contains('--voices');
  final chain = rawArgs.contains('--chain');
  final args = rawArgs.where((a) => !a.startsWith('--')).toList();
  if (args.isEmpty) {
    stderr.writeln('Usage: crisp_crossformat_roundtrip.dart <dir> [out.json]');
    exitCode = 64;
    return;
  }
  final perExt = args.length > 2 ? int.tryParse(args[2]) : null;
  final all = Directory(args[0])
      .listSync(recursive: true)
      .whereType<File>()
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  // Spread the sample across the corpus rather than taking the first N, which
  // would be one directory and therefore one encoder's habits.
  final byExt = <String, List<File>>{};
  for (final f in all) {
    byExt.putIfAbsent(f.path.split('.').last.toLowerCase(), () => []).add(f);
  }
  final files = <File>[];
  for (final entry in byExt.entries) {
    final list = entry.value;
    if (perExt == null || list.length <= perExt) {
      files.addAll(list);
    } else {
      final step = list.length / perExt;
      for (var i = 0; i < perExt; i++) {
        files.add(list[(i * step).floor()]);
      }
    }
  }

  // pair -> counts
  final tried = <String, int>{};
  final passed = <String, int>{};
  final examples = <String, String>{};
  var sources = 0;

  // A full-corpus run is hours long and writes nothing until the end, which
  // makes it indistinguishable from a hang. One line per 2,000 files is enough
  // to see it moving and to spot a pair going bad early.
  var seen = 0;
  for (final f in files) {
    if (++seen % 2000 == 0) {
      final ok = passed.values.fold(0, (a, b) => a + b);
      final n = tried.values.fold(0, (a, b) => a + b);
      stdout.writeln('… $seen/${files.length} files, $ok/$n round trips');
    }
    Score? src;
    try {
      src = _load(f);
    } catch (_) {
      continue; // reader-level failures are a separate sweep's business
    }
    if (src == null) continue;
    final want = _content(src);
    if (want.isEmpty) continue;
    sources++;

    final name = f.path.split('/').last;
    final ext = f.path.split('.').last.toLowerCase();

    /// One hop: write [from] as [to] and read it back. Records the outcome
    /// under [pair] and returns the score, or null if the hop lost or threw.
    Score? hop(Score from, List<String> before, String to, String pair) {
      tried[pair] = (tried[pair] ?? 0) + 1;
      try {
        final round = _readerFor(to)(_writerFor(to)(from));
        final got = _content(round);
        if (_sameContent(before, got)) {
          passed[pair] = (passed[pair] ?? 0) + 1;
          return round;
        }
        examples.putIfAbsent(
          pair,
          () => '$name: ${before.length} notes -> ${got.length}; '
              'first diff ${_firstDiff(before, got)}',
        );
      } catch (e) {
        var m = e.toString().replaceAll('\n', ' ');
        if (m.length > 70) m = m.substring(0, 70);
        examples.putIfAbsent(pair, () => '$name: THREW $m');
      }
      return null;
    }

    for (final to in _formats) {
      final first = hop(src, want, to, '$ext -> $to');
      if (!chain || first == null) continue;
      // Every ORDERED pair of formats, so a chain through any two of them is
      // covered rather than just the six single hops. The second hop is judged
      // against what came out of the FIRST, not against the original file: if
      // `to` already dropped something, blaming the next codec for its absence
      // would smear one defect across five cells and hide whatever the second
      // codec does on its own.
      final mid = _content(first);
      if (mid.isEmpty) continue;
      for (final then in _formats) {
        hop(first, mid, then, '  $to => $then');
      }
    }
  }

  stdout.writeln('source files with notes: $sources');
  final pairs = tried.keys.toList()..sort();
  for (final p in pairs) {
    final t = tried[p]!;
    final ok = passed[p] ?? 0;
    final pct = t == 0 ? 0.0 : ok * 100 / t;
    // NEVER print 100.0% for a cell that missed one. Over 45,000 files a single
    // failure rounds to 100.0% at one decimal, and a `grep -v 100.0%` triage
    // then reports a clean sweep while 7 round trips are broken — which is
    // exactly what happened here. The literal count is the truth; the
    // percentage is a convenience, so mark it rather than let it lie.
    final shown = ok == t
        ? '100.0%'
        : '${pct >= 99.95 ? '<100' : pct.toStringAsFixed(1)}%';
    stdout.writeln('  ${p.padRight(24)} ${ok.toString().padLeft(5)}/'
        '${t.toString().padLeft(5)}  ${shown.padLeft(6)}'
        '${ok == t ? '' : '   e.g. ${examples[p]}'}');
  }

  if (args.length > 1) {
    final report = {
      'sources': sources,
      'tried': tried,
      'passed': passed,
      'examples': examples,
    };
    File(args[1])
        .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(report));
  }
}

bool _sameContent(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _firstDiff(List<String> a, List<String> b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) return '[$i] ${a[i]} vs ${b[i]}';
  }
  return 'length only';
}
