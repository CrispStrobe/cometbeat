// The rest of what a tab column says.
//
// After the fretting and the articulation, three things were still falling off
// a tab on its way through another mode: the DYNAMIC mark, the HAIRPIN starting
// at a column, and the CHORD DIAGRAM drawn above it. Score held them; Tracker
// and Loop did not.
//
// They follow the rule established by the fretting carry: restored only where
// the fretting check confirmed this is the same note. A dynamic cannot be
// checked against a pitch any more than a vibrato can, so it inherits its
// identity from the one thing that can be checked.

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/interop/annotation_codecs.dart';
import 'package:comet_beat/core/interop/project_bridge.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

const _chord = ChordDiagram(
  [-1, 3, 2, 0, 1, 0],
  name: 'C',
  fingers: [null, 3, 2, null, 1, null],
  // baseFret 1 and fretSpan 4 are the defaults.
);

TabDocument _tab() {
  final doc = TabDocument.blank(Tuning.standardGuitar, initialColumns: 0);
  doc.columns.addAll([
    const TabColumn(frets: {5: 5}, dynamic: DynamicLevel.pp, chord: _chord),
    const TabColumn(frets: {5: 7}, hairpin: HairpinType.crescendo),
    const TabColumn(frets: {4: 9}, dynamic: DynamicLevel.ff),
    const TabColumn(frets: {4: 11}),
  ]);
  return doc;
}

List<String> _marks(Object document) => [
      for (final column in (document as TabDocument).columns)
        [
          if (column.dynamic != null) 'dyn=${column.dynamic!.name}',
          if (column.hairpin != null) 'hair=${column.hairpin!.name}',
          if (column.chord != null) 'chord=${column.chord!.name}',
        ].join('+'),
    ];

void main() {
  group('dynamics, hairpins and chord diagrams survive every waypoint', () {
    for (final waypoint in [AppMode.score, AppMode.loop, AppMode.tracker]) {
      test('through ${waypoint.name}', () {
        final original = _tab();
        final expected = _marks(original);
        expect(
          expected,
          ['dyn=pp+chord=C', 'hair=crescendo', 'dyn=ff', ''],
          reason: 'the fixture itself should carry all three kinds',
        );

        final out = ProjectBridge.convert(
          from: AppMode.tab,
          to: waypoint,
          document: original,
        );
        expect(out.document, isNotNull);

        final back = ProjectBridge.convert(
          from: waypoint,
          to: AppMode.tab,
          document: out.document!,
          annotations: out.annotations,
        );
        expect(back.document, isNotNull);
        expect(_marks(back.document!), expected);
      });
    }

    test('a chord diagram comes back whole, not just by name', () {
      final out = ProjectBridge.convert(
        from: AppMode.tab,
        to: AppMode.loop,
        document: _tab(),
      );
      final back = ProjectBridge.convert(
        from: AppMode.loop,
        to: AppMode.tab,
        document: out.document!,
        annotations: out.annotations,
      );
      expect((back.document! as TabDocument).columns.first.chord, _chord);
    });
  });

  group('the chord-diagram codec', () {
    test('round-trips every field', () {
      expect(
        chordDiagramFromAnnotation(chordDiagramToAnnotation(_chord)),
        _chord,
      );
    });

    test('a barre and a raised base fret survive', () {
      const barre = ChordDiagram(
        [1, 3, 3, 2, 1, 1],
        name: 'F',
        baseFret: 5,
        fretSpan: 5,
        barreFret: 1,
      );
      expect(
        chordDiagramFromAnnotation(chordDiagramToAnnotation(barre)),
        barre,
      );
    });

    test('nonsense decodes to null rather than an empty grid', () {
      // An empty diagram would DRAW — a blank box above the staff is worse than
      // no diagram, because it looks like a chord nobody can play.
      expect(chordDiagramFromAnnotation(null), isNull);
      expect(chordDiagramFromAnnotation('C major'), isNull);
      expect(chordDiagramFromAnnotation(<String, Object?>{}), isNull);
      expect(chordDiagramFromAnnotation({'frets': <int>[]}), isNull);
      expect(chordDiagramFromAnnotation({'frets': 'xxx'}), isNull);
    });
  });

  test('marks are NOT restored onto notes that changed', () {
    final out = ProjectBridge.convert(
      from: AppMode.tab,
      to: AppMode.loop,
      document: _tab(),
    );
    final edited = <PatternCell>[
      for (final cell in out.document! as List<PatternCell>)
        PatternCell(
          midis:
              cell.midis == null ? null : [for (final m in cell.midis!) m + 5],
          steps: cell.steps,
        ),
    ];
    final back = ProjectBridge.convert(
      from: AppMode.loop,
      to: AppMode.tab,
      document: edited,
      annotations: out.annotations,
    );
    expect(_marks(back.document!), everyElement(isEmpty));
  });
}
