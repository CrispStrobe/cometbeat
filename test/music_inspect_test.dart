// The Looking-Glass inspector: describes a score element (note name + scale
// degree + chord/roman/function) using the analysis engine.
import 'package:comet_beat/features/games/composition/music_inspect.dart';
import 'package:crisp_notation/crisp_notation.dart' as cn;
import 'package:flutter_test/flutter_test.dart';

cn.Pitch note(String s) {
  final m = RegExp(r'^([a-g])([#b]*)(-?\d+)$').firstMatch(s)!;
  final step = cn.Step.values.firstWhere((st) => st.name == m[1]);
  final acc = m[2]!;
  final alter =
      acc.isEmpty ? 0 : (acc.startsWith('#') ? acc.length : -acc.length);
  return cn.Pitch(step, alter: alter, octave: int.parse(m[3]!));
}

cn.Score _chord(List<String> notes, String id) => cn.Score(
      clef: cn.Clef.treble,
      measures: [
        cn.Measure([
          cn.NoteElement(
            pitches: [for (final n in notes) note(n)],
            duration: const cn.NoteDuration(cn.DurationBase.whole),
            id: id,
          ),
        ]),
      ],
    );

void main() {
  test('describes a chord tone: note names + roman numeral + function', () {
    final score = _chord(['c4', 'e4', 'g4'], 'x');
    final analysis = cn.analyze(score);
    final info = inspectElement(score, 'x', analysis);

    expect(info, isNotNull);
    expect(info!.noteNames, 'C4 E4 G4');
    expect(info.chordSymbol, 'C');
    expect(info.roman, 'I');
    expect(info.function, cn.HarmonicFunction.tonic);
    expect(info.degree, contains('tonic')); // C is the tonic of C major
  });

  test('returns null for an id that is not in the score', () {
    final score = _chord(['c4', 'e4', 'g4'], 'x');
    expect(inspectElement(score, 'nope', cn.analyze(score)), isNull);
  });
}
