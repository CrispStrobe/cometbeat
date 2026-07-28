// lib/core/games/highway/highway_lanes.dart
//
// LANE MAPS — the one abstraction that lets a single highway serve a piano, a
// guitar, a cello and a pad grid.
//
// A lane map answers three questions in a unit space (x ∈ 0..1 across the
// width), and knows nothing about painting:
//
//   1. where does this event sit, and how wide is it?   → [slotFor]
//   2. what does the instrument rail under the hit line look like? → [railKeys]
//   3. what did the player just tap?                     → [hitTest]
//
// Because it is unit-space and Flutter-free, the falling blocks, the rail and
// the touch input are all derived from ONE geometry — a block always lands
// exactly on the key it names, at any width, in any projection. That is the
// whole trick; everything else in the view is decoration.
//
// Unit-tested in test/highway_lanes_test.dart.

import 'package:comet_beat/core/games/highway/highway_chart.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart' show Tuning;

/// Where something sits horizontally, in unit space (0 = left, 1 = right).
class HighwaySlot {
  const HighwaySlot({
    required this.center,
    required this.width,
    this.raised = false,
  });

  final double center;
  final double width;

  /// Drawn in the upper (short) row of the rail and painted OVER its
  /// neighbours — a piano's black keys. Everything else is flush.
  final bool raised;

  double get left => center - width / 2;
  double get right => center + width / 2;

  @override
  String toString() =>
      'HighwaySlot(${center.toStringAsFixed(3)} ±${(width / 2).toStringAsFixed(3)}'
      '${raised ? ', raised' : ''})';
}

/// A vertical rule of the background grid, at unit [position].
class HighwayGridLine {
  const HighwayGridLine(this.position, {this.label, this.major = false});

  final double position;

  /// Drawn at the foot of the line when there is room (e.g. `C4`, `A`).
  final String? label;

  /// Heavier stroke — an octave boundary, or a string that anchors the hand.
  final bool major;
}

/// One touchable key of the instrument rail drawn at the hit line.
class HighwayRailKey {
  const HighwayRailKey({
    required this.slot,
    required this.lane,
    this.midi,
    this.label,
  });

  final HighwaySlot slot;

  /// Lane index — for lane-graded instruments (a string, a drum piece).
  final int lane;

  /// The pitch this key plays, when the instrument has one per key.
  final int? midi;

  /// Short label drawn on the key (`C`, `A`, `Kick`).
  final String? label;
}

/// Maps highway events onto horizontal space, and taps back onto events.
abstract class HighwayLaneMap {
  const HighwayLaneMap();

  /// How many discrete lanes exist (strings, pads). Pitch-continuous maps
  /// report the number of rail keys.
  int get laneCount;

  /// How much of a slot a falling block fills. Maps whose slots already leave
  /// a gap (string lanes, pads) return 1; a keyboard's white keys tile edge to
  /// edge, so its blocks are inset a little or two adjacent notes read as one
  /// wide block.
  double get blockFill => 1;

  /// Where [event] falls. Null = this event has no place here (out of range).
  HighwaySlot? slotFor(HighwayEvent event);

  /// Where a bare pitch falls — the live-input marker, the key-lighting.
  HighwaySlot? slotForMidi(int midi);

  /// The background grid.
  List<HighwayGridLine> gridLines();

  /// The rail, in draw order (raised keys last, so they sit on top).
  List<HighwayRailKey> railKeys();

  /// Which rail key a tap at unit ([x], [yFrac]) hits. [yFrac] is 0 at the top
  /// of the rail and 1 at the bottom, so a piano can tell a black key from the
  /// white key below it.
  HighwayRailKey? hitTest(double x, double yFrac);

  /// Does [event] belong to what the player just played? Pitch instruments
  /// compare pitch; lane instruments (strings, pads) compare lane, because on
  /// a touchscreen the lane IS what the player chose.
  bool matches(HighwayEvent event, HighwayRailKey key);
}

// ---------------------------------------------------------------------------
// Piano
// ---------------------------------------------------------------------------

const List<int> _whitePitchClasses = [0, 2, 4, 5, 7, 9, 11];

bool _isWhite(int midi) => _whitePitchClasses.contains(midi % 12);

/// Blocks land on the actual key they are played on: white keys tile the
/// width, black keys are narrower, sit on the boundary between their
/// neighbours, and are drawn raised.
class KeyboardLaneMap extends HighwayLaneMap {
  KeyboardLaneMap({required int lowMidi, required int highMidi})
      : assert(highMidi >= lowMidi),
        _low = _snapDownToWhite(lowMidi),
        _high = _snapUpToWhite(highMidi) {
    for (var m = _low; m <= _high; m++) {
      if (_isWhite(m)) {
        _whiteIndex[m] = _whites.length;
        _whites.add(m);
      }
    }
  }

