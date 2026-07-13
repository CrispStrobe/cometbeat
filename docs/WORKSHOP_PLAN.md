# Score Workshop → full score editor — plan

## 🔨 Active now (update + push to origin/main at every checkpoint)

- **Doing:** P2a editor model + UX (caret insert, selection nav, transpose,
  accidental/dot editing, key signature) — merging.
- **Next:** a full touch-first editor GUI redesign, rebuilt on top of
  `ScoreDocument` (full-bleed score canvas + a bottom input dock).
- **Status:** P0 ✅ · P1 ✅ · P2a ✅(merging) · GUI redesign ⏳ planning.

---


Branch `feature/score-workshop`, worktree `../mus-workshop` (sibling of `mus/`
so the `../partitura` path dep resolves). Merge to `origin/main` at each phase's
stopping point. **Beware parallel agents** (`../mus-playalong` on
`feature/pitch-detection-spike`, and uncommitted l10n/sing-back work on local
`main`) — rebase before each merge, keep l10n edits additive.

Goal: evolve the Composition Workshop **in place** into a single editor that is
simple by default (progressive disclosure) yet scales into a full-featured score
editor. Keep the kid "My Melody" sandbox as-is. (Convention: do **not** name or
allude to other products in code or docs, and don't frame the design as matching
anyone else — describe only our own design. Interchange **formats** are referred
to by their standard name / file extension only.)

## Reality check — partitura already does ~70% of a notation program

Verified against the `partitura`/`partitura_core` barrels + model source. The
library is deliberately **render + theory only** — editing/note-entry and audio
are permanent non-goals ("consumers build editing on top of the model").

- **Model** (`partitura_core`, immutable value classes; `Measure.copyWith`
  exists, `Score` has **none**): single staff, **2 voices/measure**, tuplets
  (`TupletSpan`), ties, slurs, dynamics, hairpins, articulations, ornaments,
  grace notes, fingerings, arpeggio, tremolo, notehead shapes; per-measure
  key/time/clef **changes**, start/end **repeats**, voltas, navigation
  (D.C./D.S./coda/segno/fine), barline styles, pickup, multi-rest; score-level
  lyrics, chord diagrams, figured bass, ottavas, pedals, tempo, transposition,
  metadata. Professional-grade richness **for a single part**.
- **Layout engine**: `LayoutEngine`, multi-system line-wrapping, page layout,
  grand staff, tab — all single-`Score` (no cross-part pagination yet).
- **Rendering** (`partitura`): `StaffView`, `InteractiveStaff` (ghost-note
  preview, drag, `highlightedIds` selection, measure-indexed hit-testing via
  `StaffTarget`), `MultiSystemView`, `ScorePageView`, `GrandStaffView`,
  `TabStaffView`. Bravura SMuFL bundled. `RenderStaffView` exposes hit-testing
  geometry (`elementIdAt`, `quantizeStaffPosition`, `localToStaff`).
- **Import**: MusicXML (+ compressed `.mxl`, multi-part), MIDI, MEI, ABC,
  Humdrum `**kern`, plus editor/tablature container formats (`.mscx/.mscz`,
  `.gp*`) and ASCII tab.
- **Export**: MusicXML/`.mxl`, MIDI, MEI, `**kern`, `.ly`, `.mscx/.mscz`, `.gp*`,
  ABC, SVG, PNG. No PDF or `.capx`.
- **Playback**: `playbackTimeline(score)` → sorted onsets (expands repeats),
  `soundingAt()` → ids to highlight. No audio in the library (app supplies it).

## What's actually missing (the editor + one model gap)

- **G1 Editable document + undo/redo** — model is immutable, `Score` has no
  `copyWith`; today's workshop reinvents a flat `_WNote` list. Need a
  `ScoreDocument` + command stack producing new immutable `Score`s.
- **G2 Selection / caret / clipboard** — none in the library (app state only).
- **G3 Entry palettes** — rests, dots, accidentals, ties/slurs, tuplets,
  dynamics, articulations, key/time/tempo/clef, barlines/repeats, lyrics.
- **G4 Multi-modal entry** — staff tap (have ghost), computer-keyboard (A–G +
  duration digits), on-screen piano (have widget), mic/MIDI step-entry (app
  already has `microphone_pitch_service`).
- **G5 File I/O** — open a file into the editor, save native, export
  PDF/PNG/MusicXML/MIDI, print.
- **G6 Multi-instrument** — `Score` is single-part; multi-staff is layout-only
  (loose `List<Score>` with global ids). True ensemble scores need a `Part`
  document model added to `partitura_core` + cross-part page layout. Biggest
  lift; coordinate in the partitura repo. Deferred to P4.
- **G7 Page/print view, layout options, PDF.**

## Phases (each ends mergeable)

- **P0 — About parity** ✅ merged: dedicated `AboutScreen`
  (provider/contact/privacy/disclaimer/license sections + license page),
  localized de/en.
- **P1 — Editor foundation** ✅ merged: `ScoreDocument` (editable element stream
  → immutable `Score`) with multi-level undo/redo + selection; workshop rebuilt
  on it with rests, dotted notes, accidentals (♯/♭/♮), and redo. Model unit-
  tested (`test/score_document_test.dart`). Next: insert-at-caret (not just
  append), change-duration-of-selected UI (command already in the model).
- **P2 — Full single-staff**: ties/slurs, triplets, key sig, tempo, dynamics +
  articulations, barlines/repeats, 2nd voice, pickup, lyrics; wire every
  partitura export; playback w/ moving cursor. **MERGE.**
- **P3 — Open existing scores** (chosen next priority): import MusicXML/MIDI/
  container formats into the editor and edit them; robust file open/save; page &
  print/PDF view; layout options. **MERGE(s).**
- **P4 — Multi-instrument**: extend `partitura_core` with a `Part`/multi-staff
  model, then multi-staff editor, instrument picker, score/part views,
  transposing instruments. **MERGE(s).**

## CI constraint (important)

mus CI/deploy resolve the `../partitura` path-dep against the **public**
`CrispStrobe/partitura@main`, which lags the local private partitura. So every
partitura API used must exist on public partitura or CI reds even though it
compiles locally. Consequence for **P4**: do NOT add a private-only `Part`
model to the local partitura — build multi-instrument on the public
`StaffSystem`/multi-`Score` layout, or port the model to public partitura first.
See memory `partitura-public-vs-private-ci`.

## Status: P0 ✅ · P1 ✅ · P2 in progress.
