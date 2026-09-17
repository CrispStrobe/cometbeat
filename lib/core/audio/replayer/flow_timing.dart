// Flow expansion, tempo/speed state, and playhead timing resolution.
// Part of tracker_replayer to preserve its public API and private helpers.
part of '../tracker_replayer.dart';

// --- Flow (phase 3): Bxx position jump + Dxx pattern break -------------------

/// One row actually played, in playback order — the output of [walkFlow].
/// [ticksPerRow] (speed) and [tempoBpm] carry the Fxx state IN EFFECT for this
/// row, so a mid-song tempo/speed change gives each row its own duration and
/// effect granularity. Added as positional-optional with defaults so existing
/// callers/tests stay source-compatible; `tempoBpm == 0` means "song default".
class PlayedRow {
  const PlayedRow(
    this.orderIndex,
    this.patternIndex,
    this.row, [
    this.ticksPerRow = kDefaultTicksPerRow,
    this.tempoBpm = 0,
  ]);

  final int orderIndex;
  final int patternIndex;
  final int row;

  /// The speed (ticks/row) in effect for THIS row (Fxx `param < 0x20`).
  final int ticksPerRow;

  /// The tempo (BPM) in effect for THIS row (Fxx `param >= 0x20`); 0 = the
  /// song's own [TrackerTiming.tempoBpm].
  final int tempoBpm;

  @override
  String toString() => 'PlayedRow(order $orderIndex, pat $patternIndex, '
      'row $row)';
}

/// Whether any cell in [song] carries a flow command (Bxx/Dxx) — the gate that
/// routes [replaySong] through the [walkFlow] path.
bool songUsesFlow(TrackerSong song) => song.patterns.any(
      (p) => p.cells.any(
        (col) => col.any(
          (c) =>
              c.fxCmd == kFxPositionJump ||
              c.fxCmd == kFxPatternBreak ||
              (c.fxCmd == kFxExtended &&
                  (((c.fxParam >> 4) & 0xF) == kExPatternLoop ||
                      ((c.fxParam >> 4) & 0xF) == kExPatternDelay)),
        ),
      ),
    );

/// Whether every pattern referenced by [song.order] has exactly
/// [song.timing.rows] rows — the classic uniform-length assumption. When false,
/// patterns vary in length (Feature B), so the render must route through the
/// walk/flatten path ([_replayFlow]) instead of the fixed-size concatenation,
/// exactly like a flow song. A uniform-length song stays on the fast path and
/// renders bit-for-bit as before.
bool songHasUniformPatternLengths(TrackerSong song) {
  final r = song.timing.rows;
  for (final oi in song.order) {
    if (oi < 0 || oi >= song.patterns.length) continue;
    if (song.patterns[oi].rows != r) return false;
  }
  return true;
}

/// Whether [song] must render through the walk/flatten path — because it carries
/// flow commands OR its patterns vary in length. The uniform, flow-free song
/// keeps the fast fixed-size render.
bool songNeedsWalkRender(TrackerSong song) =>
    songUsesFlow(song) || !songHasUniformPatternLengths(song);

/// Whether any cell in [song] carries an `Fxx` speed/tempo OR a `Txx` tempo-slide
/// command at all — a cheap pre-filter so the common command-free/single-tempo
/// song never pays for the [walkFlow] scan in [songUsesVariableTiming]. Both
/// change the per-row tempo, so both must arm the variable-timing render.
bool _songHasFxx(TrackerSong song) => song.patterns.any(
      (p) => p.cells.any(
        (col) => col.any(
          (c) =>
              c.fxCmd == kFxSetSpeed ||
              c.fxCmd == kFxSetSpeedFull ||
              c.fxCmd == kFxTempoSlide,
        ),
      ),
    );

