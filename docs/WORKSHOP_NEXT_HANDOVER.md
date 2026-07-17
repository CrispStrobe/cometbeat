# Handover — the Composition Workshop, what's next

**Read this first, then `docs/WORKSHOP_PARITY.md` for the why.** This tells a
fresh agent exactly what the Workshop can do today, the one pattern that built
almost all of it, and the well-scoped remaining work with the traps for each.

Work in a **feature branch + a worktree that is a sibling of `mus/`** (e.g.
`../mus-work`), so the `../crisp_notation/...` path dep resolves — a worktree
under `.claude/` breaks it. `lib/features/workshop/**` is a **HOT file set**
(several agents push to `origin/main`): update the `docs/PLAN.md` 🚧 board and
push **before** touching a hot file and **after** each ship, `git pull --rebase`
often, keep commits small. **Pre-commit gate:** `dart format` **first** (run
`flutter pub get` before it in a fresh worktree, or it silently reformats the
whole repo — see `analyze-after-format-full-scope` memory), then `flutter
analyze` (whole project) **last**, then the suite.

---

## What the Workshop is today (don't rebuild this)

A touch- **and** desktop-first score editor, **three source files**:

- **`lib/features/workshop/model/score_document.dart`** — `ScoreDocument`: a
  single-part editable document. A **flat mutable `List<EditorElement>`** →
  packed into bar-lined measures by the pure top-level **`reflow()`** →
  `buildScore()` returns an immutable crisp_notation `Score`. Multi-level
  undo/redo (snapshot stack). Selection is a **`Set<String>` of element ids +
  focus id** (discontiguous). Also `buildGrandStaff()` (a display trick, not two
  voices).
- **`lib/features/workshop/model/multi_part_document.dart`** — `MultiPartDocument`:
  `List<ScoreDocument>` (one per instrument) → `MultiPartScore` → the full-score
  canvas. G6; feature-complete.
- **`lib/features/workshop/screens/composition_workshop_screen.dart`** (~2500 lines)
  — the editor shell: full-bleed canvas, piano dock, value/accidental strip, a
  note-property **palette** (the ⌃ popup) + range-action buttons + a ⋮ overflow
  menu.

**Feature inventory (all shipped, all localized de/en, all with tests):**

- Note/chord/rest entry (piano, staff-tap, A–G keys), durations whole…16th + dot,
  accidentals ♮♯♭, ties, slurs, hairpins, dynamics, articulations, lyrics
  (multi-verse), pickup.
- **Mid-score clef / key / time changes**, **repeats** (start/end), **voltas +
  navigation** (D.C./D.S./coda/segno/fine), **tuplets**, **ornaments** (trill/
  mordent/turn), **full meters + circle of fifths**, **`RhythmPolicy.split`**
  (tie over-long notes across barlines; ⋮-menu toggle), **discontiguous
  selection** (marquee selects exactly what it covers).
- Import MusicXML/`.mxl`/MIDI/ABC/MEI/`**kern`/MuseScore/GuitarPro; export those +
  LilyPond/Braille/SVG/PNG. **Save → reopen is lossless** for everything the
  element stream holds. Multi-instrument authoring (G6).

**Perf is handled:** interaction costs **zero layouts** (`c968fbf`-era fixes +
`1d9c804`); the large-score layout ceiling was fixed in crisp_notation itself
(`198ef17`, justification via regula falsi).

---

## THE PATTERN that built the notation-depth features — use it

crisp_notation already **models and draws** nearly everything. The editor's job
is to *express* it. There are two shapes, and picking the right one is the whole
game:

1. **Per-note property → a FIELD on `EditorElement`.** Ornaments, articulations,
   ties, dynamics. Add a field, thread it through the two constructors +
   `toElement()` + `_copyWith` + `withId` (so paste keeps it) + a `withX` helper,
   add a `setXOfSelected` mutator, and recover it in `loadScore`. **It rides the
   existing element snapshot for undo and the clipboard for free** — no side-map,
   no invalidation plumbing. Ornaments (`194fa66`) are the reference example.

2. **Bar-anchored attribute → a SIDE-MAP keyed by element id.** Mid-score clef/
   key/time, repeats, voltas, navigation. Store `Map<String, X> _xChanges`;
   `buildScore` stamps it onto whichever bar the anchor note reflows into
   (`_withMidScoreChanges` for pure post-reflow stamps; `reflow`'s `timeChanges`
   for time, which changes bar capacity). **Anchoring to the id, not a bar index,
   is the point** — bars are reflowed on every edit, so an index would drift, but
   the id moves with its note. Wire it through `_Snapshot` (constructor + field +
   `_capture` + `_restore`), `clearAll`, and `loadScore` recovery. Clef changes
   (`685ced2`) are the reference example.

