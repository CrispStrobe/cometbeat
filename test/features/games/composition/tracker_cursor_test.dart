import 'package:comet_beat/features/games/composition/tracker_cursor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TrackerCursor', () {
    test('starts at the top-left with no block', () {
      final c = TrackerCursor();
      expect((c.channel, c.row), (0, 0));
      expect(c.hasSelection, isFalse);
      expect(c.rect, (cLo: 0, cHi: 0, rLo: 0, rHi: 0));
    });

    test('moves are clamped to the grid', () {
      final c = TrackerCursor()..moveTo(9, -3, channels: 4, rows: 64);
      expect((c.channel, c.row), (3, 0));
      c.moveTo(1, 200, channels: 4, rows: 64);
      expect((c.channel, c.row), (1, 63));
    });

    test('extending anchors at the old cursor and normalises the rect', () {
      final c = TrackerCursor()
        ..moveTo(2, 10, channels: 4, rows: 64)
        ..extendTo(0, 4, channels: 4, rows: 64);
      expect(c.hasSelection, isTrue);
      expect((c.anchorChannel, c.anchorRow), (2, 10));
      expect(c.rect, (cLo: 0, cHi: 2, rLo: 4, rHi: 10));
      // A second extend keeps the first anchor.
      c.extendTo(3, 12, channels: 4, rows: 64);
      expect(c.rect, (cLo: 2, cHi: 3, rLo: 10, rHi: 12));
    });

    test('a plain move keeps the anchor; a clearing move drops it', () {
      final c = TrackerCursor()..extendTo(1, 1, channels: 4, rows: 64);
      c.moveTo(2, 2, channels: 4, rows: 64);
      expect(c.hasSelection, isTrue);
      c.moveClearing(3, 3, channels: 4, rows: 64);
      expect(c.hasSelection, isFalse);
      expect((c.channel, c.row), (3, 3));
    });

    test('selects only cells inside a marked block', () {
      final c = TrackerCursor()..moveTo(1, 1, channels: 4, rows: 64);
      expect(c.selects(1, 1), isFalse, reason: 'no block, no selection');
      c.extendTo(2, 3, channels: 4, rows: 64);
      expect(c.selects(1, 1), isTrue);
      expect(c.selects(2, 3), isTrue);
      expect(c.selects(0, 2), isFalse);
      expect(c.selects(2, 4), isFalse);
    });

    test('selectChannel and selectAll span the pattern', () {
      final c = TrackerCursor()
        ..moveTo(2, 5, channels: 4, rows: 32)
        ..selectChannel(rows: 32);
      expect(c.rect, (cLo: 2, cHi: 2, rLo: 0, rHi: 31));
      c.selectAll(channels: 4, rows: 32);
      expect(c.rect, (cLo: 0, cHi: 3, rLo: 0, rHi: 31));
    });

    test('clampTo pulls the cursor into a shrunken grid', () {
      final c = TrackerCursor()
        ..moveTo(5, 60, channels: 8, rows: 64)
        ..clampTo(channels: 4, rows: 32);
      expect((c.channel, c.row), (3, 31));
      c.clampTo(channels: 8, rows: 64);
      expect((c.channel, c.row), (3, 31), reason: 'growing never moves it');
    });
  });
}