  /// A comfortable keyboard around a piece's range: the exact span, padded a
  /// little, widened to at least [minWhiteKeys] white keys so a two-note
  /// exercise does not draw two enormous keys, and snapped to C boundaries so
  /// the octave grid reads cleanly.
  factory KeyboardLaneMap.forRange(
    int lowMidi,
    int highMidi, {
    int minWhiteKeys = 15,
    int pad = 2,
  }) {
    var lo = lowMidi - pad;
    var hi = highMidi + pad;
    // Grow to the minimum width, alternating sides so the music stays centred.
    while (_whiteCount(lo, hi) < minWhiteKeys) {
      if (_whiteCount(lo, hi).isEven) {
        lo--;
      } else {
        hi++;
      }
    }
    // Snap outward to the nearest C so every octave line has a label.
    lo -= lo % 12;
    hi += 11 - hi % 12;
    return KeyboardLaneMap(lowMidi: lo, highMidi: hi);
  }

  final int _low;
  final int _high;
  final List<int> _whites = [];
  final Map<int, int> _whiteIndex = {};

  int get lowMidi => _low;
  int get highMidi => _high;
  int get whiteKeyCount => _whites.length;

  static int _snapDownToWhite(int m) => _isWhite(m) ? m : m - 1;
  static int _snapUpToWhite(int m) => _isWhite(m) ? m : m + 1;

  static int _whiteCount(int lo, int hi) {
    var n = 0;
    for (var m = lo; m <= hi; m++) {
      if (_isWhite(m)) n++;
    }
    return n;
  }

  @override
  int get laneCount => _whites.length;

  @override
  double get blockFill => 0.88;

  @override
  HighwaySlot? slotFor(HighwayEvent event) =>
      event.midi == null ? null : slotForMidi(event.midi!);

  @override
  HighwaySlot? slotForMidi(int midi) {
    if (midi < _low || midi > _high || _whites.isEmpty) return null;
    final n = _whites.length;
    if (_isWhite(midi)) {
      final i = _whiteIndex[midi]!;
      return HighwaySlot(center: (i + 0.5) / n, width: 1 / n);
    }
    // A black key sits on the boundary above the white key a semitone below.
    final belowIndex = _whiteIndex[midi - 1];
    if (belowIndex == null) return null;
    return HighwaySlot(
      center: (belowIndex + 1) / n,
      width: 0.62 / n,
      raised: true,
    );
  }

  List<HighwayGridLine>? _gridCache;
  List<HighwayRailKey>? _railCache;

  @override
  List<HighwayGridLine> gridLines() => _gridCache ??= _buildGridLines();

  List<HighwayGridLine> _buildGridLines() {
    final out = <HighwayGridLine>[];
    final n = _whites.length;
    if (n == 0) return out;
    for (var m = _low; m <= _high; m++) {
      if (m % 12 != 0) continue; // every C
      final i = _whiteIndex[m];
      if (i == null) continue;
      out.add(
        HighwayGridLine(
          i / n,
          label: 'C${m ~/ 12 - 1}',
          major: true,
        ),
      );
    }
    // A light rule at every F as well, so an octave reads as 3 + 4 keys
    // instead of one undivided block.
    for (var m = _low; m <= _high; m++) {
      if (m % 12 != 5) continue;
      final i = _whiteIndex[m];
      if (i != null) out.add(HighwayGridLine(i / n));
    }
    return out;
  }

  @override
  List<HighwayRailKey> railKeys() => _railCache ??= _buildRailKeys();

  List<HighwayRailKey> _buildRailKeys() {
    final out = <HighwayRailKey>[];
    for (final m in _whites) {
      out.add(
        HighwayRailKey(
          slot: slotForMidi(m)!,
          lane: _whiteIndex[m]!,
          midi: m,
          label: m % 12 == 0 ? 'C${m ~/ 12 - 1}' : null,
        ),
      );
    }
    for (var m = _low; m <= _high; m++) {
      if (_isWhite(m)) continue;
      final slot = slotForMidi(m);
      if (slot != null) {
        out.add(HighwayRailKey(slot: slot, lane: _whiteIndex[m - 1]!, midi: m));
      }
    }
    return out;
  }

  /// The black keys occupy the top [blackKeyHeightFraction] of the rail.
  static const double blackKeyHeightFraction = 0.62;

