import 'dart:convert';
import 'dart:io';
import 'dart:math';
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
/// One write-then-read hop through a format.
///
/// A single function rather than a writer/reader pair because not every codec
/// serialises to TEXT — MIDI is bytes — and the harness only ever needs the
/// round trip, never the intermediate.
typedef Hop = Score Function(Score);

/// The formats that can express a score and read it back.
///
/// GP and MIDI joined late. Both are bidirectional and both were absent, which
/// mattered more than any amount of extra chain depth: adding two formats takes
/// the ordered-pair matrix from 36 cells to 64, over codecs with no
/// cross-format coverage at all. GP in particular carries the string/fret data
/// the app ships.
const _formats = [
  'musicxml',
  'mei',
  'kern',
  'abc',
  'lilypond',
  'musescore',
  'gp',
  'midi',
];

/// Whether any meter in [s] has a measure shorter than a sixteenth, which the
/// MIDI reader's sixteenth-unit grid rounds to a zero-length bar.
bool _hasZeroCapacityMeter(Score s) {
  bool zero(TimeSignature? t) => t != null && t.beats * 16 ~/ t.beatUnit == 0;
  if (zero(s.timeSignature)) return true;
  for (final m in s.measures) {
    if (zero(m.timeChange)) return true;
  }
  return false;
}

