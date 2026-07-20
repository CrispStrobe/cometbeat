// gpFretPlanFor — the bridge from the cost-based tab arranger to a GPIF fret
// plan (bin/tabconv.dart's core). Proves the arranger's string/fret choices
// reach the .gp and that a capo keeps the sounding pitches.

import 'package:comet_beat/features/games/composition/tab_gp_plan.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _midis(Score s) => s.measures
    .expand((m) => m.elements)
    .whereType<NoteElement>()
    .expand((n) => n.pitches)
    .map((p) => p.midiNumber)
    .toList();

void main() {
  final guitar = Tuning.standardGuitar;

  test('gpFretPlanFor arranges every note and the plan reaches the .gp', () {
    final score = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q d4 e4 f4', // ids e0..e3
    );
    final plan = gpFretPlanFor(score, guitar);
    expect(plan.keys, containsAll(['e0', 'e1', 'e2', 'e3']));

    final gpif = scoreToGpif(score, tuning: guitar, frettings: plan);
    // Every emitted <String>/<Fret> is exactly the arranger's choice.
    for (final id in plan.keys) {
      final f = plan[id]!.entries.single;
      expect(
        gpif,
        contains('<String>${f.key}</String></Property>'
            '<Property name="Fret"><Fret>${f.value}</Fret></Property>'),
        reason: '$id should be written at the arranged position',
      );
    }
    // ...and the .gp still sounds the original notes.
    final back = scoreFromGpif(readGpifFromGp(writeGpFromGpif(gpif)));
    expect(_midis(back), [60, 62, 64, 65]);
  });

  test('a capo keeps the sounding pitches (absolute frets stay correct)', () {
    final score = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:q a4 b4',
    );
    final capo3 = gpFretPlanFor(score, guitar, capo: 3);
    expect(capo3, isNotEmpty);
    final gpif = scoreToGpif(score, tuning: guitar, frettings: capo3);
    // open + emitted-fret must reproduce the original pitch — a wrong capo fold
    // would transpose the read-back.
    final back = scoreFromGpif(readGpifFromGp(writeGpFromGpif(gpif)));
    expect(_midis(back), _midis(score));
  });
}
