# Tracker engine — parallel feature CONTRACTS (orchestrated build)

> **Archived contracts (2026-07-25):** these sibling-worktree instructions are
> historical. The tempo, pan, effect, native-envelope, stereo, codec-bridge,
> and long-render work described below has landed on `main`. New work must be
> based on the current code and `mod_pending.md`; do not create parallel agents
> from these stale contracts.

Three remaining engine-parity features are being built **in parallel by
capable (Opus) agents**, each in its own sibling worktree, against the contracts
below. The **orchestrator** (opus tracker-replayer) owns these contracts and an
**independent acceptance test** per feature (`test/<feature>_acceptance_test.dart`,
marked DO NOT EDIT) that is the correctness gate. Agents implement to make that
test pass, add their own unit tests, and keep `flutter analyze` clean.

Ground rules for every agent:

- Work ONLY in your assigned sibling worktree (path in your prompt); it is a
  sibling of `mus/` so the `../crisp_notation` path dep resolves.
- Wrap flutter/dart with the repo env fix:
  `PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT flutter test …`
  (needed on this machine; `flutter test`/`pub get` need no pods).
- `dart format` FIRST, then `flutter analyze` (whole project incl `test/`) LAST →
  "No issues found".
- Do NOT edit `test/<your-feature>_acceptance_test.dart` — it is the gate the
  orchestrator owns. Make it pass; add your OWN unit tests alongside.
- Preserve all existing behaviour: the fast/mono/uniform paths must stay
  byte-identical when your feature is not in use (each acceptance test pins a
  regression case for this).
- Commit small; leave the branch ready for the orchestrator to integrate. Do NOT
  push to `origin/main` — report back and the orchestrator integrates + gates.

The current engine (already on `main`): the replayer (`tracker_replayer.dart`)
plays the full MOD/XM command set; `walkFlow(song)` expands order→pattern→row
(Bxx/Dxx/E6x) into `List<PlayedRow>`; `_replayFlow` flattens the played rows and
renders; additive channels use a tick oscillator, non-additive use
`renderChannelPerNote` (per-note, honours per-cell instrument). `Fxx` speed/tempo
is applied UNIFORMLY (first value only). `mixStems`/`wavBytes` (synth.dart) are
MONO. Read the module header of `tracker_replayer.dart` before starting.

---

## Feature A — mid-song tempo & speed CHANGES (per-row duration)

**Worktree:** `../mus-tempo` · **branch:** `feature/tracker-midsong-timing`

**Problem.** `Fxx` currently applies only the FIRST speed/tempo to the whole
song (uniform). A song that changes tempo/speed mid-way is rendered at the first
value. Fixing it makes row DURATIONS non-uniform (tempo change) — the current
flatten render assumes one `stepMs` for every row.

**Contract (API + semantics):**

1. `PlayedRow` (in `tracker_replayer.dart`) gains two fields, added as
   **positional-optional with defaults** so existing `walkFlow` tests/callers
   stay source-compatible:
   ```dart
   const PlayedRow(this.orderIndex, this.patternIndex, this.row,
       [this.ticksPerRow = kDefaultTicksPerRow, this.tempoBpm = 0]);
   final int ticksPerRow;   // speed in effect for THIS row
   final int tempoBpm;      // tempo (BPM) in effect for THIS row (0 = song default)
   ```
2. `walkFlow(song, {maxRows})` populates `ticksPerRow`/`tempoBpm` per row by
   scanning each row's cells (in play order) for `Fxx`: `param < 0x20` sets speed
   (min 1) from that row onward; `param >= 0x20` sets tempo from that row onward.
   The value takes effect ON its own row. `tempoBpm` defaults to
   `song.timing.tempoBpm` when never set.
3. The render honours per-row tempo: each played row's sample length is
   `round(stepMsForTempo(tempoBpm) * sampleRate / 1000)` where
   `stepMsForTempo = (60000/tempoBpm) ~/ song.timing.stepsPerBeat`. Rows are laid
   back-to-back at accumulated sample offsets. Additive channels use each row's
   `ticksPerRow` for tick granularity; non-additive notes are placed at the
   accumulated offsets over their run's summed duration (extend
   `renderChannelPerNote` or add a variable-timing sibling — your call).
4. `resolveTimingMap(song)` and `TrackerSong.songTotalMs` reflect the summed
   per-row durations (so the playhead + transport stay correct). Keep the fast
   path for songs with no mid-song change.
5. **Gate:** route through the variable-timing render when the song has a
   mid-song change — i.e. more than one distinct `Fxx`-speed value AND/OR more
   than one distinct `Fxx`-tempo value across the played rows, or a value that
   first appears after play-position 0. A song with a single (or no) speed/tempo
   value MUST still use the existing uniform path unchanged.

**Acceptance invariants** (see `test/midsong_timing_acceptance_test.dart`):
- Regression: a constant-tempo, constant-speed song renders the **same PCM
  length** as `replaySong` does today (uniform path untouched).
- `walkFlow`: for a 2-pattern song where pattern 1 sets `F1E` (tempo 30) at row 0,
  every played row of order-entry-1 reports `tempoBpm == 30`, entry-0 rows report
  the song tempo.
- A song that halves the tempo halfway is **longer** than at constant tempo, and
  `songTotalMs == replaySong(song).pcm.length / sampleRate * 1000` (±few ms) — the
  map, the length and the transport agree.
- A sample note that triggers AFTER a tempo change lands at the correct
  accumulated sample offset (non-additive stays aligned) — asserted via the
  onset being silent-before / non-zero-at the expected offset.

---

## Feature B — per-pattern variable length

**Worktree:** `../mus-patlen` · **branch:** `feature/tracker-pattern-length`