  @override
  HighwayRailKey? hitTest(double x, double yFrac) {
    HighwayRailKey? white;
    for (final key in railKeys()) {
      if (x < key.slot.left || x > key.slot.right) continue;
      if (key.slot.raised) {
        if (yFrac <= blackKeyHeightFraction) return key; // black wins up top
      } else {
        white = key;
      }
    }
    return white;
  }

  @override
  bool matches(HighwayEvent event, HighwayRailKey key) =>
      event.midi != null && event.midi == key.midi;
}

// ---------------------------------------------------------------------------
// Fretted and bowed strings
// ---------------------------------------------------------------------------

/// One lane per string, string 1 (highest) on the right so the lanes read like
/// a fretboard seen by the player — low strings to the left, as on a keyboard.
/// Blocks carry the fret number as their caption (set by the chart builder).
class StringLaneMap extends HighwayLaneMap {
  StringLaneMap(this.tuning, {this.laneFill = 0.78});

  final Tuning tuning;

  /// How much of a lane a block fills — the gap is what makes the grid read.
  final double laneFill;

  @override
  int get laneCount => tuning.stringCount;

  /// Lane 0 is drawn leftmost = the LOWEST string, so pitch still rises to the
  /// right (the same mental model as the keyboard view). `Tuning.strings` is
  /// ordered highest-first, so the two are mirrored.
  int _xLaneOf(int stringIndex) => tuning.stringCount - 1 - stringIndex;

  HighwaySlot _slotOfLane(int xLane) => HighwaySlot(
        center: (xLane + 0.5) / tuning.stringCount,
        width: laneFill / tuning.stringCount,
      );

  @override
  HighwaySlot? slotFor(HighwayEvent event) {
    final s = event.lane ?? _stringForMidi(event.midi);
    if (s == null || s < 0 || s >= tuning.stringCount) return null;
    return _slotOfLane(_xLaneOf(s));
  }

  @override
  HighwaySlot? slotForMidi(int midi) {
    final s = _stringForMidi(midi);
    return s == null ? null : _slotOfLane(_xLaneOf(s));
  }

  /// Fallback when a chart carries no fretting: the highest string that can
  /// reach the pitch at a low fret — what a beginner would pick.
  int? _stringForMidi(int? midi) {
    if (midi == null) return null;
    int? best;
    var bestFret = 1 << 30;
    for (var s = 0; s < tuning.stringCount; s++) {
      final open = tuning.strings[s].midiNumber;
      final fret = midi - open;
      if (fret < 0 || fret > 20) continue;
      if (fret < bestFret) {
        bestFret = fret;
        best = s;
      }
    }
    return best;
  }

  @override
  List<HighwayGridLine> gridLines() => [
        for (var x = 1; x < tuning.stringCount; x++)
          HighwayGridLine(x / tuning.stringCount),
      ];

  @override
  List<HighwayRailKey> railKeys() => [
        for (var s = tuning.stringCount - 1; s >= 0; s--)
          HighwayRailKey(
            slot: _slotOfLane(_xLaneOf(s)),
            lane: s,
            midi: tuning.strings[s].midiNumber,
            label: tuning.strings[s].step.name.toUpperCase(),
          ),
      ];

  @override
  HighwayRailKey? hitTest(double x, double yFrac) {
    final xLane = (x * tuning.stringCount).floor();
    if (xLane < 0 || xLane >= tuning.stringCount) return null;
    final s = tuning.stringCount - 1 - xLane;
    return HighwayRailKey(
      slot: _slotOfLane(xLane),
      lane: s,
      midi: tuning.strings[s].midiNumber,
      label: tuning.strings[s].step.name.toUpperCase(),
    );
  }

  /// On a touchscreen the player chooses a STRING, not a fret — grading the
  /// fret would need a real instrument. So the lane is the answer.
  @override
  bool matches(HighwayEvent event, HighwayRailKey key) =>
      (event.lane ?? _stringForMidi(event.midi)) == key.lane;
}

// ---------------------------------------------------------------------------
// Pads (the simplified arcade mode)
// ---------------------------------------------------------------------------

/// N equal lanes with pitch collapsed onto them by contour — the mode for
/// players who cannot yet play the real thing, and for pieces that are too
/// hard to. Also the drum-kit map, where the lane is the kit piece.
class PadLaneMap extends HighwayLaneMap {
  PadLaneMap({
    required this.laneCount,
    this.lowMidi,
    this.highMidi,
    this.labels = const [],
    this.laneFill = 0.72,
  });

  /// Contour mapping for a melodic chart: [laneCount] equal pitch bands
  /// between the piece's lowest and highest note.
  factory PadLaneMap.forChart(HighwayChart chart, {int laneCount = 4}) =>
      PadLaneMap(
        laneCount: laneCount,
        lowMidi: chart.lowMidi,
        highMidi: chart.highMidi,
      );

