// How it is played, not just what.
//
// A tab column carries articulation as well as pitch: vibrato, a slide, a palm
// mute, a let-ring. Score held all of it already. Tracker held the techniques
// but dropped palm mute and let ring — they are not members of
// `TabColumn.techniques`, they are their own flags, so listing that set alone
// let a palm-muted riff come back open. A loop track held none of it, because a
// loop cell is pitch and duration and nothing else.
//
// The rule for restoring it is the interesting bit. There is no pitch to check
// a vibrato against, so articulation is only restored where the FRETTING check
// already confirmed this is the same note (see interop_fretting_carry_test).
// Identity is established once, by the thing that can prove it, and the rest
// rides along.

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/interop/project_bridge.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

TabDocument _tab() {
  final doc = TabDocument.blank(Tuning.standardGuitar, initialColumns: 0);
  doc.columns.addAll([
    const TabColumn(frets: {5: 5}, techniques: {TabTechnique.vibrato}),
    const TabColumn(frets: {5: 7}, techniques: {TabTechnique.slide}),
    const TabColumn(frets: {4: 9}, palmMute: true),
    const TabColumn(frets: {4: 11}, letRing: true),
  ]);
  return doc;
}

/// Articulation per column, in a form that is readable when it differs.
List<String> _articulation(Object document) => [
      for (final column in (document as TabDocument).columns)
        [
          ...(column.techniques.map((t) => t.name).toList()..sort()),
          if (column.palmMute) 'palmMute',
          if (column.letRing) 'letRing',
        ].join('+'),
    ];

void main() {
  group('articulation survives every waypoint', () {
    for (final waypoint in [AppMode.score, AppMode.loop, AppMode.tracker]) {
      test('through ${waypoint.name}', () {
        final original = _tab();
        final expected = _articulation(original);
        expect(
          expected,
          ['vibrato', 'slide', 'palmMute', 'letRing'],
          reason: 'the fixture itself should carry all four',
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
        expect(_articulation(back.document!), expected);
      });
    }
  });

  test('articulation is NOT restored onto notes that changed', () {
    // Same guard as the fretting: an EventAddress is a position, and an edited
    // loop has different notes at the same positions. Since a technique cannot
    // be checked against a pitch, it is only restored where the fretting check
    // passed — so editing the notes drops it rather than stamping a vibrato
    // onto whatever now sits there.
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
    expect(
      _articulation(back.document!),
      everyElement(isEmpty),
      reason: 'articulation was stamped onto notes it never belonged to',
    );
  });

  test('an unarticulated tab stays unarticulated', () {
    // The negative case: nothing should invent a technique.
    final plain = TabDocument.blank(Tuning.standardGuitar, initialColumns: 0);
    for (final fret in [0, 2, 3, 5]) {
      plain.columns.add(TabColumn(frets: {5: fret}));
    }
    for (final waypoint in [AppMode.score, AppMode.loop, AppMode.tracker]) {
      final out = ProjectBridge.convert(
        from: AppMode.tab,
        to: waypoint,
        document: plain,
      );
      final back = ProjectBridge.convert(
        from: waypoint,
        to: AppMode.tab,
        document: out.document!,
        annotations: out.annotations,
      );
      expect(
        _articulation(back.document!),
        everyElement(isEmpty),
        reason: '${waypoint.name} invented an articulation',
      );
    }
  });
}
