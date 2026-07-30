// BB-A0 — a real chart, audible through the band we already ship.
//
// The card's acceptance: a four-bar I–vi–IV–V chart plays through the current
// Loop Studio band in a headless render, every chord the projection cannot
// represent appears in the report, and the existing engine is not modified.
//
// The engine's envelope is six diatonic triads and one chord per bar, so most
// real charts do NOT fit — which makes the REPORT the substance of this card
// rather than a courtesy. These tests are mostly about the two different ways a
// chord can fail, because conflating them is the actual danger:
//
//   * approximated — it plays, minus its colour (`Cmaj7` → `C`);
//   * unrepresentable — it cannot play, and must NOT be bent onto something
//     nearby, because a wrong chord in a backing track makes a player doubt
//     their own reading of the chart.
//
// BB-D4a (text in) is not built yet, so `_chart` below is this file's own
// minimal "chords separated by bars" reader. It uses BB-D1's real parser for the
// chords themselves, which is the part that matters here.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_to_groove.dart';
import 'package:comet_beat/core/harmony/chord_spec_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// `'C | Am | F | G'` → a one-section chart. Bars split on `|`; a bar may hold
/// several space-separated chords; an empty bar is a held chord.
Chart _chart(
  String text, {
  int fifths = 0,
  bool minor = false,
  int tempo = 100,
}) {
  final bars = <ChartBar>[];
  for (final raw in text.split('|')) {
    final symbols = raw.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    bars.add(
      ChartBar(
        chords: [
          for (final (i, s) in symbols.indexed)
            if (parseChordSpec(s) case final spec?)
              ChartBeatChord(chord: spec, beat: i.toDouble()),
        ],
      ),
    );
  }
  return Chart(
    keyFifths: fifths,
    minor: minor,
    tempoBpm: tempo,
    sections: [ChartSection(label: 'A', bars: bars)],
  );
}