/// Whether [song] has a MID-SONG tempo/speed change — i.e. its played rows do
/// NOT all share one tempo AND one speed (more than one distinct `Fxx` value in
/// play order, OR a value that first takes effect after play-position 0, e.g. a
/// later order entry changing tempo while the first plays at the song default).
/// When true, [replaySong] routes through the per-row-duration variable render;
/// a song with a single (or no) value returns false → the uniform/flow path is
/// used unchanged (byte-identical). The caller is expected to have synced the
/// live pattern (like [songUsesFlow]).
bool songUsesVariableTiming(TrackerSong song) {
  final initialSpeed =
      song.initialSpeed > 0 ? song.initialSpeed : kDefaultTicksPerRow;
  if (!_songHasFxx(song) && initialSpeed == kDefaultTicksPerRow) return false;
  final played = walkFlow(song);
  if (played.length < 2) return false;
  for (final p in played) {
    if (p.ticksPerRow != kDefaultTicksPerRow) return true;
  }
  final tempo0 = played.first.tempoBpm;
  for (final p in played) {
    if (p.tempoBpm != tempo0) return true;
  }
  return false;
}

// There used to be a `_rowMsFor(tempo, ticks)` here returning a row's duration
// ROUNDED to whole milliseconds, and four callers that accumulated its result.
// That rounding is precisely the bug [rowOnsets] exists to remove, so the
// function is gone rather than left available: every row boundary, in
// milliseconds or in samples, now comes from one exact accumulator. If you find
// yourself wanting a single row's duration as an int, take the difference of
// two `rowOnsets` entries instead of reintroducing the rounding.

/// The onset of each played row, in units of [perSecond] units per second —
/// 1000 for milliseconds, [kSampleRate] for samples. The result has
/// `played.length + 1` entries; the last is the end of the song.
///
/// What matters here is WHERE the rounding happens. A classic tracker row lasts
/// `speed * 2.5 / bpm` seconds, which is a whole number of milliseconds only at
/// convenient tempos: 125 BPM at speed 6 is exactly 120 ms, but 160 BPM is
/// 93.75 and 80 BPM is 187.5. Rounding each row and then ADDING the rounded
/// values compounds the error in one direction forever.
///
/// It was doing exactly that. On `test/fixtures/flow/tempo_change_Fxx.mod` our
/// render came out 20.720 s where libopenmpt, libxmp and NodMOD all agree on
/// 20.670 — 50 ms long, from +0.25 ms on each of 24 rows at 160 BPM and +0.5 ms
/// on each of 88 rows at 80 BPM. The error is unbounded: it grows with the row
/// count, so a long module at an awkward tempo drifts by seconds, and the
/// playhead drifts against the audio because both read this.
///
/// Accumulating the exact duration and rounding only at each boundary holds the
/// error below half a unit no matter how long the song is. (PLAN.md §6 X5.)
List<int> rowOnsets(List<PlayedRow> played, int defaultBpm, int perSecond) {
  final out = List<int>.filled(played.length + 1, 0);
  var seconds = 0.0;
  for (var i = 0; i < played.length; i++) {
    out[i] = (seconds * perSecond).round();
    final bpm = played[i].tempoBpm > 0 ? played[i].tempoBpm : defaultBpm;
    final ticks = played[i].ticksPerRow <= 0
        ? kDefaultTicksPerRow
        : played[i].ticksPerRow;
    seconds += ticks * 2.5 / bpm;
  }
  out[played.length] = (seconds * perSecond).round();
  return out;
}

/// The accumulated onset (ms) of each played row, honouring per-row tempo. Entry
/// `i` is the ms offset where played row `i` begins; the sum of all step
/// durations is the song length ([variableSongTotalMs]).
List<int> _variableRowStartMs(TrackerSong song, List<PlayedRow> played) =>
    rowOnsets(played, song.timing.tempoBpm, 1000).sublist(0, played.length);

/// The total song length (ms) as the SUM of per-row durations under a mid-song
/// tempo change — used by [TrackerSong.songTotalMs] when [songUsesVariableTiming].
int variableSongTotalMs(TrackerSong song) =>
    rowOnsets(walkFlow(song), song.timing.tempoBpm, 1000).last;

