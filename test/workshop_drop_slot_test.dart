// Unit tests for computeDropSlot — the reading-order drop-slot math behind the
// Workshop's horizontal drag-to-reorder and its live drop caret. Pure (no
// render pass), so it exercises the ordering across bars and wrapped lines that
// a widget test can't reach reliably.

import 'dart:ui';

import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart';
import 'package:flutter_test/flutter_test.dart';

// A 10-wide element whose notehead centre sits at x + 5, in [measure].
({String id, Rect bounds, int measureIndex}) region(
  String id,
  double x,
  int measure,
) =>
    (id: id, bounds: Rect.fromLTWH(x, 0, 10, 10), measureIndex: measure);

void main() {
  // a (bar0, cx5) · b (bar0, cx25) · c (bar1, cx5) — reading order a,b,c.
  final regions = [
    region('a', 0, 0),
    region('b', 20, 0),
    region('c', 0, 1),
  ];

  test('drop at the very start goes before the first element', () {
    final s = computeDropSlot(regions, 'a', -100, 0);
    expect(s.index, 0);
    expect(s.beforeId, 'b'); // ordered without a = [b, c]; slot 0 = b
  });

  test('drop between two elements in the same bar', () {
    // Drag a; drop just right of b's centre (x=30) in bar 0.
    final s = computeDropSlot(regions, 'a', 30, 0);
    expect(s.index, 1); // b is before the drop
    expect(s.beforeId, 'c'); // a lands before c
  });

  test('ordering is by bar first, then x (across wrapped lines)', () {
    // Drag b; drop in bar 1 left of c (x=2). Bar 0's a counts (earlier bar);
    // c does not (same bar, but to the right of the drop).
    final s = computeDropSlot(regions, 'b', 2, 1);
    expect(s.index, 1); // only a precedes
    expect(s.beforeId, 'c');
  });

  test('drop past the last element yields a null caret target', () {
    final s = computeDropSlot(regions, 'a', 1000, 1);
    expect(s.index, 2); // both b and c precede
    expect(s.beforeId, isNull); // nothing to sit before at the end
  });

  test('the dragged element is excluded from its own slot count', () {
    // Drag c to the far left of bar 0; only the other two remain, none precede.
    final s = computeDropSlot(regions, 'c', -100, 0);
    expect(s.index, 0);
    expect(s.beforeId, 'a');
  });
}
