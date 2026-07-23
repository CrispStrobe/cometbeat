// The Viterbi guitar-tab arranger — assigns (string, fret) minimising hand
// movement + chord span. Pure Dart, no widgets. Standard-guitar string MIDIs:
// E2=40 A2=45 D3=50 G3=55 B3=59 E4=64 (string index 0 = top line = high E).

import 'package:comet_beat/features/games/composition/tab_arranger.dart';
import 'package:crisp_notation/crisp_notation.dart' show Tuning;
import 'package:flutter_test/flutter_test.dart';

/// The sounding MIDI of every fretted position in an arrangement (flattened).
/// The stretch a fretting demands: highest minus lowest *fretted* fret. Open
/// strings need no finger, so they never widen it.
int _span(Fretting f) {
  final fretted = f.values.where((v) => v > 0).toList();
  if (fretted.length < 2) return 0;
  fretted.sort();
  return fretted.last - fretted.first;
}

List<int> _sounding(List<Fretting> a, Tuning t, {int capo = 0}) => [
      for (final col in a)
        for (final e in col.entries)
          t.strings[e.key].midiNumber + e.value + capo,
    ];

void main() {
  final guitar = Tuning.standardGuitar;

  test('preserves column count and order (rests included)', () {
    final a = arrangeTab(
      [
        [60],
        const [], // rest
        [64],
      ],
      guitar,
    );
    expect(a, hasLength(3));
    expect(a[1], isEmpty); // the rest stays an empty column
  });

  test('every chosen position actually sounds the requested pitch', () {
    final tune = [60, 62, 64, 65, 67, 69, 71, 72].map((m) => [m]).toList();
    final a = arrangeTab(tune, guitar);
    expect(_sounding(a, guitar)..sort(), [60, 62, 64, 65, 67, 69, 71, 72]);
  });

  test(
      'stays in position instead of taking a distant lower fret (beats greedy)',
      () {
    // From D#5 (only high-E fret 11) to A#4: greedy picks the LOWER fret 6 on
    // the high-E string (a 5-fret jump); the arranger keeps the hand at 11 by
    // taking A#4 on the B string (fret 11) — same position, no jump.
    final a = arrangeTab(
      [
        [75], // D#5 → high-E fret 11
        [70], // A#4 → high-E f6  OR  B-string f11
      ],
      guitar,
    );
    expect(a[0].values.single, 11);
    expect(
      a[1].values.single,
      11,
      reason: 'held the position, not the low fret',
    );
    expect(_sounding(a, guitar)..sort(), [70, 75]);
  });

  test('a chord is seated on distinct strings with a small span', () {
    // C major triad C4 E4 G4 — should take one playable shape, one note/string.
    final a = arrangeTab(
      [
        [60, 64, 67],
      ],
      guitar,
    );
    final col = a.single;
    expect(col, hasLength(3)); // three distinct strings
    expect(col.keys.toSet(), hasLength(3));
    expect(_sounding(a, guitar)..sort(), [60, 64, 67]);
  });

  test('unreachable pitches are dropped, not crashed on', () {
    // 20 = way below the lowest string (E2=40); no position exists.
    final a = arrangeTab(
      [
        [20],
        [60],
      ],
      guitar,
    );
    expect(a[0], isEmpty); // dropped
    expect(_sounding(a, guitar), contains(60));
  });

  test('a capo shrinks the frets for the same fretted pitch', () {
    // G4 (67) is fretted (not an open string), so the capo cleanly shifts it.
    final open = arrangeTab(
      [
        [67],
      ],
      guitar,
    );
    final capo2 = arrangeTab(
      [
        [67],
      ],
      guitar,
      capo: 2,
    );
    expect(capo2.single.values.first, open.single.values.first - 2);
    expect(_sounding(capo2, guitar, capo: 2), [67]); // still sounds G4
  });

  test('empty input yields empty output', () {
    expect(arrangeTab(const [], guitar), isEmpty);
  });

  test('a TabPositionModel biases the local choice (seam routes)', () {
    // E4 (64) is normally taken open on the high-E string (fret 0). A model that
    // strongly prefers fret 5 on the B string (index 1) should win the column.
    final a = arrangeTab(
      [
        [64],
      ],
      guitar,
      model: _FavourModel((1, 5)),
    );
    expect(a.single[1], 5);
    expect(_sounding(a, guitar), [64]); // still the requested pitch
  });

  test('arrangeTab consults the TabArranger.shared global when no model given',
      () {
    addTearDown(() => TabArranger.shared = null);
    // Wire the same fake via the global (what the app does with TabLabeler) —
    // no explicit `model` arg, yet the global biases the choice.
    TabArranger.shared = _FavourModel((1, 5));
    final a = arrangeTab(
      [
        [64],
      ],
      guitar,
    );
    expect(a.single[1], 5); // the global model drove it
    expect(_sounding(a, guitar), [64]);
  });

  test('a hand-span cap keeps an impossible stretch out of the candidates', () {
    // Regression: found by benchmarking 337 Mutopia guitar works. `move` (1.0
    // per fret) outbids `span` (0.6 per fret), so before the cap the Viterbi
    // would buy a 13-fret stretch to avoid shifting the hand — for a plain C
    // major chord that has an easy 2-fret voicing. Span was only ever a soft
    // cost; nothing rejected shapes no hand can make.
    const cMajor = [60, 64, 67, 72];
    final capped = arrangeTab([cMajor], guitar, maxFret: 24);
    expect(
      _span(capped.single),
      lessThanOrEqualTo(kHandSpan),
      reason: 'the default cap must exclude unreachable shapes',
    );
    // Every pitch still sounds — the cap narrows the choice, it does not drop
    // notes.
    expect(_sounding(capped, guitar)..sort(), cMajor);

    // Opting out restores the old, unconstrained search space.
    final uncapped = arrangeTab([cMajor], guitar, maxFret: 24, maxSpan: null);
    expect(_sounding(uncapped, guitar)..sort(), cMajor);
  });

  test('a column with no shape inside the cap falls back, never to silence',
      () {
    // C2 + C6: five octaves apart, unreachable inside any hand span. The cap
    // must not delete the column — a wide shape beats no notes at all.
    const wide = [36, 84];
    final a = arrangeTab([wide], guitar, maxFret: 24, maxSpan: 2);
    expect(a, hasLength(1));
    expect(a.single, isNotEmpty, reason: 'fell back rather than vanishing');
  });

  test('the hand-span cap still binds when a model drives the local cost', () {
    // With a model active, local() returns the model score and NEVER calls
    // _localCost — so the SOFT span cost disappears and the hard cap is the
    // only thing left preventing an unplayable shape. A model is free to adore
    // a position that would stretch the hand 13 frets; the cap must still win,
    // because candidates are filtered before the model ever scores them.
    addTearDown(() => TabArranger.shared = null);
    const cMajor = [60, 64, 67, 72];

    // Favour the high-E string at fret 14 — reachable for the top note alone,
    // but only inside a very wide voicing of this chord.
    TabArranger.shared = _FavourModel((0, 14));
    final withModel = arrangeTab([cMajor], guitar, maxFret: 24);
    expect(
      _span(withModel.single),
      lessThanOrEqualTo(kHandSpan),
      reason: 'a model must not be able to introduce an unplayable stretch',
    );
    expect(_sounding(withModel, guitar)..sort(), cMajor);

    // Opting out of the cap is the only way that voicing becomes reachable.
    final uncapped = arrangeTab([cMajor], guitar, maxFret: 24, maxSpan: null);
    expect(_sounding(uncapped, guitar)..sort(), cMajor);
  });

  test('the shared model applies TabArranger.sharedSpanCost (compact shapes)',
      () {
    addTearDown(() {
      TabArranger.shared = null;
      TabArranger.sharedSpanCost = 0.5;
    });
    // The tuned default the app relies on to hit the 84% / span-1.47 benchmark.
    expect(TabArranger.sharedSpanCost, 0.5);

    // A model that scores EVERY reachable position equally leaves span the only
    // differentiator, so the span penalty alone decides the voicing. A large
    // penalty must never widen the shape vs none (monotonic), and for a chord
    // with both a tight and a spread option it strictly tightens it.
    const cMajor = [60, 64, 67, 72];
    TabArranger.shared = _FlatModel();

    TabArranger.sharedSpanCost = 0.0;
    final loose = arrangeTab([cMajor], guitar);
    TabArranger.sharedSpanCost = 5.0;
    final tight = arrangeTab([cMajor], guitar);

    expect(_span(tight.single), lessThanOrEqualTo(_span(loose.single)));
    expect(_sounding(tight, guitar)..sort(), cMajor); // still the same chord
  });
}

/// Scores every reachable position of every column equally — so the arranger's
/// span term (not the emission) picks the voicing. Lets a test isolate the span
/// penalty from the model's own preferences.
class _FlatModel implements TabPositionModel {
  @override
  List<Map<(int, int), double>?>? score(
    List<List<int>> columns,
    Tuning tuning, {
    int capo = 0,
    int maxFret = 20,
  }) =>
      [
        for (final col in columns)
          {
            for (final midi in col)
              for (var s = 0; s < tuning.strings.length; s++)
                if (midi - tuning.strings[s].midiNumber - capo
                    case final int fret when fret >= 0 && fret <= maxFret)
                  (s, fret): 0.0,
          },
      ];
}

/// A stand-in [TabPositionModel] that lavishes score on one position and stays
/// neutral (null → heuristic) elsewhere — enough to prove the seam is consulted.
class _FavourModel implements TabPositionModel {
  _FavourModel(this.favoured);
  final (int, int) favoured;

  @override
  List<Map<(int, int), double>?>? score(
    List<List<int>> columns,
    Tuning tuning, {
    int capo = 0,
    int maxFret = 20,
  }) =>
      [
        for (final _ in columns) {favoured: 100.0},
      ];
}