/// The total song length in SAMPLES under a mid-song tempo/speed change.
///
/// Deliberately not `songTotalMs * kSampleRate / 1000`: milliseconds are a
/// coarser grid than samples (one ms is 44.1 of them), so going through the
/// rounded millisecond total put the transport up to a millisecond away from
/// the render it is supposed to describe. Both now come from the same exact
/// accumulator, so they agree to the sample.
int variableSongTotalSamples(TrackerSong song) =>
    rowOnsets(walkFlow(song), song.timing.tempoBpm, kSampleRate).last;

/// Expands [song]'s order/pattern/row walk under the flow rules (Bxx jump, Dxx
/// break, E6x pattern loop) into the flat sequence of rows actually played. Bxx
/// wins the order, Dxx sets the landing row; both on one row ⇒ jump order + break
/// row. E60 marks a loop start, E6x (x>0) repeats the marked span x extra times.
/// Guarded by [maxRows] as a last resort. A Bxx/Dxx landing on an order-row that
/// already played is treated as the module's intentional song loop and stops the
/// offline render instead of unrolling to the cap.
List<PlayedRow> walkFlow(TrackerSong song, {int maxRows = 65536}) {
  final order = song.order;
  final played = <PlayedRow>[];
  final visitedOrderRows = <(int, int)>{};
  var oi = 0;
  var row = 0;
  var loopStartRow = 0; // E6x pattern-loop start (defaults to row 0)
  var loopCount = 0; // remaining E6x repeats
  // Fxx state carried across rows: speed (ticks/row) + tempo (BPM). A value takes
  // effect ON its own row and persists until the next Fxx of that kind.
  var curSpeed = song.initialSpeed;
  var curTempo = song.timing.tempoBpm;
  while (oi >= 0 && oi < order.length && played.length < maxRows) {
    final patternIndex = order[oi];
    final cells = song.patterns[patternIndex].cells;
    // Per-pattern length: each entry uses ITS OWN row count (Feature B). A jump/
    // break landing row is clamped to the TARGET pattern's length here.
    final rows = song.patterns[patternIndex].rows;
    if (row < 0) {
      row = 0;
    } else if (row >= rows) {
      row = rows - 1;
    }
    visitedOrderRows.add((oi, row));

    // Apply any Fxx (set-speed/tempo) or Txx (tempo SLIDE) on this row BEFORE
    // recording it (effect is on its own row): Fxx param < 0x20 → speed (min 1),
    // >= 0x20 → tempo (BPM) (Feature A); Txx steps the tempo by amount×(speed−1),
    // row-granular. First Txx across channels wins.
    var slidThisRow = false;
    for (final col in cells) {
      final c = col[row];
      if (c.fxCmd == kFxSetSpeed) {
        if (c.fxParam >= 0x20) {
          curTempo = c.fxParam;
        } else if (c.fxParam > 0) {
          curSpeed = c.fxParam; // already >= 1
        }
      } else if (c.fxCmd == kFxSetSpeedFull) {
        // IT/S3M Axx: always speed, never tempo, full range.
        if (c.fxParam > 0) curSpeed = c.fxParam.clamp(1, 255);
      } else if (c.fxCmd == kFxTempoSlide && !slidThisRow) {
        slidThisRow = true;
        final up = ((c.fxParam >> 4) & 0xF) == 1;
        final amount = c.fxParam & 0xF;
        final ticks = curSpeed > 1 ? curSpeed - 1 : 1;
        curTempo = (curTempo + (up ? amount : -amount) * ticks).clamp(32, 255);
      }
    }
    played.add(PlayedRow(oi, patternIndex, row, curSpeed, curTempo));

    // EEx pattern delay: repeat THIS row x additional times (x+1 total) before
    // advancing. The extra copies re-run the row (additive voices re-trigger on
    // each), lengthening it consistently across walk → timing → render. First
    // EEx on the row wins; delay of 0 is a no-op.
    int? patternDelay;
    for (final col in cells) {
      final c = col[row];
      if (c.fxCmd == kFxExtended &&
          ((c.fxParam >> 4) & 0xF) == kExPatternDelay) {
        patternDelay ??= c.fxParam & 0xF;
      }
    }
    if (patternDelay != null && patternDelay > 0) {
      for (var i = 0; i < patternDelay && played.length < maxRows; i++) {
        played.add(PlayedRow(oi, patternIndex, row, curSpeed, curTempo));
      }
    }

    // Scan the row across channels for flow commands (first of each wins).
    int? jumpToOrder;
    int? breakToRow;
    int? loopValue; // E6x low nibble (0 = set the loop start)
    for (final col in cells) {
      final c = col[row];
      if (c.fxCmd == kFxPositionJump) {
        jumpToOrder ??= c.fxParam;
      } else if (c.fxCmd == kFxPatternBreak) {
        // Decimal row param; clamped to the TARGET pattern's length at landing.
        breakToRow ??= (c.fxParam >> 4) * 10 + (c.fxParam & 0xF);
      } else if (c.fxCmd == kFxExtended &&
          ((c.fxParam >> 4) & 0xF) == kExPatternLoop) {
        loopValue ??= c.fxParam & 0xF;
      }
    }

    void advance() {
      row += 1;
      if (row >= rows) {
        oi += 1;
        row = 0;
      }
    }

    bool wouldReplayOrderRow(int targetOrder, int targetRow) {
      if (targetOrder < 0 || targetOrder >= order.length) return false;
      final targetPattern = order[targetOrder];
      if (targetPattern < 0 || targetPattern >= song.patterns.length) {
        return false;
      }
      final targetRows = song.patterns[targetPattern].rows;
      final clampedRow = targetRow.clamp(0, targetRows - 1);
      return visitedOrderRows.contains((targetOrder, clampedRow));
    }

    if (jumpToOrder != null) {
      final targetRow = breakToRow ?? 0;
      if (wouldReplayOrderRow(jumpToOrder, targetRow)) break;
      oi = jumpToOrder;
      row = targetRow;
    } else if (breakToRow != null) {
      if (wouldReplayOrderRow(oi + 1, breakToRow)) break;
      oi += 1;
      row = breakToRow;
    } else if (loopValue == 0) {
      loopStartRow = row; // E60 marks the loop start, then plays on
      advance();
    } else if (loopValue != null && loopValue > 0) {
      if (loopCount == 0) {
        loopCount = loopValue; // arm the loop
        row = loopStartRow;
      } else {
        loopCount -= 1;
        if (loopCount > 0) {
          row = loopStartRow;
        } else {
          advance(); // loop finished
        }
      }
    } else {
      advance();
    }
  }
  return played;
}

