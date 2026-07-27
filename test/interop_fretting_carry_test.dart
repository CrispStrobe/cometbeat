// The strings you wrote it on come back.
//
// A tab says "5th string, 7th fret". Score and Tracker can both hold that —
// Score in `tabVoicings`, Tracker as one channel per string — so a trip through
// either already returned the original fretting. A LOOP track holds pitches and
// nothing else, so the way back had to re-arrange from scratch: same notes,
// different strings, a fingering the player did not choose.
//
// The fretting now rides in the side-car, keyed by the same EventAddress both
// directions already used for velocity.
//
// The interesting part is the CHECK. An address is a position, and a loop that
// was edited in between has different notes at the same positions — so a
// remembered fretting is trusted only when playing it sounds exactly the
// pitches in the cell. That makes a stale side-car harmless instead of
// dangerous: it is ignored, and the arranger decides as before.

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/interop/project_bridge.dart';
import 'package:comet_beat/core/interop/symbolic_annotation.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Frets an arranger would not pick on its own: high up the low strings.
const _awkward = [(5, 5), (5, 7), (4, 9), (4, 11)];

TabDocument _tab(Tuning tuning) {
  final doc = TabDocument.blank(tuning, initialColumns: 0);
  for (final (string, fret) in _awkward) {
    doc.columns.add(TabColumn(frets: {string: fret}));
  }
  return doc;
}

List<Map<int, int>> _frettingOf(Object document) =>
    [for (final column in (document as TabDocument).columns) column.frets];

void main() {
  group('a fretting survives every waypoint', () {
    for (final tuning in [Tuning.standardGuitar, Tuning.dadgadGuitar]) {
      for (final waypoint in [AppMode.score, AppMode.loop, AppMode.tracker]) {
        test('${tuning.name} through ${waypoint.name}', () {
          final original = _tab(tuning);
          final expected = _frettingOf(original);

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
          expect(
            _frettingOf(back.document!),
            expected,
            reason: 'the tab came back on different strings',
          );
        });
      }
    }
  });

  group('a remembered fretting is checked, not trusted', () {
    test('an edited loop falls back to the arranger', () {
      // Convert away, then REPLACE the notes. The side-car still describes the
      // old ones at the same addresses; applying it would put a real fretting
      // on the wrong pitches.
      final out = ProjectBridge.convert(
        from: AppMode.tab,
        to: AppMode.loop,
        document: _tab(Tuning.standardGuitar),
      );
      final edited = <PatternCell>[
        for (final cell in out.document! as List<PatternCell>)
          PatternCell(
            midis: cell.midis == null
                ? null
                : [for (final m in cell.midis!) m + 5],
            steps: cell.steps,
          ),
      ];

      final back = ProjectBridge.convert(
        from: AppMode.loop,
        to: AppMode.tab,
        document: edited,
        annotations: out.annotations,
      );
      final doc = back.document! as TabDocument;

      // Whatever it chose, it must actually sound the edited notes.
      for (var i = 0; i < doc.columns.length; i++) {
        final wanted = edited[i].midis;
        if (wanted == null || wanted.isEmpty) continue;
        final sounded = [
          for (final entry in doc.columns[i].frets.entries)
            Tuning.standardGuitar.strings[entry.key].midiNumber + entry.value,
        ]..sort();
        expect(
          sounded,
          List<int>.of(wanted)..sort(),
          reason: 'column $i is fretted to the wrong pitch',
        );
      }
    });

    test('a garbled side-car is ignored rather than fatal', () {
      final out = ProjectBridge.convert(
        from: AppMode.tab,
        to: AppMode.loop,
        document: _tab(Tuning.standardGuitar),
      );
      final junk = SymbolicAnnotations()
        ..set(
          const EventAddress(track: 0, step: 0),
          AnnotationKeys.fretting,
          'not a fretting at all',
        );

      final back = ProjectBridge.convert(
        from: AppMode.loop,
        to: AppMode.tab,
        document: out.document!,
        annotations: junk,
      );
      expect(back.unsupportedReason, isNull);
      expect((back.document! as TabDocument).columns, isNotEmpty);
    });

    test('a fretting off the end of the tuning is refused', () {
      // Six-string side-car, four-string instrument.
      final out = ProjectBridge.convert(
        from: AppMode.tab,
        to: AppMode.loop,
        document: _tab(Tuning.standardGuitar),
      );
      final back = ProjectBridge.convert(
        from: AppMode.loop,
        to: AppMode.tab,
        document: out.document!,
        annotations: out.annotations,
        tuning: Tuning.standardBass,
      );
      expect(back.unsupportedReason, isNull);
      for (final column in (back.document! as TabDocument).columns) {
        for (final string in column.frets.keys) {
          expect(string, lessThan(Tuning.standardBass.stringCount));
        }
      }
    });
  });

  group('the report matches what the side-car preserves (C4)', () {
    test('tab → score no longer warns about lost fretting', () {
      final out = ProjectBridge.convert(
        from: AppMode.tab,
        to: AppMode.score,
        document: _tab(Tuning.standardGuitar),
      );
      // The string/fret choice rides in `tabVoicings`, so the conversion loses
      // nothing — the old "string and fret choice (a score carries pitches)"
      // warning was stale.
      expect(out.report.lossless, isTrue);
      final notes = [...out.report.lost, ...out.report.approximated]
          .join(' ')
          .toLowerCase();
      expect(notes, isNot(contains('fret')));
    });

    test('score → tab does not invent a fingering when one is already stored',
        () {
      // A score that came FROM a tab carries a voicing per note, so the
      // round-trip back honours it instead of re-arranging.
      final fromTab = ProjectBridge.convert(
        from: AppMode.tab,
        to: AppMode.score,
        document: _tab(Tuning.standardGuitar),
      );
      final back = ProjectBridge.convert(
        from: AppMode.score,
        to: AppMode.tab,
        document: fromTab.document!,
      );
      expect(
        back.report.lossless,
        isTrue,
        reason: 'every note had a stored voicing, so nothing was invented',
      );
    });

    test('score → tab still warns for a hand-engraved score with no voicings',
        () {
      final plain = MultiPartScore([
        Score(
          clef: Clef.treble,
          measures: [
            Measure([
              NoteElement.note(const Pitch(Step.c), NoteDuration.quarter),
              NoteElement.note(const Pitch(Step.e), NoteDuration.quarter),
            ]),
          ],
        ),
      ]);
      final out = ProjectBridge.convert(
        from: AppMode.score,
        to: AppMode.tab,
        document: plain,
      );
      expect(
        out.report.approximated,
        isNotEmpty,
        reason:
            'no stored voicing means the fingering really is chosen for you',
      );
    });
  });
}
