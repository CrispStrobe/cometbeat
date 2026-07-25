# Tracker Replayer — Handover for Effect-Command Phases 2 & 3

> **Superseded status (2026-07-25):** this file describes the pre-replayer
> implementation plan. `lib/core/audio/tracker_replayer.dart` now owns flow
> walking, tick effects, variable timing, stereo rendering, native sample-zone
> playback, and the bounded long-song path. Use `mod_pending.md` for the live
> audit. The historical design notes below do not describe the current code.

**Goal:** finish the classic MOD effect-command set in the Advanced Tracker.
Phase 1 (the effect-column *model* + the volume-domain commands **Cxx**, **Axy**)
is shipped. This doc hands a fresh agent everything needed to build **phase 2
(pitch commands)** and **phase 3 (flow commands)** — which together require a
real tick-based **replayer**, not an incremental UI slice.

> Read this whole doc before writing code. The two big traps (§4) will waste a
> day each if you don't know them going in.

---

## 0. TL;DR of the shape

Today the Advanced Tracker renders **offline**: each channel → a `Float64List`
stem (per-note segments) → `mixStems` (unit-peak-per-stem) → one WAV → looped by
a player. There is **no tick clock and no cross-note state**, so:

- **Phase 2 (pitch: `0/1/2/3/4/7/9`)** needs a *tick-level replayer* that walks
  rows × ticks holding per-channel pitch/volume/sample-position state. The
  current per-note segment renderer structurally cannot do portamento (it renders
  each note in isolation).
- **Phase 3 (flow: `Bxx/Dxx/Fxx/Exy`)** changes the *sequence and timing* of
  playback. Because we render offline-then-loop, flow must be resolved **at
  render time** by producing the correctly-ordered/timed PCM — not by real-time
  scheduling.

Recommended: build one new `TrackerReplayer` that OWNS the order→pattern→row→tick
walk and emits (a) the mixed PCM and (b) a **row-timing map** for the playhead.
Make it the Advanced render path when a song uses commands; keep the existing
simple path for the Beginner grid and the no-command case (don't regress).

---

## 1. What phase 1 shipped (so you know the seam)

Commit `3e7e62e`. Files:

- **`lib/core/audio/tracker_engine.dart`**
  - `TrackerCell` gained `fxCmd` (nibble 0x0–0xF) + `fxParam` (byte 0x00–0xFF) —
    the classic effect column — **added additively**; the Beginner path's
    `effect` (a `TrackerEffect` enum) is untouched. `hasCommand` = any non-zero.
    `==`/`hashCode` include the new fields.
  - `_renderWithDynamics(channel)` (~L765): renders the instrument stem, applies
    the soft-note `volume`, then `applyVolumeColumn(...)`, then
    `applyChannelEffects(...)`. **This is where phase 2/3 hook in / replace.**
- **`lib/core/audio/tracker_replay.dart`** (NEW, Flutter-free, unit-tested):
  `applyVolumeColumn(stem, cells, timing, {ticksPerRow=6})` — **Cxx** (set
  volume) and **Axy** (volume slide, ramped across the row, level persists). It's
  a **post-multiply gain envelope** on the stem; a no-op when the channel has no
  volume commands. Constants `kFxSetVolume=0xC`, `kFxVolumeSlide=0xA`,
  `kDefaultTicksPerRow=6`.
- **`advanced_tracker_screen.dart`**: cells render the hex code (`C20`/`A04`) in
  the fx sub-column (`_commandHex`); the long-press cell menu has a
  `_CommandEditor` (command dropdown + live hex param slider) → `_setCellCommand`.
- Tests: `test/tracker_replay_test.dart` (Cxx level, Axy ramp/persist/clamp,
  identity) + a relative engine test in `test/tracker_song_test.dart`.

**Migration note:** when the tick replayer lands, `Cxx`/`Axy` should move INTO the
replayer's per-tick volume model (the row-ramp in `applyVolumeColumn` is an
approximation). Keep `applyVolumeColumn` for the non-replayer path or retire it.

---

## 2. The current render pipeline (read the code at these anchors)