**Problem.** Every pattern is forced to `song.timing.rows`. Real trackers let
each pattern have its own length. The cell data already supports it
(`TrackerPattern.cells` have their own length); the block is `TrackerSong`/
`TrackerEngine` forcing uniformity and the render assuming one length.

**Contract (API + semantics):**

1. `TrackerPattern.rows` already returns `cells.first.length` — keep it; it
   becomes the authoritative per-pattern length.
2. `TrackerSong.setPatternRows(int patternIndex, int newRows)` — resize ONE
   pattern (truncate extra rows / pad with `TrackerCell.empty`), leaving other
   patterns untouched. `assert(newRows > 0)`. If it resizes the CURRENT pattern,
   re-time the engine to `newRows`. (Keep the existing `setRows` = all patterns.)
3. `TrackerSong.selectPattern(index)` re-times the engine to
   `patterns[index].rows` (so editing a variable-length pattern works). The
   engine's per-channel cell-count assert must hold for the selected pattern.
4. `TrackerSong.rows` returns the CURRENT pattern's rows (already does via the
   engine). `TrackerEngine` operates on one pattern; its `timing.rows` == the
   current pattern's length at all times.
5. Rendering: `renderSongWav`/`replaySong`/`walkFlow` use each pattern's OWN row
   count. In `walkFlow`, `rows` is `song.patterns[patternIndex].rows` (per entry),
   NOT a single `song.timing.rows`. Dxx break rows clamp to the TARGET pattern's
   length.
6. `TrackerSong.songTotalMs` = Σ over the played sequence of `stepMs`
   (uniform tempo — this feature does NOT change tempo, only row COUNT). Reuse
   the flow/walk length machinery.
7. **Gate:** route through the walk/flatten render when patterns have differing
   lengths (or when already routed for commands/flow). A song whose patterns are
   all the same length MUST render exactly as today.

**Acceptance invariants** (see `test/pattern_length_acceptance_test.dart`):
- Regression: an all-equal-length song renders identical PCM length + `songTotalMs`
  as today.
- `setPatternRows(1, 16)` on a 2-pattern (8-row) song → `patterns[1].rows == 16`,
  `patterns[0].rows == 8`; `selectPattern(1)` → `song.rows == 16` and a note set
  at row 15 survives and reads back.
- Order `[0, 1]` with rows 8 and 16 → the song plays 24 rows; `songTotalMs ==
  24 * stepMs`; `resolveTimingMap(song).length == 24`; render length matches.
- A note at row 12 of the 16-row pattern sounds (non-silent at its offset).

---

## Feature C — stereo output + panning (+ volume/pan envelopes, stretch)

**Worktree:** `../mus-stereo` · **branch:** `feature/tracker-stereo-pan`

**Problem.** The whole mix is MONO (`mixStems`→mono PCM16, `wavBytes`→1-channel
WAV). Panning needs stereo. This is the most pervasive change — keep every mono
path intact.

**Contract (API + semantics):**

1. `synth.dart` gains stereo primitives (ADDITIVELY — do NOT change `mixStems`/
   `wavBytes`):
   ```dart
   typedef MixStemPan = ({Float64List samples, double gain, double pan}); // pan −1..1
   Int16List mixStemsStereo(List<MixStemPan> stems, {required int totalSamples});
     // returns INTERLEAVED L,R,L,R… of length totalSamples*2. Per stem: unit-peak
     // × gain (same as mixStems), constant-power pan (L=cos θ, R=sin θ,
     // θ=(pan+1)/2·π/2), summed, tanh soft-knee (same 0.95 as mixStems).
   Uint8List wavBytesStereo(Int16List interleaved, {int sampleRate = kSampleRate});
     // a valid 2-channel PCM16 WAV (numChannels=2, blockAlign=4, byteRate×2);
     // `interleaved.length` must be even (L,R pairs).
   ```
2. `TrackerChannel.pan` (`double`, −1..1, default 0 = centre), mutable via a new
   `TrackerEngine.setChannelPan(int, double)` (invalidate the mixed WAV, like
   `setChannelGain`).
3. `8xx` cell command (constant `kFxSetPan = 0x8` in `tracker_replayer.dart`):
   per-note pan, `0x00`=hard left … `0x80`=centre … `0xFF`=hard right, mapped to
   −1..1. Honoured by the replayer (per channel, persists like volume).
4. The replayer produces a STEREO mix (`mixStemsStereo` + `wavBytesStereo`) when
   the song "uses pan" — any `channel.pan != 0` OR any `8xx`. Add
   `TrackerSong.usesPan`. Route `renderSongWav`/`renderCurrentPatternWav` to the
   stereo output then. **Songs with no pan stay MONO and byte-identical.**
5. **Stretch (do only if the above is solid + green):** a per-instrument volume
   (and pan) ENVELOPE — a small breakpoint model
   `VolumeEnvelope(List<({int ms, double level})> points)` applied over a note in
   the replayer's additive voice. Define it additively; leave a clear seam if you
   run short. Not required for acceptance.

**Acceptance invariants** (see `test/stereo_pan_acceptance_test.dart`):
- Regression: a song with no pan renders a MONO WAV byte-identical to today.
- `wavBytesStereo`: header says 2 channels, `byteRate = sampleRate*4`,
  `blockAlign = 4`, data length = `interleaved.length*2`.
- `mixStemsStereo` centre pan (0) → L == R for every sample; a single stem panned
  −1 → R channel ≈ 0 and L carries the signal; panned +1 → L ≈ 0.
- A hard-left `TrackerChannel.pan == -1` song → stereo render's L energy ≫ R
  energy; `8x00` on a note pans it left likewise.
- `usesPan` is false for a plain song (stays mono), true when a channel is panned
  or an `8xx` is present.
