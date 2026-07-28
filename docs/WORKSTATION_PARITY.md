# Workstation parity — making Tracker, Loop Studio and Audio one instrument

**The ask (maintainer, 2026-07-27).** The app should be as *powerful* and as
*intuitive* as a full professional digital audio workstation. Concretely: raise
**Tracker**, **Audio Editor** and **Loop Studio** on three axes — UX, feature
parity, and interoperability.

**No contender names.** Not in code, not in docs, not in comments, not in commit
messages. This file describes *capabilities* and *conventions*, never products.
Where a convention is genuinely industry-standard ("a session grid", "a mixer
console", "ripple edit") the capability is named and the origin is not.

**Clean-room, always.** Every DSP block is written from published theory. See
auto-memory `cleanroom-gpl-port-process`.

---

## 1. Where we actually stand (verified by reading the code, 2026-07-27)

This is not a project that needs more engine. It needs a *shell*.

| Layer | Evidence | State |
|---|---|---|
| Timeline / clip model | `core/audio/daw_timeline.dart` (1080 l) | Stereo, clip→`ClipSource` ("vector, not bitmap"), per-clip/track/bus/master FX, gain automation, buses + sends, markers, tempo map, byte-identical windowed render | ✅ strong |
| Destructive edits | `core/audio/daw_edits.dart` (858 l) | normalize · amplify · invert · DC · trim-silence · stats · generators · range surgery | ✅ strong |
| FX rack | `core/audio/fx/` | Mode-neutral `FxSpec`, ~30 types, machine-readable param table, chain-string codec, GUI **and** CLI generated from one registry | ✅ exemplary |
| DAW service | `core/services/daw_service.dart` (2572 l) | ~130 verbs incl. undo/redo, split/fade/crossfade/freeze/merge/reverse/resample, stems, instrument slots, re-source | ✅ strong |
| Tracker replay | `core/audio/tracker_replayer.dart` (7448 l) | MOD/XM/S3M/IT fidelity, macros, tick voices, mono+stereo+variable+flow paths | ✅ strong |
| Loop engine | `core/audio/loop_engine.dart` (2763 l) | `GrooveSpec → WAV`, scenes, variants, arrangement, automation lanes, per-track length | ✅ strong |
| Symbolic interop | `core/interop/project_bridge.dart` | One door, every symbolic pair, per-edge loss report, side-car annotations that survive a hop | ✅ strong |
| **Project shell** | — | **does not exist** | ⛔ |
| **Transport** | three private clocks, three private UIs | **not shared** | ⛔ |
| **Interaction grammar** | `LogicalKeyboardKey` hits: tracker **33** · Audio **4** · Loop **0** | **not shared** | ⛔ |

The engines are ahead of the product. Everything below is about closing that.

---

## 2. Diagnosis — three structural gaps

Feature lists will not fix these, and every feature added before they are fixed
gets added three times.

### S1 — Five documents, not one project

`home_screen.dart:175–179` pushes five independent full-screen routes. Each owns
a different document type, a different persistence mechanism and a different
undo stack:

| Mode | Document | Persistence |
|---|---|---|
| Audio | `DawTimeline` | `.cbdaw` file (`daw_screen.dart:3416`) |
| Loop Studio | `GrooveSpec` | `SharedPreferences` slots (`groove_slots.dart`) |
| Tracker | `TrackerSong` | module files / catalog |
| Score | `MultiPartScore` | MusicXML / user songs |
| Tab | `TabDocument` | side-car |

`ProjectBridge` converts between them honestly and losslessly-where-possible —
but by design it produces **a copy**: *"a converted document opens as a copy,
never back into the source clip"* (`AUDIO_EDITOR_SUITE.md`, C3). That is the
right call for a one-way conversion and the wrong one for a workstation, where
the tracker pattern in bar 9 *is* the thing on the timeline, not a snapshot of
it.

Everything a workstation feels like follows from the missing project object:

- one transport that all surfaces follow;
- one mixer where every track — audio, tracker channel, loop track, score part —
  has a strip;
- one undo history;
- one Save; one recent-projects list; one template;
- and the ability to see a loop track and an audio clip *on the same timeline*.

### S2 — Offline render-then-play (the honest boundary)

Playback is: render to a buffer → hand it to the player. `soloud_live_voice.dart`
is the only real-time voice in the app and it plays pre-decoded one-shots. There
is no live audio graph.

This is a **deliberate** architecture (`AUDIO_EDITOR_SUITE.md` §8) and it buys
real things: exact reproducibility, byte-identical render guarantees, headless
CLI testability, a gapless loop seam, and web parity without worklet plumbing.
Those are not to be thrown away.

But it is also the single hardest ceiling against the ask, because it removes:

- **input monitoring through the chain** — you cannot hear yourself with the
  track's reverb while recording;
- **playing an instrument in context** — tap a key, hear it against what plays;
- **punch/loop recording against the mix**;
- **immediate knob feedback** — a filter sweep is heard after a re-render, not
  under the finger.

**This needs a maintainer decision (see §7, D-RT).** The recommendation is a
*bounded* one, not a rewrite: a **real-time preview bus** that runs alongside
the offline renderer — live input + live played notes + a short FX chain — while
the timeline itself keeps playing its rendered buffer. Monitoring and
instrument-play become real-time; mixing and export stay offline and exact.

### S3 — No shared interaction grammar

Three surfaces, three vocabularies:

- **Keyboard.** The tracker has 33 `LogicalKeyboardKey` sites (block select,
  copy/cut/paste-mix, transpose, interpolate). The Audio Editor has 4. Loop
  Studio has 0 — not even space-to-play.
- **Transport.** Three separate transport bars, none shared, each with its own
  play/stop/loop semantics.
- **Direct manipulation.** Audio clips move by long-press-drag with grid snap
  (`daw_screen.dart:5426`) — good — but there are **no edge trim handles**;
  trimming is an inspector round trip. Loop Studio has no zoom at all
  (`InteractiveViewer|zoom`: 0 hits).
- **Discovery.** 157 registry tiles, and the five authoring modes hide behind a
  piano icon in a popup menu. There is no project browser and no "start from
  this" template shelf except in the Audio Editor.

A workstation is learnable because *one* set of gestures works everywhere. Ours
must be learned three times.

> **STATUS, audited against the code 2026-07-28** (`origin/main` @ `3a018344`).
> The Loop D1–D4 arc and the Audio swiss-army arc closed **12 of the 39** tasks
> since this was written and narrowed three more; **27 remain open.** ✅ = shipped
> and verified by symbol · 🔶 = narrowed, still open · ⬜ = open. The
> canonical, per-task detail is the ladder in [PLAN.md](../PLAN.md); this file is
> kept in step with it but is the *reasoning*, not the board.

---

## 3. Pillar W — the workstation shell (fixes S1, unlocks everything)

The highest-leverage work in this document. Build it first; the per-surface
ladders in §4–§6 get materially cheaper afterwards.

- ⬜ **WS-W1 — `Project`: one document, many track kinds.** A `Project` holds an
  ordered list of `ProjectTrack`s, each carrying a `kind` (audio · tracker ·
  loop · score · tab) plus its native document — *the existing document types,
  unchanged*. Not a new music model: a container. `daw_timeline.dart`'s
  `ClipSource` ("vector, not bitmap") is exactly the right precedent and its
  `.cbdaw v2` already stores a clip's model beside its audio, so half of the
  serialization thinking is done. Acceptance: a project with one track of every
  kind round-trips; opening it in any mode shows that mode's tracks editable and
  the others read-only-but-audible.
- ⬜ **WS-W2 — `TransportService`: one clock.** Position, tempo map, loop range,
  play/stop/record, count-in, metronome — a single `ChangeNotifier` every
  surface listens to. Today three clocks exist and none can follow another.
  Acceptance: pressing play in the Tracker moves the Loop Studio playhead.
- ⬜ **WS-W3 — one transport bar widget.** `shared/widgets/transport_bar.dart`,
  driven by WS-W2, hosted identically by all three surfaces. Kills three
  divergent implementations. Pure UI once WS-W2 lands.
- ⬜ **WS-W4 — one undo history.** Each service has its own stack
  (`daw_service.dart:2553 _Snapshot`, `LoopStack`, tracker `_clipboard`
  history). One `UndoService` with per-track scoping; the surfaces push
  labelled entries. Acceptance: an edit in Loop Studio is undoable from the
  Audio Editor's history list, and the label says what it was.
- ⬜ **WS-W5 — the mixer console.** One screen: a strip per project track (any
  kind) with level · pan · mute · solo · inserts (the shared `FxRack`) · sends ·
  meter. `daw_screen.dart` already has `_busMixerMatrix`, `_levelMeter` and the
  bus editor — this is a generalization of shipped code, not new DSP.
- ⬜ **WS-W6 — the browser.** One left-side panel: projects · templates ·
  instruments (the shared Sound Library) · samples · FX presets (chain strings)
  · the licensed asset catalog. Drag from it onto any surface. This is where
  the 157-tile registry and the asset catalog finally meet the authoring modes.
- ⬜ **WS-W7 — session ⇄ arrangement.** Loop Studio's scenes are already a real
  session grid (`GrooveScene(enabled, variants)`), and the Audio Editor is
  already a linear arrangement. Make them two views of the *same* project:
  launch scenes live, record the launches into the arrangement.

**Migration is additive, not a rewrite.** Every mode keeps its own screen and
its own document. `Project` wraps them; a mode opened without a project behaves
exactly as today. No slice may change a rendered byte — the same guard the
polymeter and automation slices used.

---

## 4. Pillar T — Tracker

The deepest editor we have, and the one closest to parity. Gaps are ergonomic
and connective, not musical.

### T-UX
- ⬜ **WS-T1 — eased playhead follow.** `_playFrac` already tracks sub-row
  position; the follow scroll still `jumpTo`s per row. Ease it. (Carried over
  from `PLAN.md` §3.2 — small, and it is the difference between "a grid that
  jerks" and "a machine that runs".)
- ⬜ **WS-T2 — pattern-matrix overview.** A block-per-pattern bird's-eye of the
  order list with drag-to-reorder, so a 64-pattern song is navigable.
- ⬜ **WS-T3 — the keymap becomes shared.** The tracker's 33 key handlers are the
  app's best interaction work and they are trapped in one file. Extract to
  `shared/keymap/` with named intents (`transposeUp`, `blockCopy`,
  `toggleFollow`, …) so the Audio Editor and Loop Studio inherit them. A
  discoverable, printable, **rebindable** keymap sheet is the deliverable.
- ⬜ **WS-T4 — a piano-roll view of a channel.** The tracker row grid is exact and
  unapproachable; `StepGridView` is approachable and quantized. Neither is a
  continuous piano roll, and the app has none anywhere (`pianoRoll`: 0 hits).
  One channel, one roll, same document — the single biggest legibility win for
  a newcomer opening a tracker module.

### T-parity
- ✅ **WS-T5 — per-channel FX rack.** `FxSpec` is mode-neutral; the tracker exposes
  only per-cell hex commands. Surface the shared rack on a channel's output
  (`AUDIO_EDITOR_SUITE.md` C7).
- ⬜ **WS-T6 — pattern-level time signature / groove templates** beyond global
  speed/tempo.
- ⬜ **WS-T7 — record from the transport.** Live-record notes into a pattern from
  the on-screen keyboard or a hardware controller (see WS-X5), with quantize.

---

## 5. Pillar L — Loop Studio

The most *approachable* surface and the least *equipped*. Under the Scratch
model (auto-memory `cometbeat-audience-scratch-model`) the ceiling is the point.

### L-UX
- ⬜ **WS-L1 — a keyboard at all.** Zero shortcuts today. Space = play, arrows =
  navigate cells, digits = velocity, Cmd/Ctrl+D = duplicate. Inherits from WS-T3.
- ⬜ **WS-L2 — zoom and a real timeline ruler.** No zoom exists. A 4-bar loop and a
  32-bar arrangement cannot both be legible at one scale.
- ✅ **WS-L3 — show the session grid.** Tracks × scenes as a matrix. *The data
  already exists* (each scene stores a per-track variant); it is rendered as a
  row of buttons. Pure UI, no model risk, exposes shipped power. **Cheapest
  large win in this document.**
- ✅ **WS-L4 — visible queued launch.** `_launchScene` applies state immediately
  while audio swaps at the loop seam, so correct musical timing reads as lag.
  Show the pending state. Small; it is what makes a performance surface feel
  professional.
- 🔶 **WS-L5 — duplicate a PATTERN** (narrowed twice; see PLAN.md). A section
  *is* a `GrooveScene`, so `_duplicateSection` already covers both; only the
  pattern half is open, and it needs a product decision first.
  "Copy A to B, change one thing" is how sequencer users work.

### L-parity
- ✅ **WS-L6 — per-track filter, then automate it.** `_masterFilter` is global and
  `AutomationParam.filter` renders nothing (verified: `trackFilter` 0 hits). A
  biquad per track in the mix path; then wire the filter param through the
  envelope seam `mixStems` already takes. Decision **D3** on the board.
- ✅ **WS-L7 — per-section repeat counts.** Chaining advances one pass per section,
  so A×4 B×2 A×4 is unsayable. Extends `renderArrangement`.
- ✅ **WS-L8 — add / rename tracks.** `duplicateTrack` + `removeExtraTrack` ship;
  arbitrary add and rename do not. Decision **D1** on the board.
- ✅ **WS-L9 — per-track swing.**
- ⬜ **WS-L10 — audio tracks in the loop.** Today a Loop Studio track is symbolic
  only. A recorded audio loop, tempo-matched, belongs here — and after WS-W1 it is
  the *same* clip type the Audio Editor holds.

---

## 6. Pillar A — Audio Editor

Engine-complete; the gaps are direct-manipulation and workflow.

### A-UX
- ⬜ **WS-A1 — edge trim handles + fade handles on the clip.** Move works
  (long-press-drag, cross-lane, snapped). Trim and fade do not — they are
  inspector round trips, and they are the two most-used gestures in any
  timeline.
- ✅ **WS-A2 — ripple edit and time selection.** `daw_service.dart` has ripple
  primitives; the timeline has no time-range selection to apply them to. Select
  a span across tracks → delete/insert/silence, everything after moves.
- ⬜ **WS-A3 — the keymap** (inherits WS-T3): 4 shortcuts today for a surface that
  lives on shortcuts.
- ✅ **WS-A4 — clip groups / linked clips, and nudge by grid or ms.**
- ⬜ **WS-A5 — loudness metering as a first-class view.** `crisp_dsp/loudness.dart`
  computes LUFS and the CLI reports it; the GUI does not show integrated /
  short-term / momentary, true-peak, or a correlation meter.

### A-parity
- ✅ **WS-A6 — take lanes and comping.** Record several passes, choose per phrase.
  `findPhrases` already finds the phrase boundaries. Zero matches for `takeLane`
  today.
- ⬜ **WS-A7 — clip warp / tempo-match.** Time-stretch exists as an effect; a clip
  cannot *follow the project tempo map*. With WS-W2's tempo map this is a clip flag
  plus a render-time stretch factor.
- ✅ **WS-A8 — per-clip gain envelope**, distinct from lane automation.
- 🔶 **WS-A9 — remaining A6/A7 DSP tiers** from `AUDIO_EDITOR_SUITE.md`: stretch
  quality knob, band-limited SRC tiers, raw up/down-sample.

---

## 7. Pillar X — interoperability (the part users actually feel)

The conversion matrix is built and honest. What is missing is *liveness* and
*reach*.

- ⬜ **WS-X1 — live links, not copies.** After WS-W1, "Open in Tracker" on a project
  track should open **that track**, not a duplicate — edits land in the project.
  Keep `ProjectBridge`'s loss report as the gate for a *kind change*; a same-kind
  open needs no conversion at all. This is the single change that turns five
  editors into one workstation.
- ⬜ **WS-X2 — drag between surfaces.** Drag a tracker pattern onto the timeline;
  drag a loop track into the Tab editor; drag an instrument from the browser
  onto any track. One `DragTarget` protocol carrying `(kind, document)`, with
  the loss report shown on drop when the kinds differ.
- 🔶 **WS-X3 — the FX rack in every mode** (`AUDIO_EDITOR_SUITE.md` C7). The model
  is already mode-neutral; Tracker/Loop/Tab/Score simply do not expose it. The
  chain string is the interchange format, so a chain travels with the track.
- ✅ **WS-X4 — lane-level send** (C6). You can send a clip somewhere; not a lane.
- ⬜ **WS-X5 — hardware and virtual controllers.** No MIDI input exists
  (`MidiDevice`: 0 hits). A MIDI-in seam feeding *any* surface's record path —
  tracker pattern, loop track, score, timeline — plus a shared on-screen
  keyboard/pad widget for platforms without one. Prerequisite for WS-T7 and for
  real-time play (D-RT).
- ⬜ **WS-X6 — one export sheet.** Every mode exports differently. One sheet:
  stems · master · symbolic (MusicXML/MIDI/module) · project archive · share
  token, with the codec matrix already in `AUDIO_CODEC_MATRIX.md`.

---

## 8. The one decision that needs the maintainer

**D-RT — do we add a real-time preview path?**

| Option | What it buys | What it costs |
|---|---|---|
| **A. Stay fully offline** (status quo) | Exact reproducibility, byte-identical guards, headless CLI tests, easy web parity | No monitoring, no play-in-context, no live knob feedback. The ceiling in §S2 stays. |
| **B. Real-time *preview bus* only** ⭐ recommended | Monitoring through a short chain, playable instruments over the rendered mix, live knob feedback on the previewed track. Mixing and export stay offline and exact — every existing guarantee and test survives. | One new audio path (input → chain → out) and its platform plumbing; latency budgeting; a second code path for a subset of FX. |
| **C. Full real-time graph** | Everything a conventional workstation does | Rewrites the engine, forfeits the byte-identical render guarantees the test suite rests on, and breaks web parity. **Not recommended.** |

Option B is scoped so that no existing render path changes: the preview bus is
*additive*, exactly as automation and polymeter were.

---

## 9. Build order

> **The executable task list lives in [PLAN.md](../PLAN.md) →** *"Workstation
> parity — the executable ladder"*, where each item below is broken out with
> **Goal · Depends · Files · Build · Acceptance · Size** and its traps. That is
> the canonical pending board; this section is the shape, not the work.

Foundations first, because everything after them is cheaper if they exist. IDs
below are shortened — on the board they carry a `WS-` prefix (`WS-W1`, `WS-L3`),
because `L1`–`L6` / `A1`–`A4` / `D1`–`D4` already mean different Loop Studio
work there.

```
1  the shell        W1 Project · W2 TransportService · W3 transport bar
2  the grammar      T3 shared keymap · L1 · A3 · A1 clip trim/fade handles
3  liveness         X1 live links · W4 one undo · X2 drag between surfaces
4  the console      W5 mixer · W6 browser · X3 rack in Score (last mode)
5  surface depth    L5 · L2 · L10 · A5 · A7 · A9 · T1 · T2 · T4 · T6 · T7
6  reach            X5 controllers · X6 one export sheet · W7 session⇄arrange
D-RT                decide before phase 3; build after phase 4 if B

closed 2026-07-28   L3 L4 L6 L7 L8 L9 · A2 A4 A6 A8 · T5 · X4
```

**Cheap wins that need no phase and can be pulled any time:** WS-L3 (session grid —
pure UI over shipped data), WS-L4 (queued-launch feedback), WS-A1 (trim handles), WS-T1
(eased follow).

## 10. Acceptance — what "done" means per slice

1. `dart format` first, `flutter analyze` (whole project incl. `test/`) last.
2. A **behavioural** test, not a plumbing test: for DSP, a spectral / gain-
   transfer / correlation assertion; for the shell, a cross-surface assertion
   ("play in Tracker moves the Loop Studio playhead"); for interop, a round-trip
   identity assertion.
3. **The byte-identical guard.** Any slice touching a render path proves that a
   project not using the new feature renders byte-for-byte as before. This is
   the discipline that carried polymeter and automation; it is not optional.
4. A CLI invocation where one exists — it is what makes an op both unit-testable
   and hearable in one command.
5. Small commit → board update → push.

## 11. Non-goals (stated so they are not re-litigated)

- **A full real-time audio graph** — see D-RT option C.
- **Third-party plugin hosting.** A native plugin ABI is a different project and
  most plugin standards carry licence entanglements we deliberately avoid.
- **Editing symbolic models *from* the waveform.** Audio → notes is estimation
  and stays behind the explicit Transcribe door.
- **A hardware-emulator path for the Tracker.** Classic pattern-editor
  *conventions*, yes; a rigid emulation of any specific machine, no.
- **Replacing any mode's native document.** `Project` wraps; it does not absorb.
