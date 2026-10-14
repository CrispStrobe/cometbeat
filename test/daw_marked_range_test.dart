// The Audio Editor's marked range, without a widget.
import 'package:comet_beat/features/games/composition/daw_marked_range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a range needs both marks, more than a few ms apart', () {
    final r = DawMarkedRange();
    expect(r.isSet, isFalse);
    r.markIn(1000);
    expect(r.isSet, isFalse);
    r.markOut(1003); // a double tap, not a range
    expect(r.isSet, isFalse);
    r.markOut(2500);
    expect(r.isSet, isTrue);
    r.clear();
    expect((r.inMs, r.outMs, r.isSet), (null, null, false));
  });

  test('marks may be set in either order', () {
    final r = DawMarkedRange()
      ..markIn(3000)
      ..markOut(1000);
    expect((r.startMs, r.endMs), (1000, 3000));
  });

  test('the readout shows what is set so far', () {
    final r = DawMarkedRange();
    expect(r.label(), 'Range ----- s');
    r.markIn(1200);
    expect(r.label(), 'Range 1.20--- s');
    r.markOut(3450);
    expect(r.label(), 'Range 1.20-3.45 s');
  });

  test('range operations target the selected tracks, else all', () {
    expect(DawMarkedRange.targetTracks({2, 0, 9}, 3), [0, 2]);
    expect(DawMarkedRange.targetTracks({}, 3), [0, 1, 2]);
    expect(DawMarkedRange.targetTracks({7}, 3), [0, 1, 2]);
  });
}