Hop _hopFor(String f) => switch (f) {
      'musicxml' => (s) => scoreFromMusicXml(scoreToMusicXml(s)),
      'mei' => (s) => scoreFromMei(scoreToMei(s)),
      'kern' => (s) => scoreFromKern(scoreToKern(s)),
      'abc' => (s) => scoreFromAbc(scoreToAbc(s)),
      'lilypond' => (s) => scoreFromLilyPond(scoreToLilyPond(s)),
      'musescore' => (s) => scoreFromMscx(scoreToMscx(s)),
      'gp' => (s) => scoreFromGpif(scoreToGpif(s)),
      'midi' => (s) => scoreFromMidi(scoreToMidi(s)),
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

/// Compare everything BUT pitch and rhythm as well, under `--rich`.
///
/// Off by default so the historical numbers stay comparable, and because the
/// two axes fail for different reasons and are worth reading apart.
bool _rich = false;

List<String> _content(Score s) {
  final out = <String>[];
  for (final m in s.measures) {
    for (var v = 0; v < (_allVoices ? 4 : 1); v++) {
      // Ratio per element index, so a note can be scaled without searching the
      // spans again for every one.
      final scale = <int, Fraction>{};
      for (final t in m.tuplets) {
        if (t.voice != v) continue;
        for (var i = t.startIndex; i <= t.endIndex; i++) {
          scale[i] = Fraction(t.normal, t.actual);
        }
      }
      // `voiceAt`, NOT `voices[v]`. `Measure.voices` is a COMPACTING view — it
      // drops empty voices — while `TupletSpan.voice` is an ABSOLUTE index, so
      // indexing one by the other pairs voice 3's notes with voice 2's tuplets
      // the moment a voice is empty. The same confusion crashed the layout
      // engine; here it would have invented failures and sent me chasing them.
      final elements = m.voiceAt(v);
      for (var i = 0; i < elements.length; i++) {
        final e = elements[i];
        if (e is! NoteElement) continue;
        final sounding = e.duration.toFraction() * (scale[i] ?? Fraction(1, 1));
        final pitches = e.pitches.map((p) => p.midiNumber).toList()..sort();
        final buf = StringBuffer()
          ..write(v == 0 ? '' : 'v$v:')
          ..write(pitches.join('.'))
          ..write('@$sounding');
        if (_rich) buf.write(_noteExtras(e));
        out.add(buf.toString());
      }
    }
    if (_rich) {
      final bar = _measureExtras(m);
      if (bar.isNotEmpty) out.add('bar{$bar}');
    }
  }
  if (_rich) {
    out.addAll(_scoreExtras(s));
    // Metadata was NOT compared at all until now, so `ScoreMetadata.words`
    // (ABC's `W:` verse text) was invisible the moment it was added — a new
    // field is only as tested as the signature that looks at it.
    final m = s.metadata;
    for (final (k, v) in [
      ('title', m.title),
      ('composer', m.composer),
      ('lyricist', m.lyricist),
      ('copyright', m.copyright),
    ]) {
      if (v != null && v.isNotEmpty) out.add('meta:$k=$v');
    }
    for (final (i, w) in m.words.indexed) {
      out.add('meta:words[$i]=$w');
    }
  }
  return out;
}

/// Everything about a NOTE beyond its pitch and length.
///
/// Omitted from the signature the corpus sweep ran with for its first
/// 634,044 round trips, which is why that number means "pitches and rhythms
/// survive" and nothing stronger. Each field is written only when it is set, so
/// an ordinary note's signature is unchanged and a diff stays readable.
String _noteExtras(NoteElement e) {
  final parts = <String>[
    if (e.tieToNext) 'tie',
    if (e.articulations.isNotEmpty)
      'art:${(e.articulations.map((a) => a.name).toList()..sort()).join(',')}',
    if (e.ornament != null) 'orn:${e.ornament!.name}',
    if (e.graceNotes.isNotEmpty)
      'grace:${e.graceStyle.name}:'
          '${e.graceNotes.map((p) => p.midiNumber).join('.')}',
    if (e.fingerings.isNotEmpty) 'fing:${e.fingerings.join(',')}',
    if (e.arpeggio != null) 'arp:${e.arpeggio!.name}',
    if (e.tremolo != null) 'trem:${e.tremolo}',
    if (e.notehead != NoteheadShape.normal) 'head:${e.notehead.name}',
  ];
  return parts.isEmpty ? '' : '[${parts.join(' ')}]';
}

/// Per-bar structure: the mid-score changes and repeat marks.
String _measureExtras(Measure m) => [
      if (m.clefChange != null) 'clef:${m.clefChange!.name}',
      if (m.keyChange != null) 'key:${m.keyChange!.fifths}',
      if (m.timeChange != null) 'time:${m.timeChange}',
      if (m.startRepeat) 'repeatStart',
      if (m.endRepeat) 'repeatEnd',
      if (m.volta != null) 'volta:${m.volta}',
      if (m.multiRest != null) 'multiRest:${m.multiRest}',
      if (m.navigation != null) 'nav:${m.navigation!.name}',
    ].join(' ');

/// Score-level attachments, keyed by the NOTE they point at rather than by the
/// element id — ids are regenerated by every reader, so comparing them across a
/// round trip compares nothing. The index of the note in play order is stable.
List<String> _scoreExtras(Score s) {
  final index = <String, int>{};
  var n = 0;
  for (final m in s.measures) {
    for (var v = 0; v < 4; v++) {
      for (final e in m.voiceAt(v)) {
        if (e is NoteElement && e.id != null) index[e.id!] = n++;
      }
    }
  }
  String at(String id) => '${index[id] ?? -1}';
  final out = <String>[
    for (final l in s.lyrics) 'lyric@${at(l.elementId)}:${l.verse}:${l.text}',
    for (final d in s.dynamics) 'dyn@${at(d.elementId)}:${d.level.name}',
    for (final a in s.annotations) 'ann@${at(a.elementId)}:${a.text}',
    // Chord symbols were the last channel this signature did not look at, and
    // that is exactly why three codecs could read them and silently drop them
    // on write without a single cell going red.
    for (final c in s.chordSymbols)
      'chord@${at(c.elementId)}:${c.root.step.name}${c.root.alter}'
          ':${c.quality.name}${c.bass == null ? '' : '/${c.bass!.step.name}'}',
    for (final sl in s.slurs) 'slur@${at(sl.startId)}-${at(sl.endId)}',
    for (final h in s.hairpins)
      'hairpin@${at(h.startId)}-${at(h.endId)}:${h.type.name}',
    // The rest of the general-notation channels. `Score` has 44 of them and
    // this signature checked 6, which is how chord symbols could be dropped by
    // five of the six codecs with every cell green — and, under the same
    // blindness, how `\tempo` stayed write-only, how a glissando went out as
    // MusicXML's `<slide>`, and how `cueNoteIds`/`portamentos` stayed dead.
    // A concept nothing compares is a concept nothing protects.
    for (final o in s.ottavas)
      'ottava@${at(o.startId)}-${at(o.endId)}:${o.down}',
    for (final p in s.pedals) 'pedal@${at(p.startId)}-${at(p.endId)}',
    for (final t in s.trillExtensions)
      'trillext@${at(t.startId)}-${at(t.endId)}',
    for (final g in s.glissandos) 'gliss@${at(g.startId)}-${at(g.endId)}',
    for (final p in s.portamentos) 'port@${at(p.startId)}-${at(p.endId)}',
    for (final l in s.laissezVibrer) 'lv@${at(l.noteId)}',
    for (final f in s.figuredBass) 'figbass@${at(f.noteId)}:${f.figures}',
    for (final c in s.cueNoteIds) 'cue@${at(c)}',
    // ⚠️ To the nearest bpm, deliberately. LilyPond CANNOT carry more — a
    // fractional `\tempo` is a syntax error there, not a rounding choice — so
    // comparing exactly reports a false failure on every score whose tempo came
    // from MuseScore's quarters-per-second float (1.5333 * 60 = 91.9998).
    // A signature must not demand more precision than a target format has.
    if (s.tempo != null) 'tempo:${s.tempo!.quarterBpm.round()}',
  ]..sort();
  return out;
}

void main(List<String> rawArgs) {
  _allVoices = rawArgs.contains('--voices');
  _rich = rawArgs.contains('--rich');
  final chain = rawArgs.contains('--chain');
  final fixedPoint = rawArgs.contains('--fixed-point');
  final fixedPointPasses = int.tryParse(
        rawArgs
            .firstWhere((a) => a.startsWith('--passes='), orElse: () => '')
            .replaceFirst('--passes=', ''),
      ) ??
      4;
  final walkLength = int.tryParse(
        rawArgs
            .firstWhere((a) => a.startsWith('--walk='), orElse: () => '')
            .replaceFirst('--walk=', ''),
      ) ??
      0;
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
  // ⚠️ A per-2,000-file heartbeat cannot tell a slow stretch from a HANG. One
  // corpus file spun a codec for 5.5 hours at full CPU inside a single such
  // block, and the log looked identical to "still working" the whole time —
  // there was no way to learn even which file it was without re-running.
  //
  // The current file goes to a sidecar, overwritten each time, so the answer is
  // always one `cat` away and costs nothing to keep.
  final marker =
      File(args.length > 1 ? '${args[1]}.current' : '/tmp/xrt.current');
  for (final f in files) {
    if (++seen % 2000 == 0) {
      final ok = passed.values.fold(0, (a, b) => a + b);
      final n = tried.values.fold(0, (a, b) => a + b);
      stdout.writeln('… $seen/${files.length} files, $ok/$n round trips');
    }
    try {
      marker.writeAsStringSync('$seen\t${f.path}\n');
    } catch (_) {
      // A sidecar that cannot be written must never stop the sweep.
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
      // 🛑 WORKAROUND, not a format limit: `scoreFromMidi` HANGS FOREVER on a
      // meter whose measure is shorter than a sixteenth. Its internal grid is
      // sixteenth-note units, so such a bar has capacity ZERO and the packing
      // loop never advances — one corpus file (`11 for pdf with custom
      // ambitus.ly`, a legitimate `\time 1/32` used so an early-music ambitus
      // is not barred) froze a full sweep for 5.5 hours at 100% CPU.
      //
      // Skipped rather than counted, so the cell reports what it measured.
      // Remove this the moment the reader is fixed — it is scoped on the board.
      if (to == 'midi' && _hasZeroCapacityMeter(from)) return null;
      tried[pair] = (tried[pair] ?? 0) + 1;
      try {
        final round = _hopFor(to)(from);
        final got = _content(round);
        if (_sameContent(before, got)) {
          passed[pair] = (passed[pair] ?? 0) + 1;
          return round;
        }
        examples.putIfAbsent(
          pair,
          // "entries", not "notes": under --rich the signature also holds bar
          // markers, lyrics, dynamics, annotations and metadata, so calling the
          // count notes reads as note LOSS when a format simply does not carry
          // text. It misled me into diagnosing a GP note-loss bug that did not
          // exist — GP was dropping lyrics and annotations, and its notes were
          // exact.
          () => '$name: ${before.length} entries -> ${got.length}; '
              'first diff ${_firstDiff(before, got)}',
        );
      } catch (e) {
        var m = e.toString().replaceAll('\n', ' ');
        if (m.length > 70) m = m.substring(0, 70);
        examples.putIfAbsent(pair, () => '$name: THREW $m');
      }
      return null;
    }

    // FIXED POINT: apply each codec repeatedly. `read(write(x))` being lossless
    // does NOT imply `read(write(read(write(x))))` is — a codec that normalises
    // on the first pass and then drifts a little on each one looks perfect under
    // single application. That failure mode is not hypothetical here: the
    // relative-octave creep compounded across voice splits until pitches left
    // the MIDI range. Pass 1 may legitimately renormalise (a respelled tuplet,
    // a re-barred overfull measure), so stability is required from pass 2 on.
    if (fixedPoint) {
      for (final to in _formats) {
        Score? cur;
        List<String>? settled;
        for (var pass = 1; pass <= fixedPointPasses; pass++) {
          final input = cur ?? src;
          try {
            cur = _hopFor(to)(input);
          } catch (e) {
            var m = e.toString().replaceAll('\n', ' ');
            if (m.length > 70) m = m.substring(0, 70);
            examples.putIfAbsent('fix:$to', () => '$name: pass $pass THREW $m');
            tried['fix:$to'] = (tried['fix:$to'] ?? 0) + 1;
            cur = null;
            break;
          }
          final now = _content(cur);
          if (pass == 1) {
            settled = now;
            continue;
          }
          final before = settled!;
          tried['fix:$to'] = (tried['fix:$to'] ?? 0) + 1;
          if (_sameContent(before, now)) {
            passed['fix:$to'] = (passed['fix:$to'] ?? 0) + 1;
          } else {
            examples.putIfAbsent(
              'fix:$to',
              () => '$name: drifted on pass $pass; '
                  '${before.length} -> ${now.length}; '
                  'first diff ${_firstDiff(before, now)}',
            );
          }
          settled = now;
        }
      }
    }

    // RANDOM WALKS: the honest form of deeper permutations. Every ordered PAIR
    // is already covered, and a longer chain is lossless by induction over
    // whatever the pairs preserve — so enumerating 6^k buys little. What a walk
    // genuinely explores is a different INPUT DISTRIBUTION: scores shaped by our
    // own writers rather than by third parties. Sampling that beats enumerating
    // it. The seed is derived from the file path, so a failing walk reproduces.
    if (walkLength > 0) {
      final rng = Random(f.path.hashCode);
      final route = [
        for (var i = 0; i < walkLength; i++)
          _formats[rng.nextInt(_formats.length)],
      ];
      var cur = src;
      var expect = want;
      for (var i = 0; i < route.length; i++) {
        final label = 'walk:${route.sublist(0, i + 1).join('>')}';
        final next = hop(cur, expect, route[i], label);
        if (next == null) break;
        cur = next;
        expect = _content(cur);
        if (expect.isEmpty) break;
      }
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
