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
- ✅ **Playback (bucket F) — fully shipped.** Real transport + moving green cursor
  over `playbackTimeline`/`TempoMap`. `AudioService.playTimedChords` renders one
  gap-accurate WAV (empty pitch list = rest; chords together; tempo-scaled); a
  `Timer` drives the cursor over a seconds schedule shared with the audio (no
  player position stream needed). **Multi-part** shipped too (`7125e80`):
  `playMixedTimedChords` mixes every non-muted part via `mixStems` into one WAV,
  the cursor spans the full-score canvas (global `p{i}:` ids), and each part has a
  **Mute** toggle in its ⚙ menu. `_renderPart` scans all voices, so **voice 2
  sounds** (`34e223a`). A **practice-speed chip** (0.5×/0.75×/1×, `4638e81`) applies
  a wall-clock stretch to the audio ms *and* the cursor schedule together (pitch
  unaffected).
- ✅ **Song Book sing-along** (`337339d`, not a Workshop file but reuses this
  engine) — `chartFromScore(Score)→PlayAlongChart` via `playbackTimeline` +
  a "Sing along" button on the song viewer launching `PlayAlongScreen`; stars scale
  to song length (`scaledStarScore` + opt-in `PlayAlongScreen.scaleStarsToLength`,
  `f32a139`).

## Remaining work, scoped (pick one; each is its own commit + board claim)

**The Workshop parity arc is essentially complete** (as of 2026-07-17): every big
bucket — notation depth (tempo, grace, ornaments, tuplets, mid-bar clef, voice 2,
repeats/voltas/navigation), the Studio shell (input modes, inspector, Sandbox/
Studio shelf), playback (transport, cursor, multi-part mix/mute, practice speed,
**count-in + loop-a-selection**), and **PDF export** — has shipped. **What's left is
a little polish; nothing is architecture:**

- **Polish (doable now):** richer inspector (multi-select / rests / bar
  attributes), categorized *insertion* palettes, keyboard-first navigation in
  select mode (⚠ `opus (parity)` in flight — check the board), un-dual-purposing
  the value strip.
- **Voice-2 v1 gaps (doable now, model-side):** voice 2 carries no dynamics/
  lyrics/slurs, and tuplets/mid-score changes anchored while voice 2 is active
  don't stamp; cross-voice tap-select isn't wired.
- ✅ **Playback count-in + loop-a-selection SHIPPED** (`3c89abc`) — opt-in from the
  ⋮ menu, default off; count-in clicks render into the same WAV so they can't
  drift, loop clips every part and rebases to 0.
- ✅ **PDF export SHIPPED** (`e0954bd`) — turned out **not** to need a
  crisp_notation change: `SystemLayout.layout` is a `ScoreLayout`, so
  `layoutPages` (pagination) + `renderLayoutToPng` (per-system raster) + the `pdf`
  package compose a print-ready multi-page A4 file entirely app-side
  (`lib/features/workshop/export/score_pdf.dart`). Raster-per-system because the
  SVG path embeds `@font-face` text the pdf pkg can't parse and Bravura is
  CFF/OTF. This is the reusable recipe if a print *preview* is ever wanted.
- **Genuinely blocked on crisp_notation:** none of the remaining items are —
  grace-note LIST beyond a single run is the only "if ever wanted" library ask.

The sections below record HOW each shipped bucket was built (the pattern to reuse
for the polish items). Full context in `WORKSHOP_PARITY.md` §"Notation-depth
roadmap" and §"Suggested order of attack".

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
- **Voice 2** — ✅ **SHIPPED** (`bb6b7d0`). `Measure.voice2`; crisp_notation
  engraves voices 1+2 only. The document keeps `_v1`/`_v2`; `_elements` became a
  getter over the **active** voice (`_activeVoice`), so the ~25 mutation sites are
  untouched — only render/persist paths (`buildScore`/`loadScore`/`_capture`/
  `_restore`/`clearAll`/`buildGrandStaff`/dynamics/lyrics) are voice-explicit.
  `_withVoice2` reflows `_v2` onto the shared grid + stamps `Measure.voice2`
  (empty-voice byte-identity fast path). V1/V2 toolbar toggle; `setActiveVoice`
  clears the per-voice selection; `isEmpty` = both empty. MusicXML round-trips
  (writer backup). `test/voice2_test.dart`. **Known v1 limits (follow-ups):** voice
  2 carries no dynamics/lyrics/slurs (voice-1 side lists); tuplets/mid-score
  changes anchored while voice 2 is active don't stamp (they target voice-1 bars);
  cross-voice tap-select isn't wired (entry works, tap-to-select stays in the
  active voice). `buildGrandStaff` shows voice 1 only (unchanged display trick).