/// The first `Fxx` value in [columns] (scanned row-major) of the requested kind:
/// [wantTempo] false → a SET-SPEED (`0 < param < 0x20`, ticks/row); [wantTempo]
/// true → a SET-TEMPO (param ≥ 0x20, BPM). Returns -1 if none of that kind.
int _firstFxx(
  List<List<TrackerCell>> columns,
  int rows, {
  required bool wantTempo,
}) {
  for (var r = 0; r < rows; r++) {
    for (final col in columns) {
      if (r < col.length) {
        final c = col[r];
        if (c.fxCmd == kFxSetSpeed) {
          final isTempo = c.fxParam >= 0x20;
          if (wantTempo && isTempo) return c.fxParam;
          if (!wantTempo && c.fxParam > 0 && !isTempo) return c.fxParam;
        } else if (c.fxCmd == kFxSetSpeedFull && !wantTempo) {
          // Never a tempo, so it only ever answers the speed question.
          if (c.fxParam > 0) return c.fxParam;
        }
      }
    }
  }
  return -1;
}

/// The speed ([TrackerTiming]-independent ticks/row) a song should replay at: the
/// first `Fxx` set-speed command in play order, else [fallback]. Applied by
/// [replaySong] so an imported/authored module's authored speed sets the effect
/// granularity. Tracker rows last `speed * 2500 / bpm` ms, so imported module
/// speed affects both duration and per-tick effect cadence.
int songInitialSpeed(TrackerSong song, {int fallback = kDefaultTicksPerRow}) {
  for (final oi in song.order) {
    if (oi < 0 || oi >= song.patterns.length) continue;
    final s =
        _firstFxx(song.patterns[oi].cells, song.timing.rows, wantTempo: false);
    if (s > 0) return s;
  }
  return fallback;
}