- **Timing** — `TrackerTiming` (`tracker_engine.dart:38`): `tempoBpm`, `rows`,
  `stepsPerBeat`, `swing`. Derived: `stepMs = beatMs/stepsPerBeat`,
  `totalMs = stepMs*rows`, `totalSamples`, `stepStartSample(step)`. **No tick
  concept.** One row = one `stepMs`.
- **Cells → runs** — `cellRuns(cells)` (`:124`): a non-empty cell triggers a note
  that rings across following empty cells until the next trigger. This is the
  "note on / let ring" model.
- **Instruments** — `TrackerInstrument.renderChannel(cells, timing)` (`:161`):
  - `AdditiveInstrument` (`:171`) — segments via `cellsToSegments`; a per-note
    effect path calls `renderNoteWithEffect` (see below).
  - `SfxrInstrument`, `SampleInstrument` (resampling; `baseMidi`; per-note
    envelope + pitch-glide), `PercussionInstrument`.
- **Per-note effects (legacy)** — `lib/core/audio/tracker_effects.dart`:
  `TrackerEffect {none,arpeggio,vibrato,slideUp,slideDown}` and
  `renderNoteWithEffect(midi, ms, effect, {timbre, depth})`. **This function is
  your phase-2 oscillator prototype**: it integrates base phase sample-by-sample
  (`phase += 2*pi*freq/sr`) so a time-varying frequency stays phase-continuous,
  and reads harmonics as `sin(phase*(h+1))`. Extract a reusable
  phase-accumulating additive oscillator from it.
- **Mix** — `renderLoopPcm()` (`:785`): `mixStems([(samples, gain) for each
  non-muted channel with notes], totalSamples)`. `renderLoop()` caches `_wav`.
- **Song** — `tracker_song.dart`: `TrackerSong` (patterns, order, engine).
  `renderSongWav()` = `renderSong(engine, [patterns in order])` — concatenates one
  `renderLoopPcm()` per order entry. **Uniform rows across patterns.**
- **Playback** — the screen renders a WAV and loops it on `GaplessLoopPlayer`; a
  `Stopwatch` derives the playhead (`_row`/`_playingOrder`) from **fixed** pattern
  lengths (`advanced_tracker_screen.dart` ticker, ~L272). Song mode plays the
  concatenated order.

---

## 3. The MOD command set to implement

Command = nibble `fxCmd` + byte `fxParam` (`x` = high nibble, `y` = low nibble).

### Phase 2 — pitch / per-note (need the tick replayer)
| Cmd | Name | Semantics (per tick unless noted) |
|-----|------|-----------------------------------|
| `0xy` | Arpeggio | cycle note, note+x, note+y each tick |
| `1xx` | Porta up | raise pitch by a rate ∝ xx each tick |
| `2xx` | Porta down | lower pitch by ∝ xx each tick |
| `3xx` | Tone porta | slide current pitch **toward the row's note** by ∝ xx/tick; xx omitted = reuse last |
| `4xy` | Vibrato | sine LFO on pitch: x=speed, y=depth; advanced per tick |
| `5xy` | Tone porta + vol slide | `3` with the *previous* porta speed + `Axy` |
| `6xy` | Vibrato + vol slide | `4` (continue) + `Axy` |
| `7xy` | Tremolo | sine LFO on **volume**: x=speed, y=depth |
| `9xx` | Sample offset | start the sample at xx×256 (SampleInstrument only) |

Notes: pitch commands don't retrigger the sample (except a new note). `3xx` needs
the **row's target note** even though it doesn't retrigger. Vibrato/tremolo are
zero-mean LFOs applied on top of the base pitch/volume, reset (or continued, per
waveform) on a new note. Each command has **memory** (a 0 param reuses the last
non-zero param for that command).

