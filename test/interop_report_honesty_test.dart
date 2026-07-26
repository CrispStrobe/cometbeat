// A conversion that loses something has to SAY so.
//
// The report is the only thing standing between a user and a surprise: the
// "Open in…" sheet shows it before they commit, and `lossless` renders as
// "nothing is lost". So a report that under-claims is worse than a lossy
// conversion — the user consents to a trade they were never shown.
//
// This is the property the Tracker truncation bug violated. `trackerSongFrom
// MultiPart` silently dropped everything past row 64, and the report for that
// edge said only "notes quantized onto the pattern grid" — true, and not the
// thing that had just eaten half the song. No test could have caught it by
// looking at one converter, because each converter's report was *locally*
// plausible. It shows up only by comparing the report against what actually
// survived a round trip.
//
// So: for every ordered pair of symbolic modes, take a real song, make the trip
// and come BACK BY THE SAME EDGE. If the music changed, the reports must not
// both claim it didn't.
//
// Two things this deliberately does not do. It does not judge how much an edge
// may lose — that is a per-edge design decision, and a Tab has no room for a
// tracker's effect column no matter how the conversion is written. And it does
// not judge whether the report names the RIGHT loss; that is a wording call a
// test cannot make. It only refuses silence.
//
// Measuring is via each mode's own trip to Score, applied to BOTH sides of the
// round trip, so whatever that measurement itself loses cancels out. Measuring
// `A → B` by reading the B document as a Score instead would fail edges that
// are perfectly faithful in their own terms — Tab → Tracker puts one string per
// channel, which reads back as six overlapping parts, and that is the
// measurement being wrong, not the converter.

import 'package:comet_beat/core/interop/project_bridge.dart';
import 'package:comet_beat/features/games/songs/song_book.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show MultiPartScore, NoteElement, Score;
import 'package:flutter_test/flutter_test.dart';

/// The symbolic modes. Audio is excluded: it is deliberately one-way, and
/// `convert` reports that as an `unsupportedReason` rather than a conversion.
const _modes = [AppMode.score, AppMode.tracker, AppMode.tab, AppMode.loop];

List<int> _pitches(Score score) => [
      for (final measure in score.measures)
        for (final element in measure.elements)
          if (element is NoteElement) element.pitches.first.midiNumber,
    ];

List<int> _pitchesOf(MultiPartScore score) =>
    score.parts.expand(_pitches).toList();

/// A document in [mode] holding [song], or null if that seeding trip fails.
///
/// Seeding goes through the bridge itself so the fixtures are documents the app
/// would really produce, not hand-built ones that dodge the converters.
Object? _seed(Song song, AppMode mode) {
  final score = MultiPartScore([song.score]);
  if (mode == AppMode.score) return score;
  return ProjectBridge.convert(
    from: AppMode.score,
    to: mode,
    document: score,
  ).document;
}

/// The pitches of [document] (given as [mode]), via Score.
List<int>? _contentOf(Object document, AppMode mode) {
  if (mode == AppMode.score) return _pitchesOf(document as MultiPartScore);
  final back = ProjectBridge.convert(
    from: mode,
    to: AppMode.score,
    document: document,
  ).document;
  return back == null ? null : _pitchesOf(back as MultiPartScore);
}

void main() {
  // One representative song keeps the matrix readable; the per-song sweep lives
  // in interop_corpus_test.dart. This one is about the REPORTS.
  final song = kSongs.firstWhere((s) => s.id == 'london_bridge');

  group('a lossy round trip never reports itself lossless', () {
    for (final from in _modes) {
      for (final to in _modes) {
        if (from == to) continue;
        test('${from.name} → ${to.name} → ${from.name}', () {
          final document = _seed(song, from);
          if (document == null) {
            markTestSkipped('cannot seed a ${from.name} document');
            return;
          }

          final forward = ProjectBridge.convert(
            from: from,
            to: to,
            document: document,
          );
          if (forward.unsupportedReason != null) return; // refusing is honest
          expect(forward.document, isNotNull);

          final back = ProjectBridge.convert(
            from: to,
            to: from,
            document: forward.document!,
          );
          if (back.unsupportedReason != null) return;
          expect(back.document, isNotNull);

          final before = _contentOf(document, from);
          final after = _contentOf(back.document!, from);
          expect(before, isNotNull, reason: 'could not measure the original');
          expect(after, isNotNull, reason: 'could not measure the round trip');

          if (!_sameContent(before, after)) {
            expect(
              forward.report.lossless && back.report.lossless,
              isFalse,
              reason: 'the music changed over the round trip but both reports '
                  'claimed nothing was lost — this is the shape of the Tracker '
                  'truncation bug',
            );
          }
        });
      }
    }
  });

  group('reports say something a person can act on', () {
    for (final from in _modes) {
      for (final to in _modes) {
        if (from == to) continue;
        test('${from.name} → ${to.name}', () {
          final document = _seed(song, from);
          if (document == null) {
            markTestSkipped('cannot seed a ${from.name} document');
            return;
          }
          final result = ProjectBridge.convert(
            from: from,
            to: to,
            document: document,
          );
          if (result.unsupportedReason != null) return;

          // Every entry is shown to the user verbatim, so an empty or stub
          // string is a UI bug as much as a documentation one.
          for (final note in [
            ...result.report.lost,
            ...result.report.approximated,
          ]) {
            expect(note.trim(), isNotEmpty);
            expect(
              note.length,
              greaterThan(8),
              reason: '"$note" is too terse to mean anything to a user',
            );
          }
        });
      }
    }
  });

  test('converting a document to its own mode is a no-op and says so', () {
    for (final mode in _modes) {
      final document = _seed(song, mode);
      if (document == null) continue;
      final result = ProjectBridge.convert(
        from: mode,
        to: mode,
        document: document,
      );
      expect(result.document, same(document));
      expect(
        result.report.lossless,
        isTrue,
        reason: 'staying put cannot lose anything',
      );
    }
  });
}

/// Whether two readings hold the same music.
///
/// A null reading means "could not be read back", which is not sameness.
bool _sameContent(List<int>? a, List<int>? b) {
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
