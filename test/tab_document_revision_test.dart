// `TabDocument.revision` — the guard that makes it safe to CACHE from.
//
// The Tab Workshop derives a whole `Score` from the document to draw anything,
// and it now does that once per change instead of once per build, keyed on this
// counter. That trade is only sound if every mutation bumps it: a missed bump is
// not a slow screen, it is a screen showing the wrong music, which is far worse
// than the cost it saves.
//
// So this file walks EVERY public mutator by hand. A new one that forgets to
// bump fails here, and the list itself is the reminder to add it — the same
// "test that keeps working after we stop looking" shape as the copyWith drift
// guard in crisp_notation.

import 'package:comet_beat/features/games/composition/tab_chords.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

TabDocument _doc() => TabDocument.blank(Tuning.standardGuitar)
  ..setFret(0, 0, 3)
  ..setFret(1, 1, 5);

void main() {
  test('a fresh document starts somewhere and only moves forward', () {
    final doc = TabDocument.blank(Tuning.standardGuitar);
    final start = doc.revision;
    doc.setFret(0, 0, 1);
    expect(doc.revision, greaterThan(start));
  });

  group('every public mutator bumps it', () {
    // Named so a failure says which one forgot.
    final mutators = <String, void Function(TabDocument)>{
      'setFret': (d) => d.setFret(2, 0, 4),
      'clearCell': (d) => d.clearCell(0, 0),
      'setDuration': (d) => d.setDuration(0, NoteDuration.half),
      'toggleTechnique': (d) => d.toggleTechnique(0, TabTechnique.hammer),
      'setTie': (d) => d.setTie(0, true),
      'setTuplet': (d) => d.setTuplet(0, (3, 2)),
      'setBend': (d) => d.setBend(0, TabBends.bend()),
      'setWhammy': (d) => d.setWhammy(0, TabBends.bend()),
      'setSlide': (d) => d.setSlide(0, SlideInOut.inFromBelow),
      'setTap': (d) => d.setTap(0, true),
      'setHarmonic': (d) => d.setHarmonic(0, TabNoteStyle.harmonic),
      'setPalmMute': (d) => d.setPalmMute(0, true),
      'setLetRing': (d) => d.setLetRing(0, true),
      'toggleArticulation': (d) =>
          d.toggleArticulation(0, Articulation.staccato),
      'setDynamic': (d) => d.setDynamic(0, DynamicLevel.f),
      'setHairpin': (d) => d.setHairpin(0, HairpinType.crescendo),
      'setBarRepeat': (d) => d.setBarRepeat(0, start: true),
      'setBarVolta': (d) => d.setBarVolta(0, 1),
      'setBarNavigation': (d) => d.setBarNavigation(0, NavigationMark.dalSegno),
      'setBarTempo': (d) => d.setBarTempo(0, 96),
      'setSection': (d) => d.setSection(0, 'A'),
      'makeTuplet': (d) => d.makeTuplet(0, 3),
      'setChord': (d) => d.setChord(0, kGuitarChords.values.first),
      'setChordVoicing': (d) =>
          d.setChordVoicing(0, kGuitarChords.values.first),
      'insertColumn': (d) => d.insertColumn(1),
      'insertColumnsAt': (d) => d.insertColumnsAt(1, const [TabColumn()]),
      'duplicateBar': (d) => d.duplicateBar(0),
      'transposeBy': (d) => d.transposeBy(2),
      'removeColumn': (d) => d.removeColumn(1),
      'tuning=': (d) => d.tuning = Tuning.standardBass,
      'timeSignature=': (d) => d.timeSignature = const TimeSignature(3, 4),
      'keySignature=': (d) => d.keySignature = const KeySignature(2),
    };

    for (final entry in mutators.entries) {
      test(entry.key, () {
        final doc = _doc();
        final before = doc.revision;
        entry.value(doc);
        expect(
          doc.revision,
          greaterThan(before),
          reason:
              '${entry.key} changed the document without bumping revision — '
              'a cache keyed on it would now show stale music',
        );
      });
    }
  });

  group('growing the column list counts as a change', () {
    test('writing past the end bumps once for the growth and once for the set',
        () {
      // `_ensure` pads the list, which is itself a change: a document that grew
      // is not the document a cache was built from.
      final doc = TabDocument.blank(Tuning.standardGuitar, initialColumns: 2);
      final before = doc.revision;
      doc.setFret(10, 0, 3);
      expect(doc.columns.length, 11);
      expect(doc.revision, greaterThan(before + 1));
    });

    test('a write inside the existing range does not pay for growth', () {
      // Purely so the counter stays a meaningful signal rather than noise.
      final doc = TabDocument.blank(Tuning.standardGuitar);
      final before = doc.revision;
      doc.setFret(0, 0, 3);
      expect(doc.revision, before + 1);
    });
  });

  test('reading does NOT bump it', () {
    // Otherwise a cache keyed on the revision would miss every time, and the
    // optimisation would silently do nothing at all — the failure mode that
    // looks like success.
    final doc = _doc();
    final before = doc.revision;
    doc
      ..toScore()
      ..barBoundsAt(0)
      ..toPlaybackEvents();
    expect(doc.revision, before);
  });
}