### Phase 3 — flow / timing (need the render-order model)
| Cmd | Name | Semantics |
|-----|------|-----------|
| `Bxx` | Position jump | after this row, continue at order index xx, row 0 |
| `Dxx` | Pattern break | end this row; go to the *next* order entry, row = `(xx>>4)*10 + (xx&0xF)` (decimal!) |
| `Fxx` | Set speed/tempo | xx < 0x20 → set **speed** (ticks/row); xx ≥ 0x20 → set **tempo** (BPM) |
| `Exy` | Extended | E1x/E2x fine porta, E3x glissando, E4x vibrato waveform, E5x finetune, E6x **pattern loop**, E7x tremolo waveform, E9x retrigger, EAx/EBx fine vol, ECx **note cut**, EDx **note delay**, EEx pattern delay |

`Bxx`+`Dxx` on the same row: jump wins for the order, break sets the row.
`Fxx` set-speed changes effect granularity AND row timing thereafter.
`E6x` pattern loop can loop a span within a pattern (state per channel).

---

## 4. THE TWO TRAPS (read twice)

**Trap A — `mixStems` normalizes each stem to UNIT PEAK, then applies gain.**
(`synth.dart` `mixStems`; see auto-memory `loop-mixer-groovebox`.) So an
**absolute** volume change on a *lone* note in a channel is normalized away — it's
only observable **relative to a louder note in the same channel**. This already
affects the pre-existing soft-note `volume` and phase-1 `Cxx`. Consequences:
- **Tremolo/volume tests must be relative** (compare regions against a louder
  reference note in the same channel), or test the replayer's **state trajectory**
  directly (pre-mix), which is what you should mostly do (§6).
- If you want channel volume to be *absolute across channels*, the replayer must
  produce the final mix itself (summing at true amplitude with a soft-limiter)
  rather than going through per-stem unit-peak `mixStems`. **Decide this early.**
  Recommendation: the replayer sums voices at true amplitude and applies the same
  `tanh` soft-knee `mixStems` uses at the end — do NOT unit-peak per channel, so
  Cxx/tremolo are audible. (This is a divergence from the current path; gate it to
  the replayer path so the simple path is unchanged.)

**Trap B — playback is OFFLINE-render-then-loop, with a `Stopwatch` playhead over
FIXED pattern lengths.** Flow (`Bxx/Dxx/Fxx`) makes the timeline non-uniform
(tempo changes, jumps, breaks, variable row counts). So:
- The replayer must emit a **row-timing map**: an ordered list of
  `(startMs, orderIndex, patternIndex, row)` for every row actually played, so the
  screen can drive `_row`/`_playingOrder` from elapsed time instead of assuming
  `row = elapsed % totalMs / stepMs`. Wire this into the ticker
  (`advanced_tracker_screen.dart`) — replace the fixed-length math with a lookup
  into the map. **This is required for the playhead to stay correct under flow.**
- `renderSongWav` (concatenate fixed patterns) is replaced by the replayer's
  order-walk for the command path.

---

## 5. Recommended architecture

Create **`lib/core/audio/tracker_replayer.dart`** (Flutter-free):

```
class ChannelState {            // per channel, mutable across ticks
  int? note;                    // current MIDI note (base)
  double pitch;                 // current pitch in semitones (fractional; porta/vibrato move this)
  double targetPitch;           // for 3xx tone-porta
  int volume;                   // 0..64
  double samplePos;             // for SampleInstrument (offset/loop)
  int lastPortaParam, lastVibParam, lastVolSlide, ...; // effect memory
  double vibPhase, tremPhase;   // LFO phases
  // ... retrigger/delay/cut counters
}

class ReplayResult {
  final Int16List pcm;
  final List<RowTiming> timing;    // (startMs, orderIndex, patternIndex, row)
}

ReplayResult replaySong(TrackerSong song, {int ticksPerRow = 6});
```

Walk: `for order → pattern → row → tick`:
1. **Tick 0 of a row:** read each channel's cell — trigger note (set `note`,
   reset LFOs per waveform, apply `9xx` offset), set volume (`Cxx`/`E Ax/Bx`),
   arm the row's effect (fill memory on 0 param), handle `3xx` target.
2. **Every tick:** apply the armed effect's per-tick update to `pitch`/`volume`
   (porta step, vibrato/tremolo LFO advance + apply, arpeggio note pick, vol
   slide). Synthesize `tickMs` of audio for each channel at its instantaneous
   `pitch`/`volume` using a **phase-accumulating oscillator** (additive) or a
   **resampling read pointer** (sample), summing into the mix.
