// The interop matrix over the REAL song book, not synthetic fixtures.
//
// `project_bridge_test.dart` proves each edge is wired and that no pair throws,
// using documents built to exercise one thing at a time. That is the right shape
// for a routing test, but it means every converter has only ever seen input I
// wrote while thinking about that converter. The bundled songs were written by
// someone else for another purpose entirely: they have pickups, repeats, dotted
// rhythms, ties, rests in awkward places and ranges that wander off a guitar.
//
// So this is the differential pass the tab reader got against its corpus — same
// idea, much smaller corpus. Two properties, both cheap to state and hard to
// satisfy by accident:
//
//   1. NOTHING CRASHES and nothing silently refuses. Every song must make every
//      trip the matrix claims to support.
//   2. THE PITCHES SURVIVE a round trip. Score → X → Score must return the same
//      MIDI sequence. This is the property a "preserve as much symbolic info as
//      possible" bridge actually promises, and it is the one that catches an
//      off-by-one octave, a swallowed rest, or a dropped final note — none of
//      which show up as an exception.
//
// Where a round trip legitimately cannot be exact, the test says so in terms of
// the musical reason rather than pinning whatever the code currently emits.

import 'package:comet_beat/core/interop/project_bridge.dart';
import 'package:comet_beat/features/games/songs/song_book.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show MultiPartScore, NoteElement, Score;
import 'package:flutter_test/flutter_test.dart';

/// Every sounding pitch of [score] in reading order.
///
/// Rests are deliberately excluded: this asks "are these the same notes", and a
/// rest's SURVIVAL is a separate property (checked via note count against the
/// original, since a swallowed rest fuses two notes and shortens the list).
List<int> _pitches(Score score) => [
      for (final measure in score.measures)
        for (final element in measure.elements)
          if (element is NoteElement) element.pitches.first.midiNumber,
    ];

List<int> _pitchesOf(MultiPartScore score) =>
    score.parts.expand(_pitches).toList();

MultiPartScore _asDocument(Song song) => MultiPartScore([song.score]);

/// Convert or fail loudly with the reason the bridge gave.
Object _convert(Object document, AppMode from, AppMode to, String song) {
  final result = ProjectBridge.convert(from: from, to: to, document: document);
  expect(
    result.unsupportedReason,
    isNull,
    reason: '"$song" could not go ${from.name} → ${to.name}',
  );
  expect(
    result.document,
    isNotNull,
    reason: '"$song" produced no ${to.name} document',
  );
  return result.document!;
}

void main() {
  // The corpus itself is a precondition — if the book is ever emptied or the
  // songs stop parsing, every expectation below passes vacuously.
  test('the song book is a usable corpus', () {
    expect(kSongs, isNotEmpty);
    for (final song in kSongs) {
      expect(
        _pitches(song.score),
        isNotEmpty,
        reason: '"${song.title}" has no notes to convert',
      );
    }
  });

  group('every bundled song makes every trip the matrix offers', () {
    for (final song in kSongs) {
      test(song.title, () {
        final document = _asDocument(song);
        for (final target in [AppMode.tab, AppMode.tracker, AppMode.loop]) {
          _convert(document, AppMode.score, target, song.title);
        }
      });
    }
  });

  group('Score → Tab → Score keeps the notes', () {
    // Tab is the strictest round trip in the matrix: a fretting plan assigns a
    // definite (string, fret) to every note and reading it back is arithmetic,
    // so anything lost here is a bug rather than a modelling compromise.
    for (final song in kSongs) {
      test(song.title, () {
        final original = _asDocument(song);
        final tab = _convert(original, AppMode.score, AppMode.tab, song.title);
        final back = _convert(tab, AppMode.tab, AppMode.score, song.title);

        expect(
          _pitchesOf(back as MultiPartScore),
          _pitchesOf(original),
          reason: '"${song.title}" changed pitch through Tab',
        );
      });
    }
  });

  group('Score → Tracker → Score keeps the notes', () {
    // A tracker row grid quantises RHYTHM, so durations may move. Pitch has no
    // such excuse — a cell stores a note number outright.
    for (final song in kSongs) {
      test(song.title, () {
        final original = _asDocument(song);
        final tracker =
            _convert(original, AppMode.score, AppMode.tracker, song.title);
        final back =
            _convert(tracker, AppMode.tracker, AppMode.score, song.title);

        expect(
          _pitchesOf(back as MultiPartScore),
          _pitchesOf(original),
          reason: '"${song.title}" changed pitch through the Tracker',
        );
      });
    }
  });

  test('a report that claims lossless must actually be lossless', () {
    // The report is what the UI shows the user before they commit to a
    // conversion, so a false "nothing lost" is worse than an honest warning.
    for (final song in kSongs) {
      final original = _asDocument(song);
      final result = ProjectBridge.convert(
        from: AppMode.score,
        to: AppMode.tab,
        document: original,
      );
      if (!result.report.lossless) continue;
      final back = _convert(
        result.document!,
        AppMode.tab,
        AppMode.score,
        song.title,
      );
      expect(
        _pitchesOf(back as MultiPartScore),
        _pitchesOf(original),
        reason: '"${song.title}" reported lossless but changed',
      );
    }
  });
}
