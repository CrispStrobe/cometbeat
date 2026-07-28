# Tracker replayer — effect coverage audit (read-only)

> **Current status (2026-07-25):** this matrix is historical unless a row is
> explicitly marked pending. The normalized MOD/XM/S3M/IT command families,
> flow timing, stereo paths, native sampled effects, and editor command picker
> are implemented on `main`. `mod_pending.md` is the authoritative current
> audit.

**By:** opus (libraries-and-tab), 2026-07-19 · **For:** @tracker-replayer (owns
`lib/core/audio/tracker_replayer.dart`) · **Method:** read-only source audit,
**no engine edits**. This refines backlog item **B) Replayer effect coverage**
(`docs/PLAN.md`) with current ground truth — the backlog list (2026-07-19) is
**stale**: several effects it calls "still-missing" are now implemented.

The state machine is `ReplayVoice` (armRow → per-tick `tick(k)`); flow commands
(Bxx/Dxx/Fxx/E6x) are resolved in `walkFlow`. Trajectories are unit-testable
pure via `traceChannel(cells, {ticksPerRow}) → ChannelTrace`
(`pitchAt/volumeAt/retriggerAt(r,k)`).

## Coverage — top-level commands 0x0–0xF (all 16 present ✅)

| Cmd | Effect | Status |
|----|--------|--------|
| 0xy | Arpeggio | ✅ per-tick cycle base/+x/+y |
| 1xx | Porta up | ✅ |
| 2xx | Porta down | ✅ |
| 3xx | Tone porta | ✅ no-overshoot |
| 4xy | Vibrato | ✅ sine only |
| 5xy | TonePorta + volslide | ✅ |
| 6xy | Vibrato + volslide | ⚠️ **present but buggy** — see Defect 1 |
| 7xy | Tremolo | ✅ sine only |
| 8xx | Set pan | ✅ |
| 9xx | Sample offset | ✅ |
| Axy | Volume slide | ✅ ⚠️ ignores the fine **F-nibble** (see G3) |
| Bxx | Position jump | ✅ walkFlow |
| Cxx | Set volume | ✅ |
| Dxx | Pattern break | ✅ walkFlow |
| Exy | Extended | ✅ partial — table below |
| Fxx | Set speed / tempo | ✅ walkFlow (split at 0x20) |

## Coverage — extended Exy sub-commands

| Sub | Effect | Status |
|----|--------|--------|
| E1x | Fine porta up | ✅ *(backlog wrongly lists as missing)* |
| E2x | Fine porta down | ✅ *(ditto)* |
| E6x | Pattern loop | ✅ walkFlow |
| E9x | Retrigger | ✅ *(backlog wrongly lists as missing)* |
| EAx | Fine vol up | ✅ |
| EBx | Fine vol down | ✅ |
| ECx | Note cut | ✅ *(backlog wrongly lists as missing)* |
| EDx | Note delay | ⚠️ **present but buggy** — see Defect 2 |
| E3x | Glissando control | ✅ *(added — tone-porta snaps to semitones)* |
| E4x | Vibrato waveform | ✅ *(added — sine/saw/square via `trackerLfo`)* |
| E7x | Tremolo waveform | ✅ *(added — sine/saw/square)* |
| E5x | Set finetune | ✅ *(added — ±(x−8)/16 semitone nudge)* |
| EEx | **Pattern delay** | ✅ *(shipped by @tracker-replayer, walkFlow)* |
| E0x/E8x/EFx | filter / sync / funk-loop | ⬜ rare, low priority |

## Not implemented — XM/S3M/IT extras (beyond MOD)

- **Rxy** retrigger + volslide (backlog-named)
- **Fine F-nibble slides** in Axy / 1xx / 2xx (backlog-named "FF nibble")
- **Gxx** global volume, **Hxy** global-vol slide
- **Mxx** set channel volume, **Nxy** channel-vol slide (backlog group B, bullet 2)
- **Txy** tremor ✅ *(`kFxTremor` 0x1D, importer wired, three per-format models
  measured against libopenmpt/libxmp — see `TremorModel`)*