3. **End of row:** resolve flow — `Dxx` (break → next order, row yy), `Bxx`
   (jump → order xx, row 0), `Fxx` (set speed/tempo → change `ticksPerRow`/`tempo`
   for subsequent rows), `E6x` pattern loop. Guard against infinite loops (cap
   total rows rendered; `log`/document the cap).

`tickMs = timing.stepMs / ticksPerRow` (keeps our musical timing) — or adopt the
MOD `tickMs = 2500/tempo` model if you prefer strict MOD semantics. **Pick one and
document it.** The Advanced tempo control (`_kTempoOptions`) is musical BPM;
mapping `Fxx` set-tempo onto it is the cleanest UX.

**Instruments in the replayer:** you need two primitives per instrument —
"advance N samples at pitch P, volume V into the mix buffer". For additive: reuse
the phase integrator from `renderNoteWithEffect`. For `SampleInstrument`: a
fractional read pointer with cubic interp (there's `resampleCubic` in
`crisp_dsp/resample.dart`); `9xx` sets the start pointer. Sfxr/percussion can
fall back to whole-note render on trigger (document the limitation) or be adapted.

**Integration:** add `TrackerSong.usesCommands` (any cell `hasCommand`). In the
engine/song render path, if `usesCommands` → `replaySong(...)`, else the existing
fast path. The Advanced screen calls the song's render either way; only the
internals branch. Keep `mixStems`/the simple path for Beginner untouched.

---

## 6. Testing strategy (how to be correct without ears)

The replayer is a **state machine** — test that directly, it's the whole game:

- **Trajectory tests** (pure, no audio): given a channel's cells + speed, assert
  the per-tick `pitch`/`volume` sequence. E.g. `C-4` then `3xx` toward `E-4`
  reaches ~`E-4` (4 semitones up) after the expected ticks; `1xx` raises pitch
  monotonically; vibrato is zero-mean and periodic; arpeggio visits {0,x,y}.
  Expose the replayer's per-tick state (or a debug trace) for assertions.
- **Flow tests** (pure): given patterns + `Bxx/Dxx/Fxx`, assert the **row-timing
  map** — the exact `(orderIndex, row)` sequence and the `startMs` cadence
  (tempo/speed changes shift it). This is the phase-3 correctness anchor.
- **Audio acceptance** (repo idiom): render → `dart run bin/listen.dart --wav`.
  Pitch commands are audible/measurable — a porta glide reads as rising cents; a
  vibrato as a cents wobble; arpeggio as note switching. (Volume/tremolo: relative
  only, see Trap A.)
- **Oracle (optional, high-value):** `libopenmpt` (BSD) decodes MOD/XM/S3M/IT and
  is the reference implementation; the memory `tracker-effort` notes it was used
  as an oracle for the IT decompressor. You can render a hand-authored/real module
  through libopenmpt and compare note-trajectory summaries. Real modules are
  gitignored (copyright) — keep only license-clean fixtures committed. The
  existing goldens are `test/fixtures/golden.{mod,s3m,xm,it}`.
- **Do NOT** rely on mix-peak for volume correctness (Trap A).

---

## 7. Bonus: import module effects (unlocks real playback of imported mods)

Currently module import **drops effects** (`module_doc.dart:13` documents this;
`tracker_song_module.dart` maps only note/volume). The format readers **do** parse
them — e.g. `mod_module.dart:90` `ModCell.effect`/`effectParam` (0..15 / 0..255).
So to make imported `.mod/.xm/.s3m/.it` play their effects:
1. Add `effect`/`effectParam` to `DocCell` (`module_doc.dart`) + carry them in
   `docFromMod/S3m/Xm/It` (`module_convert.dart`). NB each format encodes effects
   differently (S3M/XM/IT use different command letters than MOD) — a **cross-
   format effect table** is the documented follow-up (memory `tracker-effort`).
   Start with MOD (direct nibble mapping) and note the others as TODO.
2. Map `DocCell.effect/effectParam` → `TrackerCell.fxCmd/fxParam` in
   `_patternFromDoc` (`tracker_song_module.dart`).
