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
- **P2a — Cursor editing** ✅ merged: caret insert, ◀ ▶ selection nav, ▲ ▼
  transpose, edit-selected value/dot/accidental, key-signature picker.

## Editor GUI — target design (touch-first)

The stacked-chips + button-rows layout doesn't scale. Target a touch-first
score-editor shell on top of `ScoreDocument`:

- **Full-bleed score canvas** (center): continuous horizontal scroll by default
  (page view later), pinch-zoom, drag-pan. Tap a note to select; drag a note
  vertically to re-pitch (later); long-press to range-select (later).
- **Bottom input dock** (thumb zone), two rows:
  - *Duration / modifier strip* — Bravura glyph buttons for note values
    (whole…32nd), dot, tie, rest, accidental (♮ ♯ ♭); ≥ 44 px; a "hold duration"
    lock so repeated taps place the same value. Entry is **duration-first, then
    pitch**.
  - *Swappable pitch surface* — tabs: on-screen **piano** (reuse the existing
    `PianoKeyboard`), **fretboard** / **cello** for those instruments, and
    **staff-tap**. Tapping a key/fret inserts a note at the caret with the armed
    value.
- **Status line** — always shows the armed value + current selection ("Quarter ·
  Beat 3 · G4" / "Pick a value, then a note"), so the mode is never ambiguous.
- **Thin top bar** — undo / redo, a single Play (expands to Stop while playing),
  and an overflow for save / export / import / time + key.
- **Element palettes as bottom sheets** — a palette button opens categorized
  sheets (dynamics, articulations, clef, key/time, text/lyrics) applied to the
  selection; long lists get a search field + progressive "More".
- **Contextual inspector** — when one element is selected, a compact sheet with
  graphical pickers (accidental, dot, tie, transpose, delete).

Keep a **simple default** (glyph strip + piano) and reveal depth progressively —
one surface serves both the kid-sandbox feel and the full editor.

**Platforms — first-class on all of them, incl. desktop.** Mouse click / drag /
hover, touch, and keyboard must all work. The user must *see where a note will
land before committing* (hover/drag **ghost note** preview + the status line),
and **every placed note must be easily editable** — its duration via the value
strip, its pitch by drag-on-staff or ▲ ▼, plus accidental/dot — with the change
previewed. No touch-only gestures without a mouse/keyboard equivalent.

### Rebuild phases (each mergeable)

- **G1 — New editor shell** ✅ merged: full-bleed zoom/pan canvas with a
  ghost-note placement preview + bottom input dock (duration/accidental glyph
  strip + piano / staff-tap surface) + status line + contextual selection bar;
  undo/redo/play/settings on the top bar. Cross-platform (web build verified).
- **G2 — Palettes & inspector**: bottom-sheet palettes + a contextual inspector;
  the model gains dynamics, articulations, ties.

  **Direct UX feedback:**
  1. ✅ *Cleaner chrome* — consolidated to **two slim rows** (Row A: compact
     clef/time/key/zoom **dropdowns** + status; Row B: value/accidental strip +
     contextual selection actions) so the canvas gets the space; slim action bar
     (no big title) + ⋮ menu (save / export MusicXML / ABC / clear).
  2. ✅ *Gesture fix* — placement is now from the piano at the caret; the staff
     is view + select only, so pan/zoom can never drop a stray note.
  3. ⏳ *Drag placed notes* (G3) — needs a drag-move hook (partitura-side or an
     app-side custom canvas).
  4. ✅ *Select ranges + move/copy/cut/paste* — the model is now range-based
     (`ScoreDocument` selection = index range + clipboard); Row B offers
     extend-selection, move-in-score, transpose, copy/cut/paste, delete over a
     note or a whole range. (Marquee/drag-select still needs C4 — see contracts.)
  5. ◐ *Both clefs / grand staff* — auto-flip removed; clef is now a manual
     treble/bass control (no surprise flip). True simultaneous **grand staff**
     with multiline is not in the public renderer yet → G3+ (needs partitura
     work; `GrandStaffView` is single-system only).
  6. ✅ *Multiline* — canvas is now `MultiSystemView`; the score wraps into
     systems and scrolls vertically.
- **G3 — Gestures & views (all platforms)**: mouse hover-preview of the landing
  note; drag a note on the staff to re-pitch (mouse + touch); drag-select /
  long-press range-select; page vs continuous toggle; zoom control (pinch +
  ctrl-scroll). Keyboard: arrows to move the caret, letters A–G / digits for
  value.
- **G4 — Notation depth**: tuplets, 2nd voice, tempo, barlines/repeats, lyrics;
  wire every partitura export; playback moving cursor.
- **G5 — Open existing scores** ◐: ⋮ menu now opens **MusicXML / MIDI** files
  into the editor (`ScoreDocument.loadScore` flattens voice 1 → editable
  elements; undoable). Still to do: `.mxl`/`.mscz`/ABC, chords/2nd-voice import
  fidelity, page/print/PDF.
- **G6 — Multi-instrument**: multiple staves via the public `StaffSystem` /
  multi-`Score` layout (no private-only model), instrument picker, part views,
  transposing instruments.

## CI constraint (important)

mus CI/deploy resolve the `../partitura` path-dep against the **public**
`CrispStrobe/partitura@main`, which lags the local private partitura. So every
partitura API used must exist on public partitura or CI reds even though it
compiles locally. Consequence for **P4**: do NOT add a private-only `Part`
model to the local partitura — build multi-instrument on the public
`StaffSystem`/multi-`Score` layout, or port the model to public partitura first
(applies to **G6**). See memory `partitura-public-vs-private-ci`.

## Status
P0 ✅ · P1 ✅ · P2a ✅ · G1 ✅ · G2 ✅ (multiline canvas · piano placement) ·
G3a ✅ (two-row chrome · range selection + move/copy/cut/paste) · G5a ✅ (open
MusicXML/MIDI files into the editor). **Pending
partitura** (see [WORKSHOP_PARTITURA_CONTRACTS.md](WORKSHOP_PARTITURA_CONTRACTS.md)):
staff-tap on multiline (C1), hover/caret (C2), **drag-to-move (C3)**, marquee
select (C4), **interactive multiline grand staff (C5)**. App-side next while
partitura lands those: palettes/inspector (dynamics/articulations/ties), open
existing score files.