void main() {
  group('a chart that fits plays as written', () {
    test('I–vi–IV–V in C projects onto the six diatonic degrees', () {
      final p = chartToProgression(_chart('C | Am | F | G'));

      expect(p.isPlayable, isTrue);
      expect(p.isExact, isTrue, reason: 'nothing had to be compromised');
      expect(p.reductions, isEmpty);
      expect(
        p.progression!.degrees,
        [ChordDegree.i, ChordDegree.vi, ChordDegree.iv, ChordDegree.v],
      );
      expect(p.summary, 'Plays as written');
    });

    test('and in another key, by the same rule', () {
      // G major (one sharp): G–Em–C–D is the same I–vi–IV–V.
      final p = chartToProgression(_chart('G | Em | C | D', fifths: 1));
      expect(
        p.progression!.degrees,
        [ChordDegree.i, ChordDegree.vi, ChordDegree.iv, ChordDegree.v],
      );
      expect(p.reductions, isEmpty);
    });

    test('a MINOR chart projects through its relative major', () {
      // The engine has no minor mode: ChordDegree is a major-key set, and the
      // engine already models minor as "the relative-major set, +3 semitones".
      // So an A-minor chart plays the right CHORDS with relative-major numerals
      // — its tonic reads `vi`, not `i`. Mapping onto the minor tonic instead
      // would put a MAJOR triad on Am: a wrong chord, not just an odd label.
      final chart = _chart('Am | Dm | Em | Am', minor: true);
      expect(chart.tonicPitchClass, 9, reason: 'the chart is in A, not C');

      final p = chartToProgression(chart);
      expect(p.reductions, isEmpty, reason: 'all four are diatonic to C major');
      expect(p.progression!.degrees, [
        ChordDegree.vi,
        ChordDegree.ii,
        ChordDegree.iii,
        ChordDegree.vi,
      ]);
    });

    test('and a chord outside a minor key says so in ITS terms', () {
      final p = chartToProgression(_chart('Am | C#7 | Dm | Em', minor: true));
      expect(p.unrepresentable.single.detail, contains('A minor'));
      expect(p.unrepresentable.single.detail, contains('relative major'));
    });
  });

  group('it really plays — through the shipped engine, headless', () {
    test('a projected chart renders audio', () {
      final p = chartToProgression(_chart('C | Am | F | G'));
      final engine = LoopEngine()
        ..enabled.addAll({'drums', 'bass', 'chords'})
        ..progression = p.progression;

      final wav = engine.renderLoop();
      expect(wav.length, greaterThan(1000), reason: 'a real render came back');
    });

    test(
        'THE GUARD: projecting a built-in progression renders byte-identically',
        () {
      // The card requires the existing engine to be unmodified. This is the
      // strongest cheap statement of that: feed the engine a progression this
      // code BUILT, and one it already ships, and the bytes must match — so the
      // projection is provably a pure re-description, not a second arranger.
      final builtIn = kProgressions.firstWhere((p) => p.id == 'axis');
      final asText = builtIn.degrees.map(_symbolInC).join(' | ');
      final projected = chartToProgression(_chart(asText), id: builtIn.id);

      expect(
        projected.progression!.degrees,
        builtIn.degrees,
        reason: 'the round trip through text and back must be identity',
      );

      Uint8List render(Progression prog) => (LoopEngine()
            ..enabled.addAll({'drums', 'bass', 'chords'})
            ..progression = prog)
          .renderLoop();

      expect(render(projected.progression!), render(builtIn));
    });
  });

  group('what it cannot play, it says rather than bends', () {
    test('a non-diatonic chord is unrepresentable, and named', () {
      final p = chartToProgression(_chart('C | Bb7 | F | G'));

      expect(p.unrepresentable, hasLength(1));
      final bad = p.unrepresentable.single;
      expect(bad.symbol, 'Bb7');
      expect(bad.barIndex, 1, reason: 'the bar it is in, in play order');
      expect(bad.detail, contains('C major'));
      expect(
        p.progression!.degrees,
        [ChordDegree.i, ChordDegree.iv, ChordDegree.v],
        reason: 'the bar is skipped, not filled with a guess',
      );
    });

    test('a diminished chord says WHY, not just no', () {
      // vii° is the one diatonic chord the engine's enum does not contain, so
      // "not diatonic" would be a misleading reason.
      final p = chartToProgression(_chart('C | Bdim | C | C'));
      expect(p.unrepresentable.single.detail, contains('diminished'));
    });

    test('quality is matched, not just the root', () {
      // The trap: `Cm` in C major shares the tonic's root. Matching on root
      // alone would play it as a MAJOR I — a wrong chord that sounds confident.
      final p = chartToProgression(_chart('Cm | F | G | C'));
      expect(p.unrepresentable.map((r) => r.symbol), ['Cm']);
    });

    test('a chart of nothing playable is not playable, and says so', () {
      final p = chartToProgression(_chart('Bb7 | Eb7 | Ab7 | Db7'));
      expect(p.isPlayable, isFalse);
      expect(p.progression, isNull);
      expect(p.summary, contains('Nothing here can play'));
    });
  });

  group('what it plays approximately, it admits', () {
    test('a seventh is dropped, and the chord still plays', () {
      final p = chartToProgression(_chart('Cmaj7 | Am7 | F | G'));

      expect(p.unrepresentable, isEmpty, reason: 'both still play');
      expect(p.reductions, hasLength(2));
      expect(p.reductions.first.symbol, 'Cmaj7');
      expect(p.reductions.first.detail, contains('seventh'));
      expect(p.reductions.first.playedAs, 'I');
      expect(p.progression!.degrees.first, ChordDegree.i);
      expect(p.isExact, isFalse);
    });

    test('a slash bass is dropped', () {
      final p = chartToProgression(_chart('C/G | F | G | C'));
      expect(p.reductions.single.detail, contains('slash bass'));
      expect(p.progression!.degrees.first, ChordDegree.i);
    });

    test('a split bar keeps the downbeat and reports the rest', () {
      // `| Dm G |` is two chords in one bar; the engine holds one.
      final p = chartToProgression(_chart('C | Dm G | F | G'));
      final split = p.reductions.firstWhere((r) => r.symbol.contains(' '));
      expect(split.detail, contains('one chord per bar'));
      expect(split.detail, contains('1 more'));
      expect(
        p.progression!.degrees[1],
        ChordDegree.ii,
        reason: 'the downbeat chord is the one that plays',
      );
    });
  });

  group('length', () {
    test('an empty bar holds the previous chord — a chart % ', () {
      final p = chartToProgression(_chart('C | | F | G'));
      expect(
        p.progression!.degrees,
        [ChordDegree.i, ChordDegree.i, ChordDegree.iv, ChordDegree.v],
      );
    });

    test('a leading empty bar has nothing to hold, and is skipped', () {
      // Guessing a chord for it would invent harmony the chart never stated.
      final p = chartToProgression(_chart(' | C | F | G'));
      expect(p.progression!.degrees, [
        ChordDegree.i,
        ChordDegree.iv,
        ChordDegree.v,
      ]);
    });

    test('a longer chart is truncated and SAYS how much it took', () {
      final long = List.filled(8, 'C | Am | F | G').join(' | ');
      final p = chartToProgression(_chart(long));
      expect(p.barsUsed, 4);
      expect(p.barsAvailable, 32);
      expect(p.isExact, isFalse, reason: 'taking 4 of 32 is not exact');
      expect(p.summary, contains('first 4 of 32 bars'));
    });

    test('repeats are expanded before truncation, so bar indices are real', () {
      // A reduction points at a bar in PLAY order. If repeats were counted after
      // truncating, the index would refer to a bar the player never hears.
      final chart = Chart(
        sections: [
          ChartSection(
            label: 'A',
            repeatCount: 2,
            bars: [
              ChartBar(chords: [_c('C')]),
              ChartBar(chords: [_c('Bb7')]),
            ],
          ),
        ],
      );
      expect(chart.totalBars, 4);
      final p = chartToProgression(chart);
      expect(
        p.unrepresentable.map((r) => r.barIndex),
        [1, 3],
        reason: 'the Bb7 is heard twice, at two different bars',
      );
    });
  });
}

ChartBeatChord _c(String symbol) =>
    ChartBeatChord(chord: parseChordSpec(symbol)!);

/// A degree written as a chord symbol in C — for the byte-identity guard.
String _symbolInC(ChordDegree d) {
  const roots = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
  const pcToName = {0: 'C', 2: 'D', 4: 'E', 5: 'F', 7: 'G', 9: 'A', 11: 'B'};
  final name = pcToName[d.rootOffset] ?? roots.first;
  final isMinor = d.triad.length > 1 && d.triad[1] == 3;
  return isMinor ? '${name}m' : name;
}