This is orthogonal to the replayer but pairs with it: once the replayer plays
commands, imported modules come alive.

---

## 8. Suggested slicing (each shippable, tested, small commit)

- **2a** Replayer skeleton + additive oscillator + trajectory-test harness;
  implement `0xy` arpeggio, `1xx/2xx` porta, `Cxx` (migrated). No flow yet;
  `ticksPerRow` fixed. Gate behind `usesCommands`.
- **2b** `3xx` tone-porta (+ target from row), `4xy` vibrato, `7xy` tremolo,
  `5/6` combos, `Axy` (migrated to per-tick), `9xx` offset (sample voices).
- **2c** Row-timing map + wire the Advanced playhead to it (still no flow, so the
  map is uniform — proves the plumbing before phase 3 makes it non-uniform).
- **3a** `Fxx` speed/tempo (non-uniform timing; map cadence changes).
- **3b** `Dxx` break + `Bxx` jump (non-linear order; loop guard).
- **3c** `Exy` extended (note cut/delay/retrigger, fine porta/vol, pattern loop).
- **4** Import module effects (§7), MOD first.
- **UI polish:** a cursor **field** (note/inst/vol/fx) so the effect column is
  typed in-grid like a real tracker (today it's the long-press `_CommandEditor`);
  full command dropdown as the set grows.

Update the `_CommandEditor` command list (`advanced_tracker_screen.dart`) and the
ⓘ key legend as commands become real. Add ARB keys (EN+DE) for any new labels;
`flutter gen-l10n` after ARB edits; commit generated `app_localizations*`.

---

## 9. Coordination & verify (repo rules — CLAUDE.md)

- Work in a **worktree that is a sibling of `mus/`** (e.g. `../mus-replayer`) so
  the `../crisp_notation` path dep resolves. Branch off `main`.
- Update the `🚧 Actively working on` board at the top of `docs/PLAN.md` and push
  to `origin/main` before touching hot shared files (`tracker_engine.dart`, the
  ARBs, `advanced_tracker_screen.dart`) and after each ship. `git pull --rebase
  origin main` before each commit; keep commits small.
- `dart format` FIRST, then `flutter analyze` (whole project incl `test/`) LAST →
  "No issues found". Use `set -o pipefail` when a push gates on piped test output.
- Build/verify: `flutter run -d chrome` (no pods) to drive it; or macOS debug with
  `PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT flutter ...`.
- Engine ↔ replay is a **circular library import** (both reference `TrackerCell`/
  `TrackerTiming`) — fine in Dart; `tracker_replay.dart` already does it.
- Create Tickers in `initState`, never a lazy `late final` (CLAUDE.md).

## 10. Key files (map)

| File | Role |
|------|------|
| `lib/core/audio/tracker_engine.dart` | engine, `TrackerCell`(+fxCmd/param), `_renderWithDynamics` hook, `renderLoopPcm` |
| `lib/core/audio/tracker_replay.dart` | phase-1 `applyVolumeColumn` (Cxx/Axy) — migrate into the replayer |
| `lib/core/audio/tracker_effects.dart` | `renderNoteWithEffect` = the phase-integrating oscillator prototype |
| `lib/core/audio/tracker_song.dart` | `TrackerSong` (patterns/order); `renderSongWav`; add `usesCommands` + replayer branch |
| `lib/core/audio/synth.dart` | `mixStems` (unit-peak trap), `wavBytes`, timbres |
| `lib/features/games/composition/advanced_tracker_screen.dart` | grid, `_CommandEditor`, `_commandHex`, ticker/playhead (wire the timing map here) |
| `lib/core/audio/mod/{module_doc,module_convert}.dart` + `tracker_song_module.dart` | §7 import-effects work |
| `test/tracker_replay_test.dart`, `test/tracker_song_test.dart` | where to add replayer + trajectory + flow tests |
| `bin/listen.dart` | audio acceptance (pitch detection) |

Auto-memory to read: `tracker-effort` (full effort log + gotchas),
`loop-mixer-groovebox` (mixStems invariant), `pipefail-test-gates`.