  @override
  final int laneCount;

  final int? lowMidi;
  final int? highMidi;
  final List<String> labels;
  final double laneFill;

  HighwaySlot _slotOfLane(int lane) => HighwaySlot(
        center: (lane + 0.5) / laneCount,
        width: laneFill / laneCount,
      );

  int? _laneOf(HighwayEvent e) {
    if (e.lane != null) return e.lane!.clamp(0, laneCount - 1);
    final midi = e.midi;
    final lo = lowMidi, hi = highMidi;
    if (midi == null || lo == null || hi == null) return null;
    if (hi <= lo) return 0;
    final t = (midi - lo) / (hi - lo);
    return (t * laneCount).floor().clamp(0, laneCount - 1);
  }

  @override
  HighwaySlot? slotFor(HighwayEvent event) {
    final lane = _laneOf(event);
    return lane == null ? null : _slotOfLane(lane);
  }

  @override
  HighwaySlot? slotForMidi(int midi) =>
      slotFor(HighwayEvent(startBeat: 0, beats: 1, midi: midi));

  @override
  List<HighwayGridLine> gridLines() => [
        for (var i = 1; i < laneCount; i++) HighwayGridLine(i / laneCount),
      ];

  @override
  List<HighwayRailKey> railKeys() => [
        for (var i = 0; i < laneCount; i++)
          HighwayRailKey(
            slot: _slotOfLane(i),
            lane: i,
            label: i < labels.length ? labels[i] : null,
          ),
      ];

  @override
  HighwayRailKey? hitTest(double x, double yFrac) {
    final lane = (x * laneCount).floor();
    if (lane < 0 || lane >= laneCount) return null;
    return HighwayRailKey(
      slot: _slotOfLane(lane),
      lane: lane,
      label: lane < labels.length ? labels[lane] : null,
    );
  }

  @override
  bool matches(HighwayEvent event, HighwayRailKey key) =>
      _laneOf(event) == key.lane;
}

// ---------------------------------------------------------------------------
// Continuous pitch (voice, bowed, wind)
// ---------------------------------------------------------------------------

/// Pitch as a continuous axis — the original play-along highway. Nothing
/// quantises to a key, so a slide or a scoop is visible as motion between
/// blocks, which is exactly what a singer or a cellist needs to see.
class PitchLaneMap extends HighwayLaneMap {
  const PitchLaneMap({required this.lowMidi, required this.highMidi});

  factory PitchLaneMap.forChart(HighwayChart chart, {int pad = 3}) {
    final lo = chart.lowMidi ?? 60;
    final hi = chart.highMidi ?? 72;
    return PitchLaneMap(lowMidi: lo - pad, highMidi: hi + pad);
  }

  final int lowMidi;
  final int highMidi;

  int get _span => (highMidi - lowMidi) <= 0 ? 1 : highMidi - lowMidi;

  @override
  int get laneCount => _span + 1;

  double _x(num midi) => (midi - lowMidi) / _span;

  @override
  HighwaySlot? slotFor(HighwayEvent event) =>
      event.midi == null ? null : slotForMidi(event.midi!);

  @override
  HighwaySlot? slotForMidi(int midi) {
    if (midi < lowMidi || midi > highMidi) return null;
    return HighwaySlot(center: _x(midi), width: 0.72 / _span);
  }

  /// Where a *fractional* pitch sits — the live microphone trace, which is
  /// continuous by nature.
  double xForPitch(double midi) => _x(midi).clamp(0.0, 1.0);

  @override
  List<HighwayGridLine> gridLines() => [
        for (var m = lowMidi + ((12 - lowMidi % 12) % 12);
            m <= highMidi;
            m += 12)
          HighwayGridLine(_x(m), label: 'C${m ~/ 12 - 1}', major: true),
      ];

  @override
  List<HighwayRailKey> railKeys() => [
        for (var m = lowMidi; m <= highMidi; m++)
          if (m % 12 == 0)
            HighwayRailKey(
              slot: HighwaySlot(center: _x(m), width: 0.72 / _span),
              lane: m - lowMidi,
              midi: m,
              label: 'C${m ~/ 12 - 1}',
            ),
      ];

  @override
  HighwayRailKey? hitTest(double x, double yFrac) {
    final midi = (lowMidi + x * _span).round();
    if (midi < lowMidi || midi > highMidi) return null;
    return HighwayRailKey(
      slot: slotForMidi(midi)!,
      lane: midi - lowMidi,
      midi: midi,
    );
  }

  @override
  bool matches(HighwayEvent event, HighwayRailKey key) =>
      event.midi == key.midi;
}