/// The tempo (BPM) a song should replay at: the first `Fxx` set-tempo command
/// (param ≥ 0x20) in play order, else `null` (use the song's own tempo). This is
/// applied uniformly to the whole render (like the initial tempo a module sets at
/// the top) — mid-song tempo CHANGES need the per-row-duration rework and are a
/// follow-up. Because it's uniform, [TrackerSong.songTotalMs] applies the same
/// value so the render length stays consistent.
int? songInitialTempo(TrackerSong song) {
  for (final oi in song.order) {
    if (oi < 0 || oi >= song.patterns.length) continue;
    final t =
        _firstFxx(song.patterns[oi].cells, song.timing.rows, wantTempo: true);
    if (t > 0) return t.clamp(32, 255);
  }
  return null;
}

/// [song.timing] with the initial `Fxx` set-tempo applied (if any) — the tempo
/// the render and [TrackerSong.songTotalMs] both use.
TrackerTiming effectiveTiming(TrackerSong song) {
  final t = songInitialTempo(song);
  return t != null ? song.timing.copyWith(tempoBpm: t) : song.timing;
}

/// The row-timing map WITHOUT rendering any audio — the same
/// `(startMs, orderIndex, patternIndex, row)` sequence [replaySong] emits, built
/// cheaply from [walkFlow] (flow songs) or the uniform order walk. This is what
/// the Advanced playhead consumes: resolve it once when playback starts, then use
/// [rowIndexAtMs] per frame to map elapsed ms → the currently-playing row, so the
/// highlight follows Bxx/Dxx/E6x jumps instead of assuming fixed pattern lengths.
List<RowTiming> resolveTimingMap(TrackerSong song) {
  song.syncCurrent();
  // Mid-song tempo change: non-uniform per-row onsets (match [_replayVariable]).
  if (songUsesVariableTiming(song)) {
    final played = walkFlow(song);
    final starts = _variableRowStartMs(song, played);
    return [
      for (var i = 0; i < played.length; i++)
        RowTiming(
          starts[i],
          played[i].orderIndex,
          played[i].patternIndex,
          played[i].row,
        ),
    ];
  }
  final timing = effectiveTiming(song); // match the render's Fxx set-tempo
  // Flow OR variable-length patterns both resolve via the flattened walk.
  if (songNeedsWalkRender(song)) {
    final played = walkFlow(song);
    final flatTiming =
        timing.copyWith(rows: played.isEmpty ? 1 : played.length);
    return [
      for (var i = 0; i < played.length; i++)
        RowTiming(
          flatTiming.stepOnsetMs(i).round(),
          played[i].orderIndex,
          played[i].patternIndex,
          played[i].row,
        ),
    ];
  }
  final map = <RowTiming>[];
  for (var o = 0; o < song.order.length; o++) {
    final baseMs = timing.totalMs * o;
    for (var r = 0; r < timing.rows; r++) {
      map.add(
        RowTiming(baseMs + timing.stepOnsetMs(r).round(), o, song.order[o], r),
      );
    }
  }
  return map;
}

/// The index into [map] of the row playing at song-time [ms] — the last entry
/// whose `startMs <= ms` (binary search; [map] is ascending in startMs). Returns
/// -1 for an empty map, 0 for a time before the first row. Feed it
/// `elapsedMs % songTotalMs` for a looping transport.
int rowIndexAtMs(List<RowTiming> map, int ms) {
  if (map.isEmpty) return -1;
  var lo = 0;
  var hi = map.length - 1;
  var ans = 0;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (map[mid].startMs <= ms) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}