**Non-negotiable invariant:** every additive feature keeps an **empty-anchor fast
path** (`if (_xChanges.isEmpty) return bars;`) so a document without the feature
renders byte-for-byte as before. `test/score_document_packing_golden_test.dart`
pins this — if a golden moves, you changed observable behaviour and need a
decision, not a silent test update. The known-wrong goldens there are pinned on
purpose (an overflowing note short-fills in spill mode).

**Why NOT the bar-spine flip:** the original plan (`WORKSHOP_PARITY.md` Cause 1)
was to make `List<Bar>` the source of truth. It was **retired** — it means
rewriting ~60 index-based mutation sites at once and is the wrong architecture
for spill mode (reflowed bars have no stable identity). The id-anchor pattern got
every feature at a fraction of the risk. Don't resurrect the flip.

---

## Shipped since this handover was written (2026-07-17)

- ✅ **Tempo marks** — document-level `Tempo? tempo` (→ `Score.tempo`) + id-anchored
  `_tempoChanges` side-map (→ `Measure.tempoChange`), the clef/key stamp pattern.
  Tempo row in the change-here dialog + "Initial tempo…" in the ⋮ menu.
  `test/tempo_test.dart`. **Caveat:** the crisp_notation MusicXML *reader* treats
  the first `<metronome>` it sees as `Score.tempo`, so a doc with a mid-score
  change but no initial tempo reads that change back AS the initial tempo — set an
  initial tempo (real scores do) for an exact round-trip.
- ✅ **Grace notes** — per-note `EditorElement.graceNotes: List<Pitch>` + `graceStyle`
  FIELD (pattern 1). **NB the handover below was wrong:** `NoteElement.graceNotes`
  is a `List<Pitch>` (drawn as small notes), NOT a `List<NoteElement>`. Zero bar
  duration → packing untouched. "Grace notes…" palette editor. `test/grace_note_test.dart`.
