// MultiPartDocument — the multi-instrument container behind the Composition
// Workshop (G6). Mirrors the ScoreDocument test style. Covers add/remove/
// reorder/active, cross-part id namespacing + selection, bar-grid padding,
// bracket/barline re-indexing, transposing-instrument tags, and import.

import 'package:comet_beat/features/workshop/model/multi_part_document.dart';
import 'package:comet_beat/features/workshop/model/score_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

Pitch _p(Step step, {int alter = 0, int octave = 4}) =>
    Pitch(step, alter: alter, octave: octave);

const _quarter = NoteDuration(DurationBase.quarter);

void main() {
  test('a fresh document has one treble part, active 0', () {
    final doc = MultiPartDocument();
    expect(doc.partCount, 1);
    expect(doc.active, 0);
    expect(doc.clefOf(0), Clef.treble);
    expect(doc.nameOf(0), 'Part 1');
    expect(doc.activePart, same(doc.parts.first));
  });

  test('suggested import clef follows the part range', () {
    final low = Score.simple(notes: 'c2:q d2 e2 f2');
    final high = Score.simple(notes: 'c5:q d5 e5 f5');
    final explicitBass = Score.simple(clef: Clef.bass, notes: 'c4:q d4');

    expect(suggestedClefForScore(low), Clef.bass);
    expect(suggestedClefForScore(high), Clef.treble);
    expect(suggestedClefForScore(explicitBass), Clef.bass);
  });

  test('clearAll clears every part', () {
    final doc = MultiPartDocument()..addPart();
    doc.parts[0].insertNote(_p(Step.c), _quarter);
    doc.parts[1].insertNote(_p(Step.g), _quarter);

    doc.clearAll();

    expect(doc.parts.every((part) => part.isEmpty), isTrue);
  });

  test('addPart appends, names, and makes the new part active', () {
    final doc = MultiPartDocument();
    final i = doc.addPart(clef: Clef.bass);
    expect(i, 1);
    expect(doc.partCount, 2);
    expect(doc.active, 1);
    expect(doc.clefOf(1), Clef.bass);
    expect(doc.nameOf(1), 'Part 2');
  });

  test('removePart keeps at least one part and clamps the active index', () {
    final doc = MultiPartDocument()
      ..addPart()
      ..addPart(); // 3 parts, active = 2
    expect(doc.partCount, 3);
    doc.removePart(2); // remove the active (last) part
    expect(doc.partCount, 2);
    expect(doc.active, 1, reason: 'active clamps down to the new last part');
    doc.removePart(0);
    doc.removePart(0);
    expect(doc.partCount, 1, reason: 'a document always keeps one part');
  });

  test('setActive switches the edited part and notifies', () {
    final doc = MultiPartDocument()..addPart();
    var notes = 0;
    doc.addListener(() => notes++);
    doc.setActive(0);
    expect(doc.active, 0);
    expect(notes, 1);
    doc.setActive(0); // no-op, no notification
    expect(notes, 1);
  });

  test('buildMultiPart pads every part to the longest part\'s bar count', () {
    final doc = MultiPartDocument();
    // Part 0: 5 quarters -> 2 bars in 4/4.
    for (var i = 0; i < 5; i++) {
      doc.parts[0].insertNote(_p(Step.c), _quarter);
    }
    doc.addPart(); // Part 1: empty -> 1 bar
    doc.parts[1].insertNote(_p(Step.g), _quarter);

    final mps = doc.buildMultiPart();
    expect(mps.parts, hasLength(2));
    expect(
      mps.parts[0].measures.length,
      mps.parts[1].measures.length,
      reason: 'both parts share one aligned bar grid',
    );
    expect(mps.measureCount, 2);
  });

  test('buildMultiPart namespaces element ids so they are unique across parts',
      () {
    final doc = MultiPartDocument();
    doc.parts[0].insertNote(_p(Step.c), _quarter);
    doc.addPart();
    doc.parts[1].insertNote(_p(Step.g), _quarter);

    final mps = doc.buildMultiPart();
    final ids = [
      for (final part in mps.parts)
        for (final m in part.measures)
          for (final e in m.elements)
            if (e.id != null) e.id!,
    ];
    expect(ids.toSet().length, ids.length, reason: 'no id collisions');
    expect(ids, contains('p0:w0'));
    expect(ids, contains('p1:w0'));
  });

  test('partIndexOf / rawIdOf decode a global id', () {
    expect(MultiPartDocument.partIndexOf('p2:w7'), 2);
    expect(MultiPartDocument.rawIdOf('p2:w7'), 'w7');
    expect(MultiPartDocument.partIndexOf('w7'), -1);
    expect(MultiPartDocument.rawIdOf('w7'), 'w7');
  });

  test('selectByGlobalId switches to the owning part and selects the element',
      () {
    final doc = MultiPartDocument();
    doc.parts[0].insertNote(_p(Step.c), _quarter);
    doc.addPart();
    final gId =
        doc.parts[1].insertNote(_p(Step.g), _quarter); // raw id in part 1
    doc.setActive(0); // move focus away

    final owner = doc.selectByGlobalId('${MultiPartDocument.prefixFor(1)}$gId');
    expect(owner, 1);
    expect(doc.active, 1);
    expect(doc.parts[1].selectedId, gId);
  });

  test('selectByGlobalId ignores an id with no valid part prefix', () {
    final doc = MultiPartDocument();
    expect(doc.selectByGlobalId('w0'), -1);
    expect(doc.selectByGlobalId('p9:w0'), -1); // part 9 does not exist
  });

  test('movePart reorders parts, follows the active part, and clears grouping',
      () {
    final doc = MultiPartDocument()
      ..addPart()
      ..addPart(); // 3 parts
    doc.addBracket(0, 1, kind: StaffBracketKind.brace);
    doc.setActive(0);
    final moved = doc.parts[0];
    doc.movePart(0, 2); // part 0 -> index 2
    expect(doc.parts[2], same(moved));
    expect(doc.active, 2, reason: 'active follows the moved part');
    expect(doc.brackets, isEmpty, reason: 'index grouping cleared on reorder');
  });

  test('addBracket rejects degenerate spans and dedupes', () {
    final doc = MultiPartDocument()..addPart();
    doc.addBracket(0, 0); // single staff -> rejected
    expect(doc.brackets, isEmpty);
    doc.addBracket(0, 1, kind: StaffBracketKind.brace);
    doc.addBracket(0, 1, kind: StaffBracketKind.brace); // duplicate
    expect(doc.brackets, hasLength(1));
    expect(doc.brackets.first.kind, StaffBracketKind.brace);
  });

  test('removePart re-indexes brackets and barline groups', () {
    final doc = MultiPartDocument()
      ..addPart()
      ..addPart()
      ..addPart(); // 4 parts: 0,1,2,3
    doc.addBracket(2, 3);
    doc.setBarlineGroups([const BarlineGroup(2, 3)]);
    doc.removePart(0); // everything shifts down by one
    expect(doc.brackets.single.first, 1);
    expect(doc.brackets.single.last, 2);
    expect(doc.barlineGroups.single.first, 1);
    expect(doc.barlineGroups.single.last, 2);
  });

  test('removing a staff inside a two-staff bracket drops the bracket', () {
    final doc = MultiPartDocument()..addPart(); // 2 parts
    doc.addBracket(0, 1, kind: StaffBracketKind.brace);
    doc.removePart(1); // now only one staff -> bracket is degenerate
    expect(doc.brackets, isEmpty);
    expect(doc.partCount, 1);
  });

  test('a transposing part is tagged in buildMultiPart and un-transposes', () {
    final doc = MultiPartDocument();
    doc.parts[0].insertNote(_p(Step.c), _quarter);
    doc.addPart();
    doc.parts[1].insertNote(_p(Step.d), _quarter);
    doc.setTransposition(1, Transposition.bFlat);

    final mps = doc.buildMultiPart();
    expect(mps.parts[0].transposition, isNull);
    expect(mps.parts[1].transposition, Transposition.bFlat);
    // Concert-pitch view clears the tag (the public toggle).
    final concert = mps.atConcertPitch();
    expect(concert.parts[1].transposition, isNull);
  });

  test('setClefOfPart / setPartName mutate the right part and notify', () {
    final doc = MultiPartDocument()..addPart();
    var notes = 0;
    doc.addListener(() => notes++);
    doc.setClefOfPart(1, Clef.bass);
    doc.setPartName(1, 'Cello');
    expect(doc.clefOf(1), Clef.bass);
    expect(doc.nameOf(1), 'Cello');
    expect(notes, 2);
  });

  test('buildMultiPart carries a slur with a namespaced id', () {
    final doc = MultiPartDocument();
    final part = doc.parts[0]
      ..insertNote(_p(Step.c), _quarter)
      ..insertNote(_p(Step.d), _quarter);
    part.selectPrev(); // c
    part.extendRight(); // c..d
    part.slurSelected();

    final mps = doc.buildMultiPart();
    expect(mps.parts[0].slurs, hasLength(1));
    expect(mps.parts[0].slurs.first.startId, startsWith('p0:'));
  });

  test('fromMultiPartScore imports a two-part MusicXML round-trip', () {
    // grandStaffToMusicXml emits two parts; read them back as a MultiPartScore.
    final src = ScoreDocument()
      ..insertNote(_p(Step.g), _quarter) // treble
      ..insertNote(_p(Step.c, octave: 3), _quarter); // bass
    final xml = grandStaffToMusicXml(src.buildGrandStaff());
    final mps = multiPartScoreFromMusicXml(xml);
    expect(mps.parts.length, 2);

    final doc = MultiPartDocument.fromMultiPartScore(mps);
    expect(doc.partCount, 2);
    // Each imported part is an independently editable ScoreDocument.
    expect(doc.parts[0], isA<ScoreDocument>());
    // The upper part carries the treble G; the lower carries the bass C.
    final upperSteps =
        doc.parts[0].elements.where((e) => !e.isRest).map((e) => e.pitch!.step);
    expect(upperSteps, contains(Step.g));
  });

  test('buildMultiPart yields a valid MultiPartScore for a single part too',
      () {
    final doc = MultiPartDocument();
    doc.parts[0].insertNote(_p(Step.c), _quarter);
    final mps = doc.buildMultiPart();
    expect(mps.parts, hasLength(1));
    expect(mps.measureCount, greaterThanOrEqualTo(1));
    expect(mps.parts.first.measures.first.elements.first, isA<NoteElement>());
  });

  test('a built multi-part score round-trips through multiPartToMusicXml', () {
    final doc = MultiPartDocument();
    doc.parts[0].insertNote(_p(Step.c), _quarter);
    doc.addPart(clef: Clef.bass);
    doc.parts[1].insertNote(_p(Step.e, octave: 3), _quarter);
    doc.addBracket(0, 1, kind: StaffBracketKind.brace);

    final xml = multiPartToMusicXml(doc.buildMultiPart(), partNames: doc.names);
    final reread = multiPartScoreFromMusicXml(xml);
    expect(
      reread.parts.length,
      2,
      reason: 'both parts survive export + import',
    );
    // Every part shares the padded bar grid, so re-import stays aligned.
    expect(reread.parts[0].measures.length, reread.parts[1].measures.length);
  });

  test('toggleBarlineBreakAfter splits/rejoins the barline groups', () {
    final doc = MultiPartDocument()
      ..addPart()
      ..addPart(); // 3 parts, barlines all connected
    expect(doc.barlineGroups, isEmpty);
    expect(doc.hasBarlineBreakAfter(0), isFalse);

    // Break the barline after part 0 → groups [0..0] and [1..2].
    doc.toggleBarlineBreakAfter(0);
    expect(doc.hasBarlineBreakAfter(0), isTrue);
    expect(doc.barlineGroups, [
      const BarlineGroup(0, 0),
      const BarlineGroup(1, 2),
    ]);

    // Break after part 1 too → three singleton-ish groups [0..0][1..1][2..2].
    doc.toggleBarlineBreakAfter(1);
    expect(doc.barlineGroups, [
      const BarlineGroup(0, 0),
      const BarlineGroup(1, 1),
      const BarlineGroup(2, 2),
    ]);

    // Rejoin after part 0 → [0..1] and [2..2].
    doc.toggleBarlineBreakAfter(0);
    expect(doc.hasBarlineBreakAfter(0), isFalse);
    expect(doc.barlineGroups, [
      const BarlineGroup(0, 1),
      const BarlineGroup(2, 2),
    ]);

    // Rejoin the last break → back to fully connected (empty).
    doc.toggleBarlineBreakAfter(1);
    expect(doc.barlineGroups, isEmpty);
  });

  test('toggleBarlineBreakAfter is a no-op on the last part', () {
    final doc = MultiPartDocument()..addPart(); // 2 parts
    doc.toggleBarlineBreakAfter(1); // no part below → ignored
    expect(doc.barlineGroups, isEmpty);
  });

  test('loadMultiPart replaces the whole document in place and notifies', () {
    final doc = MultiPartDocument()
      ..addPart()
      ..addPart(); // 3 parts, active 2
    var notes = 0;
    doc.addListener(() => notes++);

    // A fresh two-part score to load over the top.
    final src = ScoreDocument()
      ..insertNote(_p(Step.g), _quarter)
      ..insertNote(_p(Step.c, octave: 3), _quarter);
    final incoming =
        multiPartScoreFromMusicXml(grandStaffToMusicXml(src.buildGrandStaff()));

    doc.loadMultiPart(incoming);
    expect(doc.partCount, 2, reason: 'replaced 3 parts with the 2 loaded');
    expect(doc.active, 0, reason: 'active resets to the first part');
    expect(notes, greaterThan(0));
    expect(doc.parts[0].isEmpty, isFalse);
  });

  // buildMultiPart is called from build(), so it is memoized: an unchanged
  // document must return an *identical* MultiPartScore, or the render object's
  // `document ==` fast path can never fire and every hover re-lays-out every
  // part. These lock both halves — the hit (identical) and, more importantly,
  // every way the cache must miss. A stale hit here renders the wrong score.
  group('buildMultiPart memoization', () {
    test('an unchanged document returns the identical score', () {
      final doc = MultiPartDocument()..addPart();
      doc.activePart.insertNote(_p(Step.g), _quarter);

      expect(identical(doc.buildMultiPart(), doc.buildMultiPart()), isTrue);
    });

    test('editing a part invalidates it', () {
      final doc = MultiPartDocument()..addPart();
      final before = doc.buildMultiPart();

      doc.activePart.insertNote(_p(Step.g), _quarter);

      expect(identical(doc.buildMultiPart(), before), isFalse);
    });

    test('editing a NON-active part invalidates it too', () {
      final doc = MultiPartDocument()..addPart();
      final before = doc.buildMultiPart();

      // Part 0 is not active (addPart made part 1 active) — the cache key is
      // per-part built-score identity, so this must still miss.
      doc.parts[0].insertNote(_p(Step.c), _quarter);

      expect(identical(doc.buildMultiPart(), before), isFalse);
    });

    test('adding and removing a part invalidates it', () {
      final doc = MultiPartDocument()..addPart();
      final before = doc.buildMultiPart();

      doc.addPart();
      final added = doc.buildMultiPart();
      expect(identical(added, before), isFalse);
      expect(added.parts.length, 3);

      doc.removePart(2);
      final removed = doc.buildMultiPart();
      expect(identical(removed, added), isFalse);
      expect(removed.parts.length, 2);
    });

    test('changing a transposition invalidates it', () {
      final doc = MultiPartDocument()..addPart();
      final before = doc.buildMultiPart();

      doc.setTransposition(0, Transposition.bFlat);

      expect(identical(doc.buildMultiPart(), before), isFalse);
    });

    test('changing brackets or barline groups invalidates it', () {
      final doc = MultiPartDocument()
        ..addPart()
        ..addPart();
      final before = doc.buildMultiPart();

      doc.addBracket(0, 1, kind: StaffBracketKind.brace);
      final braced = doc.buildMultiPart();
      expect(identical(braced, before), isFalse);
      expect(braced.brackets, hasLength(1));

      doc.setBarlineGroups([const BarlineGroup(0, 1)]);
      final grouped = doc.buildMultiPart();
      expect(identical(grouped, braced), isFalse);
      expect(grouped.barlineGroups, hasLength(1));
    });

    test('undo in a part invalidates it', () {
      final doc = MultiPartDocument();
      doc.activePart.insertNote(_p(Step.g), _quarter);
      final withNote = doc.buildMultiPart();

      doc.activePart.undo();

      expect(identical(doc.buildMultiPart(), withNote), isFalse);
    });

    test('a cache hit still reflects the real music', () {
      final doc = MultiPartDocument();
      doc.activePart.insertNote(_p(Step.g), _quarter);
      doc.buildMultiPart(); // prime

      final again = doc.buildMultiPart();
      expect(again.parts.first.measures.first.elements, isNotEmpty);
    });
  });

  group('assembly preserves note attributes and voice-2 anchors', () {
    // Regression: _reid rebuilt each note with only pitches/duration/id/
    // articulations/tie/accidental/notehead, DROPPING ornament, grace notes,
    // fingerings, arpeggio and tremolo from every note in the assembled score —
    // so the full-score render and multi-part MusicXML export lost them.
    test('ornaments and grace notes survive buildMultiPart', () {
      final doc = MultiPartDocument()..addPart(); // 2 parts
      final part = doc.parts.first..insertNote(_p(Step.c), _quarter);
      part.selectIndex(0);
      part.setOrnamentOfSelected(Ornament.trill);
      part.setGraceNotesOfSelected([_p(Step.d)]);

      final note = doc
          .buildMultiPart()
          .parts
          .first
          .measures
          .expand((m) => m.elements)
          .whereType<NoteElement>()
          .first;
      expect(note.ornament, Ornament.trill, reason: 'ornament dropped');
      expect(
        note.graceNotes.map((p) => p.step),
        [Step.d],
        reason: 'grace notes dropped',
      );
    });

    // Regression: _reindex namespaced voice-1 ids and every marking, but rebuilt
    // the measure with `copyWith(elements: …)`, which defaults voice2 to the
    // ORIGINAL — so voice-2 element ids stayed unprefixed while a dynamic/lyric
    // on a voice-2 note got prefixed, detaching it (and colliding across parts).
    test('voice-2 element ids are namespaced so their markings stay anchored',
        () {
      final doc = MultiPartDocument()..addPart();
      final part = doc.parts.first..insertNote(_p(Step.c), _quarter); // voice 1
      part.setActiveVoice(1);
      part.insertNote(_p(Step.e), _quarter); // voice 2
      part.selectIndex(0); // the voice-2 note
      part.setDynamicOfSelected(DynamicLevel.mf);

      final score = doc.buildMultiPart().parts.first;
      final ids = {
        for (final m in score.measures) ...[
          for (final e in m.elements) e.id,
          for (final e in m.voice2) e.id,
        ],
      }..remove(null);

      expect(
        score.dynamics,
        isNotEmpty,
        reason: 'the voice-2 dynamic recorded',
      );
      for (final d in score.dynamics) {
        expect(
          ids,
          contains(d.elementId),
          reason: 'dynamic ${d.elementId} anchors to no element (detached)',
        );
      }
      final v2ids = {
        for (final m in score.measures)
          for (final e in m.voice2)
            if (e.id != null) e.id,
      };
      expect(
        v2ids.every((id) => id!.startsWith('p0:')),
        isTrue,
        reason: 'voice-2 ids not prefixed (cross-part collision risk)',
      );
    });
  });
}
