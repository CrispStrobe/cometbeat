// lib/features/games/composition/daw_marked_range.dart
//
// The Audio Editor's marked range (Mark In / Mark Out), out of the widget.
//
// The two marks are set independently from the playhead, in either order, and
// a range only counts once both exist and are more than a few milliseconds
// apart — a double tap on Mark In / Mark Out must not produce a zero-length
// range that every range operation then has to guard against.

import 'dart:math' as math;

class DawMarkedRange {
  /// Marks closer than this are treated as no range at all.
  static const minLengthMs = 5.0;

  double? _inMs;
  double? _outMs;

  /// The Mark In position, or null if never set.
  double? get inMs => _inMs;

  /// The Mark Out position, or null if never set.
  double? get outMs => _outMs;

  void markIn(double ms) => _inMs = ms;
  void markOut(double ms) => _outMs = ms;

  void clear() {
    _inMs = null;
    _outMs = null;
  }

  /// Whether there is a usable range: both marks, and not (nearly) equal.
  bool get isSet =>
      _inMs != null && _outMs != null && (_inMs! - _outMs!).abs() > minLengthMs;

  /// The earlier mark (0 when unset). The marks may be in either order.
  double get startMs => math.min(_inMs ?? 0, _outMs ?? 0);

  /// The later mark (0 when unset).
  double get endMs => math.max(_inMs ?? 0, _outMs ?? 0);

  /// "Range 1.20-3.45 s" — or, while incomplete, the marks as set so far
  /// ("Range 1.20--- s"). A readout: units, not prose, so not localised.
  String label() {
    String seconds(double ms) => (ms / 1000).toStringAsFixed(2);
    if (!isSet) {
      final inText = _inMs == null ? '--' : seconds(_inMs!);
      final outText = _outMs == null ? '--' : seconds(_outMs!);
      return 'Range $inText-$outText s';
    }
    return 'Range ${seconds(startMs)}-${seconds(endMs)} s';
  }

  /// The tracks a range operation applies to: the valid [selected] ones in
  /// order, or every track when none is selected.
  static List<int> targetTracks(Set<int> selected, int trackCount) {
    final valid = [
      for (final i in selected)
        if (i >= 0 && i < trackCount) i,
    ]..sort();
    return valid.isNotEmpty
        ? valid
        : Iterable<int>.generate(trackCount).toList();
  }
}