- ✅ **Playback (bucket F)** — real transport + moving green cursor over
  `playbackTimeline`/`TempoMap`. `AudioService.playTimedChords` renders one gap-
  accurate WAV (empty pitch list = rest; chords together; tempo-scaled). A `Timer`
  drives the cursor over a seconds schedule shared with the audio (no player
  position stream needed). **Scoped to the active part** — multi-part mixing +
  per-part mute is unbuilt (needs a `mixStems`-style overlapping renderer; the
  synth's `renderWav` only sequences segments, so this is a real audio task, not
  wiring). Multi-part canvas cursor also unbuilt (its `highlightedIds` are global
  ids, not the active part's local element ids).

## Remaining work, scoped (pick one; each is its own commit + board claim)

Ordered roughly easiest → hardest. Full context in `WORKSHOP_PARITY.md`
§"Notation-depth roadmap" and §"Suggested order of attack".

### Small notation follow-ups (the id-anchor / field pattern, low risk)

- **Mid-*bar* clef changes** — ✅ **SHIPPED, fully lossless** (`12404e1` model +
  `854ab25` UI; writer `crisp_notation@3c1b8bd`). `_inlineClefs` id-anchor side-map
  → `Measure.inlineClefs`; the `_withInlineClefs` stamp walks each reflowed bar
  accumulating the tuplet-scaled onset and emits an `InlineClefChange` at the
  anchor's onset (onset-0 anchors are a bar-start change, skipped). "Clef
  (mid-bar)" row in the change-here dialog; `loadScore` recovers them.
  `test/inline_clef_test.dart`. **The MusicXML writer now emits mid-measure clefs**
  (it used to only write the bar-start clef; the reader already parsed them), so
  **save → reopen is lossless** — both the in-memory and the MusicXML *file*
  round-trip are asserted. This closed the `workshop-musicxml-writer-gaps` blocker.
- **Voice 2** — `Measure.voice2` (crisp_notation engraves voices 1 **and** 2 only
  — stop there). The flat `_elements` gains a sibling `_voice2` list; `reflow`
  packs each independently onto the **shared** bar grid (they must agree on bar
  count). Medium. **Trap:** `buildGrandStaff` is a second packing path — decide
  whether it shows voice 2. Selection/UI needs an "active voice" concept.

### Grace notes (the one remaining "hole" that isn't a one-liner)

- `NoteElement.graceNotes` is a **`List<NoteElement>`** (+ `graceStyle`
  acciaccatura/appoggiatura), so a grace note is a mini-sequence attached to a
  note, not a single enum. Model: `EditorElement.graceNotes: List<...>` (a FIELD,
  rides the snapshot); a small entry UI (place notes into the grace slot of the
  selected note). Grace notes have **zero** bar duration, so `reflow` ignores
  them for packing — good, no capacity interaction. Medium; the UI is the work.

### The two big buckets — the Studio shell (Causes 2 + 3)

These are **not** notation attributes; they're the editor's interaction model,
and the biggest remaining lift. The palette popup is straining under the number
of attributes now — that's the signal these are due.

- **Cause 2 — input modes.** An explicit *insert* vs *select/object* state
  machine. Today the staff is always live for placement and the value strip is
  dual-purpose (arming the next note *and* rewriting the selection). Real
  keyboard-first entry needs the separation. Rides on the caret (already an
  address via `caretBeforeId`). Design it as a mode enum on the screen with the
  status line always showing the current mode.
- **Cause 3 — the inspector.** A selection-driven properties panel that reflects
  whatever is selected, replacing the growing ⌃ popup. Scales to arbitrary
  element types at ~zero marginal UI cost. Pair it with categorized *insertion*
  palettes (the popup stays for quick actions).

**These two are where the "Studio shelf" gets built** (`WORKSHOP_PARITY.md`
§"The strategic tension" — two shelves, Sandbox + Studio, on one document). Keep
the kid Sandbox surface unchanged; reveal Studio depth behind a toggle.

### Playback (bucket F — high user value, mostly wiring)

- `_play` in the screen is a fixed-tempo, rest-less, chord-less, active-part-only
  beep. The library ships `playbackTimeline(score)` (expands repeats + navigation
  — which you already emit), `soundingAt()` (the cursor), and `TempoMap`; the app
  owns audio (`AudioService`, `audioplayers`). Build a real transport + a moving
  playback cursor (highlight `soundingAt` ids) + per-part mute. `RhythmPolicy.
  split` / repeats / navigation already expand in the timeline, so playback would
  reflect them.

### Scale (bucket G — only if needed)

- The layout ceiling is done. Still open: no incremental/dirty-range layout (each
  edit re-engraves the whole score's *cheap* natural pass — measured near-free,
  **not** worth a crisp_notation contract yet), the `maxNotes = 256` flat cap,
  page/print view, PDF export (crisp_notation has none).

---

## Test + verify conventions (match these)

- **Model features:** a dedicated `test/<feature>_test.dart` — set/clear + undo,
  applies-to-selection, a **byte-identity** case (no-feature → goldens hold), and
  a **MusicXML save→reopen round-trip** (the real Save/Open path). See
  `test/ornament_test.dart` / `test/mid_score_change_test.dart` for the template.
- **UI:** extend `test/composition_workshop_test.dart` — drive the real control
  (open the palette, tap the item) and assert the effect. To check a
  `CheckedPopupMenuItem`'s state, find the **IconButton/menu item by its glyph or
  text**, not `find.byTooltip` (that points at the `RawTooltip`, not the button).
- The interactive views' `CheckedPopupMenuItem` is typed `<(String, Object?)>` —
  match that generic in `find.byType`.
- The `CompositionWorkshopTester` interface exposes a few observables
  (`noteCount`/`barCount`/`hasSelection`/`partCount`…). **Don't widen it** for a
  new feature — verify via the rendered `Score` or the menu item's checked state.

## Gotchas that cost real time here

- **`dart format` in a fresh worktree before `flutter pub get`** reformats the
  whole repo into the new "tall" style and adds trailing commas the correct style
  then force-splits — *not* reversible by reformatting. Always `pub get` first;
  format only *your* files.
- **The shared machine** runs several agents + Xcode concurrently; load has spiked
  to ~200 and OOM-killed test runs. Watch for a quiet window (Monitor on
  `uptime`) rather than hammering it. When killing stray flutter procs, **scope by
  cwd** to your own worktree — a global `pkill flutter_tester` kills another
  agent's suite.
- **`buildGrandStaff` is a second, independent packing path** — the id-anchor
  stamps run only on single-staff `buildScore`. Any feature that should show in
  grand-staff mode needs explicit handling there.
- CI resolves the **public** `CrispStrobe/crisp_notation@main`; a private-only API
  reds CI even when local is green (memory `partitura-public-vs-private-ci`).

## Key file map

- Model: `lib/features/workshop/model/score_document.dart` — `EditorElement`,
  `ScoreDocument`, the top-level `reflow()` / `notate()` / `Tuplet` /
  `RhythmPolicy`.
- Screen: `lib/features/workshop/screens/composition_workshop_screen.dart` —
  `_paletteButton` (note-property popup), `_showChangeHereDialog` (bar-anchored
  changes), the ⋮ menu, the input-bar range actions.
- Tests: `score_document_test`, `score_document_more_test`,
  `score_document_packing_golden_test` (byte-identity), `reflow_test`,
  `mid_score_change_test`, `tuplet_test`, `ornament_test`, `rhythm_split_test`,
  `composition_workshop_test` (widget).
- Strategy: `docs/WORKSHOP_PARITY.md`. crisp_notation editor contracts:
  `docs/WORKSHOP_CRISP_NOTATION_CONTRACTS.md`.
</content>