### Grace notes

- ✅ **SHIPPED** (`5b2df1a`). Per-note `EditorElement.graceNotes: **List<Pitch>**`
  + `graceStyle` (acciaccatura/appoggiatura) — a FIELD (pattern 1) riding the
  snapshot/clipboard. **NB `NoteElement.graceNotes` is a `List<Pitch>`, drawn as
  small notes — NOT a `List<NoteElement>` as an earlier draft of this doc claimed.**
  Zero bar duration, so `reflow` ignores them for packing (goldens hold). A "Grace
  notes…" palette editor (tap C–B at a chosen octave, chips remove, acciaccatura/
  appoggiatura toggle). Round-trips through MusicXML. `test/grace_note_test.dart`.

### The two big buckets — the Studio shell (Causes 2 + 3)

These are **not** notation attributes; they're the editor's interaction model,
and the biggest remaining lift. The palette popup is straining under the number
of attributes now — that's the signal these are due.

- **Cause 2 — input modes.** ✅ **FIRST SLICE SHIPPED** (`8526bc0`). An
  `_InputMode { insert, select }` on the screen, default insert. In select mode
  empty-staff taps deselect instead of placing (`_onStaffTap`/`_onMpStaffTap`) and
  letter keys no-op (`_handleKey`); tapping a note still selects, and the explicit
  piano keyboard still places in either mode. An Insert⇄Select toggle (icon+label)
  in the top bar keeps the mode visible. ✅ **The value strip is un-dual-purposed
  too:** `_pickAppliesToSelection` gates `_pickValue`/`_toggleDot`/
  `_pickAccidental` — Sandbox keeps the forgiving dual behaviour (unchanged),
  Studio *insert* arms without rewriting the selection, Studio *select* applies to
  it. ✅ **And keyboard-first *navigation*** (`b26a6b5`): in select mode the A–G
  keys jump the selection to the next note on that pitch (`selectNextOfStep`,
  wrapping, accidental-insensitive) instead of no-op'ing. **Cause 2 is fully
  done.**
- **Cause 3 — the inspector.** ✅ **FIRST SLICE SHIPPED** (`6306151`). An opt-in
  selection-driven panel (`_inspectorPanel`), docked right of the canvas
  (`Row[canvas, panel]`), toggled from the ⋮ view menu, **OFF by default** so the
  Sandbox surface is unchanged. Shows the selected note's articulations/tie
  (FilterChips), dynamic + ornament dropdowns, and buttons to the grace +
  change-here dialogs — reusing the `_doc` mutators. The ⌃ palette stays for quick
  actions. **Remaining inspector work:** multi-select and rest/bar-attribute views;
  categorized *insertion* palettes.

**The "Studio shelf" is built** ✅ (`5d467dc`, `WORKSHOP_PARITY.md` §"The strategic
tension" — two shelves, Sandbox + Studio, on one document). A `_Shelf { sandbox,
studio }` toggle (⋮ menu, default Sandbox) hides the Studio-tier controls (voice
toggle, input-mode toggle, inspector) on the kid surface and reveals them together
in Studio; leaving Studio resets those to their Sandbox defaults. **What's left is
polish, not architecture:** richer inspector, insertion palettes, keyboard-first
navigation in select mode, un-dual-purposing the value strip. PDF export ✅ shipped;
the capability-parity-with-progressive-disclosure goal is met.

### Playback (bucket F)

- ✅ **SHIPPED, fully** — real transport + moving cursor + multi-part mix/mute/
  full-score-cursor + voice-2 audio + practice speed + **count-in + loop-a-selection**
  (`3c89abc`). Reflects repeats/navigation/`RhythmPolicy.split` via `playbackTimeline`.
  Nothing open here.

### Scale (bucket G — only if needed)

- The layout ceiling is done; **PDF export shipped** (`e0954bd`). Still open (all
  low value): no incremental/dirty-range layout (each edit re-engraves the whole
  score's *cheap* natural pass — measured near-free, **not** worth a crisp_notation
  contract yet), the `maxNotes = 256` flat cap, an in-app print *preview* (the PDF
  raster recipe would reuse).

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
