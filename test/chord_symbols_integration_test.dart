// Proves the APP sees the chord-symbol readers, not just the library.
//
// The app reads crisp_notation_core through a path dependency on the SHARED
// clone, so a reader change only reaches users once that clone is current. This
// test fails loudly if the app is resolving an older copy — which is a real
// failure mode here, not a hypothetical: several agents share that checkout.
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
