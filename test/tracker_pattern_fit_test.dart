// WS-X2 — fitting a foreign pattern into the one on screen.
//
// `TrackerEngine.setChannelCells` asserts that the cell list matches the row
// count. Every existing caller satisfies that by construction — they edit the
// pattern they are in — so nothing had ever handed it a grid from another
// document. These tests pin the fit, and in particular pin the two ways of
// getting it wrong that would look plausible: wrapping the overflow (which
// interleaves the second half of the music with the first) and reporting shape
// instead of content (which alarms the user about rows that were empty anyway).

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_pattern_fit.dart';
import 'package:flutter_test/flutter_test.dart';

List<List<TrackerCell>> _grid(int channels, int rows, {int? noteEvery}) => [
      for (var c = 0; c < channels; c++)
        [
          for (var r = 0; r < rows; r++)
            if (noteEvery != null && r % noteEvery == 0)
              TrackerCell(midi: 60 + c)
            else
              TrackerCell.empty,
        ],
    ];

void main() {
  group('the result always matches the target exactly', () {
    test('a smaller source is padded, not left short', () {
      // The assert this exists for: a 4-row grid handed to an 8-row pattern
      // would be indexed past its end.
      final fitted = fitCellsToPattern(_grid(2, 4), channels: 4, rows: 8);
      expect(fitted.cells, hasLength(4));
      for (final channel in fitted.cells) {
        expect(channel, hasLength(8));
      }
    });

    test('a larger source is cut', () {
      final fitted = fitCellsToPattern(_grid(8, 32), channels: 4, rows: 16);
      expect(fitted.cells, hasLength(4));
      expect(fitted.cells.first, hasLength(16));
    });

    test('an equal source comes through cell for cell', () {
      final source = _grid(2, 4, noteEvery: 2);
      final fitted = fitCellsToPattern(source, channels: 2, rows: 4);
      expect(fitted.cells, source);
      expect(fitted.isLossy, isFalse);
    });
  });

  group('what is cut, and what the user is told', () {
    test('the overflow is DROPPED, not wrapped', () {
      // Wrapping would put the second half of the music on top of the first,
      // which is unrecognisable rather than merely shorter.
      final source = [
        [
          const TrackerCell(midi: 60),
          TrackerCell.empty,
          const TrackerCell(midi: 72), // past the end of a 2-row pattern
          TrackerCell.empty,
        ],
      ];
      final fitted = fitCellsToPattern(source, channels: 1, rows: 2);
      expect(fitted.cells.single.map((c) => c.midi), [60, null]);
      expect(fitted.droppedNotes, 1);
    });

    test('it counts NOTES lost, not rows trimmed', () {
      // A 32-row song that only uses its first four rows loses nothing by
      // landing in a 16-row pattern. Reporting "16 rows trimmed" would be true
      // and alarming for no reason.
      final source = _grid(1, 32)
        ..first[0] = const TrackerCell(midi: 60)
        ..first[3] = const TrackerCell(midi: 64);
      final fitted = fitCellsToPattern(source, channels: 1, rows: 16);
      expect(fitted.droppedRows, 16, reason: 'the shape did shrink');
      expect(fitted.droppedNotes, 0, reason: 'but nothing was lost');
      expect(fitted.isLossy, isFalse, reason: 'so the drop need not warn');
    });

    test('notes on channels the target does not have are counted too', () {
      final fitted = fitCellsToPattern(
        _grid(6, 4, noteEvery: 1),
        channels: 2,
        rows: 4,
      );
      expect(fitted.droppedChannels, 4);
      expect(fitted.droppedNotes, 4 * 4, reason: '4 channels × 4 notes');
      expect(fitted.isLossy, isTrue);
    });

    test('both directions at once', () {
      final fitted = fitCellsToPattern(
        _grid(4, 8, noteEvery: 1),
        channels: 2,
        rows: 4,
      );
      expect(fitted.droppedChannels, 2);
      expect(fitted.droppedRows, 4);
      // 2 kept channels × 4 trimmed rows + 2 dropped channels × 8 rows.
      expect(fitted.droppedNotes, 2 * 4 + 2 * 8);
    });
  });

  group('degenerate shapes do not throw', () {
    test('an empty target', () {
      expect(
        fitCellsToPattern(_grid(2, 4), channels: 0, rows: 4).cells,
        isEmpty,
      );
      expect(
        fitCellsToPattern(_grid(2, 4), channels: 2, rows: 0).cells,
        isEmpty,
      );
    });

    test('an empty source fills the target with empties', () {
      final fitted = fitCellsToPattern(const [], channels: 2, rows: 4);
      expect(fitted.cells, hasLength(2));
      expect(fitted.cells.first.every((c) => c.isEmpty), isTrue);
      expect(fitted.isLossy, isFalse);
    });

    test('ragged channels are handled per channel', () {
      // Nothing in the app produces one, but a converted document is not ours.
      final fitted = fitCellsToPattern(
        [
          [const TrackerCell(midi: 60)],
          _grid(1, 6, noteEvery: 1).single,
        ],
        channels: 2,
        rows: 4,
      );
      expect(fitted.cells.first, hasLength(4));
      expect(fitted.cells.last, hasLength(4));
      expect(fitted.droppedNotes, 2, reason: 'rows 4 and 5 of the long one');
    });
  });
}