- **Kxx** key-off ✅ *(as an EFFECT — XM `14h` now routes to the neutral model's
  `noteOff`, which the note column has always carried as note 97; it used to be
  read as tremor)*
- **Pxy** panning slide, **Lxx** env position, **Xxx**
  extra-fine porta
- **Volume-column mini-commands** — the volume column exists as a static level
  (`applyVolumeColumn`, Cxx-equivalent) but not the XM vol-column
  vibrato/porta/pan sub-commands.

## Status update (2026-07-19)

- The two defects the earlier board report flagged (**6xy** vibrato-memory,
  **EDx** re-attack) are **now FIXED** by @tracker-replayer — verified in source
  (armRow leaves the vib memory alone; the render resets `noteStartSample` only
  at the actual fire tick).
- **E3x/E4x/E7x/E5x + Rxy + Txy added** by opus (libraries-and-tab, cross-lane,
  maintainer-authorized), all zero-regression. E3x glissando + E4x/E7x
  vibrato/tremolo waveforms + E5x finetune (Extended sub-commands, were no-ops,
  flow through real `.mod`/`.xm` E-commands); **Rxy** retrigger+volslide
  (`fxCmd 0x1B`, exact XM volume table) and **Txy** tremor (`fxCmd 0x1D`,
  on-x/off-y gate) on new non-colliding commands. Tests:
  `tracker_effect_coverage_test.dart`. ✅ **Importer wiring DONE.** It needed no
  new mapping in the end — XM's effect numbering IS ours from `10h` up, so `R`
  (`1Bh`) already passed straight through. `T` was the exception, and it was
  mapped the wrong way round: `14h` is XM's **key off**, not tremor, so tremor
  was written into the key-off slot in both directions at once. Removing that
  swap wired the importer and fixed the file format together
  (`test/xm_effect_numbering_test.dart`).

## Remaining, by value ÷ effort (needs core/model work — @tracker-replayer)

These are deliberately NOT done by the cross-lane pass — each touches the timing/
render core or the cell model, i.e. exactly the parts that would conflict with
the active tracker worker:

1. ✅ **EEx pattern delay** — **SHIPPED by @tracker-replayer** (walkFlow, row-level
   flow). Was the highest-impact gap; done.
2. ✅ **Rxy / Txy importer wiring** — DONE. XM numbers its effects the way we do
   from `10h` up, so `R` needed nothing; `T` needed the tremor↔key-off swap
   removed (see above). Tremor's REPLAY then turned out to be three different
   machines per format (`TremorModel`), all now matching their references tick
   for tick.
3. **Fine F-nibble slides (Axy/1xx/2xx)** — **format-ambiguous**: in MOD, `1F0`
   is a fast slide; in S3M/XM, `1Fx` is fine. The replayer doesn't track source
   format, so this needs a format flag (or a decision to assume S3M/XM) before
   it's safe — otherwise it regresses MOD playback.
4. **Gxx global / Mxx channel volume** — needs a scalar in the mix stage
   (`mixStems`), not just per-voice; larger, do last.

## Test pattern (matches the repo's convention)

Per-tick trajectory test via the pure API — no audio needed:

```dart
// EEx pattern delay: a 1-row pattern with EE1 should render two rows of audio.
final t = traceChannel([TrackerCell(midi: 60, fxCmd: kFxExtended, fxParam: 0xE1)]);
// (EEx is walkFlow-level — assert replaySong(...).pcm length doubles instead.)

// Rxy: retrigger every y ticks while volsliding by x.
final t = traceChannel([TrackerCell(midi: 60, fxCmd: kFxRetrigVolSlide, fxParam: 0x23)]);
expect(t.retriggerAt(0, 3), isTrue);          // retrigger on tick 3
expect(t.volumeAt(0, 3), lessThan(kMaxVolume)); // …and volume slid down
```

Then a synth → `dart run bin/listen.dart --wav` acceptance where the effect
changes pitch/level audibly (the pattern used elsewhere in the tracker suite,
e.g. `midsong_timing_acceptance_test.dart`).

---
*Read-only audit. I did not touch `tracker_replayer.dart` or its tests — the
lane is @tracker-replayer's. Relaying so it can be actioned with full context.*
