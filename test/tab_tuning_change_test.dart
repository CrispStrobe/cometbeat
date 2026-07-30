// A fret on a string the tuning does not have must not crash.
//
// ⚠️ It did, in shipped code: `tuning.strings[stringIndex]` was indexed
// unchecked, so a six-string tab switched to a bass tuning — which the settings
// sheet offers in two taps — threw `RangeError` out of `toScore`, i.e. out of
// `build`. Nothing about that is exotic: an import, a dropped document from
// another surface and a plain tuning change all reach the same state.
//
// Skipping is the only sensible reading of it: a fret on a string that is not
// there has no pitch. What must NOT happen is losing the whole score over it.

import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

TabDocument _sixStringTab() =>
    TabDocument.blank(Tuning.standardGuitar, initialColumns: 2)
      ..setFret(0, 0, 1) // high E — a bass has this string index
      ..setFret(0, 5, 3); // low E — a bass does not

void main() {
  test('a six-string tab survives a switch to a four-string tuning', () {
    final doc = _sixStringTab();
    expect(doc.toScore().measures, isNotEmpty, reason: 'fine as a guitar');

    doc.tuning = Tuning.standardBass;
    expect(doc.toScore, returnsNormally);
    expect(doc.toPlaybackEvents, returnsNormally);
  });

  test('the notes that DO fit still sound', () {
    // The fix must not be "drop the column": one unreachable string in a chord
    // cannot silence the rest of it.
    final doc = _sixStringTab()..tuning = Tuning.standardBass;
    final notes = doc
        .toScore()
        .measures
        .expand((m) => m.elements)
        .whereType<NoteElement>()
        .toList();
    expect(notes, isNotEmpty);
    expect(
      notes.first.pitches,
      hasLength(1),
      reason: 'the reachable string sounds; the missing one is skipped',
    );
  });

  test('the frets themselves are KEPT, not deleted', () {
    // Switching back must restore the music: the tuning decides what sounds, not
    // what the document holds. Deleting the unreachable frets would make a
    // tuning change destructive.
    final doc = _sixStringTab()..tuning = Tuning.standardBass;
    doc.toScore(); // the render that used to throw
    doc.tuning = Tuning.standardGuitar;
    expect(doc.columns[0].frets[5], 3);
    expect(
      doc
          .toScore()
          .measures
          .expand((m) => m.elements)
          .whereType<NoteElement>()
          .first
          .pitches,
      hasLength(2),
      reason: 'both strings sound again',
    );
  });

  test('soundingFrets reports what a caller can tell the user', () {
    // The drop path needs the COUNT to warn honestly, which is why this is a
    // named method rather than an inline filter.
    final doc = _sixStringTab()..tuning = Tuning.standardBass;
    expect(doc.soundingFrets(doc.columns[0]), hasLength(1));
    expect(doc.columns[0].frets, hasLength(2), reason: 'both are still held');
  });
}
