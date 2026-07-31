// Proves the APP sees the chord-symbol readers, not just the library.
//
// The app reads crisp_notation_core through a path dependency on the SHARED
// clone, so a reader change only reaches users once that clone is current. This
// test fails loudly if the app is resolving an older copy — which is a real
// failure mode here, not a hypothetical: several agents share that checkout.
import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chord symbols reach the app', () {
    test('a LilyPond chord track yields chord symbols', () {
      final s = scoreFromLilyPond(r'''
akkorde = \chordmode { \germanChords f4 c:7 g:m7 bes:maj7 }
melodie = \relative c' { f4 g a bes }
\score { << \new ChordNames { \akkorde } \new Staff { \melodie } >> }
''');
      expect(
        s.chordSymbols.map((c) => c.text).toList(),
        ['F', 'C7', 'Gm7', 'Bbmaj7'],
      );
      // …and the chord track still contributes no melody notes.
      expect(
        s.measures.expand((m) => m.elements).whereType<NoteElement>().length,
        4,
      );
    });

    test('a MuseScore <Harmony> yields chord symbols', () {
      final s = scoreFromMscx('''
<museScore version="1.14"><Score><Staff id="1"><Measure number="1">
  <nom1>4</nom1><den>4</den>
  <Harmony><root>14</root><extension>1</extension></Harmony>
  <Chord><durationType>quarter</durationType>
    <Note><pitch>60</pitch><tpc>14</tpc></Note></Chord>
  <Harmony><root>19</root><extension>16</extension></Harmony>
  <Chord><durationType>quarter</durationType>
    <Note><pitch>62</pitch><tpc>16</tpc></Note></Chord>
</Measure></Staff></Score></museScore>
''');
      expect(s.chordSymbols.map((c) => c.text).toList(), ['C', 'Bm']);
    });

    // Reading a chord is only half the chain — the app's song, play-along and
    // workshop views all render through `layoutSystems`, whose slicer dropped
    // every chord symbol. Reader-only tests passed throughout, so this asserts
    // the symbols survive as far as laid-out text.
    test('chord symbols survive the multi-system layout the app renders with',
        () {
      // Read from the path dependency itself rather than rootBundle: this is a
      // plain unit test with no asset bundle, and going through the real file
      // also re-checks that the shared clone is where pubspec says it is.
      final metadata = SmuflMetadata.fromJson(
        jsonDecode(
          File('../crisp_notation/packages/crisp_notation/assets/smufl/'
                  'bravura_metadata.json')
              .readAsStringSync(),
        ) as Map<String, Object?>,
      );
      final settings = LayoutSettings(metadata: metadata);

      final score = scoreFromLilyPond(r'''
akkorde = \chordmode { c1 f c g }
melodie = \relative c' { c4 d e f | f4 g a bes | c4 b a g | g4 a b c }
\score { << \new ChordNames { \akkorde } \new Staff { \melodie } >> }
''');
      expect(score.chordSymbols, hasLength(4));

      // Narrow enough to force a break, which is what the app does on a phone.
      final multi = layoutSystems(score, settings, maxWidth: 35);
      expect(
        multi.systems.length,
        greaterThan(1),
        reason: 'the slicing path must actually be exercised',
      );

      final rendered = multi.systems
          .expand((s) => s.layout.primitives.whereType<TextPrimitive>())
          .map((p) => p.text)
          .where((t) => RegExp(r'^[A-G]').hasMatch(t))
          .toList();
      expect(rendered, ['C', 'F', 'C', 'G']);
    });

    test('duration-weighted per-bar analysis is available', () {
      const score = Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement(
              pitches: [Pitch(Step.c), Pitch(Step.e), Pitch(Step.g)],
              duration: NoteDuration(DurationBase.whole),
            ),
          ]),
        ],
      );
      final a = analyze(
        score,
        weighting: HarmonicWeighting.durationWeightedPerBar,
      );
      expect(a.segments.single.chord?.symbol, 'C');
    });
  });
}
