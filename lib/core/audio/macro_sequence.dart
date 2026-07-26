// lib/core/audio/macro_sequence.dart
//
// Instrument MACROS (roadmap §4): a per-TICK modulation sequence — the classic
// tracker/Furnace instrument envelope, one value stepped off every tick, with a
// sustain loop and an optional release segment. Distinct from the point-based
// [DocEnvelope] (which interpolates between `(tick, value)` breakpoints over a
// note): a macro is a raw step table, which is how chiptune volume/arpeggio/duty
// modulation is actually authored.
//
// This file is the pure MODEL + evaluation only — no rendering, no Flutter — so
// it unit-tests exhaustively. Wiring a macro into the per-tick voices is a
// separate, opt-in step; an absent macro changes nothing.

/// What a macro modulates. The stored values are raw ints; the CONSUMER decides
/// the scale (see the per-target notes), so one model serves every target.
enum MacroTarget {
  /// 0..64 (tracker volume). The voice multiplies amplitude by `value / 64`.
  volume,

  /// Signed semitone offset added to the note's pitch (a pitch envelope).
  pitch,

  /// Signed semitone offset added to the note (an arpeggio table — usually a
  /// short 0/+x/+y loop). Same units as [pitch]; kept separate so a voice can
  /// carry both a slow pitch bend and a fast arpeggio at once.
  arpeggio,

  /// -32..+32 pan offset around centre (0). The voice maps it to its pan law.
  pan,

  /// 0..63 pulse-width / duty for a square/pulse voice; ignored by voices that
  /// have no duty.
  duty,
}

/// A per-tick step table for one [target].
///
/// Playback advances one entry per tick from note-on (`tick == 0`). Semantics
/// (matching common trackers):
///  * **Sustain** — steps forward through [values]; once past [loopEnd] it loops
///    the inclusive `[loopStart, loopEnd]` segment forever (while the note is
///    held). With no valid loop it plays to the end and holds the last value.
///  * **Release** — when the note is released (a `releaseTick` is supplied) and a
///    [releaseStart] is set, playback jumps to that index and steps forward once
///    per tick to the end, holding the last value (no looping past release). With
///    no [releaseStart], release does not affect the macro — the note's own
///    fadeout silences it.
class MacroSequence {
  const MacroSequence({
    required this.target,
    required this.values,
    this.loopStart,
    this.loopEnd,
    this.releaseStart,
  });

  final MacroTarget target;

  /// One value per tick step. Empty means "no macro" (see [isEmpty]).
  final List<int> values;

  /// Inclusive sustain-loop bounds (indices into [values]); both must be set,
  /// in range, and `loopEnd >= loopStart` for the loop to apply.
  final int? loopStart;
  final int? loopEnd;

  /// Index playback jumps to on note-off; null = release has no effect.
  final int? releaseStart;

  bool get isEmpty => values.isEmpty;

  /// Whether [loopStart]/[loopEnd] form a usable sustain loop.
  bool get hasLoop {
    final ls = loopStart, le = loopEnd;
    return ls != null &&
        le != null &&
        ls >= 0 &&
        le >= ls &&
        le < values.length;
  }

  int _clampIndex(int i) {
    if (i < 0) return 0;
    final last = values.length - 1;
    return i > last ? last : i;
  }

  /// The step index that [tick] (0-based ticks since note-on) maps to, honoring
  /// the sustain loop and — when [releaseTick] is non-null — the release segment.
  int indexAt(int tick, {int? releaseTick}) {
    assert(values.isNotEmpty, 'indexAt on an empty macro');
    final t = tick < 0 ? 0 : tick;

    // Release segment: step forward from releaseStart, no loop, clamp at end.
    if (releaseTick != null && releaseStart != null && t >= releaseTick) {
      return _clampIndex(releaseStart! + (t - releaseTick));
    }

    // Sustain with a loop: linear up to loopEnd, then wrap the loop segment.
    if (hasLoop) {
      final ls = loopStart!, le = loopEnd!;
      if (t <= le) return _clampIndex(t);
      final loopLen = le - ls + 1;
      return ls + ((t - ls) % loopLen);
    }

    // Sustain, no loop: linear, hold the last value.
    return _clampIndex(t);
  }

  /// The macro VALUE at [tick] ([fallback] when the macro is empty).
  int valueAt(int tick, {int? releaseTick, int fallback = 0}) =>
      isEmpty ? fallback : values[indexAt(tick, releaseTick: releaseTick)];

  MacroSequence copyWith({
    MacroTarget? target,
    List<int>? values,
    int? loopStart,
    int? loopEnd,
    int? releaseStart,
    bool clearLoop = false,
    bool clearRelease = false,
  }) =>
      MacroSequence(
        target: target ?? this.target,
        values: values ?? this.values,
        loopStart: clearLoop ? null : (loopStart ?? this.loopStart),
        loopEnd: clearLoop ? null : (loopEnd ?? this.loopEnd),
        releaseStart: clearRelease ? null : (releaseStart ?? this.releaseStart),
      );

  Map<String, dynamic> toJson() => {
        'target': target.name,
        'values': values,
        if (loopStart != null) 'loopStart': loopStart,
        if (loopEnd != null) 'loopEnd': loopEnd,
        if (releaseStart != null) 'releaseStart': releaseStart,
      };

  /// Decodes a macro; returns null on anything malformed (a corrupt macro costs
  /// modulation, never the instrument).
  static MacroSequence? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final targetName = raw['target'];
    if (targetName is! String) return null;
    final target =
        MacroTarget.values.where((t) => t.name == targetName).firstOrNull;
    if (target == null) return null;
    final rawValues = raw['values'];
    if (rawValues is! List) return null;
    final values = <int>[
      for (final v in rawValues)
        if (v is num) v.toInt(),
    ];
    int? asInt(Object? v) => v is num ? v.toInt() : null;
    return MacroSequence(
      target: target,
      values: values,
      loopStart: asInt(raw['loopStart']),
      loopEnd: asInt(raw['loopEnd']),
      releaseStart: asInt(raw['releaseStart']),
    );
  }
}
