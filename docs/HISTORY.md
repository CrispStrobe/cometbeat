# KlangUniversum — Shipped history

The record of what's been built and lives in production
([mus-theta.vercel.app](https://mus-theta.vercel.app)). Forward-looking work —
what's pending and planned — lives in the canonical [PLAN.md](../PLAN.md) at
the repo root (detailed roadmap planning and the agent board are in
[docs/PLAN.md](PLAN.md)); this file is the changelog they graduate from.

## Progression

## Chord-chart backing band — the whole ladder, and it plays (2026-08-01)

**One-line status:** the backing-band arc went from a headless engine nobody
could reach to a **complete feature** — write a chart, read it on a stand, hear
a styled band play it, keep it. `BB-D1`, `D2`, `D4a`, `A0`–`A7`, `U1`, `U2` are
all closed, plus chart persistence and autoscroll.

**What you can now do:** open **Chord Chart** in the harmony category → a
twelve-bar blues is already there → tap a bar for the keypad (one tap for a
major chord, two for anything on the main grid) or paste a text chart → pick a
style and how many times through → press play and a kit, a bass and a comp
arrive, with a count-in, fills at phrase ends and an ending. Charts autosave and
can be named and reopened.

**The pattern that produced most of it:** *the tests kept catching real defects
in my own design, not just typos.* Four worth keeping:

- **A style pattern validates against its LONGEST claimed meter, not its
  shortest.** The validator's first run rejected my own data: `straight` claimed
  meters 2–7 while writing 4-beat patterns. That forced a decision left
  implicit — a pattern is written for the longest bar and truncated to the
  actual one, so validating against the longest is what proves no hit is dead
  code. Truncation is an author's judgement the validator cannot make: a plain
  pulse survives being cut to three beats, a bossa clave does not, which is why
  `straight` claims 2–7 and every characterful style claims one meter.
- **`(seed + barIndex) % 4` was degenerate exactly where it was used.** Drum
  fills land on phrase ends; phrases are 4 or 8 bars; so every fill index is
  congruent mod 4 and the "varying" fill shape was always the same one. Bars 7,
  15, 23 and 31 all produced shape 3. A mixing hash has no such resonance with
  the phrase length.
- **`StyleHit.voice` had to become REQUIRED because 0 is the kick.**
  `avoid_redundant_argument_values` stripped every `voice: _kick` out of the
  style data the moment `dart fix` ran, leaving drum hits that read as
  *unspecified* when they meant *kick*. The lint was right about code and wrong
  about data.
- **Swing is the STYLE, not humanisation.** `humanize: false` keeps the swing
  and drops only the feel and jitter, or turning humanisation off would silently
  straighten a swing chart.

**Three silent-data-loss bugs, all found by looking at DATA rather than at parse
status** — the same class as the historical `\<` truncation:

- **System slicing dropped every chord symbol.** `multi_system.dart:_slice`
  forwards ~40 attachment lists and `chordSymbols` was not among them, so
  multi-system, grand-staff, multi-part and paged rendering lost them — which is
  every score view the app shows. Only the single-system `StaffView` path ever
  displayed them, which is why the feature looked like it worked
  (crisp_notation `41a05d1`).
- **The Workshop threw away a lead sheet's harmony.** `ScoreDocument` neither
  read nor wrote `Score.chordSymbols`, so opening a chart-bearing score there
  dropped its chords and export could never put them back. Six sites, following
  the existing `_lyrics`/`_annotations` pattern.
- **Two LilyPond reader bugs**, surfaced by indexing 547 exact charts and
  noticing sixteen malformed `C/C` symbols in the output: duration multipliers
  (`c1*3/4`) were *dropped* by a `$`-anchored note gate — a rejected token
  vanishes rather than being mis-read — and an octave mark on a chord root
  (`f,2/c`) blocked the duration group. Between them they corrupted roots and
  silently truncated charts (crisp_notation `ca8051c`, `7525a1a`).

**Process failures worth recording, because they cost other people time:**

- I committed a new test file without re-running `flutter analyze`, and another
  agent had to fix seven lints I left on main. **CI runs Analyze BEFORE Test, so
  green tests are not evidence.** A pre-commit hook now enforces the order.
- Two of us fixed the same red concurrently and the merge produced a **duplicate
  ARB key**, which survives both git and `flutter analyze` (analyze reads the
  *generated* Dart, which only `flutter gen-l10n` rebuilds) and surfaces as a
  compilation failure. Delete-and-recreate is not the fix; checking for
  duplicates after every rebase is.

**Known limitations, stated rather than hidden:** per-note dynamics reach the
kit (`renderDrumPattern` takes gains) but not comp or bass — `Segment` is
`(freqs, ms)` with no level field, so melodic dynamics come only from the stem
gain, and fixing it means changing `Segment` in the shared `synth.dart`. Live
changes *during* playback (`BB-T2`, `BB-U3`) still need `BB-T1`'s windowed
renderer; the current path renders the whole performance up front.

---

### BB-T4 — transposition, on both axes (2026-08-01)

A horn player reads B♭ while the band plays concert pitch, and collapsing
those into one "transpose" control is the classic mistake. **Sounding** moves
the tune, audio and print together; **display** (a B♭ instrument, a capo) moves
only what is printed and must never touch the audio.

Interval-based rather than semitone-based throughout, which is what makes the
spelling come out right for free: up a major third from A♭ is C, not B♯, and a
semitone count cannot express that difference.

⚠️ **Two real defects the tests caught before shipping:**

- **F♯ major up a major second is G♯ major — eight sharps, a signature that
  does not exist.** I had clamped to ±7, which silently lands on an unrelated
  key. The right answer is to respell the INTERVAL: F♯ up a *diminished third*
  is A♭, four flats, and every chord then spells in flats to match. A
  consequence worth stating: a key that leaves the circle **cannot** round-trip
  and must not — F♯ up a tone and back is G♭, which is F♯ enharmonically.
- **Wiring the grid to the printed chart nearly shipped a silent rewrite.**
  Tapping a bar that prints `C` would have opened the keypad on the *sounding*
  chord and stored the result as concert pitch, so a trumpeter editing their
  own part would rewrite the tune for everyone. The keypad now opens on what
  the user sees and converts back through `documentChordOf` — the inverse in
  reverse order: capo, then instrument, then the sounding shift.

`lib/core/harmony/chart_transpose.dart` + `features/harmony/transpose_sheet.dart`,
24 model tests (including an exhaustive sweep of all 15 keys × 23 shifts) and 4
widget tests.

### The cards, as they were written

- ✅ **Generate FX creates instruments — DONE (verified 2026-07-26).**
  `_generateFx` (`my_instruments_sheet.dart:470`) lives in the Sound Library
  creation menu and returns a `SavedInstrument` that is merged straight into the
  library list, so a generated FX is thereafter pickable anywhere the sheet
  opens — Tracker, Workshop playback, Audio Editor voicing. It is **not**
  reachable from Audio Editor > Add clip, which was the anti-requirement.

- ✅ **Add clip adds timeline material — DONE (verified 2026-07-26).** The
  Add-clip menu (`daw_screen.dart:~4390`) offers exactly the specified set and
  nothing else: `dawAddFromLibrary`, `dawImportAudioFile`, `dawAddMusic`,
  `dawExtractSample`, `dawAddBeat` (+ tune). No sound-design entry — that work
  happens in the Sound Library.

- ✅ **Every surface with a rack can SAVE a chain, and every surface HAS a rack
  — DONE 2026-07-30/31** (opus, daw-suite). Two halves, both found by auditing
  rather than by a card:
  - **`fx_presets.dart` was a fixed enum of factory sounds with two callers**, so
    five surfaces hosted an FX rack and none could keep the chain you dialled in.
    `core/services/fx_preset_store.dart` (the `ProjectStore` shape, storing chain
    STRINGS — already the interchange format, already what the Audio Editor puts
    on the clipboard, and readable in a bug report) plus a shared sheet on the
    `keymap_sheet` pattern, hosted by **all five racks**. A chain string cannot
    carry per-param automation, so the sheet says so before saving one, and stays
    quiet for a plain chain.
  - ⚠️ **The ADVANCED Tracker had no rack at all** while the BEGINNER one did —
    `TrackerChannel.fxChain` and `setChannelFxChain` already existed and that
    screen simply never offered them, making the serious tracker the only surface
    with no per-channel effects. Now a long-press on the channel header (that
    header is 74 px and already carries three controls).

- ✅ **Voice Shaping is an audio FX module — DONE (verified 2026-07-26).**
  `voiceShape` / `voiceChipmunk` / `voiceDeep` / `voiceRobot` / `voiceRadio` are
  `FxType` values with defaults in `fx_spec.dart`, and `daw_screen.dart`'s single
  `_clipEffectTypes` list feeds **all four scopes** — `_trackFxEditor`,
  `_masterFxEditor`, `_busEditor` and `_openClipInspector` — plus the marked-range
  FX action. So the voice-shaping DSP already processes any clip, track, bus,
  master or segment, which was the ask.

- ✅ **Controls must be scannable — DONE (verified 2026-07-26).** The BPM control
  is a slider (`loop_mixer_screen.dart` ~3685, `kMinTempoBpm`..`kMaxTempoBpm` →
  `_setTempo`) PLUS a numeric field (~3702, `onSubmitted` → `_setTempo`), so
  Chill/Groove/Fast is no longer the only tempo control. The style presets that
  remain are GROOVE styles, not tempo — which the bullet explicitly allows.

- ✅ **Notation is a view of the document — DONE (grand staff landed 2026-07-26).**
  It engraves every enabled track, follows the selection, and shares the
  transport. The missing piece was the clef: `clefForGrooveCells` returned ONE
  clef, so a track straddling middle C was forced onto a single staff and its far
  end vanished under ledger lines (the "hard-coded clef choices" the retirement
  map lists under Replace). `grooveStaffForCells` (`groove_notation.dart`) now
  returns `GrooveStaff.treble|bass|grand` from the range actually used, and
  `_buildScorePanel` renders `GrandStaffView` for the grand case — reusing the
  primitive the Tab Workshop already uses, not new notation code.
  The rule is "at least two notes clearly on EACH side of middle C" (a third of
  margin either way). A single low pickup or high grace note therefore does not
  split the staff. A span-based rule was tried and removed: >2 octaves fires on a
  treble line with one low pickup — exactly the incidental note the count guard
  exists to ignore — and it was redundant, since notes bunched at two extremes
  already give two clear notes per side. +20 tests (15 classifier boundaries,
  5 widget).

- ✅ **D1 — "Add a track" = roles AND empty (option C).** The ＋ offers the five
  authored roles (drums / bass / chords / melody / sparkle) *and* an "empty"
  entry, with the role list first so nothing is ever a blank page but the
  ceiling is uncapped. A role-add arrives with that role's authored patterns and
  variants and plays immediately; an empty-add arrives silent for the tune grid.
  **Rename matters only for empty tracks** ("Track 6" means nothing) — do it
  with the empty path, not before.
  Build on `duplicateTrack`/`removeExtraTrack` (`loop_engine.dart`), which
  already handle the extra-track roster, id allocation and settings cleanup.
  ⚠️ Copies/new tracks are NOT in `_trackColors` or `_trackLabel` — see the
  `_sourceIdOf` fallback; an empty track needs its own colour + name, not a
  suffix fallback. ⚠️ The track-card row is FULL (23px overflow); put any new
  control in the inspector.

- ✅ **D2 — pan automation gets a parameter SWITCH (option A).** One 16-cell
  strip per track with a Volume / Pan toggle above it, not two strips. The
  render path already exists (A3); this is the editor. Reuse
  `_cycleAutomationStep` with the param as an argument, and keep the
  "cycling back to neutral DROPS the lane" rule — it is what preserves the
  byte-identical guarantee.

- ✅ **D3 — build a PER-TRACK FILTER, then automate it.** Approved as real work.
  Today `_masterFilter` is global and `AutomationParam.filter` renders nothing.
  A biquad per track in the mix path; the payoff is the filter sweep (dull the
  bass while the hats stay bright, then open it across the loop). Do the filter
  FIRST, then wire `AutomationParam.filter` through the same envelope seam
  `mixStems` already takes.

- ✅ **D4 — the two orphaned tests are BACK (they needed no port).**
  `test/generator_shapes_test.dart` (238 lines) and
  `test/mod_effect_memory_test.dart` (218) were deleted by `8a2c2d52`. Recovered
  with `git show 8a2c2d52^:<path>` — and they compile and pass **unchanged**, so
  no owner call was needed after all. The note that said otherwise was written
  while A7's generator code was still reverted; `9adc7b9b` put it back. **The
  lesson worth keeping: "the test no longer compiles" can mean the CODE is
  missing, not that the API moved on** — check what the clobber took before
  concluding a test is stale, or you will edit a good test to match bad code.

- ✅ **WS-W1 — `Project`: one document, many track kinds.** `M` · **SHIPPED
  2026-07-28** (opus, loop-d1d4). `lib/core/project/project.dart` +
  `project_codec.dart`, 26 tests. **Everything below is the ORIGINAL card, kept
  because its warnings still apply to WS-W2/W5.** What shipped differs in three
  ways, each forced by the code rather than chosen:
  - The codec is a **REGISTRY**, not a switch over five types. Two kinds have no
    codec to name (`tab` has none at all — WS-L11; `audio` needs a PCM render
    callback a pure container should not hold), and a switch would have dragged
    every mode's types, two of them Flutter-bound, into the container.
    `registerProjectDocumentCodec` lets those register from their own side.
  - **"No codec registered" and "kind I have never heard of" are ONE path**,
    both preserved verbatim. `ProjectTrack.unreadable` holds the raw document
    and `unknownKind` the stored kind string, so an older build opening a newer
    file writes the track back byte-identical instead of deleting it on the
    second save. `Project.hasUnreadableTracks` lets a caller warn BEFORE saving.
  - `AppMode` moved to `core/interop/app_mode.dart` (re-exported, no call site
    changed) because its old home is Flutter-bound. **Purity is now asserted**,
    not assumed: a test fails if any of the three files gains a Flutter import.
  - **Goal.** One container the three surfaces can share, so "the tracker
    pattern in bar 9" and "the clip on the timeline" can be the same object.
  - **Depends.** Nothing. *Do this first.*
  - **Files.** New `lib/core/project/project.dart` (pure Dart, no Flutter) +
    `project_codec.dart`. Reads, does not modify: `core/audio/daw_timeline.dart`,
    `tracker_song.dart`, `loop_engine.dart`, `tab_document.dart`.
  - **Build.** `Project { List<ProjectTrack> tracks, TempoMap tempo, String name }`;
    `ProjectTrack { id, name, AppMode kind, Object document, mix }` where
    `document` is the mode's **existing** type, unchanged. Codec to/from JSON.
    ➕ The **Loop** document is now a trustworthy one to assert on: `GrooveSpec`
    carries per-track length, swing and automation lanes as of `3a018344`.
    Before that it silently dropped every lane, so "each document intact" would
    have passed while losing state.
    The precedent to follow is `.cbdaw v2`, which already stores a clip's model
    beside its audio — the same trick, one level up. Reuse `AppMode` from
    `core/interop/project_bridge.dart` rather than declaring a second enum.
  - **Acceptance.** A project holding one track of every kind round-trips
    through the codec with each document intact (assert on the documents, not on
    the JSON). An unknown `kind` in a stored file is preserved verbatim rather
    than dropped, so a newer project opened by an older build loses nothing.
  - ⚠️ **Do not** put mix state inside the mode documents — it belongs to
    `ProjectTrack`, or WS-W5 will have to unpick it from four places.
  - 🔴 **Found while building (2026-07-28): `TabDocument` has NO codec, and
    Tab's only persistence is LOSSY** — `saveToSongBook` goes through MusicXML,
    which drops tuning, strings, frets and every technique, i.e. everything that
    makes a tab a tab. `TabColumn` has ~22 fields plus nested
    `crisp_notation_core` types, so a lossless codec is **its own task** (see
    WS-L11 below), not a sub-task of this one. WS-W1 therefore ships a codec
    REGISTRY: a kind with no registered codec is preserved verbatim, the same
    mechanism the unknown-kind rule already needs.
  - ⚠️ **The card contradicts itself on `AppMode`**: "reuse it from
    `project_bridge.dart`" + "pure Dart, no Flutter" cannot both hold, because
    that file imports the Flutter `crisp_notation`. Resolved by extracting the
    enum to `core/interop/app_mode.dart` and re-exporting it — additive, no call
    site changes.

- ✅ **WS-W1b — make `Project` REACHABLE.** `S` · **SHIPPED 2026-07-28**
  (opus, workstation-parity). `lib/core/services/project_service.dart`, 13 tests.
  **A card the ladder did not have, added because the audit found the same shape
  twice.** `WS-W1` built the container and **nothing in the app ever constructed
  one** — a grep for `Project(` outside `lib/core/project/` returned only the
  Audio Editor's unrelated `.cbdaw` save/load. Worse, `registerTabProjectCodec()`,
  whose own comment says *"call once at start-up"*, **was never called**, so a
  tab track would have been carried as `unreadable` despite a working codec
  existing. Both are fixed in `main.dart`: one provider, one registration call.
  - The seam `WS-X1` needs is `updateDocument(id, doc)` — swap a track's document
    while keeping its id, name and **mix**. A live link that reset the level and
    pan on return would be worse than the copy it replaces, so that is the
    assertion the test leads with.
  - ⚠️ `ProjectTrack.copyWith` resolves `document ?? this.document` and therefore
    **cannot clear a document**. The service builds the track directly for that
    reason; a test pins it so nobody "simplifies" it back into `copyWith`.
  - **The pattern worth generalising:** twice now a card has shipped complete,
    tested and unreachable (the shared count-in on the unused `advance` path;
    `Project` with no owner). **Before ticking any remaining card, grep for a
    caller.** Passing tests are not reachability.

- ✅ **WS-W5d — the shared bar and the shared undo get their first host.**
  `S` · **2026-07-28** (opus, workstation-parity). The mixer console hosts
  `TransportBar` and pushes a labelled `UndoEntry` for every mix change.
  - **Found by applying this ladder's own reachability rule to my own work.**
    `TransportBar` (`WS-W3`) had **no host** and `UndoService` (`WS-W4`) was
    provided in `main.dart` and **consumed by nothing** — `UndoEntry(` appeared
    only inside its own file. Two more complete-tested-and-inert artefacts, both
    mine, after I had flagged the pattern four times.
  - **Drags coalesce.** Level and pan push with a `coalesceKey` and end the run
    on `onChangeEnd`, so a fader drag is ONE undo rather than one per frame —
    the first real exercise of `UndoEntry.coalesceKey`, and without it Cmd-Z
    would nudge instead of undo.
  - The mixer passes `showRecord: false`: arming a record here would imply a
    capture path this screen does not have.

- ✅ **WS-W4 — one undo history. COMPLETE 2026-07-30 — ALL THREE surfaces**
  (Audio Editor · Loop Studio · Tracker). Service shipped 2026-07-28 (opus,
  workstation-parity); the Audio Editor and Loop Studio folded in 2026-07-29;
  **the Tracker's block history folded in 2026-07-30** (opus, daw-suite), taking
  the dispose trap and the private-service rule the card warned about rather
  than rediscovering them, with all 84 of that screen's tests passing
  unchanged. `lib/core/services/
  undo_service.dart`, 17 tests. **PHASE 1 IS NOW COMPLETE as services** — W1
  Project · W2 TransportService · W3 transport bar · W4 undo history all exist.
  What shipped, and what it deliberately does not do:
  - **It does not replace the snapshot mechanisms.** A surface keeps capturing
    exactly as it does today and hands over `(label, scope, undo, redo)`
    closures. Re-implementing capture/restore for four document types would be
    a rewrite wearing a refactor's clothes, and the card says to change only
    who owns the stack.
  - **Scope and order are both real, and not in conflict** — the card reads as
    if they were. The history is ONE ordered list so the Audio Editor can show
    what you just did in Loop Studio; `undo()` takes the most recent entry from
    any surface (what Cmd-Z means); `undoScope(id)` takes the most recent of one
    surface, so an undo cannot silently rewind another's unrelated work.
  - **Coalescing is first-class.** A 200-frame drag is one edit to a user and
    200 entries to a naive stack. The run keeps the FIRST entry's undo and the
    LAST entry's redo, which is what makes it reversible in one step. Different
    scopes never merge even on the same key.
  - `clearScope` exists for closing a surface: its closures capture state that
    is going away, and running them afterwards would restore into nothing.
  - ✅ **The acceptance IS discharged now, on the real screens** (2026-07-29,
    loop-d1d4). It is worded at the screen level — "an edit made in Loop Studio
    is undoable from the Audio Editor's history list" — and neither earlier
    author would tick it, correctly: @workstation-parity had no screen migrated
    and proved it headlessly with two adapters; @daw-suite had one, and one
    folded-in surface cannot demonstrate a boundary. With Loop Studio folded in
    there are two, so `loop_shared_undo_test`'s last four cases run a **real
    `DawService` and the real Loop Studio screen against one `UndoService`**: an
    edit made in Loop Studio appears in the shared history and is reversed by a
    `Cmd-Z` that knows nothing about Loop Studio; neither surface's own button
    reaches into the other; the redo branch holds the same line; and leaving
    Loop Studio leaves the Audio Editor's history fully usable.
    ✅ **AND THE LIST IS BUILT — the acceptance is met in full** (2026-07-29,
    loop-d1d4). `lib/shared/undo/undo_history_sheet.dart`, hosted by BOTH the
    Audio Editor (its width-aware `secondary` toolbar list) and Loop Studio (its
    overflow menu — that toolbar Row has five fixed icon buttons before its
    scrollable region and has overflowed twice, so a secondary action does not
    get to be the sixth). Until this, `history` and `nextUndoLabel` had **no
    viewer at all**: both fold-ins produced careful labels — the DAW's free from
    its coalesce token, Loop's derived by diffing snapshots — and nobody could
    read a single one. **An output with no reader is this ladder's recurring
    defect one level up from the usual unused method, and much harder to see,
    because every test passes and the data is genuinely correct.**
    * **Tapping a row reverts to it**, which was a product call and is written
      down as one. A history you cannot navigate is a log. Crossing another
      surface's entries is *unavoidable* rather than chosen — one ordered list,
      and an entry's closure assumes everything after it is already undone — and
      it is safe because it is itself reversible. So no confirm dialog; instead
      each row states how many edits its tap takes back, and every row names its
      surface.
    * **Scope names are a REGISTRY** (`registerUndoScopeName`), following
      `project_codec.dart`: a shared widget hard-coding every surface's scope
      would sit in `shared/` importing half the feature tree. Each surface
      registers on mount, which is always in time — a scope only has entries
      while its screen lives.
    * ⚠️ **The redo BRANCH is not listed, deliberately.** `UndoService` exposes
      `history` and `nextRedoLabel` but no accessor for the future queue, and
      adding one to a file two agents were folding into, for a nice-to-have, was
      not worth the collision. A labelled Redo action ("Redo Move clip") meets
      "the label says what it was" for the entry that matters. **This ship
      touches no shared file.** Tests: `undo_history_sheet_test` (17), both
      hosts driven through their real UI rather than by calling the function —
      a sheet nobody can open would be the same defect wearing the fix's
      clothes.
  - ✅ **Fold-in — the AUDIO EDITOR is done (opus, daw-suite).**
    `DawService({UndoService? history})`; omit it and the surface keeps a
    private one, so every existing caller behaves exactly as before. The
    snapshot MECHANISM is untouched, per this card — only the owner changed.
    * **The evidence is what did NOT change:** their 17 service tests and every
      existing DAW undo test pass **unchanged, none edited**. Editing one would
      have been the signal I changed behaviour rather than ownership.
    * `_coalesceToken` does map onto `coalesceKey`, as this card guessed — and
      the token already names the gesture, so **labels came free** (`('move',…)`
      → "Move clip") instead of editing 97 call sites, which is the churn this
      card warns against. Sites with no token still say "Edit".
    * ⚠️ **`UndoService` scoped UNDO but not redo**, so I added `canRedoScope` /
      `redoScope` (additive, mirrors `undoScope`). Without them the Audio
      Editor's redo button would replay another surface's edit — exactly what
      `undoScope` prevents, in the other direction.
    * `loadProject` calls `clearScope`, not `clear`: its closures capture state
      that is going away, but another surface's entries are still good.
    Tests: `daw_shared_undo_test` (10).
  - ✅ **Fold-in — LOOP STUDIO is done (opus, loop-d1d4).** `loop_mixer_screen`
    no longer owns a stack; capture and restore are unchanged (`_engine.spec` →
    `_applyHistory`), and the evidence is again what did NOT change — **all 105
    existing `loop_mixer_test` cases pass unedited.**
    * **Labels are DERIVED, not set per call site** (`groove_change_label.dart`,
      new). Every Loop edit funnels through ONE hook that knows the groove
      changed but not what changed — which is why one hook could cover them all.
      The label is diffed out of the two snapshots' canonical `toJson()`, the
      same view `cacheKey` already uses to decide there was anything to record.
      Setting a label at ~20 sites would be this ladder's recurring inert seam:
      the site that forgets does not fail, it files its edit under the wrong
      name. A new `GrooveSpec` field falls through to a generic label — missing,
      never wrong. (The DAW got labels free from `_coalesceToken`; Loop had no
      equivalent token, hence the diff.)
    * ⚠️ **THE TRAP THE DAW DOES NOT HAVE, and the tracker WILL.** Loop Studio
      is a GAME SCREEN — pushed and popped — while the service outlives it, and
      every entry closes over the `State`. An undo pressed elsewhere afterwards
      would `setState` on a dead screen. `clearScope` in `dispose` (what this
      card provides it for) plus a `mounted` guard in the restore path.
      **Anything the games registry mounts inherits this.**
    * ⚠️ **`redoScope` was written TWICE, independently, within the hour** — by
      daw-suite (above) and by loop-d1d4, same semantics, from opposite ends of
      the service. Theirs landed first and mine was deleted in favour of it. Two
      agents on adjacent cards converge on the same gap even when both announce
      it on the board first; announcing it is still what kept the collision to a
      comment-level conflict.
    * A screen with NO service in scope keeps a private `UndoService` rather
      than not recording: the registry and most of this screen's own tests mount
      it bare, and undo has worked there since it shipped. One code path either
      way. Tests: `loop_shared_undo_test` (24).
  - ✅ **Fold-in COMPLETE — the tracker screen's block history, 2026-07-30**
    (opus, daw-suite). All three surfaces are in. It did inherit Loop Studio's
    dispose trap rather than the DAW's clean case, exactly as this card
    predicted: `clearScope` in `dispose` plus `mounted` guards, pinned by a test
    that tears the screen down and asserts the scope is empty. Labels are coarse
    on purpose ("Pattern edit"/"Recorded notes") — naming them at ~30 sites is
    the inert-seam shape, where the site that forgets files its edit under the
    wrong name. All 84 of that screen's existing tests pass unchanged.
  - ⚠️ **This card's own premise mislabels the third stack, and whoever takes it
    should decide rather than assume.** The header says "three surfaces, three
    private stacks: `DawService` … `LoopStack` holds loop state … the tracker".
    But `loop_record.dart`'s `LoopStack<T>` is **not an edit history** — it is a
    live looper's ORDERED OVERDUB LAYER STACK with per-layer mute, where `undo`
    means "drop the take I just recorded", a performance action taken while
    playing. Loop Studio's edit history was a different structure entirely
    (`GrooveSpec` snapshots in `loop_mixer_screen`), and that is what was folded
    in. Folding the take stack into a shared *edit* history is a real question,
    not a chore: it would put "remove my last overdub" in the same list as
    "changed the tempo", and a `Cmd-Z` from another surface would silently
    delete a recording. **My read is that it should stay out**, but it is the
    next agent's call and it should be made deliberately. `maxEntries` defaults to 50 to match `DawService._maxUndo`, so that
    fold-in changes nothing a user can observe.
  - **Goal.** One labelled, cross-surface history instead of three private
    stacks.
  - **Depends.** WS-W1.
  - **Files.** New `lib/core/services/undo_service.dart`. Existing stacks to
    fold in: `daw_service.dart` (`_undo`/`_redo`/`_Snapshot`, `_maxUndo`),
    `loop_record.dart` (`LoopStack`), and the tracker screen's block clipboard
    history.
  - **Build.** Entries carry `(trackId?, label, undo, redo)`. Keep the existing
    snapshot **mechanism** — it is proven — and change only who owns the stack.
    Scope by track so an undo in one surface cannot silently rewind another's
    unrelated edit.
  - **Acceptance.** An edit made in Loop Studio is undoable from the Audio
    Editor's history list **and the label says what it was**. Existing
    per-surface undo tests stay green unchanged.

- ✅ **WS-T3 — the keymap is shared, hosted and rebindable — SHIPPED.**
  `lib/shared/keymap/` = `intents.dart` (the verb) · `keymap.dart` (which chord
  means it) · `keymap_service.dart` (the live one, persisted) ·
  `keymap_sheet.dart` (the reference). Hosted by the **Tracker**, the **Audio
  Editor** and **Loop Studio**, each declaring the subset it handles.
  * ⚠️ **this card's acceptance was written against a regression suite that did
    not exist.** "The tracker's existing keyboard behaviour is unchanged (its
    tests are the regression suite)" — `LogicalKeyboardKey` and `KeyDownEvent`
    appeared ZERO times across every tracker test, including the screen's own
    78. So step one was to WRITE it
    (`tracker_keymap_characterization_test`, 13), and only then extract. It
    passes unchanged across the extraction, as do the tracker's own 112.
  * ⚠️ **two harness traps, both of which make a keyboard test lie.**
    `pumpAndSettle` never completes on the tracker (continuous ticker); and a
    screen's `autofocus: true` does NOT win against the route's focus scope in
    the test binding, so **every key press is silently swallowed and the suite
    passes vacuously**. Claim the node directly. The DAW and Loop `Focus`
    widgets now carry explicit, disposed `FocusNode`s for the same reason.
  * **Loop Studio had no keyboard at all** — not even space-to-play. It has one
    now purely by hosting the table, which is the clearest evidence the
    extraction bought something rather than moving code.
  * what stayed in each screen is the DISPATCH and the ORDER of the checks,
    which is itself behaviour: block ops resolve before note entry, or Ctrl+C
    types a C.
  * **only the DIFFERENCE from the defaults is stored**, including defaults the
    user removed. Storing the whole table would freeze today's bindings on their
    device, so a later release that improves one would never reach anyone who
    had opened the sheet. `fromJson` never throws — a keymap that will not load
    would lock someone out of their own keyboard.
  * the sheet lists only intents the CURRENT surface handles, and every chord
    bound to each (Delete and Backspace both delete; showing one teaches half
    the truth).
  Tests: `keymap_test` (18) · `keymap_hosting_test` (12) ·
  `tracker_keymap_characterization_test` (13).
  **This unblocks WS-A3 and WS-L1**, which are now about which intents those
  surfaces choose to handle, not about plumbing.

- ✅ **WS-L1 — keyboard support in Loop Studio.** `S` · **SHIPPED 2026-07-28**
  (opus, loop-d1d4) — a cursor on the lane strip, 12 tests. Depended WS-T3.
  Space = play/stop, arrows = move the cell cursor, digits = velocity,
  Cmd/Ctrl+D = duplicate, Cmd/Ctrl+Z = undo. Acceptance: a widget test drives
  the grid entirely from the keyboard.
  ⚠️ **Sizing note from @daw-suite (I claimed this an hour before you and am
  standing down — it is yours).** Two things worth knowing before you start:
  * **The transport half is already done.** Space/Stop/undo/redo landed with
    WS-T3; this screen had NO keyboard at all before that, and got one purely
    by hosting the shared table. Covered by `keymap_hosting_test`. What is
    left is only the grid half.
  * **The grid half is not `S`.** `cursor` matches ZERO times in
    `loop_mixer_screen.dart` — the step grids are tap-only, so "arrows move
    the cell cursor" means introducing a cursor concept (selection state,
    painting it, threading it through the shared `StepGridView`) plus
    per-cell velocity, which is its own model question. Re-size before you
    commit to it; the acceptance is right, the `S` is not.
  * New intents go on the END of `AppIntent` — the names are persisted in
    user rebindings. `duplicate` is already there and bound to Ctrl+D.
  - ⚠️ **Half of this card was already shipped by the thing that unblocked it.**
    WS-T3 step three wired space, stop, undo and redo into `loop_mixer_screen`
    (96 lines). What was missing — and what the acceptance is actually about —
    was a CURSOR: Loop Studio had no notion of a selected cell at all.
  - ✅ **Built on the lane strip** (16 steps × N tracks), the one grid in this
    surface with per-step VALUES, so digits map to it directly. Arrows move in
    two dimensions and **clamp** rather than wrap (wrapping steps jumps from the
    end of a bar to its start, which reads as a mis-key). The cursor does not
    EXIST until a key asks for it, and a tap moves it to the tapped cell so the
    two ways in agree. Typing keeps the drop-when-neutral rule, so a second way
    in is not a way around the byte-identical guarantee.
  - ✅ **`Cmd/Ctrl+D = duplicate` DONE — and I was wrong about it.** I had
    recorded "there is no duplicate intent, so this is left out"; @daw-suite's
    stand-down note above corrected me, and they are right: `AppIntent.duplicate`
    has been at `intents.dart:87` bound to Ctrl+D all along. My grep was
    truncated and cut it off. It duplicates the track the cursor is on.

- ✅ **WS-A3 — keyboard support in the Audio Editor — SHIPPED.** Split at the
  playhead (Ctrl+S) · trim to the marked range (Ctrl+T) · nudge (`,` / `.`) ·
  marker jump (`[` / `]`) · mute and solo (M / S), all resolved through the
  shared keymap, so a rebinding made in the Tracker applies here.
  * **every one acts on the SELECTION and does nothing without one.** A
    timeline shortcut that guesses which clip you meant is worse than one that
    refuses: the guess is silent, and the arrangement is already wrong by the
    time you notice. Pinned per verb.
  * mute/solo are per-LANE, so a selection spanning two lanes is ambiguous and
    does nothing rather than picking one.
  * split walks the selection highest-index-first — splitting inserts a clip
    and would otherwise shift the indices of everything after it on that lane.
  * ⚠️ **plain M and S are NOTE KEYS in the Tracker** (classic QWERTY piano
    layout) — found by writing the test, not by reading. Binding them is safe
    only because the Tracker does not dispatch those intents, so an unhandled
    intent falls through to note entry. Recorded at the binding site and pinned
    by `tracker_keymap_characterization_test`; if the Tracker ever handles
    mute/solo, these two must move first.
  * new `DawTester.selectClip` — every keyboard verb here acts on the
    selection, so a test could not drive one without it.
  Tests: `daw_keyboard_test` (11).

- ✅ **WS-A1 — clip edge handles: trim and fade — SHIPPED.** Narrow strips at
  both clip edges drag to trim; the two top corners drag the fades. Honours
  `snapOn`; handles appear only on a clip wide enough to hold them (below that
  they would cover the clip they edit, and the inspector is still the way in).
  * **It needed a new verb, not a composition of the two existing ones.**
    `setClipTrim` + `moveClip` per frame alternates their coalescing tokens and
    pushes an undo snapshot on EVERY drag frame — the user then presses undo
    and watches the edge crawl back a pixel at a time. `trimClipEdge` does both
    under one token, and trimming the leading edge moves the start with it so
    the remaining audio stays anchored in the arrangement.
  * ⚠️ **a no-op must not cost an undo entry either.** The first cut coalesced
    before working out whether anything would change, so every frame a drag
    spends against a clamp — and a drag spends many — bought a snapshot. The
    delta is now computed first; the verb returns what actually landed so the
    caller can tell the edge has stopped.
  * `endCoalescedEdit()` ends the run so a SECOND drag is its own entry; without
    it two drags merge and one undo jumps further back than expected.
  * ⚠️ **the scroll warning in this card is real and I broke a different thing
    first:** wrapping the clip in a `Stack` to host the handles let the body
    collapse to zero height, and the waveform painter's clamp went min > max.
    `StackFit.expand` fixes it; a widget test now drags across the clip BODY and
    asserts the clip is neither moved nor trimmed, so the long-press-to-move /
    plain-drag-to-scroll split stays intact.
  Tests: `daw_edge_handles_test` (16, incl. a gesture test that drags the real
  handle and asserts bounds + a single undo entry — the card's acceptance).

- ✅ **WS-X1 — live links, not copies. COMPLETE 2026-07-30 — all five surfaces**
  (Tracker · Tab · Score · Loop Studio · Audio Editor).
  ⚠️ **The last one shipped because a "not possible" note had expired.** The
  card recorded, correctly at the time, that the Audio Editor could not hold a
  link because audio had no project codec. `WS-W1c` then added one — making the
  timeline the document — and nothing re-read the note. **A note that says
  something is impossible is the least re-read line in a plan; date them, and
  re-check them when the thing they depend on lands.**

- ✅ **WS-X2 — drag between surfaces. COMPLETE 2026-07-30** — the protocol plus
  **all FIVE** drop targets (Audio Editor · Loop Studio · Tracker · Tab
  Workshop · **Score Workshop**, added 2026-07-30 after an interop-matrix audit
  showed Score as the one surface that could neither receive music nor put its
  own on the shelf).
  ⚠️ **The protocol gained one rule after shipping, from probing rather than
  reading it: a CONTAINER also accepts what can BECOME what it holds.** A tab
  could not be dropped on the Audio Editor's timeline at all — it fell through
  to `convert(tab → audio)`, correctly unsupported since a bounce is one-way, so
  the one mode that could put nothing on the timeline was the one most likely to
  want to. The order of `acceptsDirectly` is now the caller's stated preference
  (score before tracker, because score keeps a tab's pitches and voicings), and
  a test flips the order to prove it is a promise rather than a coincidence.
  📌 **The lesson the four targets share:** every single one broke an invariant
  its own callers had always satisfied — a container that is not a mode, one
  `AppMode` carrying two document shapes, a grid-length assert, a row-count
  assert, and an unchecked string index that CRASHED. The protocol was right
  each time; what a protocol cannot carry is the target's own constraints, and
  only wiring a real surface finds them.
  * ✅ `core/interop/drag_payload.dart` — `MusicDragPayload (kind, document,
    label, trackId)`, `DropDecision`, `dropDecisionFor`, `dropSummary`. Pure
    Dart, no widgets, so the decision is testable without pumping a surface.
  * **one protocol, not a handler per pair, is arithmetic:** five modes is
    twenty ordered pairs, and twenty handlers is how nineteen end up subtly
    different. `ProjectBridge` already converts any pair and already reports
    the cost — this decides what should HAPPEN.
  * ⚠️ **a same-kind drop does not touch the bridge at all.** A round trip
    would introduce loss the drop never needed — the copy-instead-of-link bug
    WS-X1 fixed, in another shape. Pinned by identity, not equality.
  * **only a lossy drop asks for confirmation**, and a lossy decision must have
    a non-empty report (a dialog with nothing in it is a lie). Making people
    dismiss a dialog on every drop is how they learn to dismiss the one that
    mattered.
  * the conversion runs ONCE and is handed back: the report IS the conversion's
    output, so a preview cannot be free, and the commit must not run it again
    and risk a different answer.
  * ✅ **the first drop TARGET is wired: the Audio Editor's timeline.** A lane
    accepts a dragged document, shows what a release would do while the finger
    is down, confirms BEFORE committing when the conversion costs something,
    and does nothing at all if the user declines.
  * ⚠️ **wiring that first consumer exposed a real gap in the protocol, which
    the contract alone hid: not every drop target is a MODE.** The timeline is
    a CONTAINER — it holds `ScoreSource`/`TrackerSource`/`GrooveSource` clips
    as they are. Asking `ProjectBridge` to convert a score "to audio" answers
    *unsupported*, correctly (a bounce is one-way), and would have refused a
    drop the timeline handles natively. `acceptsDirectly` names the kinds a
    container holds; empty by default, so pure mode targets are unchanged. It
    is a whitelist, not a bypass — an unlisted kind is still refused.
  * ✅ **the third drop target is wired: the TRACKER** (2026-07-30, daw-suite).
    A drag onto the pattern grid shows what a release would do, warns when it
    costs something, and lands as ONE undoable edit.
    ⚠️ **It lands in the CURRENT PATTERN rather than replacing the song, and
    that is the opposite call to Loop Studio's — for a concrete reason.** The
    Tracker's replace path (`_replaceSong`) calls `_clearUndo()`, because a
    snapshot history cannot survive a change of channel/row shape; a replacing
    drop would therefore be unrecoverable. The dialog states the cost of the
    choice: a dropped song's other patterns stay behind.
    ⚠️ **`setChannelCells` asserts the row count** — the third invariant in this
    arc that only a foreign document could break. `tracker_pattern_fit.dart`
    (pure) cuts or pads to the target's shape and reports **notes** lost, not
    rows trimmed: a 32-row song using its first four rows loses nothing in a
    16-row pattern, and a warning people learn to dismiss is worse than none.
    ➕ Simpler than the Loop target in one way: everything converting into
    tracker yields a `TrackerSong`, so there is one document shape, not two.
  * ✅ **the second drop target is wired: LOOP STUDIO** (2026-07-29, loop-d1d4).
    A drag onto the mixer surface shows what a release would do, confirms when
    it costs something, and lands as one undoable edit.
    ⚠️ **"a few lines over this protocol" was wrong, and the reason is worth
    reading before wiring the remaining two.** The protocol is sound; what it
    does not carry is the target's own constraints, and each of the three below
    was found only by wiring a real surface — the same way `acceptsDirectly` was.
    1. **`kind` does NOT determine the document type.** `AppMode.loop` travels
       as a **`GrooveSpec`** when Loop Studio produced it and as a
       **`List<PatternCell>`** when the bridge converted INTO loop. Same-kind
       never consults the bridge, so `dropDecisionFor` answers *exact* for both
       and the hint reads "Moves here unchanged" either way. **A handler keyed
       on `payload.kind` hands a cell list to `applySpec` and loses it
       silently.** Switch on the document TYPE. Every mode that both produces
       and receives a document should be assumed to have this shape.
    2. **The target can lose something the REPORT cannot know about.** Loop
       Studio plays a two-bar grid; a longer melody has to be trimmed, and that
       happens *after* the conversion the bridge reported on. Landing the head
       and dropping the tail silently is exactly the lossy-drop-that-did-not-ask
       the protocol exists to prevent — so the trim is added to the same
       confirmation, and declining leaves the groove untouched.
    3. **A foreign document can violate an invariant every existing caller
       happened to satisfy.** `MelodicPattern.render` ASSERTS its cells fill the
       grid exactly. Nothing had ever handed it a melody from elsewhere — a
       capture is recorded against the grid — so the first drop crashed the
       render. Cells are now fitted (`takeSteps` + `tileCellsTo`). Also:
       `setUserTrack` creates the track but does not ENABLE it, which every
       other caller in that file pairs by hand; without it a dropped melody
       lands silent and looks like a failed drop.
    📌 Consistent with `openProjectTrack` refusing a converted document: that
    refusal was because *opening* hid the cost, and a drop does not hide it.
  * 🛑 **UPDATE 2026-07-30, AFTER ALL FOUR TARGETS EXIST: the count went 2 → 4
    and the number of drag SOURCES is still ZERO.** Re-measured on `origin/main`:
    `Draggable<MusicDragPayload>` appears 0 times in `lib/`. `10ed9a25` records
    the card as complete; the four targets are complete, the FEATURE is not,
    because nothing in the app can begin the gesture. **Do not wire a fifth.**
    The stop-flag below was written when there were two and did not travel — a
    note on a card is not a message to a person, and that is on me as much as
    anyone. What is needed is a SOURCE and a frame where source and target
    coexist (the WS-W6 browser as a docked panel, or a split view); the
    maintainer has meanwhile leaned to parking the whole gesture and keeping
    `OpenInMenu`. 📌 The targets were still worth building: each one exposed a
    real latent bug in its own surface, which is @tab's tally and is the honest
    win here.
  * 🛑 **STOP — DO NOT WIRE THE REMAINING TWO TARGETS YET. This whole card is
    structurally unreachable in the product, and I only found it after adding
    to it.** Measured 2026-07-30 (loop-d1d4):
    1. **`Draggable<MusicDragPayload>` appears ZERO times in `lib/`.** There is
       no drag SOURCE anywhere in the app. Both drop targets are wired to a
       gesture nothing can start.
    2. **No two music surfaces are ever on screen together.** Every
       `DawScreen()` / `LoopMixerScreen()` / `AdvancedTrackerScreen()` is a
       full-screen route push or an exclusive home-tab index. So even given a
       source, you could not drag from one surface to another — there is no
       frame in which both exist.
    ⇒ The protocol and both targets are correct code that **cannot fire**. This
    is the ladder's own recurring defect — shipped but never called — one level
    up: not an uncalled method, but an entire interaction with no way in. ⚠️ **I
    wired the second target the day before finding this, without checking there
    was a producer. Owning that plainly: the first target's author could not
    have seen it (they built the protocol AND its first consumer, which looks
    complete from inside), but I could have, and did not.**
    📌 **The capability is NOT missing — only this gesture is.** `OpenInMenu`
    already moves a document between surfaces and is hosted by **six** of them
    (Workshop, Drumkit, Loop Studio, Tracker, Tab Workshop, Audio Editor). So
    nothing a player can do today is blocked by any of this; X2 is an
    alternative UI for a solved problem.
    ⬜ **MAINTAINER DECISION before any more of this card is built** — how
    should music move between surfaces?
    **(a)** Make the WS-W6 browser a DOCKED panel (its card already anticipates
    this: "when the browser becomes a docked panel, this is what goes in the
    projects tab") and drag from the panel onto the surface behind it. This is
    the only option that makes the two existing targets live, and it works on
    tablet/desktop while being cramped on a phone.
    **(b)** A split view with two surfaces at once — heaviest, and a large
    change to navigation.
    **(c)** Keep `OpenInMenu` as the only route and treat the drag protocol as
    a dead end: delete the two targets, or leave them dormant behind (a).
    **My recommendation is (a) if drag is wanted at all, otherwise (c) —** and
    (c) is not a failure: the menus work, are discoverable, and already state
    the conversion's cost, which is the thing the drag protocol was written to
    preserve.
  Tests: `drag_payload_test` (17) · `loop_drop_target_test` (11).

- ✅ **WS-X3 — the shared FX rack in the LAST mode. SHIPPED 2026-07-29** (opus,
  daw-suite), route 1 as the maintainer chose. `lib/core/audio/score_fx.dart` +
  the rack in the Workshop's per-part menu + `bin/rendersong.dart`; the chain
  lives in `ScoreMetadata.extras` (crisp_notation `ee7dbc9`), which MusicXML
  carries per part in `<miscellaneous-field>`. 16 tests.
  ⚠️ **The card's premise did not hold, in two places** — the library neither
  read nor wrote `<miscellaneous-field>`, and `multiPartToMusicXml` discarded
  metadata outright, so the field alone would have been a no-op end to end. Both
  closed first; the card was an `S` only after that. Details, plus two measured
  caveats (CLI normalisation cancels a level-only chain; an effect tail is cut
  at the part's end, app-wide) and one hole left open (`midiProgram`/
  `isPercussion` never reach MusicXML at all), on the board in `docs/PLAN.md`.
  ⚠️ Also fixed there: a multi-part export was dropping its whole header.

- ✅ **WS-L5 — copy a PATTERN.** `S` · **SHIPPED 2026-07-28** (opus, loop-d1d4)
  — `copyPattern`/`copyTargetsFor` + a two-tap chip row, 21 tests.
  **Narrowed twice, then resolved.** The first
  pass said "`duplicateSection` shipped, so the section half is done;
  duplicating a scene or a single pattern still has no route." Re-audited
  2026-07-28 (loop-d1d4): **a section IS a `GrooveScene`** — `_scenes` is
  `List<GrooveScene?>` and the UI merely calls them sections — so
  `_duplicateSection` already IS scene duplication, deep-copying both the
  enabled set and the variant map. **Only the PATTERN half is open.**
  ⚠️ **It needs a product decision before it is pullable**, which is why it is
  no longer an `S`: a "pattern" here is either an authored **variant** (data,
  not editable per slot) or a `_cellOverrides`/`_drumOverrides` entry that
  REPLACES whichever variant is active. So "copy A to B, change one thing" has
  no B to copy *into* — either editable variant slots have to exist first, or
  the feature is really "copy this track's pattern onto that track".
  ⚠️ Deep-copy automation lanes; the aliasing trap already bit the track-copy.
  - ✅ **Resolved by taking the second reading:** the feature is "copy this
    track's pattern ONTO that track", which writes an override on the
    destination — no new model, no editable variant slots, no schema change.
    Pitched↔pitched and drums↔drums only; the meaningless pairings are not
    offered rather than offered-then-refused, and an audio track has no pattern
    in either direction.
  - ⚠️ **The aliasing trap, in its pattern form:** `setTrackCells` copies its
    list but `setTrackDrums` stores the `DrumRowsPattern` OBJECT, so a shallow
    copy leaves both tracks sharing one grid and editing either edits both.
    Rows and velocities are deep-copied; two tests pin it, because the bug is
    invisible until somebody edits.
  - ⚠️ **And the one that would have shipped a broken render:** the copy takes
    the AUTHORED 2-bar pattern, not `cellsFor`, which resolves to FOUR bars
    under a progression — writing that back as an override is a length the
    renderer asserts on.

- ✅ **WS-L11 — a lossless `TabDocument` codec.** `M` · **SHIPPED 2026-07-28**
  (opus, loop-d1d4) — `tab_document_codec.dart`, 16 tests. **NEW, found while
  building WS-W1 (2026-07-28).** Tab is the only mode with no way to save what
  it actually is: `saveToSongBook` converts to MusicXML, which drops the tuning,
  the strings, the frets and every technique. There is no `toJson`/`fromJson`
  for `TabDocument` anywhere. Until this exists, a tab cannot live in a
  `Project`, cannot be a DAW clip model (`daw_clip_source_codec` has no `tab`
  kind either), and cannot survive its own app restart.
  - **Files.** New codec file; READS `tab_document.dart`, does not modify it.
  - **Build.** ~22 `TabColumn` fields + `Tuning`/`TimeSignature`/`KeySignature`/
    `ChordDiagram`/`BendPoint` and the enums, all from `crisp_notation_core`.
  - **Acceptance.** A document using every field round-trips equal, asserted on
    the DOCUMENT not the JSON; an unknown enum name degrades that one field
    rather than failing the parse.
  - ⚠️ `tab_document.dart` is Flutter-bound (it imports `crisp_notation`), so
    this codec cannot live in a pure-Dart core file — register it into
    `project_codec`'s registry rather than hardcoding it there.
  - ✅ **Shipped as scoped**, plus one thing the card did not ask for and should
    have: the real failure mode for a save format is not "the codec is wrong",
    it is "`TabColumn` grew four fields and nobody told the codec". So the codec
    exports `tabColumnFieldKeys` and a test PARSES `TabColumn`'s constructor out
    of the source and diffs the two — **add a field without teaching the codec
    and the suite fails**, instead of saves quietly shrinking. Thirty fields
    round-trip today, asserted on one fully-populated column rather than thirty
    separate tests that would all pass while a thirty-first was dropped.
  - ⬜ **Still open, deliberately:** nothing CALLS `registerTabProjectCodec()`
    yet, because nothing loads a `Project` yet — that call belongs to whoever
    first wires Project into the app (WS-W6 / WS-X1). And
    `daw_clip_source_codec` still has no `tab` kind, so a tab still cannot be a
    DAW clip model; that is a ~10-line addition **in a hot file** (`daw_*` took
    19 commits in 30 hours), so it is left to that file's owner.

- ✅ **WS-L10 — audio tracks in the loop.** `M` · **SHIPPED 2026-07-28** (opus,
  loop-d1d4) — `AudioPattern` + `loop_audio_fit.dart` + an import chip, 33
  tests. Depended on WS-W1. A Loop Studio
  track is symbolic only today, so a recorded audio loop has nowhere to live
  except a bounce. After WS-W1 it is the **same** clip type the Audio Editor
  holds, so this is a track-kind admission plus tempo-matching, not a new
  model. ⚠️ Honour the sample-integrality invariant the whole engine rests on
  (tempos 75/100/120 keep eighth-steps integral in ms **and** samples) — an
  audio track whose length does not land on that grid must be resampled to it,
  not tiled past it, or the gapless seam clicks.
  - ✅ **How it landed.** `AudioPattern extends LoopPattern` — a pattern that IS
    the render rather than a description of one. That is the whole admission:
    `_renderMix` only ever asked a track for a `Float64List`, so level, pan, the
    D3 filter and every automation lane apply to audio with **no audio-specific
    mixing code**, and the tests assert exactly that.
  - ⚠️ **A trap worth passing on.** Audio is excluded from `GrooveSpec` (PCM
    cannot travel in a paste-able token) — and the render cache was keyed on
    `spec.cacheKey`, so the moment audio left the spec, changing an audio
    track's level served the STALE cached WAV back. Fixed by splitting
    `renderIdentity` (everything that decides the sound) from `spec` (everything
    that can be shared). **If you make anything else unserialisable, that
    getter is where it has to be accounted for.**
  - ⬜ **Left open:** the take is fitted to exactly ONE loop. A four-bar
    recording over a two-bar groove is therefore played at double speed rather
    than lengthening the loop — `audioStretchOf` reports it and the UI says so,
    but offering "make the loop longer instead" is the obvious next step.

- ✅ **WS-A5 — loudness metering as a VIEW — SHIPPED.** A **Loudness** button in
  the Audio Editor toolbar measures the mix (or the **marked range**, since "is
  the chorus louder than the verse" is the question people actually have) and
  reads it back. The judgement lives in a pure `core/audio/loudness_advice.dart`
  rather than in the widget, so it is testable: a meter that renders five
  numbers beautifully and reasons about them wrongly is worse than no meter,
  because it is trusted. It reports against a **target** (streaming −14 LUFS ·
  broadcast −23 · none), because a LUFS number means nothing without one —
  and *quieter than target is GOOD*, not a fault, which is the judgement most
  meters get backwards and the one that pushes people into squashing a mix for
  no gain. True peak over −1 dBTP and negative correlation are WARNINGS at any
  target: they are the two failures that break on the listener's device while
  looking clean on yours. Tests: `loudness_advice_test` (17, incl. a widget half
  — the door opens on real audio and reads it, and is disabled rather than
  opening onto "Silence").

- ✅ **WS-A7 — clip warp / follow the tempo map — SHIPPED.** `Clip.warp` +
  `Clip.nativeBpm`, an optional `TempoMap` on both render entry points (**null =
  the old behaviour, byte-identical**), a "Follow project tempo" toggle in the
  clip inspector.
  * **WSOLA, not a resampler.** Warp is a TIMING feature; resampling would have
    been half the code and would transpose the loop, which is a different (and
    wrong) feature. A test measures the pitch after warping.
  * **it refuses rather than guesses.** Warp with no stated native tempo leaves
    the audio alone, and so does an absurd factor (a 60 BPM loop declared at
    240 is a mis-stated tempo, not a request for a 4× stretch). An invented
    factor shifts the arrangement's timing invisibly, and the listener cannot
    tell that from a mistake they made themselves.
  * a clip spanning a tempo CHANGE gets one factor derived from the map's
    real-time span, so the change is smeared inside the clip but its **end lands
    exactly** — nothing after it drifts, which is the invariant that matters.
  * a RECORDING is the case warp exists for and cannot know its own tempo, so
    the toggle **asks**; a symbolic clip (drum/groove) already carries its grid
    and just toggles. Cancelling does nothing at all.
  * the **length calculation** warps too (computed, not stretched) — without it
    a clip that warped longer would simply be truncated.
  Tests: `daw_warp_test` (20, incl. windowed-vs-full byte-identity for a warped
  clip and a widget half for all three toggle paths).

- ✅ **WS-A9 — the last DSP tier — SHIPPED. The Audio Editor ladder is
  COMPLETE.** `StretchQuality{light, balanced, deep}` on `timeStretch`, a
  `quality` param on the `timeStretch` effect (so the GUI panel, `fxproc
  --list` and the chain string all got it with no per-effect code), and a
  per-clip `Clip.warpQuality` the WS-A7 warp honours.
  * ⚠️ **I scoped this wrong and the measurements corrected it.** The plan
    (and my own claim on the board) said this was a MATERIAL trade-off —
    "short frames keep drum hits sharp, long frames are smooth on held
    notes". **Only half of that is real.** The transient half did not
    reproduce: across 768/1024/2048 the crest factor of a stretched drum
    pattern is flat to within noise, and at a factor of 2 every setting
    doubles the hits identically (8 in, 15 out) — that is WSOLA repeating
    material, which frame length does not fix. The names and the tests follow
    what measurement supports, not what the plan predicted.
  * **What IS real, and is now the feature:** the correlation window sets a
    PITCH FLOOR. A window shorter than one period cannot find the right
    alignment, so the stretch locks onto a sub-harmonic — the note comes out
    at the wrong pitch, not merely rougher. Measured floors ≈ 85 / 67 / 39 Hz,
    each within ~25% of the analytic `sampleRate / overlap`.
  * ⚠️ **This exposed a pre-existing bug nobody had measured:** the hardcoded
    1024-sample window that every stretch used cannot hold a bass low E — a
    41.2 Hz note comes out at 26.7 Hz. Not a regression from this work; it has
    been there since WSOLA shipped, invisible because nothing measured pitch
    after stretching. Now pinned by a test, and `deep` is the fix.
  * `lowestReliableHz` is advertised to the user, so it is deliberately
    CONSERVATIVE — a first cut put `deep`'s claim exactly on its measured floor
    and it failed there.
  * ⚠️ **A choice label is also the CLI token** in a chain string, which is the
    whole point of sharing one text form. A first cut labelled these
    "Deep — bass (≥43 Hz)" and was unusable from the command line; the pitch
    guidance moved to the caption and the labels are single words.
  Tests: `stretch_quality_test` (12) + `daw_warp_test` (+3, incl. deep keeping
  a 55 Hz bass in tune through a warp where light does not).

- ✅ **WS-T1 — eased playhead follow — SHIPPED.** `followScrollOffset` (pure) +
  a follow toggle in the toolbar.
  * ⚠️ **two stale details in the card:** the sub-row field is `_rowPhase`, not
    `_playFrac` (which matches nothing in `lib/`); and only ONE of its "two
    jumpTo sites" is the follow — the other is cursor-into-view for keyboard
    nav, where jumping is *correct* and easing would lag behind key-repeat.
  * **the defect was not `jumpTo`.** `jumpTo` against a continuously-moving
    target is exactly right; `animateTo` per frame fights itself. The defect was
    that `_followPlayhead` only ran when the INTEGER row changed, so the view
    sat still for a row then lurched a row's height, while `_rowPhase` already
    knew where between rows the music was and nothing used it.
  * ⚠️ **a bigger bug found on the way: the SONG branch never called it at
    all.** Following worked when auditioning one pattern and silently did
    nothing when playing the actual song — the mode people listen in.
  * ⚠️ **`_followPlay` was hardcoded `true` and toggled NOWHERE** — there was no
    way to turn following off. That mattered less when the view moved once per
    row; now that it glides continuously, anyone editing while the song plays
    needs the switch, so the toolbar has one.
  Tests: `tracker_follow_test` (9) — **unit tests over the pure function, and
  the reason is worth inheriting.** My first version drove the widget and
  guarded on `maxScrollExtent <= 0`; on the shared 1400x2400 surface the grid
  never overflowed, so all three tests returned early and **passed while
  asserting nothing**. The version after that measured a per-frame delta, passed
  alone and flaked under `--concurrency` — it was measuring how much time the
  harness delivers per pump. The arithmetic is the interesting part and it is
  exact.

- ✅ **WS-T2 — pattern overview + drag-to-reorder — SHIPPED.** A "Song overview"
  sheet listing every order slot, and `reorderOrderSlot` behind a real drag.
  * the card's premise held, with a sharper edge than it stated: the strip is a
    `Wrap` of chips whose move buttons **SWAP with a neighbour**. That is the
    right verb for a nudge and the wrong one for "this chorus belongs at the
    end" — sixty presses at sixty slots, and each one displaces something. A
    drag is a remove-and-insert, so the slots between shift instead.
  * **the cursor follows the SLOT, not the index.** Keeping it on the same
    number would leave it pointing at whatever slid into that position, so the
    next edit lands somewhere the user did not look. Both crossing directions
    are pinned, and mutation-checked: collapsing the bookkeeping to
    `if (cursor == from) cursor = to` fails them.
  * ⚠️ `ReorderableListView.onReorder` is **deprecated** in favour of
    `onReorderItem`, which already accounts for the removed item — so the
    classic `to > from ? to - 1 : to` correction is not merely unnecessary
    there, it is an off-by-one. I wrote the old form first.
  Tests: `tracker_order_overview_test` (8).

- ✅ **WS-T4 — a piano-roll view of one channel — SHIPPED (read-only).**
  `tracker_piano_roll.dart`: `rollNotesFor` (pure) + a painted roll, opened from
  the tracker toolbar for the cursor's channel. Premise verified before
  building: `pianoRoll` really was 0 hits across `lib/`.
  * **a view beside the grid, not instead of it.** The grid is exact and
    unapproachable; the roll is legible and imprecise. They answer different
    questions, which is why both exist and why the roll is one CHANNEL — the
    grid is already the multi-channel view.
  * **where a note ENDS is the whole logic.** A tracker cell says a note starts
    and says nothing about when it stops, so a run ends at the next note (the
    channel is monophonic — a new note takes the voice), at a key-off, or at the
    pattern edge. That last is a stated simplification: a note held across a
    pattern boundary really does sound on, but this view shows one pattern and
    a note running off the edge with no end is less honest than stopping there.
  * the same pitch re-struck is **two** notes, not one long one — merging them
    would erase the rhythm, which is the thing the view exists to show.
  * an empty channel **says so** rather than drawing a blank grid, which reads
    as broken software.
  * ⛔ **read-only, deliberately.** A roll you could edit that silently
    disagreed with the grid would be worse than no roll; making them agree is
    its own piece of work and should be its own card.
  Tests: `tracker_piano_roll_test` (14) — arithmetic over the pure function,
  plus the two doors.

- ✅ **WS-T6 — pattern-level time signature — SHIPPED** (groove templates
  deliberately NOT, see below). `tracker_meter.dart`: one `TrackerMeter` the
  tracker grid AND the piano roll both read, and a "Beats and bars" picker.
  * ⚠️ **beats-per-bar was hardcoded to 4.** The grid drew its bar line at
    `row % (highlightEvery * 4)`, so a pattern in **3/4 was barred as common
    time** — a waltz drawn as 4/4. That is what the card's one line was really
    about.
  * ⚠️ **`_highlightEvery` was DEAD**: declared, read once as
    `_highlightEvery ?? stepsPerBeat`, **assigned nowhere in `lib/`**. The
    "configurable" row-highlight spacing had never been configurable — the same
    shape as `_followPlay` in WS-T1. It is a real, settable meter now.
  * ⚠️ **and one of the three was mine**: the WS-T4 roll hardcoded `% 4` / `% 16`
    and read no beat at all, so it disagreed with the grid for any pattern that
    is not 4 rows to the beat. Both views now share one value and cannot drift.
  * the load-bearing detail: **every bar row is also a beat row**, so a painter
    must test `isBar` FIRST — test the beat first and every bar draws as a beat
    and the meter reads as 4/4 whatever it is. Pinned as a property across all
    the offered meters.
  * **display only, and the sheet says so.** This changes where a line is drawn,
    not when a note sounds, which is why it lives screen-side rather than in
    `TrackerTiming` — putting it in the engine's timing model would imply the
    replayer cared, and it does not. (That also keeps it out of the replay
    lane's files.)
  * ⛔ **groove templates are NOT in this card.** They change WHEN notes play;
    everything above changes only how the grid is drawn. Conflating them is how
    a display change turns into a playback change nobody asked for. Still open.
  Tests: `tracker_meter_test` (12).

- ✅ **WS-T7 — record into a pattern from the transport. SHIPPED 2026-07-29**
  (opus, daw-suite). ⚠️ **Mostly already built when the card was pulled** —
  FT2 live record, the record button, the quantize chip and `quantizeRowToBeat`
  all existed in `advanced_tracker_screen.dart`. The delta that shipped:
  `PerformancePads` finally has a host (its first anywhere), so notes can be
  PLAYED in through `ManualMidiInput` — hardware MIDI (X5 3a) will land as a
  second producer with nothing else to change; record-arm reaches the shared
  transport and the count-in length comes from `countInBars`; and three defects
  are gone — a chord collapsed into one cell, live record was silent, and every
  recorded note cost a full-pattern undo snapshot against an 80-entry cap.
  New pure `lib/core/audio/pattern_record.dart`; 26 tests.
  ✅ **Note LENGTH followed the same day** (`b37536d8`): a release writes a
  key-off cell at the sounding row (`releaseRowFor`), so a staccato stab and a
  held pad are no longer identical; it never overwrites a cell that has a note
  in it.
  ⬜ **Still open:** the WAV re-render per note (needs `tracker_engine.dart`,
  another lane's file) · the swing-correct ms→row inverse · the transport
  arming the Tracker (today it is one-way) · a note held a whole lap or more
  records as one row.

- ✅ **D-RT — DECIDED by the maintainer 2026-07-29: build B, and keep C
  REACHABLE.** Not "B instead of C" — **B now, with C later as an optional USER
  SETTING**, so the architecture must not foreclose it.
  **What that constraint means concretely, because "keep it open" is otherwise a
  slogan:**
  1. **Put the preview behind a SEAM, not a special case.** B is one audio path
     today; C is a different implementation of the same idea. If B is bolted
     onto one surface, C is a rewrite. If B implements an interface, C is a
     second implementation of it.
  2. **Playback mode becomes a RUNTIME choice, not a build-time one.** A user
     setting means offline and real-time must coexist in one binary, so the
     render/transport boundary has to be an abstraction from the start —
     `TransportService` schedules, it does not render, which is already the
     right shape.
  3. **Do NOT fork the FX vocabulary.** B's "subset of FX" must stay `FxSpec`;
     a second vocabulary would force C to write a third.
  4. **The byte-identical guards stay — CONDITIONED, never deleted.** They are
     assertions about the OFFLINE path, and that path remains the default and
     the export path. A test that is removed because a second mode exists is a
     guarantee quietly dropped.
  Mixing and export stay offline and exact under B; C, if it ever ships, is an
  opt-in preview mode, not a replacement for the render.
  Original card and the three-option table: `docs/WORKSTATION_PARITY.md` §8.
  **Build after Phase 4.**

- ✅ **SHIPPED (`chord_spec.dart` + `chord_spec_parser.dart`). BB-D1 — the chord-symbol vocabulary and its parser.** `M`
  - **Goal.** One type that can represent any chord a chart needs, parse it from
    what a musician types, and print it back.
  - **Depends.** Nothing. *Do this first.*
  - **Files.** New `lib/core/harmony/chord_spec.dart` (pure Dart, no Flutter) +
    `chord_spec_parser.dart`. Reads, does not yet modify:
    `features/games/songs/import/chord_quality.dart` (the 18-quality table),
    crisp_notation `theory/chord_analysis.dart`, `model/element.dart:1542`.
  - **Build.** `ChordSpec { Pitch root, ChordCore core, Set<Extension>,
    Set<Alteration>, List<AddedTone>, Set<int> omitted, Pitch? bass }` →
    `pitchClasses`, `guideTones`, `voicingCandidates`. Parser accepts the ugly
    real-world set: `Cmaj7` `CM7` `C∆` `C-7` `Cmi7` `F#m7b5` `F♯m7♭5` `Cø`
    `Bb7alt` `A7#11/E` `C6/9` `Dsus` `G7sus4` `Ealt` `C/G` `N.C.` `%` (repeat
    previous) and the German `H`/`B` convention the app already honours
    elsewhere. Formatter is **convention-parameterised** (jazz `∆`/`ø` vs pop
    `maj7`/`m7b5`, `♭`/`♯` vs `b`/`#`) — a display choice, never stored.
  - **Acceptance.** A table-driven test of ≥150 real symbol strings → expected
    pitch-class set + expected canonical print. `parse(print(x)) == x` for every
    representable spec. **An unparseable symbol is preserved verbatim as text and
    voiced as its best-guess triad — it never fails to load a chart** (the
    existing `intervalsForSuffix` fallback ethos).
  - ⚠️ **Do not** extend `ChordSymbolKind` (crisp_notation `element.dart:1542`)
    to carry extensions. It is a 15-value MusicXML `<kind>` mapping and belongs to
    the *notation* layer; a chart needs a richer type that can *narrow* to it.
    BB-D3 owns that narrowing, with its loss report.

- ✅ **BB-D2 — the chart document. SHIPPED 2026-07-30** (opus, loop-d1d4;
  maintainer-authorised cross-lane pull, claimed before writing code).
  `lib/core/harmony/chart.dart` + `chart_codec.dart`, pure Dart, 17 tests.
  - **CHORDS ARE STORED AS SYMBOLS, and that is exact rather than merely tidy.**
    `ChordSpec` (BB-D1) documents the invariant it rests on — *"`parse(format(x))
    == x` holds even where `format(parse(s)) != s`"* — so a chart file says
    `"Cmaj7"` and not eleven fields, which matters because a chart is a file
    people open in a text editor. ⚠️ **Verified, not trusted:** the encoder
    re-parses every symbol it writes and falls back to a structural form for any
    chord that does not come back identical, and a 30-symbol corpus test asserts
    the fallback is never needed today. A construct D1's formatter could not
    express would otherwise be saved as a *different chord*.
  - **Unknown keys survive TWO round trips**, not one. One can pass by accident
    if `extra` is merely held in memory; open→save→open→save is the sequence that
    actually loses a newer build's form, so that is what the test does.
  - **Hostile input costs the smallest possible thing:** an unreadable chord
    symbol costs that chord, not the bar or the file; a garbage meter falls back
    to 4/4; `repeat: 0` plays once instead of vanishing; nonsense reads as "not a
    chart" rather than throwing at the call site.
  - ⬜ **ONE piece of the acceptance is DEFERRED, deliberately and measured:**
    *"`Chart` opens as a `ProjectTrack`"*. The registry is keyed by `AppMode` and
    there is no `AppMode.chart`. Adding one is not free — **3 files switch on
    `AppMode` (`advanced_tracker_screen`, `daw_screen`, `tab_workshop_screen`),
    none with a fallback case**, so a new value puts analyzer complaints in three
    other lanes' hot files, and whole-project `flutter analyze` is a CI gate. My
    claim promised not to touch hot shared files, so this wants its own
    coordinated card rather than a drive-by enum edit. Everything else the card
    asked for is done, and nothing in Phase 2 is blocked by it.
  Original card:

- ✅ **BB-A0 — drive the EXISTING groove engine from a `Chart`. SHIPPED
  2026-07-30** (opus, loop-d1d4). `lib/core/harmony/chart_to_groove.dart`, 17
  tests. A chart is audible through the shipped band before any of BB-A1–A6
  exists, exactly as the card intended.
  - **THE GUARD the card asked for, in its strongest cheap form:** feed the
    engine a progression this code BUILT from text and one the engine already
    ships, and the two renders are **byte-identical**. That makes the projection
    provably a re-description rather than a second arranger — stronger than
    "I did not edit the file".
  - **Two failure kinds, kept apart because they mean different things to a
    player.** *Approximated* — it plays without its colour (`Cmaj7` → `C`), which
    is what a beginner's band would play anyway. *Unrepresentable* — it cannot
    play, and is **not** bent onto something nearby, because a wrong chord in a
    backing track makes a player doubt their own reading of the chart. `Bb7` in C
    and any diminished/augmented triad are reported, never substituted.
  - ⚠️ **QUALITY IS MATCHED, NOT JUST THE ROOT — the trap in this card.** `Cm` in
    C major shares the tonic's root, so a root-only match would play it as a
    MAJOR `I`: a wrong chord that sounds confident. Pinned by a test.
  - ⚠️ **THE ENGINE HAS NO MINOR MODE, and anyone reading a report needs to know.**
    `ChordDegree` is a MAJOR-key set, so a minor chart projects through its
    RELATIVE MAJOR — which is how the engine already models minor
    (`GrooveScale.minorPentatonic` is "the relative-major set, +3 semitones").
    An A-minor chart therefore reports its tonic as **`vi`, not `i`**. The chords
    are right; the numerals are relative-major. Mapping onto the minor tonic
    instead would put a major triad on `Am`.
    📌 A test caught that the *message* still named the wrong key ("C minor" for
    an A-minor chart) because the shifted tonic was passed to the reporter as
    well as to the mapper. Reports get read; a report naming the wrong key is
    worse than no report.
  - **Answering the card's own question early:** reduction is useful enough to
    keep as a beginner fallback *when the chart is diatonic*, and useless outside
    that — a I–vi–IV–V chart plays exactly, while a chart of dominant sevenths
    yields nothing playable at all. So it is scaffolding for jazz and a real
    feature for pop. Decide at the end of Phase 2, as the card says.
  Original card:

- ✅ **SHIPPED (`comp_arranger.dart`). BB-A1 — the voicing arranger.** `L` — *split it: candidates, then path.*
  - **Goal.** Chord symbol → an actually playable voicing per instrument role,
    voice-led into the next chord.
  - **Depends.** BB-D1.
  - **Files.** New `lib/core/harmony/comp_arranger.dart`. **Read
    `lib/core/notation/bowed_arranger.dart` and the tab arranger first** — this
    is the same Sayegh/Viterbi optimum-path shape with a different state and a
    different cost, and it should be recognisably the same code.
  - **Build.** State = a candidate voicing (register-bounded pitch list). Cost =
    voice-leading distance + `checkVoiceLeading` violations (crisp_notation
    `theory/voice_leading.dart:80`) + register/spread/hand-span penalties + an
    avoid-note table (natural 11 over a major triad, ♭9 where unmarked…).
    Candidate generators per role: **piano** close/drop-2/shell/rootless-A-and-B,
    **guitar** from the bundled MIT chords-db grips
    (`composition/chord_db.dart` — real multi-position shapes, already loaded),
    **pad/horns** guide-tone lines.
  - **Acceptance.** Over a ii–V–I in all 12 keys the top voice moves by ≤2
    semitones per change and no parallel fifths/octaves are reported. A rootless
    voicing never doubles the bass's root in the same octave. Golden voicing sets
    for 20 named progressions, pinned.

- ✅ **SHIPPED (`style_spec.dart`). BB-A2 — the style model.** `M`
  - **Goal.** A style is *data*, so adding one is content work, not code work.
  - **Depends.** BB-D5.
  - **Files.** New `lib/core/harmony/style_spec.dart` + `style_library.dart`.
  - **Build.** `StyleSpec { id, feel, swingAmount, meters, tempoRange,
    Map<Role, RolePattern> }` per **intensity level** (0..3), where `Role` is
    drums · bass · comp1 · comp2 · pad · perc. A `RolePattern` is a cell list on
    the chart clock's subdivision, expressed *relative to the harmony*
    (attack points + which voicing slot + accent), never absolute pitches.
    Bass modes as an enum: root · root-5 · 2-feel · 4-feel walking · pedal ·
    arpeggiated · tumbao · alberti. Plus per-style default kit and default
    instrument per role, from the registry.
  - **Acceptance.** A validator rejects a malformed style (cells overrunning the
    bar, an intensity level missing a role, a meter the pattern can't fill) with
    the offending field named. The 3 existing `kGrooveStyles`
    (`loop_engine.dart:1598`) are expressible in the new model, proving it is a
    superset — **but leave them running on the old path** (rule 1).

- ✅ **SHIPPED (`bass_generator.dart`). BB-A3 — the bass line generator.** `M`
  - **Goal.** A bass line that walks *into* the next chord instead of restating
    this one.
  - **Depends.** BB-A2. **Files.** New `lib/core/harmony/bass_generator.dart`.
  - **Build.** Given (this chord, next chord, beats available, mode, register):
    chord-tone skeleton on strong beats, **approach note** into the next root
    (chromatic below/above, scalar, dominant-5th), 2-feel ↔ 4-feel by intensity,
    repeated-chord variation so eight bars of one chord are not eight identical
    bars, register continuity (no octave leaps between bars unless the range
    forces it), open-string/low-limit awareness per instrument.
  - **Acceptance.** Over a 12-bar blues and a 32-bar AABA: every bar-final note
    is a semitone, a whole tone or a fifth from the next bar's root; no note
    leaves the instrument's range; two consecutive identical bars occur only
    where the seed says so. Render → `dart run bin/listen.dart --wav` and assert
    the detected pitches match the generated line (the proven acceptance pattern).

- ✅ **SHIPPED (`drum_generator.dart`). BB-A4 — the drum generator.** `M`
  - **Goal.** A kit that plays the feel, marks the form, and fills into it.
  - **Depends.** BB-A2. **Files.** New `lib/core/harmony/drum_generator.dart`;
    `core/audio/synth.dart:412` (`enum Drum`) — **append only**.
  - **Build.** Groove per style × intensity; **fills** at 2/4/8-bar phrase ends
    and every section boundary; a count-in; an ending. Section intensity comes
    from the chart (`ChartSection.intensity`), so the last chorus lifts.
  - ⚠️ **Three real constraints, verified — record them, don't rediscover them:**
    (a) `enum Drum` has 12 values and is an **order-locked ordinal palette**
    (`interop/drum_tracker.dart` uses the ordinal *as* a MIDI note) — new voices
    (shaker, tambourine, congas, clave, timbale, sticks, brush snare, ride bell)
    must be **appended**. (b) The SFZ loader parses no `group`/`off_by`, so
    **there is no hi-hat choke** — an open hat is not cut by the closed hat that
    follows it; either accept it or shorten the open-hat sample per style.
    (c) `midi_render.dart` **sums every zone** covering a key+velocity, so a
    round-robin kit stacks into an N×-louder comb-filtered hit — emit exactly one
    region per (key, velocity) window. All three are in `CLAUDE.md` in full.
  - **Acceptance.** A fill lands in the last bar of every 8-bar phrase and nowhere
    else at a given seed. Rendered kit hits are within ±1 sample of the chart
    clock's grid. Byte-identical guard on the existing groove render path.

- ✅ **SHIPPED (`form_realizer.dart`). BB-A5 — form realisation.** `M`
  - **Goal.** Chart + repeats + form → the flat bar timeline everything renders
    from.
  - **Depends.** BB-D2, BB-A2. **Files.** New
    `lib/core/harmony/form_realizer.dart`.
  - **Build.** Expand `|: :|`, endings, `D.C.`/`D.S. al Coda`, chorus counts and
    a solo section into `List<RealizedBar { chords, meter, intensity, roleVariant,
    isFill, sectionLabel, choruseIndex }>`. Generate an intro (count-in · vamp on
    the first chord · turnaround into bar 1) and an ending (last-bar hold ·
    ritardando · button). **Vary each chorus** from the seed so eight passes are
    not eight identical passes.
  - **Acceptance.** A chart with two endings, a `D.S. al Coda` and `x4` realises
    to exactly the bar sequence a musician would play — a table-driven test with
    hand-written expected bar lists for six pathological forms. Same seed → same
    realisation, byte-identical.

- ✅ **SHIPPED (`humanize.dart`). BB-A6 — humanisation.** `S`
  - **Goal.** The difference between "a band" and "a sequencer".
  - **Depends.** BB-A5. **Files.** New `lib/core/harmony/humanize.dart`.
  - **Build.** Per-role micro-timing (a drummer's hat slightly early, a bassist
    slightly behind, a comp pushed), swing as a *continuous* ratio not a
    triplet-only switch, velocity shaping by metric position and phrase arc,
    per-note timing jitter bounded by role. All from one seed.
  - **Acceptance.** Offsets are bounded (no note moves more than a configured
    fraction of a subdivision), the seed reproduces exactly, and humanisation
    **off** renders byte-identically to the pre-card output.

- ✅ **SHIPPED (`style_library.dart`). BB-A7 — the starter style pack: SIX, done properly.** `M` — *content.*
  - ✅ **Decision 6: depth before breadth, and this card is `M` not `L`.** A
    shallow style is *immediately* audible as fake, and "does the band sound real"
    is the entire product. Six also keeps the BB-Q2 fingerprints meaningful.
  - **Goal.** Six feels that stand up to a musician, authored as data.
  - **Depends.** BB-A2..A6. **Files.** `assets/styles/*.json` + registry entry.
  - **Build.** **Swing · blues shuffle · rock 8ths · bossa · ballad · waltz.**
    Chosen because between them they exercise every mechanism Phase 2 must prove:
    4/4, 12/8 and 3/4; straight and swung; a latin clave feel; a two-feel and a
    four-feel bass; and a half-time intensity floor. Each with 4 intensity levels,
    fills, intro and ending, and default instruments.
  - **Then widen, as pure data behind the validator** — samba, funk, pop 16ths,
    country two-beat, reggae one-drop, gospel, folk strum, latin montuno, up-tempo
    swing, jazz ballad. No new code should be needed for any of them; if one *does*
    need code, BB-A2's model is short a mechanism and that is the finding.
  - **Acceptance.** Every style passes the BB-A2 validator, renders at the low,
    middle and high end of its tempo range without drift, and has a pinned audio
    fingerprint at a fixed seed (BB-Q2). A per-style provenance note stating the
    published-theory basis — clean-room rule 4.

- ✅ **SHIPPED (`chart_screen.dart` + `chart_grid_view.dart`). BB-U1 — the chart view.** `L`
  - **Goal.** Readable at a music stand, at arm's length, in a dim room.
  - **Depends.** BB-D2, BB-T2. **Files.** New
    `lib/features/harmony/chart_screen.dart` + `chart_grid_view.dart`.
  - **Build.** Bar grid (4 bars/line, 2 on a phone in portrait), section labels
    and colour bands, repeat/ending/coda marks, split bars, current-bar highlight
    + next-section preview, autoscroll that never scrolls during a bar, landscape
    and tablet layouts, a high-contrast stage theme, and **no accidental edits
    while playing**.
  - **Acceptance.** A headless layout audit at phone-portrait, phone-landscape and
    tablet with no overflow (`../testing_dart.md` methodology). Chord type stays
    above a stated minimum size at every breakpoint. Playhead tracks the transport
    in a widget test driven by `advance`.

- ✅ **SHIPPED (`chord_keypad.dart`). BB-U2 — chord entry fast enough to be used.** `M`
  - **Goal.** A 32-bar tune entered in a couple of minutes, or nobody enters one.
  - **Depends.** BB-U1. **Files.** New
    `lib/features/harmony/chord_keypad.dart`.
  - **Build.** Tap a bar → a root ring + quality grid + extension/alteration
    chips + slash-bass picker; hold a bar to split it; paste a text grid (BB-D4);
    drag-copy a bar or a whole section; long-press a section to repeat it; undo
    through the shared undo service. Recently-used chords surface first.
  - **Acceptance.** A scripted widget test enters a named 32-bar form in a bounded
    number of taps (assert the count — it is the actual product metric). Every
    quality BB-D1 can parse is reachable from the keypad in ≤3 taps.

- ✅ **BB-H1 — bass detection. SHIPPED 2026-07-30, but NOT as carded.** `S`
  - **Result:** the bass pitch class is now on `ChordReading.bassPc`. Measured
    (`tool/bass_detect_ab.dart`, 100 root-position chords + 84 inversions):
    **74% correct at the shipped 4096 window, 100% at 8192; inversions 82% / 87%.**
    All four collision cases resolve at *both* windows — `C6`→C, `Am7`→A,
    `Cm6`→C, `Am7♭5`→A. Chroma path **unchanged**: the template A/B still reads
    exactly 82.6% exact / 86.8% root.
  - ❌ **The card's own premise was WRONG and is refuted by measurement.** "A
    second chroma over the bass band" cannot work at any window we can afford: at
    44.1 kHz a 4096-point FFT has 10.77 Hz bins while a semitone spans 7.8 Hz at
    C3, 4.9 Hz at E2 and 3.3 Hz at A1 — **midi 28–40 all land in bins 4–8**, so
    folding the low band into 12 pitch classes measures leakage, not the bass.
  - **Three measured dead ends on the way, recorded so nobody retries them:**
    1. **Harmonic summation alone** → 29% correct / 71% unknown. Candidates a
       fourth or fifth away collect the real note's partials, so the scores
       cluster and everything reads as ambiguous.
    2. **+ a fundamental-presence test, taking the argmax** → 14% correct /
       **43% wrong**. The conceptual error: **the bass is the LOWEST note, not
       the loudest**, and an argmax finds the strongest note in the register.
    3. **Walking upward with a widened window** → 4% correct / 96% wrong. The
       ±2-bin widening lets a candidate steal the peak of the note a semitone
       above it, giving a systematic "reports the note just below" error.
  - ✅ **What actually worked: peak-picking with parabolic interpolation.** The
    insight is that the resolution limit applies to *separating* two close
    partials, not to *locating* an isolated one — and a bass fundamental has
    nothing within a semitone of it. Sub-bin interpolation over the peak and its
    two neighbours recovers its frequency far more precisely than the bin width,
    which is what makes this tractable at 4096 at all.
  - ⚠️ **`bassMaxMidi` is E4, deliberately above a "bass" register**: an
    inversion puts the lowest sounding note in the middle of the chord, and that
    note is still the bass for naming. Capping at G3 cost 60pp on inversions.
  - 📌 **Follow-on, unclaimed:** the default window stays **4096** — raising it to
    8192 takes bass detection to 100% but doubles latency to 186 ms, which is a
    call for whoever owns live grading (`BB-X5`), not one to make here. And now
    that the bass is available, **re-run the rejected template extension with
    bass disambiguation** — the 66 collisions that sank it are exactly what
    `bassPc` resolves.

- ✅ **BB-H4b — `ChordSmoother`: temporal smoothing. SHIPPED 2026-07-30.** `S`
  - **The largest measured win in the non-neural path, and nothing in the app did
    it before.** Measured on GuitarSet (real audio, 70 segments), against the
    performed annotation:

    | mode | exact | root |
    |---|---|---|
    | single window (was) | 12.9% | 57.1% |
    | `labelVote` | **24.3%** | 62.9% |
    | `medianChroma` | 21.4% | 68.6% |
    | `meanChroma` | 20.0% | **70.0%** |

  - ⚖️ **My hypothesis was half wrong and the split is the finding.** I expected
    chroma-domain smoothing to beat label voting outright because it keeps the
    continuous evidence. It wins decisively on **root** (+12.9pp over a single
    window) and LOSES on **exact** (20.0 vs 24.3). Explicable: averaging
    stabilises the overall pitch-class profile but blurs qualities that differ by
    a single note, so the muddier the chroma the harder maj7-vs-maj becomes. With
    the dense 17-template set `meanChroma` collapses to 11.4% exact for the same
    reason.
  - ⇒ **Pick the mode by what the caller needs, and the defaults differ by use
    case.** Live grading (`BB-X5`) wants **root** → `meanChroma`. Chart-from-audio
    (`BB-X2`) wants **exact** → `labelVote` with the fuller vocabulary. The class
    defaults to `medianChroma` as the balanced middle; neither extreme is right
    for both.
  - **Design.** Separate class, because `ChordDetector` documents itself as
    stateless per window and stays that way. `matchChroma` was extracted and made
    public so a smoothed chroma is ranked by **identical** ordering rules to an
    unsmoothed one — otherwise the two paths would disagree subtly. The bass
    votes rather than averages, being categorical. `reset()` exists because
    without it the previous take's chords bleed into the next one's first second.
  - ⚠️ Still n=70 on solo guitar. The direction is unambiguous; the exact
    percentages are not load-bearing.

- ✅ **BB-H7/step-zero — ANSWERED 2026-07-30. The neural path is dramatically
  better, so the licence IS the blocker and training a replacement is justified.**

  `docs/BTC_TRAINING_HANDOVER.md` §0.2 said step zero is a measurement, not a
  training run. Run, on the same 12 GuitarSet takes and the same MIREX-style
  majmin duration-weighted metric (`tool/btc_guitarset_eval.dart`):

  | path | majmin | root |
  |---|---|---|
  | chroma templates, best config (`BB-H0`) | 70.7% | 71.4% |
  | **BTC (neural, NC weights)** | **89.7%** | **95.8%** |
  | | **+19.0pp** | **+24.4pp** |

  - ⇒ **The gap is real, large, and measured on our own data.** 89.7% sits at the
    top of the published band (~83–85%), consistent with our set being
    favourable (solo guitar, close mic). Chroma is not merely behind — it is a
    different class of result.
  - ⇒ **This validates `BB-H7`.** We have a model that works and cannot ship it.
    The weeks of training work now have a measured prize rather than a hunch, and
    a replacement has two numbers to hit: **clear 70.7% to be worth shipping at
    all, approach 89.7% to be worth the effort.**
  - ⇒ **And it re-prices the licence decision.** Choosing "ship symbolic only"
    now means knowingly giving up a 19-point capability we have already built and
    measured. That is a much sharper trade than it looked before.
  - **Speed is not a blocker: RTF 0.20** — 289 s of audio in 58 s, ~5× real time
    on this laptop. Fine offline (`BB-X2`); a real-time path would need work but
    is not obviously out of reach.
  - ⚠️ **Caught a harness bug before believing a wrong answer.** The first run
    reported **majmin 4.5% against root 95.8%** — a gap that large between root
    and quality is a bug in the ruler, not a property of a model. Cause:
    `ChordEvent.quality` is literally `'maj'`/`'min'`, and I had reduced `''` to
    major, so every major chord scored zero. 4.5% was exactly the minor-chord
    fraction of the set. **The check that saved it was a plausibility check on the
    shape of the result, not on the code.**
  - **Licence posture, unchanged:** the weights are CC-BY-NC-SA-4.0, this was
    non-commercial evaluation scoped by `COMET_ACCEPT_LICENSES`, and nothing here
    makes the model shippable or weakens `model_license.dart`.
  - ⚠️ Same caveat as everything else on this set: 69 maj/min segments, 278 s,
    solo guitar.

- ✅ **BB-H10 — duration-weighted per-bar harmonic analysis. SHIPPED to
  crisp_notation `main` (`0b6e863`), worktree `../crisp_notation-harmony`.**
  - **What.** `analyze(score, weighting: HarmonicWeighting.durationWeightedPerBar)`
    reads ONE chord per bar from the bar's duration-weighted pitch content. That
    is the mode a lead sheet wants — one symbol per bar — so it is the primitive
    `BB-X1` needs to derive charts from the 46k-score corpus. `perSlice` stays the
    default and every existing caller sees identical output.
  - **Why.** `BB-H9` measured that WHICH NOTES the identifier sees matters far
    more than the identifier does — a 32-point spread from the selection rule
    alone — and `analyze()` was using the weakest shape.
  - 🔴 **The design detail worth keeping, because a test forced it.** The rule is
    a threshold **relative to the strongest tone**, not a fixed top-N. Top-N
    sounds equivalent and is not: on a held C-E-G decorated with three
    sixteenths, top-4 admits one arbitrary passing note, and `analyze`'s existing
    one-non-chord-tone recovery then discards a REAL chord tone to make the
    intruder fit — **the bar read as `C#dim`, having dropped its own root.** A
    relative threshold excludes decoration by construction; the search widens to
    every significant tone and then to the whole bar only if the confident set
    names nothing.
  - **Ties resolve by pitch class**, so the reading is deterministic rather than
    dependent on map iteration order.
  - Additive: new enum, two optional parameters, default unchanged. 6 new tests,
    **full core suite green at 2,022**.
  - ⚠️ **The app cannot see this yet.** `../crisp_notation` (the shared path-dep
    clone) is on `main` but **behind origin and carrying another agent's 16
    uncommitted changes**, so I did not pull it — that is their tree. The change
    lands app-side the moment someone pulls it.
  - ✅ **NOW MEASURED END TO END** (crisp_notation `a36643a`,
    `packages/crisp_notation_core/tool/guitarset_symbolic_eval.dart`), through
    `analyze()` itself rather than a standalone selection rule:

    | mode | named | root | majmin | full quality |
    |---|---|---|---|---|
    | `perSlice` (default) | 70.8% | 49.1% | 36.6% | 30.9% |
    | `durationWeightedPerBar` | **87.7%** | **78.7%** | **66.7%** | **63.9%** |

    **+30.2pp majmin**, and within **0.2pp** of `BB-H9`'s standalone prediction
    (66.5 → 66.7) — so `analyze`'s wrapper (slicing, NCT recovery, merging, key
    context) costs nothing and the gain survives the real code path. Root gains a
    similar margin; full quality doubles.
  - 📊 **In context: symbolic now beats the audio chroma path on its own ground.**
    78.7% root from notes vs 70.5% from audio chroma — though still short of the
    neural audio model's 95.8%. For `BB-X1`, where the input is a real score
    rather than pitch-tracked guitar, this is a **lower bound**.
  - Bonus: the commit also corrected pre-existing `dart format` drift in
    `analysis_test.dart`, which CI enforces (`--set-exit-if-changed` on
    `packages/*/test`).

- ✅ **BB-X1c — HARVEST RESULT + a source assessment (2026-07-30).**

  **The `.mxl` harvest, by source** (271 unique files carrying `<harmony>`;
  staging-dir duplicates excluded):

  | source | charts from the file's OWN symbols | bars named | files ≥70% |
  |---|---|---|---|
  | **OpenEWLD** (MIT) | **103 of 103** | **74.9%** | **71** |
  | PDMX | 57 of 79 | 45.6% | 34 |
  | CPDL | 11 of 85 | 7.8% | 4 |

  - ⇒ **OpenEWLD is the gold: real lead sheets, MIT, 100% carry chords.** PDMX is
    worth taking. **CPDL is not** — Renaissance polyphony with an occasional stray
    `<harmony>`, not lead sheets.
  - **Standing total of exact charts: ~375** — 238 Ebersberger (LilyPond) + ~137
    usable MusicXML.
  - ⚠️ **The OpenEWLD ceiling is RIGHTS, not availability.** The upstream dataset
    is thousands of lead sheets; we hold **103** because it was filtered to EU
    public domain. The rest is in-copyright popular song. There is no bigger clean
    slice to take.

  🆕 **NEW in-corpus source found while checking: `.mscz` carries `<Harmony>`.**
  **7 of 60 sampled (~12% → ≈300 of 2,555 files)** — where `.mscx` sampled **0 of
  200**, so the two have different provenance and must be measured separately.
  🔴 **And our MuseScore reader does not read `<Harmony>` at all**, so those ~300
  charts are invisible today. That is the same shape as the `\chordmode` fix and
  the obvious next card.

  ❌ **`.mid` chord-text check was INVALID** — the probe used `grep -qmE1`, which
  is not a flag, so every invocation errored and the "0 of 150" is meaningless.
  Unmeasured, not zero.

  **Assessment of externally-suggested tab/chord sources:**

  | source | verdict |
  |---|---|
  | `tombatossals/chords-db` (MIT) | ✅ **already shipped** — bundled in `assets/chords/`, read by `composition/chord_db.dart`. Chord *shapes*, not songs. |
  | **SynthTab** (CC BY-NC 4.0) | ❌ **NC → excluded**, and axis-2 dirty as well: synthesised from user-transcribed Guitar Pro files. Fails both axes. |
  | **Tabs-Lite** (Apache-2.0) | ❌ ⚠️ **The APP is Apache; the "million songs" are not.** It is a client for a third-party tab database. Same "wrapper is not the grant" pattern as the MIDI-rendered corpora — and that database is already on this repo's do-not-connect list. |
  | TuxGuitar (LGPL), alphaTab | 🔧 **tools, not content.** Genuinely useful as *oracles* for differential-testing our Guitar Pro import, the way OLGA is used for ASCII tab. No corpus value, and GPL/LGPL code must not be ported (clean-room rule). |
  | OpenSong, OpenChord (GPL-3.0), Chord-Provider | 🔧 apps; their songs are user-supplied. No corpus. |
  | ChordPro, MusicXML | ✅ already read. |
  | OpenTab, alphaTex | ➕ **import features we lack**, not sources. Cheap to add, zero content. |

  ⇒ **None of the suggested list adds Tier A/B corpus content.** The real remaining
  leads are the ~300 `.mscz` above and, for tab specifically, GuitarSet's 360 takes
  and IMSLP's 235 CC0 tab PDFs.

- ✅ **BB-X1d — ~500 EXACT CHARTS NOW READABLE. Running total (2026-07-30).**

  | source | format | files with exact charts | bars named |
  |---|---|---|---|
  | Ebersberger | `.ly` `\chordmode` | **238** | 37 of 40 sampled, 28 ≥90% |
  | OpenEWLD | `.mxl` `<harmony>` | **103** | 74.9% |
  | MuseScore corpus | `.mscz` `<Harmony>` | **122** of 132 | 64.7%, 43 ≥90% |
  | PDMX | `.mxl` | ~34 usable | 45.6% |
  | | | **≈497** | |

  All three readers shipped today (crisp_notation `0aaaf43`, `82150b9`,
  `5d02482`); before this, **every one of these was discarded at read time.**

  🔬 **The MuseScore 1.x chord ids were INFERRED FROM THE MUSIC, and the method
  generalises.** 1.x writes quality as an integer indexing a list we cannot
  resolve. Over 132 files, taking only bars with exactly one harmony so
  attribution is unambiguous, the interval the melody plays above each harmony's
  own root separates them cleanly:

  | ext | n | top intervals | reading |
  |---|---|---|---|
  | 1 | 1920 | 1 · 5 · **3** (25.4%), no ♭3 in top six | major |
  | 64 | 356 | 5 · 1 · **♭7** (17.4%) · 3 | dominant 7th |
  | 16 | 138 | 1 · 5 · **♭3** (23.2%), no major 3 in top six | minor |

  Corroborated twice independently: `joy-world.mscz` gives C and G under "Joy to
  the World"; and *Stille Nacht* now reads `| C | C | Dm | C | F | C | F | C |`,
  where the **Dm is a correct ii in C major and appears only because of the
  inferred mapping**. Values outside the table still emit nothing.
  ⚠️ It remains an INFERENCE — documented as such in the code and in a test, so
  anyone meeting real documentation replaces the table rather than extending it
  by pattern-matching.

  📌 **Display is already handled** — `layout_annotations.dart` places
  `score.chordSymbols`, so the app renders all ~497 the moment
  `../crisp_notation` is pulled. **That pull is the only thing standing between
  this work and the user seeing it.**

- ✅ **BB-X1g — INGESTED: 21 MIT Christmas carols. `db.json` 46,335 → 46,356
  (2026-07-31).** The first Tier A/B acquisition of this arc, and it is finished
  end to end rather than left staged.
  - **Path:** `bin/build_xmas_manifest.py` → `bin/append_manifest.py
    christmas-manifest.json "Christmas ChordPro"`. Backup taken first
    (`db.json.bak-xmas-*`); the tool is idempotent per source and **aborts on any
    dangling path**. Verified afterwards: 21 rows added, **0 pre-existing rows
    lost**, every path resolves, no id collision against the existing 46,335.
  - **Titles come from the `{title:}` directive, not the filename** — the
    transcriber wrote "The First Noel" where the file is `First-Noel.txt`, and
    `{subtitle:}` carries composer/lyricist for several ("Music by Lowell Mason,
    Words by Isaac Watts").
  - 🆕 **`chordpro` is a NEW format in `db.json`** — the census had gabc/midi/krn/
    mxl/mscx/abc/ly/… and no chordpro. The app already reads it
    (`songs/import/chordpro.dart` + `chord_sheet_screen.dart`), so it is playable,
    but anything that switches on format should be checked.
  - ✅ **The Tier B obligation is discharged.** `emit_catalog._tier` maps MIT to
    Tier A, but **MIT still requires its notice to travel with the files we
    redistribute** — so a `kMusicSourceCredits` entry was added and the credit
    reaches the user. Per the Dahlhoff precedent: an ingest is not finished when
    `db.json` is written.
  - 🛑 **NOT published to the HF catalog.** That is `bin/music_db_publish.py`'s
    gate and a separate decision.
  - ⚠️ Two candidates deliberately left behind, both correctly:
    `frescobaldi_fiori_musicali` (CC BY-NC-SA, **not** the CC0 it is often called)
    and `pathawks/Christmas-Songs` (no licence at all).

- ✅ **BB-X1e DONE — `HarmonicWeighting.auto`** (crisp_notation `f8030da`, suite
  **2,468**). Chooses per-slice vs per-bar from the music's **texture**:
  more than one sounding voice ⇒ a real vertical sonority exists ⇒ `perSlice`;
  a single line ⇒ harmony is only implied ⇒ per-bar pooling.
  - ❌ **A chord-rate heuristic was tried FIRST and failed — do not retry it.**
    Counting named segments per bar measures how often chord IDENTIFICATION
    succeeds, not how often harmony changes, and Bach scores *low* on it
    **because** his suspensions defeat the identifier: measured **0.63
    named-chords/bar for chorales against 0.11 for folk song**, so both fell the
    same side of any threshold and chorales would have been read per bar — the
    exact error the mode exists to prevent.
  - 🔴 **AND IT EXPOSED A DEEPER DEFECT, unclaimed:** `analyze()` takes a single
    `Score`, so a multi-staff work read through the single-score readers arrives
    with **its staves collapsed into voices** — a two-staff chorale comes back
    with soprano and alto interleaved in voice 1 (measured: bar 2 = 6 notes in
    voice 1, 4 in voice 2). Slices then mix parts into 6-note sonorities that
    identify as `Gmaj13/E`, `G6/9/D`. **Choosing `perSlice` there is correct and
    still yields nonsense, because the input was already wrong.**
    `multiPartScoreFromMscx` reads the 2 parts fine — what is missing is a
    `MultiPartScore` entry point for `analyze()`. **That is the next card, and
    until it exists, chart derivation from POLYPHONIC sources is not trustworthy.**

- ✅ **BB-H3 — deterministic ordering + bass tie-break. SHIPPED 2026-07-30, and
  it made the SHIPPED detector better.** `S`
  - **Measured, same grid as the rejection above:** the shipped 8 qualities go
    **82.6 → 86.1% exact and 86.8 → 90.3% root (+3.5pp each)**. A free win — the
    tie-break costs nothing and improves the path we already ship.
  - **Two parts.** (a) A fully deterministic comparator: score, then FEWER TONES
    (a documented prior, and also how the cosine already behaves on
    subset/superset), then root, then name — because `List.sort` is not stable
    and any exact tie otherwise makes the reported name arbitrary between runs.
    (b) The bass then breaks a *near*-tie, which is real evidence rather than a
    prior. Applied only within `bassTieEpsilon` — **never as a general
    preference**, because a first-inversion C major has E in the bass and is
    still a C chord. A test pins exactly that.
  - 📊 **And it re-opened the rejected extension — but not far enough to ship.**
    Re-measured with bass disambiguation: the full 17-quality set improves from
    **63.5 → 75.3% exact** yet still regresses the shipped 8 by **−10.8pp**. A
    targeted "+4 four-note only" set (`m7b5 dim7 6 m6`, no five-note ninths)
    lands at **81.9% exact / 86.5% root — −4.2pp** while covering 12 qualities.
  - ⚖️ **Neither is adopted, and the reason is that the synthetic grid cannot
    settle it.** The −4.2pp is measured on a vocabulary that EXCLUDES the very
    chords the extension exists to catch: today a half-diminished or a diminished
    seventh is confidently named as something else entirely, so the 86.1%
    baseline flatters the shipped set on any real jazz chart. **The decisive test
    is real audio** — GuitarSet (CC BY, chord-annotated, axis-2 clean, and
    already acquired in `jams-corpus/tierA`, parsed by our own `jams.dart`).
    That is the next measurement, and it is cheap because both harnesses exist.

- ✅ Standalone `ring_mod` → `crisp_dsp/ring_mod.dart` (`ringModFx`).

- ✅ Full `distortion` set → `crisp_dsp/distortion.dart` has `hardClip`/`softClip`/
  `fuzz`/`wavefold` (`DistortionKind`).

- ✅ sfxr FM/LFO → `crisp_dsp/sfxr.dart` carries `fmDepth`/`lfoDepth`/`lfoSpeed`.

- ✅ Cubic-Hermite interpolation → `resampleCubic` in `crisp_dsp/resample.dart`,
  used by `sound_library.dart` + `tracker_replayer.dart`.

- ✅ Multi-effect per-channel chain → `tracker_engine.dart` applies an ordered
  chain of inserts per stem; the DAW has clip/track/bus/master chains.

- ✅ Reverb/delay send on the Loop Mixer → `loop_engine.dart` `_applySend` /
  `_applySendStereo`.

- ✅ FFT-convolution reverb → `crisp_dsp/convolution_reverb.dart` (synthesized IR,
  FFT overlap-add) existed and was tested, **but was only reachable from the Voice
  Lab.** Now wired into the shared FX rack as `FxType.convolutionReverb`
  (appended; `.cbdaw` stores effects by name) with tail/decay/pre-delay/mix, so
  clips, tracks, buses and the master can use it alongside the algorithmic
  Freeverb. Tests assert it actually behaves like a reverb — decaying tail,
  pre-delay moves the onset, deterministic (fixed IR seed, so baked clips stay
  byte-identical), and audibly different from `FxType.reverb`.

- ✅ **DONE (verified 2026-07-26)** — pitch envelope on both voices:
  `pitchEnvSemitones`/`pitchEnvDecay` on `crisp_dsp/sfxr.dart`'s `SfxParams` AND
  on `synth.dart`'s additive voice (`238fa39e`). ⇒ **the whole Audio-FX block is
  now done.**

- ✅ **DONE (verified 2026-07-26)** — "starter-module generator" shipped as
  `starterBeatHits` in `lib/features/library/starter_pattern.dart` (pure, with
  `test/starter_pattern_test.dart`) plus the Tracker action wired in
  `advanced_tracker_screen.dart` (`case 'starterBeat'`).

- ✅ **DONE** P0.1 convolution reverb — `crisp_dsp/convolution_reverb.dart`
  (synthesized IR + FFT overlap-add) landed and is tested; as of 2026-07-26 it's
  also wired into the shared FX rack as `FxType.convolutionReverb`, where before
  it was reachable only from the Voice Lab.

### Shipped modes and the Songbook, moved out of the plan

#### Modes & games

#### 1. Tuner — DONE (real)
Chromatic/cello tuner: big note, cents needle, in-tune zone. Cello-first
(fretless intonation is where it matters). Keeper tile.

#### 2. Play-along (moving score) — DONE
Target notes are scored against your live pitch (correct pitch within a cents
window for enough of a note's duration = hit); `PlayAlongEngine` is pure-Dart
and unit-tested. **Four switchable scroll views** (a menu in the app bar):
highway (piano-roll), falling (vertical), notation (real engraved staff +
moving cursor, via crisp_notation), and coach (big current/next note for beginners).
Cello/guitar/keyboard charts + count-in metronome.

#### 3. Sing-along — DONE (v1)
The same engine + screen with a vocal-range melody preset. Voice is the same
monophonic detection; only the chart/labelling differs.

#### 4. Chord listener — DONE (spike)
Names the chord you strum/play with runner-up guesses + a chroma bar chart.

#### 5. Chord-progression play-along — DONE
A moving chord chart (C–G–Am–F): strum the progression as it scrolls; each
chord is scored by the fuzzy ChordDetector (`ChordProgressionEngine`, top-2
lenient match). Records to ProgressService + stars. Validated end-to-end via
the BlackHole loop — all four roots detected on real captured audio (the
7th/maj7 variants are expected overtone pickup, hence the lenient match).

#### Songbook — scan sheet music into playable songs (DONE — audited 2026-07-26)

> Audit against the code, because the PLANNED marker was badly out of date:
> ✅ **collection model** — `SongCollection` in `user_songs_service.dart` +
> `songbook_screen.dart` (named, ordered books; drag-reorder; remove-from-book
> without deleting the song). ✅ **persistence** — `UserSongsService.load/_save`
> over SharedPreferences. ✅ **OMR → notation bridge** — `songs/import/
> omr_import{,_io,_stub}.dart` + `import_screen.dart`, consuming CrispEmbed's
> GGUF engines as intended. ✅ **per-song metadata** — composer / key / tempo,
> derived from the stored MusicXML, persisted, shown in the book (2026-07-26).
> ✅ **source image retained** — `import/omr_source_store{,_io,_stub}.dart` keeps
> the photo in the same `~/.cache/crisp_notation` tree as the model cache, and
> `ImportedSong.hasSourceImage` records it (`4c86257b`).
> ✅ **re-run correction flow** — `_RescanButton` on the song row re-runs
> recognition on the retained scan and replaces the notation, so a bad read is
> fixed without re-photographing (`4c86257b`).
>
> ⇒ **This section is now complete.** Everything it scoped is built.
>
> ✅ Related sibling-repo bug, FIXED (crisp_notation `d8589c5`): the MusicXML
> reader took its tempo from `<metronome>` only and ignored `<sound tempo="…">`,
> so files from exporters that write just the playback attribute imported with no
> tempo. `<metronome>` stays authoritative (it is what the score PRINTS);
> `<sound tempo>` is the fallback. Our own writer already emitted both, which is
> exactly why round-trip tests never caught it.

Product feature, not a detector: let the user build **songbooks** from real sheet
music. Flow: import/scan a score photo → **Optical Music Recognition** → notation
→ store as a song the existing play-along/notation modes can drive → group songs
into named collections (browse / search / reorder / export).

- **OMR engine — reuse CrispEmbed, don't rebuild.** `CrispEmbed` already ships
  two validated OMR engines with Dart FFI bindings (`CrispEmbedOmr`): **SMT**
  (printed pianoform → bekern) and **Polyphonic-TrOMR** (printed/camera-robust →
  rhythm/pitch/lift → symbolic notation, `cstr/tromr-GGUF`). Auto-detected from
  the GGUF; a plain photo of a staff system works. So this app consumes those
  GGUFs via the FFI wrapper rather than porting any model here.
- **Scope TBD:** persistence format (song = source image + recognized notation +
  metadata), per-song metadata (title/composer/key/tempo), collection model,
  and an edit/re-run flow for correcting recognition mistakes before it becomes a
  chart. Bridge OMR notation → the app's internal note/chart representation that
  `PlayAlongEngine` / the `crisp_notation` notation view already consume.
- Flagged here so the OMR work in CrispEmbed and this app's songbook UI stay
  aligned; sequencing vs. the AEC/backing work is open.

### Agent-board entries

- ✅ **FIXED (was a shared CI blocker) — `test/layout_audit_test.dart` red overflow.** The `cello_finger_quiz` position selector overran 375px by 26px [en] after `6daeac99` (feat cello positions 1–4 added chips to a `Row`); I converted that Row → `Wrap` (label + 1–4 chips flow to a second line on a phone, centered on wide). Layout-audit green again → **CI gate unblocked for everyone**. Not my file (cello), but a red shared gate is worth a 1-line safe fix + this note. — opus Turning `bin/tts_render.dart` into a shipped feature: `tool/bake_narration.dart` (input JSON list of {text,lang} → `assets/narration/<lang>/<hash>.wav` + `manifest.json`), a pure-Dart `PrebakedNarration` runtime lookup (dep-free hash key; loads the manifest via `rootBundle`, resolves text+lang→asset — web-safe) + a `PrebakedNarrationBackend` that plays the baked WAV via a sink, and an ADDITIVE prebaked-first check in `TtsService.speak()` (falls through to the existing `_pick()` flow when nothing is baked → no behaviour change until assets exist). ⚠️ Touching shared `TtsService` (additive optional field only) + `pubspec.yaml` (an `assets/narration/` line). NOT committing baked WAV binaries — the bake is a maintainer/CI step (which strings + size budget is a product call); tests bake to a temp dir + inject fake loaders. — opus

- ✅ **DONE: replay-fidelity ladder X5 (flow/timing vs NodMOD) — @opus (daw-ux), 2026-07-27.** **The first CI-able piece of the replay audit** (everything else needs openmpt123/xmp/mod2wav and is opt-in): `test/mod_flow_timeline_test.dart` walks six order-list shapes × three formats against a frozen NodMOD oracle. **It found row onsets accumulating rounding without bound** — a row is `speed*2.5/bpm` seconds, whole ms only at convenient tempos, and we rounded EACH row then summed, so `tempo_change_Fxx` rendered 20.720 s against everyone else's 20.670 and 4000 rows at 160 BPM would drift a full second. It reached the AUDIO too (sample counts came off the rounded ms), so long modules rendered the wrong length with a playhead sliding against their own audio. One shared `rowOnsets()` now accumulates exactly. ⚠️ **Verify an oracle before trusting it:** NodMOD's S3M walker does not model `SBx` pattern loop (we are right, it is incomplete — pinning to it would have been a self-inflicted bug), and libopenmpt/libxmp disagree with EACH OTHER on FT2's XM loop counter. Both excluded by name with reasons. *(originally claimed before starting, per the X2-done-twice lesson)* Claiming it here BEFORE starting because X2 just got built twice in parallel by two agents off the same unclaimed ladder (see root `PLAN.md` §6). Touching: `tool/make_flow_fixtures.dart`, `test/fixtures/flow/`, a new `test/mod_flow_timeline_test.dart`, and READING `module_flow_timeline.dart` / `tracker_replayer.dart`'s `walkFlow`. If you want any of those, say so here first.

- ✅ **DONE: X3/X4 effect memory — @opus (daw-ux), 2026-07-27.** ProTracker's effect memory is **per-COMMAND**: `1xx`/`2xx`/`Axy` read the ROW's parameter (a bare `100`/`A00` does nothing) while `3xx`/`4xy` latch. We latched everything. **`mem_porta_up` 0.270 → 1.000, `mem_porta_down` 0.531 → 1.000** against three engines agreeing at 1.000; the control `mem_tone_porta` was already 1.000, which is what proved it was the RULE not the mechanism. ⚠️ **Design note worth inheriting:** threading a flag through the render helpers CASCADED — seven functions became thirty-five call sites and still growing, my automation mis-parsed and the count doubled each round until I reverted. The flag rides **`TrackerChannel`** instead, which every render path already receives, so it reaches all ten `ReplayVoice` sites with **no signature changes**. A cascade that grows under you is the design telling you it is wrong. CI-able test: `test/mod_effect_memory_test.dart` (asserts BOTH rules; `traceChannel` gained an optional flag).

- ✅ **X10 sample-playback layer (mostly) — @opus (daw-ux), 2026-07-27.** Five XM fixtures, one property each. **Loop arithmetic is SOUND** — forward wrap, ping-pong, a 32-frame loop inside a longer sample, and a one-shot that must stop all land on the references (0.999–1.000). **One bug: 16-bit loop UNITS.** XM stores length AND loop points in BYTES, so a 16-bit sample's frame counts are half the stored numbers; our reader halved the length but passed the loop points through verbatim, looping past the end of the buffer. ⚠️ **The writer had the matching bug**, so `parseXm(writeXm(x)) == x` held while the file meant something else to everyone else — caught by asking the references whether our 16-bit fixture and our byte-identical 8-bit one were the same music (**they said 0.21**; now 1.000). Ours 0.207 → 0.999. **This is the THIRD both-directions format bug this audit** (IT hex break row, XM loop units): `parse(write(x)) == x` cannot catch a misunderstanding the reader and writer SHARE. ⬜ Open: interpolation quality, stereo samples; and `oneshot_held` is a case where the references only agree at 0.960 with each other (fade vs hard stop past the end), so there is no single right answer.

- ✅ **X9 continued — S3M/IT fine portamento — @opus (daw-ux), 2026-07-27.** S3M/IT overload the porta parameter by RANGE (`0xFx` fine, once; `0xEx` extra-fine, quarter units; below `0xE0` per-tick). We passed the byte through as a normal slide, so `EF4` — four units ONCE — became 244 units EVERY tick. **`fine_porta_up_FFx.it` 0.131 → 1.000**, fine down 0.510 → 1.000, extra-fine 0.458 → 1.000. The replayer already had `E1x`/`E2x`, so it was routing, not a new mechanism; they were also missing from the REVERSE map, so fine porta was silently dropped on export. ⬜ **Two gaps remain, in `_kKnownOpenDefects` so they print every run:** IT plain porta (0.683/0.544 where S3M is 1.000 — probably IT's LINEAR frequency slides) and S3M fine porta (0.857/0.828 where IT is 1.000 — looks like a constant scale factor, since extra-fine has a quarter the step and a quarter the error). ⚠️ **My premise was wrong and measuring caught it:** the stale comment blamed VOLUME slides, which read 1.000 — but spectral similarity is amplitude-invariant, so **those 1.000s are not evidence of anything** and the volume fixtures need an ENVELOPE metric. ⚠️ I also re-made X1's fixture mistake (holding a slide 31 rows runs it off the period table so clamping dominates); bounding to 8 rows moved `porta_down_Exx.s3m` 0.982 → 1.000 with no code change.

- ✅ **The sweep has an ENVELOPE metric now — @opus (daw-ux), 2026-07-27.** Spectral similarity is amplitude-invariant, so every volume effect was ungated (it hid tremolo's 4× depth in X2). Envelope correlation on the same inter-reference baseline, gated only where the references agree AND the envelope actually moves (90/10 percentile ratio ≥1.6 — without that it false-reds on pure PITCH fixtures). Found three things: (1) ✅ **S3M/IT fine VOLUME slides misread** (`DFy`/`DxF` are once-per-row, we used MOD's per-tick `Axy`) — 0.63 → 0.98 envelope, and `EAx`/`EBx` were missing from the reverse map so they were dropped on export too; (2) ✅ **S3M/IT slide volume on EVERY tick** including tick 0 (libxmp `QUIRK_VSALL`), we skipped tick 0 for all formats — ⚠️ source-justified but NOT measurement-confirmed, because (3) masks it; (3) ⬜ **the VOLUME COLUMN does not set the channel volume** — a cell's volume becomes `noteVolume` (a 0..1 multiplier) while `Axy` slides the 0..64 channel volume, still at its default 64, so a slide UP from a quiet note starts already clamped. **Diagnosed by the asymmetry** (DOWN fixtures start at 64 = the default and pass; only UP fails — a rate error would hit both). **NOT fixed:** `TrackerCell.volume` is shared with the app's own authoring (Loop Mixer ghost notes use it as a multiplier), so this is a decision about the tracker's model, not a bug fix. In `_kKnownOpenDefects`, printing every run.

- ✅ **IT/XM linear frequency slides — @opus (daw-ux), 2026-07-27.** IT/XM bend pitch LINEARLY; MOD/S3M bend the Amiga PERIOD. We always slid the period. **`porta_*.it` 0.683/0.544 → 1.000/1.000**, with S3M staying at 1.000 — the diagnosis needed no source reading because the same command in both formats under each model is a **perfect mirror image**. IT's fine and extra-fine porta came along too (extra-fine envelope 0.19 → 0.93). ⚠️ **This means `PORTA_PERIOD` is the wrong SHAPE, not just off by a default** — the slide model is per-FORMAT and no global switch can be right for a library holding all four. `TrackerChannel.linearSlides` takes precedence for IT/XM and leaves MOD/S3M to the gate, so the pending MOD decision is untouched; when it is made the gate should probably become "MOD/S3M use period slides" outright. ⚠️ **The sweep's own reporting had two opposite bugs** — "now passing" checked only the spectral gap (telling me to retire exemptions whose envelope still failed), and a known-open entry failing only on envelope printed no flag at all. Both fixed; every row now names which metric failed.

- ✅ **`ReplayProfile`/`PitchDomain` + the slide model is a SETTING now — @opus (daw-ux), 2026-07-28.** Three per-format booleans became one profile per format; `PitchDomain` owns the sign convention that made the vibrato branches drift. **`PORTA_PERIOD` is DELETED** — it was wrong in shape, not just default: one global switch cannot serve MOD/XM/S3M/IT at once. **Every portamento fixture now reads 1.000 with no compile flag**, so the shipped default is the measurably correct one. Where a genuine preference remains (MOD/S3M hardware vs evenly-spaced) it is **`SettingsService.authenticSlides`**, on by default, de/en. It changes the pitch domain and NOTHING else, reaches MOD/S3M only (touching XM/IT would be breaking them, which is what the gate did), and is resolved at IMPORT into the song's profile — so the replayer holds no global state and module import stays a pure function for the CLI tools. `ReplayProfile.native` keeps app-authored songs out of it entirely, which was the actual blocker all along.

- ✅ **D1 SHIPPED** (`233ead40`): global volume now on the mono flow/variable paths + ALL stereo paths (shared _applyGlobalVolumeStereo + _flatRowScan helpers; null-gated → byte-identical without the command). Was: Shipped on
  `replayPattern` + uniform mono `replaySong`; still missing on `_replayFlow`
  (mono flow), `_replayVariable` (mono mid-song-tempo), and ALL stereo paths
  (`replayPatternStereo`, uniform `replaySongStereo`, `_replayFlowStereo`,
  `_replayVariableStereo`). Fix: build the row scan each path already has
  (`_rowScan` / a flat scan from `walkFlow`'s `played`) and multiply the
  `globalVolumeEnvelope` into `mix` (mono) or `left`+`right` (stereo).

- ✅ **D2 SHIPPED** (`233ead40`): _panRegionsVariable now handles Pxy (+ticksPerRow), so a variable-timing panned song slides too. Was: Shipped in
  `_panRegions` (uniform stereo); `_panRegionsVariable` still only reads 8xx.
  Fix: mirror the Pxy step into `_panRegionsVariable`.

- ✅ **D3 SHIPPED** (`f6633e4e`): the command-editor effect dropdown now offers Gxx/Hxy/Pxy/Txy; the in-grid effect column renders via radix-36 so extended commands show their letter code (G20/T02/PF0) and fit the 3-char column. Field-cursor hex stays 0–F. Was: Gxx/Hxy/Txx/Pxy (+ the already-
  engine-supported Exy sub-commands) have no tracker UI — the `_CommandEditor`
  only types a 0x0–0xF nibble. Needs an "extended effects" picker. Touches
  `advanced_tracker_screen.dart` (hot lane) — coordinate with @tracker-ui.

- ✅ **C12b — `EditorCaret` on `InteractiveMultiPartView`** (crisp_notation
  `afc283a`): the render paints a caret before its `beforeElementId` — the id
  locates the part, so it lands in the right staff. mus `_mpCaret` feeds the
  active part's caret (namespaced).

- ✅ **C12c — `ElementRegionController` on `InteractiveMultiPartView`**
  (`afc283a`): `RenderMultiPartView implements ElementRegionProvider`; a
  controller binds for marquee / cross-part region queries. mus binds `_regions`
  + shows the rubber-band overlay in multi-part mode (`_applyMpMarquee` selects
  within the most-covered part).

- ✅ **C12a — live drag preview** (no lib change needed): built app-side from the
  existing `suppressElementIds` (hide the dragged note) + placement ghost
  (`onElementDragUpdate` moves it under the pointer) — same visual as single-part
  `dragPreviewOpacity`. A dedicated multi-part `dragPreviewOpacity` (real-glyph
  translation) is an optional future nicety, not required.

- ✅ **C11b — multi-part MEI/kern/MuseScore writers** — **SHIPPED (un-deferred 2026-07-19, `opus (multipart-*)`).** The deferral premise (that it needs refactoring the oracle-hardened single-part writers, for low value + regression risk) turned out wrong: the app's export sheet + Workshop were **dropping all-but-the-first part** on MEI/kern/MuseScore export — a concrete data-loss — and each writer was added as a **NEW** function with the single-part path untouched (zero regression). Shipped: `multiPartToMei` (`crisp_notation@f613c9f`), `multiPartToMscx` (`ac68a08`), `multiPartToKern` (columnar N-way time-merge, `af10bcb`) + a `multiPartScoreFromMscx` reader (`516dcd2`); wired into `music_export.dart` + Workshop + fixed the online-library import. `multiPartToAbc` already exists app-side (`multi_part_export.dart`). **⇒ every multi-capable format keeps every part on import AND export.** LilyPond now keeps every part too (`multiPartToLilyPond` — a `\new StaffGroup` of one `\new Staff` per part, `crisp_notation@fb32573`; wired `4745d89`). **⇒ every multi-capable format keeps every part: MusicXML, MEI, MuseScore, kern, ABC, LilyPond, PDF.** **PDF now too** (`exportMultiPartToPdf`, `c729704`): mirrors the single-staff PDF but uses `layoutMultiPartPages` + `renderStaffSystemLayoutToPng` (BOTH already in crisp_notation — the renderer engraves all staves per system with connected systemic barlines), so a full score prints every instrument; zero library change, wired into the export sheet + Workshop. **Only Braille stays first-part** (genuinely complex/niche — no multi-part Braille writer). Bug-hunt aside: probed the theory/analysis engine (roman numerals, chord ID) and MIDI/robustness — all verified excellent + already comprehensively tested (roman numerals get secondary dominants, all dom7 inversions, ø7/°7, Neapolitan right); the one real find was the MIDI dotted-decoder fix above. **+ MIDI fidelity fix (`crisp_notation@9276dfb`):** a probe of MIDI round-trip (a heavily-used codec absent from the property suites) found dotted notes importing as tied splits (dotted quarter → quarter+eighth); the tick→value decoder now recognises dotted/double-dotted values directly. +4 regression tests. (Triplets through MIDI stay lossy — inherent to the format's lack of tuplets.)

- ✅ **Measure numbers in the editor** — crisp_notation `MultiSystemView` gained
  opt-in `showMeasureNumbers` (system-start numbering off `SystemLayout.
  firstMeasure`, paint-only, defaults off — ported from `png_export`'s
  convention; it previously existed only on `StaffView`). Wired a **"Bar
  numbers"** toggle in the Workshop ⋮ menu, wired to **all three** editor
  canvases — single-staff (`MultiSystemView`), grand-staff
  (`InteractiveGrandStaffView`) and multi-part (`InteractiveMultiPartView`) all
  gained the same opt-in system-start numbering. **Feature complete.**

- ✅ **Metric-aware beaming** — already automatic: the layout engine
  (`_computeBeamGroups`) derives beam windows from the meter during layout, so
  the editor needs no opt-in. Nothing to wire.

- ✅ **`showNoteNames` overlay** — shipped. crisp_notation gained a
  **`NoteNameStyle`** (letter / German-H / solfège) threaded through the layout
  engine's note-name overlay (was fixed English) + `showNoteNames` on
  `MultiSystemView`; the Workshop **"Note names"** ⋮ toggle overlays each note's
  name **on all three editor canvases** (single-staff, grand-staff, multi-part —
  the flags now forward through the grand-staff/multi-part layout paths too),
  **spelled per the app's note-naming setting** (germanH → H for B, solfège →
  do/re/mi, auto → locale). **Feature complete.**

- ✅ **Per-group barlines in the chrome** — shipped. `MultiPartDocument`
  `toggleBarlineBreakAfter`/`hasBarlineBreakAfter` recompute `barlineGroups`; a
  **"Break barline below"** item in each part's ⋮ menu breaks the systemic
  barline between instrument groups (crisp_notation already paints them). **All
  Workshop→crisp_notation parity items are now shipped.**


## Workstation ladder — the daw-suite lane, day three (2026-07-30)

**One-line status:** three long-running cards CLOSED — **WS-X1** (live links,
all five surfaces), **WS-X2** (drag between surfaces, all five targets) and
**WS-W4** (one undo history, all three fold-ins) — plus a measured optimisation
pass on the Tab Workshop and the last surfaces brought to interop parity.

**The pattern that produced most of it:** *check the card's premise before
building to it, and audit with a matrix rather than a list.*

- **WS-X3 (FX rack in Score)** shipped only after the premise failed twice —
  MusicXML `<miscellaneous-field>` was neither read nor written in the library,
  and `multiPartToMusicXml` discarded metadata outright, so the field the
  maintainer's chosen route asked for would have been a no-op end to end. Both
  closed first (crisp_notation `ee7dbc9`).
- **WS-T7 (record into a pattern)** turned out to be *mostly already built*;
  the real delta was that `PerformancePads` had no host anywhere, the transport
  drove nothing, and three defects made a jam unusable (a chord collapsed into
  one cell, live record was silent, every note cost a full-pattern undo
  snapshot).
- **WS-X1's last surface** shipped because a *"this is impossible"* note had
  expired: the same lane's later `WS-W1c` gave audio a project codec, making the
  timeline the document. **A note that says something is impossible is the least
  re-read line in a plan.**
- **Full interop parity** came from building a five-surface × four-axis matrix,
  which showed the Score Workshop could neither receive music from another mode
  nor put its own on the shelf — the mode built for writing music.

**Also shipped:** the FX-preset store + sheet (five racks could not keep a
chain); the clipboard hosted by three more editors; the transport driving two
surfaces; the shared bar hosted and its phone overflow fixed in the widget; a
live crash in `TabDocument` (a fret on a string the tuning lacks threw out of
`build`); and a Tab Workshop performance pass — FX-slider drags and the playhead
no longer rebuild the screen, the score is derived once per change, undo
snapshots share immutable columns, and the grid builds only the columns you can
see.

**Corrections I made against my own work, recorded because they are the useful
part:** a stale-cache bug my own revision counter missed (a cascade hides from
the obvious grep); an optimisation I *reverted* because I could not measure it,
and a benchmark verdict I had to retract after finding I had measured on a
contended CPU; a false pass another lane caught in my tracker tests (asserting a
count that a wrong write also satisfies); and a shared-tray field I added but
never looked up.

## Workstation ladder — the daw-suite lane (2026-07-28 … 07-29)

**One-line status:** after the Audio Editor's own ladder finished, this lane
worked the shared **WS-** workstation ladder — the cards that make the five
editors behave like one program. Everything below shipped; the board entry it
graduated from had grown to eleven nested "Previously:" chains, which is the
signal to move it here.

**Shipped, in order:** WS-A5 loudness as a view · WS-A7 clip warp · WS-A9
stretch quality · WS-A1 clip edge handles · WS-T3 the shared keymap (which
unblocked two other cards) · WS-A3 the Audio Editor's keyboard · WS-X6 one
export door (Audio Editor, Tracker, Loop Studio) · WS-T1 eased playhead follow ·
WS-T2 song overview + drag-to-reorder · WS-T4 the piano roll · WS-T6 a real time
signature · WS-X5 step 1 the MIDI-in seam.

**The recurring finding, worth stating once.** Nearly every card in this ladder
turned out to be *partly* wrong about the code, and the errors were consistently
in the same direction — a feature looked present because a FIELD existed:

  * WS-T3's acceptance leant on a keyboard regression suite that did not exist
    (`LogicalKeyboardKey`: zero hits across every tracker test).
  * `_followPlay` (WS-T1) was hardcoded `true` and toggled nowhere.
  * `_highlightEvery` (WS-T6) was declared, read once, and assigned nowhere.
  * WS-X6's premise ("every mode exports differently") was half stale — one
    sheet was already shared by eight screens.
  * WS-L1 was sized `S` for work that needs a cursor concept Loop Studio does
    not have.

So: **verify the premise before building to the card.** Every entry below that
says "the card was wrong" is one of these, and each was boarded rather than
quietly worked around.

**Three things this lane declined to do**, recorded because a card that looks
done is worse than one that looks open: the Workshop keeps its own export sheet
(already one door, and its per-format "active part only" warning is better than
a category heading); WS-L1 was stood down to @loop-d1d4 on a same-hour
double-claim; and WS-X5's platform binding was left as a maintainer decision
rather than a package added quietly across five targets.

**Test-methodology warnings this lane paid for**, all reproduced below in
context: `pumpAndSettle` never completes on the Tracker or Loop (continuous
tickers); a screen's `autofocus: true` does not win against the route's focus
scope in the test binding, so key presses are silently swallowed and a keyboard
suite passes while asserting nothing; the shared 1400x2400 game surface means
the tracker grid never overflows, so a scroll test guarded on `maxScrollExtent`
returns early and passes vacuously; and a per-frame delta assertion measures how
much time the harness delivers per pump, not the code.

The board entry as it stood:

- **opus (daw-suite)** · ✅ **DONE (idle) — WS-X5 STEP 1 (the MIDI-in seam)
  SHIPPED. The binding is NOT done and is a maintainer decision.**
  `lib/core/midi/midi_input.dart`: `MidiMessage`, the `MidiInput` interface,
  `NullMidiInput`, `ManualMidiInput`, `HeldNotes`. Pure Dart, **no dependency
  added**.
  ⚠️ **The fact this seam exists for, and that every future record path would
  otherwise have to rediscover: in MIDI a note-on with velocity 0 IS a
  note-off.** It is in the standard, most controllers rely on it, and missing it
  leaves notes stuck on forever. `HeldNotes` handles it once, along with
  same-pitch-on-two-channels, duplicate note-ons, and a `clear()` for
  disconnect (the note-offs for held notes never arrive).
  ⛔ **I did not add a MIDI package.** That is a dependency across five targets
  with permissions on two — not a call to make quietly mid-session. `NullMidiInput`
  is the honest current answer and remains the answer on web, so consumers can
  be written now and will not change when hardware lands.
  `midi_input_test` (21). **WS-T7 is unblocked on the contract side**; the
  binding + on-screen keyboard remain, and are pullable.
  Previously: ✅ **WS-T6 pattern-level time signature
  SHIPPED** (groove templates deliberately left open — they change WHEN notes
  play, not how the grid is drawn).
  `tracker_meter.dart` = one `TrackerMeter` the grid and the roll both read, +
  a "Beats and bars" picker. **Three bugs behind the card's one line:**
  beats-per-bar was hardcoded to 4 so a 3/4 pattern was barred as common time;
  `_highlightEvery` was declared, read once and **assigned nowhere**, so the
  configurable spacing never was; and my own WS-T4 roll hardcoded 4/16 and
  disagreed with the grid.
  ⚠️ **Inheritable detail: every bar row is also a beat row**, so a painter must
  test `isBar` FIRST — beat-first draws every bar as a beat and the meter reads
  as 4/4 whatever it is. Pinned as a property over every offered meter.
  Display-only by design, so it lives screen-side rather than in
  `TrackerTiming` — which also keeps it out of the replay lane's engine files.
  `tracker_meter_test` (12); 127 green across the tracker suites + layout audit.
  Previously: ✅ **WS-T4 piano roll SHIPPED
  (read-only).** `tracker_piano_roll.dart` = `rollNotesFor` (pure) + a painted
  roll for the cursor's channel. The app had no continuous roll anywhere
  (verified: `pianoRoll` 0 hits) and the tracker grid is exact-but-unreadable,
  so this is a legibility view BESIDE the grid, not a replacement.
  The whole logic is where a note ENDS — a cell says a note starts and never
  says it stops — so a run ends at the next note (monophonic channel), a
  key-off, or the pattern edge; that last is a stated simplification, since a
  held note really does sound into the next pattern.
  ⛔ **Read-only on purpose. An editable roll that silently disagreed with the
  grid would be worse than no roll** — making the two agree is its own card, and
  I have left it rather than half-doing it.
  `tracker_piano_roll_test` (14); 115 green across the tracker suites + layout
  audit; analyze clean.
  Previously: ✅ **WS-T2 pattern overview +
  drag-to-reorder SHIPPED.** A "Song overview" sheet over the order list, and a
  real drag: the strip's move buttons SWAP with a neighbour, which is sixty
  presses to move a slot to the end and displaces something every time.
  The cursor follows the SLOT rather than the index (both crossing directions
  pinned, and mutation-checked). ⚠️ `ReorderableListView.onReorder` is
  deprecated for `onReorderItem`, which **already** adjusts for the removed
  item — the familiar `to > from ? to - 1 : to` correction is an off-by-one
  there. `tracker_order_overview_test` (8); 116 green across the tracker suites
  + layout audit; analyze clean.
  Previously: ✅ **WS-T1 eased playhead follow SHIPPED.**
  `followScrollOffset` (pure) + a follow toggle that did not exist.
  ⚠️ **Three things the card did not know.** (1) The SONG branch never called the
  follow at all — it worked auditioning one pattern and did nothing when playing
  the song. (2) `_followPlay` was hardcoded `true` and toggled nowhere, so
  following could not be turned off; that matters more now it glides
  continuously, hence the toolbar switch. (3) The sub-row field is `_rowPhase`,
  not `_playFrac`.
  ⚠️ **Test-methodology warning worth inheriting, from two failures of my own.**
  A widget test of this guarded on `maxScrollExtent <= 0`; on the shared
  **1400x2400** game surface the tracker grid never overflows, so it returned
  early and **passed while asserting nothing** — I only caught it by printing
  the extent. The replacement measured a per-frame scroll delta and flaked under
  `--concurrency`, because it was measuring how much time the harness delivers
  per pump. Both are gone: the easing is a pure function now and the tests are
  arithmetic. If you test scroll-following anywhere, do the same.
  🧹 Also fixed a stray `require_trailing_commas` in
  `test/guitar_score_fingering_test.dart` (from `82b67748`, @score lane) that
  was making whole-project `flutter analyze` non-clean for everyone — one comma,
  their test still green.
  Previously: ✅ **WS-X6 shipped on the Audio Editor;
  the other surfaces are a drop-in.** One door (`shared/music_io/export_sheet
  .dart`) grouped Sound · Notes · Project · Share, listing only what the surface
  can really produce; it knows how to BUILD nothing, which is what keeps it a
  door rather than a fourth exporter.
  ⚠️ **The card's premise was half stale** — `showAudioExportSheet` was already
  shared by 8 screens. The real gap was two separate doors + no archive anywhere,
  so that is what I built to.
  ⚠️ **Wording bug my own test caught, worth inheriting:** "these clips are
  audio" is FALSE for a drum project — a drum clip is symbolic and still yields
  no score, because `ProjectBridge` tracker→score returns **null** for a
  percussion-only song. If you rely on that conversion anywhere, know it does not
  exist. The reason now states the outcome instead.
  Six `daw_screen_test` cases correctly failed on the re-routed button and were
  updated to go through the door. `export_sheet_test` (8); 113 green across
  export/DAW/keyboard/interop + both smoke suites; analyze clean.
  ✅ **Finished across the Tracker and Loop Studio too** — leaving a shared door
  wired into ONE screen would have been the exact problem it was built to fix.
  The Tracker's five sibling rows are one door (its **module** export, the format
  it is native to, sat unremarked between MusicXML and audio); Loop's **share
  code** was under "copy" and is now an export in its own right.
  ⚠️ **I walked into the trap I had just documented:** `pumpAndSettle` after
  opening a sheet on the Tracker/Loop hangs forever — continuous tickers. Two
  test runs timed out at 10 minutes before I recognised my own note. Use
  explicit pumps. Both screens gained a `debugOpenExportDoor` seam, since a
  PopupMenu cannot be driven from a widget test without the route.
  ⛔ **Workshop: deliberately NOT wrapped — WS-X6 closed.** I went to do it and
  stopped. It is already one door; all 13 formats are symbolic, so the grouping
  buys nothing — and its dialog already warns, per format and in red, which ones
  can carry only the ACTIVE part. That is more useful than a category heading and
  my `ExportOption` cannot express it. Wrapping it would have been a downgrade
  dressed as consistency.
  Previously: ✅ **WS-A3 SHIPPED · WS-L1 stood down to @loop-d1d4.
  ✅ **WS-A3** — split (Ctrl+S) · trim to range (Ctrl+T) · nudge (`,`/`.`) ·
  marker jump (`[`/`]`) · mute/solo (M/S), through the shared keymap. Every verb
  acts on the SELECTION and does nothing without one; mute/solo refuse a
  selection spanning two lanes rather than picking one. `daw_keyboard_test` (11)
  + new `DawTester.selectClip`.
  ⚠️ **Finding for anyone touching the shared table: plain M and S are NOTE KEYS
  in the Tracker** (classic QWERTY piano layout). I found this by writing the
  test, not by reading the code. Binding them for the Audio Editor is safe ONLY
  because the Tracker does not dispatch those intents, so an unhandled intent
  falls through to note entry — recorded at the binding site and pinned by the
  characterization suite. If the Tracker ever handles mute/solo, move them.
  🤝 **WS-L1 — STOOD DOWN, it is @loop-d1d4's.** We claimed it within the hour;
  they got there in the board's history and it is their lane, so I yielded on
  the rebase and kept their claim line. My sizing finding is handed to them ON
  the card rather than kept here.
  🔶 **What I found before standing down: WS-L1 is MIS-SIZED at `S`.** Its
  transport half already shipped with WS-T3 (Space/undo/redo — the screen had no
  keyboard at all before). Its grid half asks for "arrows move the cell cursor,
  digits = velocity", but **Loop Studio has no cell cursor**: `cursor` matches
  zero times in `loop_mixer_screen.dart` and the step grids are tap-only. That
  is introducing a cursor concept plus per-cell velocity — `M`–`L`, not `S`.
  Re-scoped on the card rather than half-built under an `S` label.
  Previously: ✅ **WS-T3 COMPLETE: the keymap is
  shared, hosted by three surfaces, rebindable and discoverable.**
  `lib/shared/keymap/` (intents · table · service · sheet); hosted by the
  Tracker, the Audio Editor and Loop Studio, each declaring the subset it
  handles. **Loop Studio had no keyboard at all** — not even space-to-play — and
  has one now purely by hosting the table.
  ⚠️ **For anyone writing a keyboard test here — two traps that make one LIE:**
  `pumpAndSettle` never completes on the tracker (continuous ticker), and a
  screen's `autofocus: true` does NOT win against the route's focus scope in the
  test binding, so every key press is silently swallowed and the suite passes
  vacuously. Claim the FocusNode directly; the DAW and Loop `Focus` widgets now
  carry explicit disposed nodes so a test can.
  ⚠️ **The card's acceptance leaned on a regression suite that did not exist**
  (zero `LogicalKeyboardKey` across every tracker test) — I wrote it first
  (13 tests), then extracted; it and the tracker's own 112 pass unchanged.
  Persistence stores only the DIFFERENCE from the defaults, so a later release
  that improves a binding still reaches anyone who rebound something else.
  Tests: `keymap_test` (18) · `keymap_hosting_test` (12) ·
  `tracker_keymap_characterization_test` (13). Analyze clean; 260 tests green
  across tracker/DAW/loop plus both broad smoke suites.
  **➡️ This unblocks WS-A3 (Audio Editor keyboard) and WS-L1 (Loop Studio
  keyboard) — both now about WHICH intents to handle, not plumbing. I am not
  claiming either; they are pullable.**
  Previously: ✅ WS-A1 clip edge handles SHIPPED.
· WS-A7 (clip warp) · WS-A5 (loudness
  view) — and the A/B/C/D/F ladder in the Audio Editor section.
  Previously: WS-A7 clip warp; WS-A5 loudness view. `Clip.warp`/`nativeBpm`, an optional
  `TempoMap` on both render paths (null = byte-identical to before), WSOLA so
  pitch does not move, and a "Follow project tempo" toggle that ASKS a recording
  for its tempo (the case warp exists for) and reads a symbolic clip's own grid.
  Refuses rather than guesses: no stated tempo, or an absurd factor, leaves the
  audio alone. A clip crossing a tempo change ends exactly where the map says,
  so nothing after it drifts. `daw_warp_test` (20). Touched
  `daw_timeline.dart`/`daw_project.dart`/`daw_service.dart`/`daw_screen.dart`
  additively — **@daw-ux: the `daw_timeline.dart` change is two `Clip` fields +
  one optional render param + one private helper; no DSP dispatch moved.**
  **Remaining in the Audio Editor: WS-A9 (time-stretch quality knob) only, and
  it is unclaimed.**
  Previously: WS-A5 loudness metering as a view. `core/audio/loudness_advice.dart` (pure, testable judgement) + a
  **Loudness** toolbar button and sheet in `daw_screen.dart`; measures the mix
  or the marked range, against a streaming/broadcast/none target. The
  substantive design call: the *judgement* is out of the widget, because the
  claim worth testing is "it says the right thing about a mix", not "a sheet
  opened" — and one judgement in particular is inverted in most meters, namely
  that **quieter than target is good, not a fault**. Tests:
  `loudness_advice_test` (17, incl. widget half); the layout audit (every game,
  phone+tablet, EN/DE) is green with the new toolbar button. Touched only
  `daw_screen.dart` + two new files — no tracker/loop/registry/crisp_notation.
  **WS-A7 (clip warp) and WS-A9 (stretch-quality knob) remain unclaimed and
  pullable.**
  Previously: ✅ **DONE — Audio Editor → swiss-army knife; the
  whole ladder is on `origin/main`.**
  🤝 **Coordinated with @workstation-parity** (`b8725cf8`): they re-audited the
  WS ladder against the code while this branch was unpushed, left a collision
  heads-up on the root `PLAN.md` Audio block, and asked me to prefer THEIR
  version of it and re-check one line. Done exactly that — theirs is better
  evidenced than mine (it names the symbols it checked), so I took it whole and
  discharged only the "built but NOT on main" caveat, which this push settles.
  Their **O16 correction stands and mine deferred to it**: export is
  `{wav, mp3, opus, aac}`, not WAV/MP3 — the real remainder is FLAC and
  Ogg-Vorbis *encoders*. Verified their two board entries survived my ~960-line
  move out of this file (a removal that big is exactly how another agent's work
  disappears quietly).
  **Gate:** the whole-suite run was OOM-killed twice at ~4,200 tests under a
  loaded machine, so it ran as **six bounded chunks → 5,475 pass / ~20 skip /
  0 fail**, plus format + analyze clean and a post-rebase re-run of every
  touched area. Last two slices: **D5 take lanes +
  comping** (`20b7063e`) and **A6 band-limited rate conversion** (`b2e2551d`),
  the latter fixing a real shipping bug — every downsampled export was folding
  content above the new Nyquist back into the music. Files touched in this pass:
  `daw_timeline.dart` · `daw_project.dart` · `daw_service.dart` ·
  `daw_screen.dart` · `crisp_dsp/resample.dart` · `music_io/audio_export.dart` ·
  `bin/dawedit.dart`. Nothing else is claimed; the one remaining 🔶 is
  time-stretch quality tiers (a different algorithm — phase vocoder / WSOLA —
  not a resampler setting), unclaimed.


## Audio Editor ("Multitrack") — single-file-editor parity ladder (2026-07-25)

**Complete — all 16 items shipped.** This is the arc that closed the gap to a
single-file audio editor; the swiss-army-knife arc that follows built on it.

The DAW is already a strong **non-destructive multitrack** engine: stereo
throughout; per-clip/track/bus/master FX chains + breakpoint automation (reverb,
delay, chorus, flanger, ring-mod, distortion, bit-crush, low/high-pass,
compressor, gate, pitch-shift, time-stretch, tremolo, vocoder, voice-shape, gain,
pan); split/trim/fade(linear·exp·s-curve)/gain/pan/width/reverse/respeed/freeze/
merge/crossfade; per-clip + per-track + marked-range selection with range
FX/gain/fade/mute/track-automation; WAV/MP3/FLAC import (mono/stereo, magic-byte);
WAV(8/16/24/32-bit)+MP3(128/192/320) export with sample-rate choice, whole-mix +
marked-range, optional normalize-on-export; undo/redo depth-50; stereo waveform +
ruler + beat grid; snap; whole-arrangement loop; `.cbdaw` save/load; Space/Delete
keys.

Gaps vs a capable **single-file audio editor**, to close in order. Most DSP already
exists in `crisp_dsp/` (`sample_edit.dart`: `normalizePcm`/`removeDcOffset`/
`trimSilence`/`trimPcm`/`peakMagnitude`; `biquad.dart` full filter set;
`sfxr.dart` tone/noise) — the work is wiring it as DAW clip ops (bake pattern like
`reverseClip`) + inspector UI + tests.

**Tier 1 — destructive clip processing (bake to SampleSource; DSP exists):**
- [x] **O1** Normalize clip — one gain from the loudest sample across BOTH channels (stereo image preserved), target 0.98 FS; no-op on silence.
- [x] **O2** Invert phase (×−1) — a bake op + inspector item.
- [x] **O3** Remove DC offset (`removeDcOffset`), per channel.
  > O1–O3 share a new private `_bakeClip(track, index, transform)` in
  > `daw_service.dart` — renders the clip's trimmed window (both channels),
  > hands it to `transform`, and rebuilds the `Clip` preserving placement/gain/
  > pan/width/mute/fades/effects (the `reverseClip` pattern, trim folded in).
  > O4–O6 reuse it. Undoable (`_record`); +5 tests.
- [x] **O4** Trim silence from clip edges + crop to the marked range.
  `trimSilenceFromClip` judges a stereo clip on BOTH channels at once (so they
  stay sample-aligned) and slides the clip later by exactly the leading
  silence, so the surviving audio keeps its place — this is why `_bakeClip`'s
  transform now returns a `_BakedTake` with a `startShiftMs`.
  `cropToRange(tracks, start, end)` keeps only what's inside.
- [x] **O5** `silenceRange(tracks, start, end)` cuts the covered segments out
  (no ripple — surrounding clips keep their timing). Distinct from the existing
  `setClipMutedInRange`, which is reversible and leaves the clips in place.
  Both share `_removeClipsAroundRange` (split at both bounds, then drop one
  side; a sliver too short to split is decided by its midpoint).
- [x] **O6** `amplifyClip(track, index, db)` (bake) + a conventional dB
  dialog. Complements the non-destructive Gain FX: this rewrites the samples,
  so a later normalize/statistic sees the new level.

**Headless core + CLI (done alongside Tier 1 → 2).** The edit maths lives in
`lib/core/audio/daw_edits.dart` — Flutter-free pure functions (`normalizeTake` ·
`amplifyTake` · `invertTake` · `removeDcTake` · `trimSilenceTake` ·
`clipStatsOf` · `generateWave` · `editClipsAroundRange`). `DawService` is now a
thin wrapper over them (undo · render cache · notify), and **`bin/dawedit.dart`**
drives the same functions on a real WAV, so an op can be unit-tested headlessly
AND heard: `dart run bin/dawedit.dart in.wav out.wav --normalize --amplify -6`,
`--trim-silence`, `--crop A:B`, `--silence A:B`, `--stats`,
`--generate sine:440:2 out.wav --play`. Ops chain in the order given; stereo is
preserved. Verified end-to-end (2 s sine @ 0.25): normalize → 0.98 peak / RMS
0.693, −6 dB → 0.491, crop 500:1500 → 1000 ms, silence 500:1500 → still 2000 ms
with RMS × √0.5 exactly (proof the hole doesn't ripple), head-silence →
trim-silence → exactly 500.0 ms cut. `bin/listen.dart` reads the generated tone
as A4 440.0 Hz, clarity 1.00. Tests: `daw_edits_test.dart` (19, headless) +
`dawedit_cli_test.dart` (8, real subprocess).

> ⚠️ **HEADS-UP for the loop-suite agent (not mine to fix): `main` is red in
> `layout_audit_test`.** `e4a6dfee` re-registered the orphaned DrumKit screen —
> which means the layout audit renders it for the FIRST time, and it fails:
> `drumkit @ SE 375x667 [de]: A RenderFlex overflowed by 97 pixels on the
> bottom.` (German only, phone only — the longer German labels plus the 4 new
> kits push it over.) Verified it's the re-registration: `drumkit` had 0
> registry entries before that commit and 2 after, so the screen was simply
> never audited before. Repro: `flutter test test/layout_audit_test.dart`.
> Likely a scroll/`Expanded` fix in `drumkit_screen.dart` — left alone since
> that's your file and you're actively in it.

> ⚠️ **HEADS-UP for the tracker agent (not mine to fix):** `b3858e85` committed
> `test/native_tick_zone_reuse_test.dart`, which asserts
> `test/fixtures/wonderfulpain.it` "must be present" — but that fixture is
> **untracked**; it exists only in the `mus/` worktree. So a full
> `flutter test` is RED on `main` for everyone else and in CI (3460 pass, 8
> skip, this 1 fails). I did NOT commit the fixture: it's an unclear-provenance
> module, which the licensing rules keep out of tracked files. Either gate the
> test on the file existing (skip when absent, like the other corpus-backed
> tests) or point it at a fixture that can be committed.

**Tier 2 — generation + precise editing:**
- [x] **O7** Generate clip: engine + CLI + **in-app dialog** (shape dropdown ·
  frequency, shown only for the pitched shapes · length · level → a clip on its
  own new lane). `generateWave`, 7 shapes;
  `DawService.addGeneratedClip` puts it on its own lane with a 5 ms fade so the
  hard edges don't click). Deliberately NOT built on `sfxr` — that's an
  envelope-shaped SFX generator, wrong for a steady signal. Noise is scaled by
  its realised peak (the pink filter's sum overshoots ~19% otherwise, which
  would clip a loud generated clip).
- [x] **O8** Zoom in/out/fit. The fixed `_pxPerSecond = 80` became
  `_basePxPerSecond * _zoom` behind a getter, so all twelve time↔pixel sites
  (ruler, clips, beat grid, range overlay, drag maths, tap-to-seek) rescale
  together with no other edits. 0.1x–20x in 1.5x steps; Fit solves the zoom
  that puts the whole arrangement in the viewport.
- [x] **O9** Loop the marked selection. Marking a range while Loop is on makes
  playback wrap at the range end instead of the arrangement end — the standard
  loop-region behaviour, no extra toggle to discover. `loopsMarkedRange` is the
  one condition (`_loop && _hasFxRange`), checked in `_onTick`.
- [x] **O10** Clip statistics in the inspector: duration · mono/stereo · peak
  dBFS · RMS dBFS, plus a red "clipping!" flag when any sample is at or past
  full scale. `clipStatsOf` / `DawService.clipStats`; dBFS floors at
  `silenceDb` = −160 rather than −infinity. Peak/RMS/dBFS are left untranslated
  as technical units.

**Tier 3 — filters/EQ + analysis + markers:**
- [x] **O11** Full biquad set as FX: band-pass · notch · peaking EQ · low/high
  shelf, **plus a new phaser** (`crisp_dsp/phaser.dart` — a cascade of
  first-order all-passes swept by an LFO; there was no phaser in the DSP set,
  and it isn't a delay effect so chorus/flanger couldn't stand in). ⚠ This
  touches `DawClipEffectType`; the new values are **appended**, and `.cbdaw`
  stores effects by NAME, so nothing shifts for saved projects or for the FX
  work happening in parallel. Tests assert **spectrally** (two tones in, check
  which survived), which is the only thing that proves the right `BiquadKind`
  reached the DSP with the right params.
- [x] **O12** Level meters: peak + RMS of the baked mix at the playhead, on a
  −60…0 dBFS scale, turning red at full scale. Repaints off the playhead
  notifier so it costs nothing when stopped.
- [x] **O13** Markers with labels: `DawMarker` on `DawTimeline`, kept sorted,
  **undoable** (in the snapshot) and **saved in `.cbdaw`**. Flags render on the
  ruler and are tappable to rename/delete; the Markers menu adds one at the
  playhead and jumps to previous/next. Navigation only — a test asserts a
  marker can't change the render. Also fixed the ruler at low zoom: tick
  spacing now grows (1/2/5/10/15/30/60…s) so zooming out doesn't produce a wall
  of overlapping labels.

### Beyond the ladder — real DAW gaps the ladder missed (2026-07-25)

The O1–O16 list was written against a single-file editor, so it
never asked for the things a MULTITRACK editor must do. Three were genuinely
missing and are now shipped:

- [x] **Move a clip between lanes.** `moveClipToTrack` (the old `moveClip` only
  slid a clip along the lane it was already on). Long-press-drag now moves
  vertically too — committed on release, because re-parenting mid-drag tears
  down the gesture driving it — plus a "Move to lane" picker in the inspector,
  which is the reliable path on a phone. The clip keeps source/trim/gain/pan/
  fades/FX; only the lane changes.
- [x] **Per-track (stem) export — single, selected, or all.** `bakeTrack` /
  `bakeTrackStereo` + a source dropdown in the export sheet (full mix · or one
  lane), **plus batch stems**: `showAudioStemsExportSheet` writes one file per
  lane into a chosen folder, and the export dialog offers "All as stems" or
  "Selected as stems" depending on the gutter selection. Silent lanes are
  skipped rather than written as empty files, and one bad lane doesn't abandon
  the rest. Picking a folder needs a directory picker, which desktop has and
  mobile doesn't — where it's unavailable this degrades to a save prompt per
  stem (more taps, still works) instead of hiding the feature. The path join is
  deliberately NOT `dart:io`'s separator: `audio_export.dart` is web-safe and
  must stay importable there. **Stems deliberately
  skip the master limiter** — limiting each stem is mastering a part, and it
  would stop stems summing back to the mix, which is the point of stems. Other
  lanes' solo is ignored (asking for lane 3 means lane 3); the lane's own mute
  is honoured. Filenames carry the lane (`…-stem-<lane>.wav`).
- [x] **Drawable automation curves.** `automation_curve_editor.dart`: drag a
  breakpoint to shape it, tap empty canvas to add, hold a handle to remove
  (never below two). Automation and fade curves already existed and already
  played back — what was missing was any way to SEE or draw them; the numeric
  list stays alongside for precision and accessibility.

⚠️ **Correction on that comparison:** split · copy/cut/paste/duplicate ·
per-clip/track/bus/master/range FX · fade curves (linear/exp/S) already existed
before this pass — the gap was narrower than "tiny steps", but these three were
real and are the difference between a clip arranger and a DAW.

## Audio Editor → swiss-army knife (2026-07-26 … 07-28)

**One-line status:** the Audio Editor carries the full DSP bag of tricks a
serious workstation carries — **50+ effects, every one reachable from the GUI
*and* the CLI with no per-effect UI or CLI code** — plus five-mode interop, so
any lane opens in any other editor with the same rack. All of A1–A7, B1–B6,
C1–C5, D1–D6 and the F foundations shipped; the scoping doc
**[AUDIO_EDITOR_SUITE.md](AUDIO_EDITOR_SUITE.md)** stays current for the gap
tables and the interop matrix.

**What made it cheap.** One registry (`fx_spec.dart` + `fx_params.dart`)
describes the whole rack machine-readably, so the CLI, the GUI panel, `--list`
documentation, range validation and the chain-string codec are all *generated*
from it. Adding an `FxType` reached every surface with one line for menu order,
guarded by a test — the lever held across seven DSP slices.

**Two bugs worth remembering**, both found by tests that measured the CLAIM
rather than the plumbing: export downsampling had been running through a plain
interpolator, folding everything above the new Nyquist back into the music on
every downsampled export (A6); and the GUI conversion-quality picker's value was
dropped at the encode call, leaving a control that did nothing.

The checklist below is the original ladder, as shipped.

### The build log (from the agent board)

  Worktree `../mus-daw-suite` (`feature/daw-suite`). Maintainer ask: the full
  DSP bag of tricks, **every op in the GUI *and* the CLI**, plus five-mode
  interop so any lane opens in any editor with the same FX. Full scoping in
  **[AUDIO_EDITOR_SUITE.md](AUDIO_EDITOR_SUITE.md)**; condensed ladder in the
  *"Audio Editor — swiss-army ladder"* section below.
  **Shipped so far (all on `main`):** F1 the chain-string codec · F2 `fxproc`
  regenerated from the FX registry (whole rack, stereo, `--list`) · F2b the
  GUI's hand-written label + param tables deleted and derived from the same
  registry · A1 the rest of the filter set (6 effects) · C1 `.cbdaw` v2, so a
  saved project keeps its clips **editable**, not just audible · C2 drum +
  groove round-trip, so every source kind the DAW holds can now go home · C3
  cross-mode "Open a copy in…" (hosting the already-built `OpenInMenu`, which
  had no host) · A3 dynamics (look-ahead limiter · de-esser · multiband) · A4 the
  channel/stereo ops.
  · A5 restoration (noise reduction · hum · de-click · de-clip · DC).
  **Pillars A, B, C and D are complete** — A1 filters · A2 tone curves ·
  A3 dynamics · A4 channel/stereo · A5 restoration · A7 generators (A6 is the
  one deliberate 🔶, below) · B1–B6 · C1–C5 (C4/C5 by `opus (tracker→editors)`)
  · D1 ripple · D2 groups+nudge · D3 clip envelope · D4 loudness · D5 take
  lanes+comping · D6 tempo map.
  ✅ **A6 closed too** — band-limited rate conversion (`resampleHq`) now backs
  the export path, which had been folding everything above the new Nyquist back
  into the music on every downsampled export. **The whole ladder is shipped**;
  the one remaining 🔶 is time-stretch quality tiers, which are a different
  algorithm (phase vocoder / WSOLA), not a resampler setting.
  **Rack is now 50 effects**, every one reachable from the GUI *and* the CLI with
  no per-effect UI or CLI code — the F1/F2 lever has held across five DSP slices.
  A "learn the noise from the marked range" service op is the natural next step
  for `noiseReduce` (the DSP already accepts a profile; only the UI is missing).
  ⚠ **Interop status, precisely (updated 2026-07-27 — now COMPLETE):** every
  clip kind opens its OWN editor exactly (score/tab/tracker/drum/groove — no
  conversion, nothing approximated) and that survives a save; every symbolic clip
  kind (score/tracker/drum/groove) can additionally open a CONVERTED copy OR
  round-trip-and-replace in any of the four other modes (Loop included), with the
  cost named first. Tab fretting now survives INBOUND (C4 — a tab enters as a
  score with its string/fret in `Score.tabVoicings`, so the Tab Workshop
  reproduces it rather than re-fretting), and a raw-audio clip has a
  **Transcribe → notation** action (C5 — pure-Dart monophonic, adds a new score
  clip). Nothing on the interop matrix is outstanding.
  ⚠️ **@loop-agent — `main` is RED in the registry smoke, and I bisected it for
  you.** `test/live_flow_test.dart` → *"registry smoke: every game screen renders
  with real notation"* fails with *"A RenderFlex overflowed by 5.5 pixels on the
  right"*, from the `LoopCreature` Row at `loop_mixer_screen.dart:4784`. First
  bad commit is **`bed50475` feat(loop): reach per-track length from the track
  card** — green at `90650bb5` and every commit before it, red at `bed50475` and
  every one since. The Row itself is original Loop Mixer code; the new control on
  the track card is what took the width away from it. Left to you rather than
  guessed at from outside: 5.5 px is an `Expanded`/`Flexible` or a size choice on
  the new control, and which one is a design call about what should give.
  ⚠️ **For the owner of `shared/widgets/open_in_menu.dart`:** it is entirely
  unlocalized — its menu, its loss dialog and its "cannot open" dialog are
  hardcoded English. It had no host until now, so this never showed; the Audio
  Editor's new door makes it user-visible in a de/en app. Left to you rather
  than half-localized from my side, which would leave the dialogs mismatched.
  **Files I touch:** `core/audio/fx/*` (additive — new `FxType`s are APPENDED,
  never reordered, since `.cbdaw` stores effects by name), `core/audio/crisp_dsp/*`
  (new files), `daw_edits.dart`, `daw_project.dart`, `daw_clip_source_codec.dart`,
  `bin/fxproc.dart` + `bin/dawedit.dart`, `daw_service.dart`, `daw_screen.dart`,
  later `core/interop/*`.
  ⚠️ **For anyone adding an `FxType`: you no longer need to touch
  `daw_screen.dart`.** Its label switch and its ~300-line param table are gone —
  both now come from `fx_params.dart`. Add the type, its `defaultFx`, its param
  descriptors and a dispatch case, plus one line in `kDawClipEffectTypes` for
  menu ORDER (a test names it if you forget). That was the recurring CI red on
  this file; it should not happen again.
  ⚠️ **Overlap heads-up for `opus (tracker→editors)`**: you are also in `fx/*`.
  I only append to `FxType` + add dispatch cases; if we collide, mine rebases
  onto yours. Ping via this board.
  ⚠️ **My C1 push (`c9ce38ab`) left `main` red for one test and I did not catch
  it before pushing** — `license_obligations_test` pinned the old "a saved clip
  comes back as audio" trade-off, which C1 deliberately reversed. I ran the DAW
  and FX suites plus `analyze` before pushing, but the licensing suite was
  outside that set and my full-suite run finished after the push. Fixed
  independently by another agent (`6c5b56d1`) before I got back to it, and their
  version stands. Lesson for this arc: a change to the PROJECT FORMAT needs a
  full-suite run before the push, not after — the files that care about it are
  not all named `daw_*`.
  — opus

  🔻 **MAINTAINER HANDOFF (2026-07-27) → `daw-suite`, from `tracker→editors`:** the
  maintainer has directed **`opus (tracker→editors)` to take over the cross-mode
  interop** — the requirement is that EVERY symbolic DAW clip (score/tracker/**drum/
  groove/loop**, not just score+tracker) can open in ANY other editor, be edited,
  and **round-trip back into the same clip** so mixing continues (today cross-mode
  "Open a copy in…" only forks a disconnected copy for score/tracker). **Please
  PAUSE the C-series interop** — C3 cross-mode open-in, **C4** (tab fretting
  inbound), **C5** ("Transcribe this clip") — and the interop methods of
  `daw_screen.dart` (`_openACopyIn`/`_clipAsScore`/the open-in wiring),
  `core/interop/*`, and `open_in_menu.dart`. **Keep going on the A-series** (A4
  channel/stereo ops, A5 restoration) + `fx/*` + CLI — those don't touch interop,
  so we won't collide. I'll confine my `daw_screen.dart` edits to the interop
  methods and rebase-before-push. Ping here if this bites. — opus (tracker→editors)


Maintainer ask: the Audio Editor becomes a **swiss-army knife** — the whole DSP
bag of tricks a serious workstation carries, **every op available in the GUI
*and* in a CLI** (the CLI is what makes each one unit- and live-testable), and
five-mode interop so **any lane opens in any other editor** with the **same FX
rack for every kind of track**. Everything clean-room from published DSP theory
(see auto-memory `cleanroom-gpl-port-process`); no encumbered source is read or
ported.

**Full scoping — the gap tables, the target interop matrix, acceptance criteria
and non-goals — lives in [AUDIO_EDITOR_SUITE.md](AUDIO_EDITOR_SUITE.md).** This
is the checklist; keep the detail there, not here.

**The lever.** `fx_spec.dart` (what an effect is) + `fx_params.dart` (each
param's range/unit/type) already describe the whole rack machine-readably, and
the GUI is already generated from it. So **generate the CLI from it too**: then
one new `FxType` yields a GUI control, a CLI verb, `--list` documentation, range
validation and a preset entry with no further work. The shared surface is a
**chain string** — `highpass freq=120 | compressor ratio=4 | reverb mix=0.2` —
that is simultaneously the CLI argument and the app's copy/paste preset, so a
chain tuned by ear pastes into a test and vice versa.

**Foundations**
- [x] **F1** `fx/fx_chain_codec.dart` — chain string ↔ `List<FxSpec>`, registry
  introspection, range validation. Never throws (both faces must *report* a bad
  chain); names match case/punctuation-insensitively; choices take their label;
  0..1 params take a percentage; out-of-range clamps + warns; typo hints use
  **transposition-aware** edit distance (`chorsu`→`chorus` is one finger slip and
  the commonest miss). Printing is minimal and **round-trips exactly** — the
  first cut formatted to 4 decimals, which silently moved a slider's 3.53025.
- [x] **F2** `bin/fxproc.dart` regenerated from the registry: whole rack,
  `--chain`, `--list [type]`, `--stats`, `--dry-run`, `--mono`, `--play`; old
  `--effect` flags kept byte-identical. Now **stereo per channel** (it used to
  downmix every input, discarding half of a stereo recording before processing);
  a mono input keeps two channels out exactly when the chain moved them apart,
  because folding a `pan` back to mono discards the effect that was asked for.
  Tests: `fx_chain_codec_test` (23) + `fxproc_cli_test` (18, real subprocesses).
- [x] **F2b — the GUI now comes from the registry too** (unplanned, but it is the
  same lever and it removes a recurring CI red). `daw_screen.dart` hand-wrote
  BOTH an effect-label switch and a ~300-line param table duplicating
  `fxTypeLabel`/`fxParamLabel`/`fxParamSpecs`, so every effect added to the rack
  turned this file red until someone remembered. Both are now derived. Where the
  two tables disagreed the **wider** range won and was merged back into the
  registry (a level fader reaching −60 dB, a notch's Q reaching 20), so the CLI
  now offers exactly what the sliders do. New `fxParamCaption` (label + unit) and
  `fxSliderStep` (derived from unit + range) keep the panel looking as it did.
  ⚠ Effect labels moved to the shared sentence-case vocabulary (`Low Pass` →
  `Low-pass`, `Voice: Robot` → `Robot`); `gate` gained the better name
  `Noise gate` in the registry rather than losing it.
- [x] **F3** Chain string as a copy/paste preset — Copy/Paste on the master and
  track FX racks, over new `setMasterEffects`/`setTrackEffects` (undoable, and
  cloned on the way in so a caller's list cannot mutate the timeline behind the
  service's back).
  * this closes the loop the whole arc rests on: the codec could always print a
    chain and read one back, but nothing could get the text OUT of the app or
    INTO it, so the two faces shared a format they could never exchange. Copy
    yields exactly what `--chain` takes.
  * copying an AUTOMATED chain warns that automation is dropped — the one thing
    the string form cannot carry, and losing it silently would be found much
    later, after the pasted copy had been edited;
  * pasting nonsense reports it rather than doing nothing.
  Tests: `fx_chain_clipboard_test` (7), incl. the round trip through a mocked
  clipboard.

**Pillar A — DSP vocabulary** (each: `FxType` + defaults + ranges + dispatch +
DSP + a *behavioural* test; then it appears in GUI **and** CLI for free)
- [x] **A1 filters** — all-pass · one-pole LP/HP · raw biquad (user
  coefficients) · windowed-sinc (4 shapes + steepness) · Hilbert. Six new
  `FxType`s that reached the CLI, `--list` and the GUI menu **with no CLI or
  panel code written** — the lever working as designed. New DSP:
  `crisp_dsp/one_pole.dart`, `crisp_dsp/fir.dart`, plus `BiquadKind.allpass` and
  `biquadRawFx` in `biquad.dart`. Tests are spectral/phase, not plumbing
  (`filter_zoo_fx_test`, 24). Decisions worth keeping:
  * the one-pole pair is **exactly complementary** (LP + HP sums back to the
    input sample-for-sample) at the cost of ~0.6 dB at the corner — perfect
    reconstruction is what a band-splitter needs, and A3's multiband compander
    will want it;
  * **unstable** hand-typed biquad coefficients pass through unchanged rather
    than rendering: the failure mode is not "wrong sound" but full-scale noise
    then NaN spreading through the master mix;
  * the windowed sinc is exactly **linear-phase** (a pulse stays put — pinned by
    a test), and taps set the narrowest achievable band (~6·fs/taps ≈ 520 Hz even
    at the 511-tap ceiling), so a *narrow* band is still the resonant biquad's
    job. Documented where the design lives.
  * ⛔ **Arbitrary-FIR-from-a-tap-list was dropped, not forgotten**: `FxSpec.params`
    is a fixed map of NAMED doubles by design, and an unbounded coefficient list
    does not belong in it (it would break the params table, the GUI panel and the
    chain string at once). `biquadRaw` covers the escape-hatch need with five
    named params. A real FIR-from-a-file needs a different carrier — a separate
    design, not a slice of this one.
- [x] **A2 tone curves** — `tilt` · `loudness` · `deEmphasis` · `contrast`
  (presence), in new `crisp_dsp/tone_curves.dart`. The biquads answer "remove
  this frequency"; these answer "make it darker / make it sound right quietly /
  make it cut through", so each is one or two knobs over a fixed shape.
  * **tilt is a complementary shelf PAIR**, not a single shelf: one shelf moves
    the overall level as well as the balance, which is why one-knob tone
    controls built that way always need the fader afterwards. A test pins that
    the pivot holds still, and another that it is NOT a low-pass (the top
    survives a −12 dB tilt).
  * loudness lifts the bass more than the treble, because the contours steepen
    faster at the bottom — equal shelves would be a different effect. It is
    explicitly a broad approximation: nothing here knows the playback level, so
    a "calibrated" version would be a lie.
  * presence is odd-symmetric waveshaping that leaves the PEAKS untouched — the
    "louder without louder" property, pinned by a test, plus one asserting it
    introduces no DC (an asymmetric shaper would, and the repair tools would
    then have to remove it).
- [x] **A6 (part)** — `pitchBend`, a pitch envelope across the clip (tape stop,
  vinyl brake, a scoop), over the existing `resampleGlide`. **Length-preserving
  on purpose:** reading faster runs out of source and the tail fades, which is
  what a tape stop sounds like, rather than the clip silently changing length
  under the arrangement.
  ⛔ A6's remaining items are NOT effects and are deliberately left: stretch
  quality tiers and high-quality rate conversion belong to the export/resample
  path, not to `FxSpec` (they change the sample RATE, which a same-buffer effect
  cannot), and "raw up/downsample" is that same path with the anti-aliasing
  turned off. Scoping them properly means touching `resample.dart` and the
  export sheet, which is a separate slice.
  ⚠ One real inconsistency caught by the registry tests while wiring this: I
  named the de-emphasis choice `microseconds` and defaulted it to `50`, so the
  value was simultaneously out of its own 0..1 choice range and read as an index
  by the dispatch. Renamed to `curve`, like the other choice params.
- [x] **A3 dynamics** — a **look-ahead limiter**, a **de-esser** and a
  **multiband compressor**. Re-scoped against the code first, which changed the
  list:
  * `gateFx` is already documented and built as a downward EXPANDER (threshold ·
    ratio · range), so a separate `expander` would have been a second name for
    the same thing — dropped rather than duplicated;
  * `limiterFx` already existed but was **dead code** (defined, never called,
    never exposed) *and* is a fast compressor, which is not a limiter: its gain
    comes from a peak it has already passed, so the transient that triggered it
    goes out over the ceiling. New `lookaheadLimiterFx` delays the signal while
    the detector reads ahead, so the gain is already down when the peak arrives.
    A test pins exactly this, comparing the two — the old one overshoots to 0.6+
    where the new one holds the ceiling;
  * ⛔ **arbitrary multi-segment companding is NOT built**, for the same reason
    arbitrary FIR was dropped in A1: an N-point transfer curve cannot live in
    `FxSpec.params` (a fixed map of NAMED doubles). Compressor + gate already
    span the two-slope shape, which is the useful case.
  * the multiband splitter is **A1's payoff**: it splits with the complementary
    one-poles, so the three bands sum back to the input EXACTLY and an untouched
    multiband compressor is a true no-op (asserted). A splitter that did not
    reconstruct would put a notch at every crossover.
  Tests: `dynamics_zoo_fx_test` (13), each asserting the PROPERTY that makes the
  effect what it claims to be — dynamics are the easiest DSP to test wrongly,
  because "it got quieter" passes for almost any bug.
- [x] **A4 channels/stereo** — `remix` (the general 2×2 matrix) · `swapChannels`
  · `stereoWidth` (mid/side) · `centreCancel` · `crossfeed` · `autoPan`, in a new
  `FxCategory.stereo` group. New DSP `crisp_dsp/stereo_ops.dart`.
  * **These are the first effects that cannot be run per-channel.** Every other
    effect in the rack is a per-channel transform, so the stereo path can run it
    on left and right independently; a channel op is defined by the RELATIONSHIP
    between the two, so it needs an explicit case in the STEREO dispatch. Get
    that wrong and the op does *nothing at all*, which reads as "subtle" rather
    than "broken" — so there is a test whose whole job is to run every channel op
    on a stereo input it must change, and require a change.
  * on a MONO buffer they pass through, deliberately: there is no second channel
    to relate to, and inventing one would be worse than doing nothing.
  * `remix` is the escape hatch (like `biquadRaw`) and genuinely subsumes swap, a
    mono fold, a balance and a polarity flip — asserted. The named effects exist
    because "swap the channels" is easier to find than four numbers.
  * `centreCancel`'s doc says what it actually does rather than promising "vocal
    removal": it takes the bass and kick with it, and the centred part's reverb
    is stereo and stays behind.
  Tests: `stereo_ops_fx_test` (20).
- [x] **A5 restoration** — `dcShift` · `humRemove` (harmonic notch comb) ·
  `noiseReduce` (spectral subtraction) · `declick` · `declip`, in a new
  `FxCategory.restoration` group. New DSP `crisp_dsp/restoration.dart`, reusing
  the app's own radix-2 FFT (inverse via the conjugate identity, so there is one
  transform to be right about).
  * ⚠ **The self-adaptive noise estimator cannot tell a SUSTAINED tone from
    noise, and nothing of that shape can.** Its premise is "noise is what is
    always there"; a drone or a held chord is always there too, so it lands in
    the profile and gets subtracted as hiss. Found by a test that failed
    honestly (a steady 440 Hz fixture came out at 0.022 of its level), and kept:
    the limitation is now DOCUMENTED on `noiseProfile` and **pinned by a test
    that asserts it happens**, next to one showing the escape hatch — a profile
    learned from a silent range fixes exactly that case, and `noiseReduceFx`
    accepts one.
  * the residual floor is deliberate and tested: subtracting a bin all the way
    to zero makes isolated survivors shimmer between frames ("musical noise"),
    which is more distracting than the hiss was.
  * `declip` reconstructs a plausible arc over a flat top and its doc says
    *plausible* — the height is inferred from the run length, which is the only
    evidence there is. That distinction matters to someone deciding whether to
    re-record.
  Tests: `restoration_fx_test` (20). Nearly every one is a PAIR — the damage
  went away, and the signal that should have survived did; the second half is
  where repair tools go wrong.
- [x] **A6 time/pitch** — pitch **bend envelope** (in the rack) + **band-limited
  rate conversion** (`resampleHq`/`resampleRaw` in `crisp_dsp/resample.dart`,
  the export sheet's *Conversion* choice, `dawedit --rate HZ[:QUALITY]` and
  `--raw-rate HZ`).
  * ⚠ **this fixed a real, shipping bug.** Export downsampling called
    `resampleCubic` — an INTERPOLATOR, which says nothing about the frequencies
    the destination rate cannot represent. Exporting at 22.05 kHz folded
    everything above 11 kHz back into the music as a whistle that no later
    processing could remove, because by then the alias and the music occupy the
    same frequencies. `resample_hq_test` runs one fixture through both and
    asserts the fold on the old path and its absence on the new one, so the
    regression cannot come back quietly.
  * the fix is one line of intent: the kernel's cutoff is the LOWER of the two
    Nyquist limits, so content that cannot survive is removed BEFORE it can
    fold. Windowed-sinc, Blackman, written from the published theory of
    band-limited interpolation — no implementation was read.
  * taps are **normalised per output sample**, which is what keeps the first and
    last samples at level where the kernel is truncated by the buffer ends; the
    un-normalised version fades both edges, audible as a click at every clip
    boundary.
  * quality is `fast`/`good`/`best` (8/16/32 lobes a side) — a cost/depth trade,
    not a correctness one, so a test asserts the WORST tier is still alias-free.
    The GUI shows the picker only when the rate is actually changing: a control
    that does nothing in the default case teaches people to ignore it.
  * `resampleRaw` is offered as a **deliberately aliasing lo-fi effect** (it is
    how early samplers sounded) and named so nobody reaches for it expecting
    quality — its test asserts that it DOES alias, which is the only way to
    notice if it is ever silently replaced by the good one.
  * ⚠ two wiring bugs the tests caught: the quality picker's value was dropped
    at the `build()` call, leaving a control that did nothing; and `--rate` has
    to update the buffer's OWN sample rate, or the WAV header and every later op
    still believe the old one (the file then plays at the wrong pitch).
  * verified end-to-end on written files: a 1→20 kHz sweep converted to 22.05 k
    paints as one rising line that ends at Nyquist, while `--raw-rate` paints
    the classic fold-back tent.
  Tests: `resample_hq_test` (16) + `dawedit_cli_test` (+5).
  🔶 Still not modelled, and still on purpose: **stretch quality tiers** (time
  stretching independent of pitch is a different algorithm — phase vocoder or
  WSOLA — not a resampler setting).
- [x] **A7 generators** — brown · blue · violet noise · linear and log sweep ·
  plucked string · impulse, on `GeneratorShape` + `generateWave`, in the GUI's
  generate sheet and `dawedit`.
  * the three noise colours are the two useful integrators/differentiators
    either side of white: brown for rumble and room tone, blue/violet for hiss
    and air. A test asserts each one's spectral TILT rather than that it made
    samples — a "noise" generator that returns white for all four would pass any
    plumbing test.
  * **log sweep is the one that matters** for measurement: a linear sweep spends
    most of its time in the top octave, so it barely excites the bass, while a
    log sweep spends equal time per octave. Both ship because a linear sweep is
    still the right siren.
  * **impulse** is the smallest useful generator and the most useful one for
    this app: send it through any effect and what comes out IS that effect's
    impulse response, which is how several of the FX tests now check themselves.
  * `pluck` finally reaches a user — `crisp_dsp/karplus.dart` existed and was
    unreachable from every screen.
  ⚠ this slice was reverted wholesale by another agent's stale-checkout commit
  (`8a2c2d52`) and restored from `e4f0a10e`; the ladder checkbox stayed stale
  until now. Tests: `generator_shapes_test` (12).

**Pillar B — non-FX editor ops** (`daw_edits.dart` → service → `bin/dawedit.dart`
→ inspector, the same three-way testability as O1–O6)
- [x] **B1** `padTake` · `repeatTake` · `findSilences` (anywhere, not just the
  edges) · `findPhrases` (the complement — one range per phrase, which is what
  "split this take" needs) · `spliceTakes`. CLI: `--pad`, `--repeat`,
  `--splice FILE[:MS]`, `--find-silence`, `--split-silence`.
  * pad reports a NEGATIVE `startShiftMs`, so a caller placing the take on a
    timeline slides the clip back by the lead and nothing moves;
  * a negative pad is zero, not a trim — reinterpreting it would be a surprising
    way to lose audio;
  * `minLengthMs` is what makes silence detection useful: without it every zero
    crossing of a quiet passage is a "silence".
  * ⚠ **splice offers BOTH curves because my first justification was backwards.**
    Equal-power adds POWERS, so two copies of the same audio read **+3 dB** at
    the join and *linear* is what holds the level there; equal-power is right for
    UNRELATED takes (the usual splice) and stays the default. Both pinned.
- [x] **B2** `ditherTake` — bit-depth reduction with TPDF dither and optional
  **noise shaping** (plain TPDF already shipped in export). CLI:
  `--dither BITS[:shape]`.
  * ⚠ **the shaper's signs were backwards and only a test that measured the
    claim caught it.** With `e[n] = quantised − shaped` the output noise is
    `e[n] + h1·e[n−1] + h2·e[n−2]`, so a `(1 − z⁻¹)²` high-pass needs h1 = −2,
    h2 = +1; I had +1.8/−0.9, which BOOSTED the 2–4 kHz band it exists to clear.
    The test asserts both halves (less where the ear is sharp AND more where it
    is not) — checking only the first would pass for a shaper that merely
    removed noise.
- [x] **B3** `fullStatsOf` — the measurements that say whether a file is HEALTHY
  rather than how loud it is: DC offset (invisible on a level meter), crest
  factor (says "over-compressed" when no loudness figure will), effective bit
  depth (a 24-bit file landing on 16-bit boundaries was converted, not
  recorded), zero crossings. CLI: `--full-stats`.
- [x] **B4** `voiceActivityTrim` — frame energies, a floor MEASURED as a low
  percentile rather than supplied, hysteresis, and an onset pad. CLI: `--vad`.
  * ⚠ **no dynamic contrast defeats the method**: the percentile lands on the
    signal, and a take that is voice throughout looks identical to one that is
    all room. My first cut returned EMPTY for both — backwards for the first.
    Absolute level breaks the tie (`kVoiceFloorDb` −45 dBFS), confined to where
    the better test already failed; both sides pinned.
- [x] **B5** spectrogram → PNG (`core/audio/spectrogram_png.dart`). CLI:
  `--spectrogram out.png [--max-hz N] [--grey]`. Kept OUT of `spectrogram.dart`
  so a caller wanting only the numbers does not pay for an image encoder; each
  row takes the LOUDEST bin it covers, since averaging hides a narrow tone.
  Tests assert the picture is READABLE (right row bright, axes the right way).
- [x] **B6** batch — `--batch DIR --out DIR` over a folder.
  * ⚠ **one bad file must not abandon the run**, and mine did: `_read` reported
    errors with `exit()`, which no `try` can catch. Split into `_readOrThrow`
    (batch, skips and names the file) and `_read` (single file, prints + exits).

**Pillar C — five modes, one document.** The converters already exist
(`ProjectBridge`, with honest per-route loss reports) and score/tracker clips
already round-trip **in place**. The gaps:
- [x] **C1** ⭐ **`.cbdaw` v2 — models survive Save.** `projectToJson` baked
  every clip to PCM, so the "vector, not bitmap" engine survived only until the
  user pressed Save: a reopened tracker song was a waveform and every editor
  door had closed behind it. A clip now stores its MODEL too
  (`daw_clip_source_codec.dart`), so tracker · groove · drum · score clips come
  back as themselves. Deliberately **not** a new format — it dispatches over the
  codecs that already exist (the Tracker's song JSON, `GrooveSpec.toJson` which
  is also its share token, MusicXML for engraved music), plus a `kind` tag.
  * the baked PCM STAYS: it is what a source without a model has always been, it
    is the fallback when a model cannot be decoded, and it **primes the render
    cache** on load — so a reopened arrangement is editable *and* plays without
    re-rendering every model first;
  * neither direction can fail the project: an un-encodable source just gets no
    entry, an un-decodable one falls back to its audio. Losing editability is
    bad; losing the audio would be much worse;
  * **v1 projects still open** (as audio, exactly as before); v2 is what is
    written. `ClipSourceKind`'s strings are an on-disk representation — add,
    never rename — pinned by a test.
  Tests: `daw_project_models_test` (17) — per-type round trips, placement/FX/
  **licence provenance** riding along, the fallback paths, v1 compatibility, and
  the cache priming.
- [x] **C2** Drum + groove round-trip. A beat sent from the Drum Kit and a
  groove sent from the Loop Mixer could never go home — the two source kinds
  with no accessor and no door, while score and tracker clips already
  round-tripped in place. Both clips still HOLD their model, so the way back is
  exact retrieval, not a conversion. `DawService` gains
  `isDrumClip`/`clipDrumPattern`/`clipDrumTiming`/`isGrooveClip`/`clipGroove`
  and `replaceDrum|GrooveClipSource` (over one shared `_replaceClipSource`);
  `DrumkitScreen` and `LoopMixerScreen` gain the `onReturnToDaw` callback the
  Tracker already had; `score_router.dart` gains `openDrumPattern`/`openGroove`.
  * the **timing travels with the grid** (`initialTiming` seeds the Kit's
    tempo/swing) — without it a round trip silently re-times the beat to the
    Kit's default, which is a real edit nobody asked for;
  * ghost notes, placement, and **licence provenance** all survive the trip;
  * an edit whose clip was deleted meanwhile lands as a new clip rather than
    vanishing.
  Tests: `daw_drum_groove_roundtrip_test` (10, engine + both UI doors).
  ⚠ One existing assertion had to move: `daw_screen_test`'s "a plain audio clip
  offers no way back" used a demo BEAT as its stand-in for plain audio, which
  was true only while drum clips had no door. It now uses an actual waveform —
  which is what the test always said it was about.
- [x] **C3** Cross-mode "Open a copy in…", routed through `ProjectBridge` with
  its loss report shown BEFORE the conversion runs. Turned out to be **wiring,
  not building**: `shared/widgets/open_in_menu.dart` (another agent's C4)
  already asks the bridge, names each edge's cost in the menu, and gates a lossy
  conversion behind a confirm — but **nothing hosted it**. The Audio Editor now
  does, for clips whose model IS a bridge document (score, tracker).
  * it is a SECOND door, deliberately distinct from the exact "Open in editor"
    above it: that one hands a clip's own model to its own editor and takes the
    edit back into the same clip; this one crosses modes, which always costs
    something. A converted document therefore opens as a **copy with no
    send-back** — routing a lossy conversion into the source clip would quietly
    replace the user's original with a degraded version of itself. "Send to
    Audio Editor" from the target adds a new clip, which keeps both.
  * **Loop is deliberately not offered** — the bridge reaches it, but a loop
    document is the sung user track's cells and seeding a groove from them needs
    the Loop Mixer's own track vocabulary. `OpenInMenu.targets` exists for
    exactly this ("offering one it cannot open would convert the user's work and
    then drop it"). A test asserts the bridge was never the blocker, so whoever
    can seed a groove from cells knows where to look.
  * two bugs the tests caught: score→tab yields a **`TabDocument`**, but the Tab
    Workshop is seeded from a SCORE and does its own fretting (that fretting IS
    the conversion) — so tab now routes the music as a score; and an EMPTY
    tracker song cannot become a score at all (the bridge says so, correctly),
    which made an empty-song fixture hide the case.
  Tests: `daw_open_a_copy_test` (11).
  ⚠ **Known gap, not mine to paper over:** `open_in_menu.dart` is entirely
  unlocalized (its own strings are hardcoded English), so this door is English
  in a de/en app. Localizing it is the widget owner's call — half-localizing it
  from here would leave the dialogs mismatched.
- [ ] **C4** Tab fidelity inbound — string/fret/fingering currently die at the
  door, so Audio Editor → Tab re-frets from scratch.
- [ ] **C5** "Transcribe this clip → notes → any editor" — the honest audio→
  symbolic bridge, explicitly labelled as estimation.
- [ ] **C6** Lane-level send (clip-level exists). **C7** surface the shared rack
  in Tracker/Loop/Tab/Score too, with the chain string as interchange.

**Pillar D — DAW-grade extras** (as pulled)
- [x] **D4 loudness metering** — `crisp_dsp/loudness.dart` + `--loudness`.
  Integrated / short-term / momentary **LUFS**, **true peak** in dBTP, and stereo
  **correlation**. Peak and RMS answer "how big are the numbers"; none of them
  answer "how loud does this SOUND", which is what every delivery target is
  written in.
  * clean-room from the published broadcast standard — K-weighting, the −0.691
    calibration constant, the −70 LUFS absolute gate and the −10 LU relative
    gate are all part of the definition, which is a description of a measurement
    rather than anyone's code;
  * the tests are mostly CALIBRATION, not self-consistency: a full-scale 1 kHz
    sine in both channels reads ~0 LUFS, halving the amplitude costs 6 LU, and
    mono reads ~3 LU below the same thing in stereo. Getting the absolute
    constant wrong is the easiest mistake here and the hardest to notice,
    because every relative comparison still looks right.
  * **gating is the point**: a test pins that padding a master with silence does
    NOT change its loudness, which a naive average would get wrong;
  * **true peak** oversamples before taking the peak, because a signal can sit
    under 0 dBFS at every sample and still overshoot between them — what a
    converter or a lossy encoder then clips. Linear interpolation understates it
    slightly, so it is a floor on the overshoot; that is the safe direction for
    a warning.
  * **correlation** predicts what a stereo meter cannot show you: strongly
    negative material largely disappears when folded to mono, which is what a
    phone speaker does. The CLI flags both risks inline (`⚠ over −1 dBTP`,
    `⚠ mono-fold risk`).
  Tests: `loudness_test` (16).
- [x] **D1 ripple delete / insert** — `rippleDelete` / `rippleInsert` on
  `DawService`, in the marked-range menu beside Silence and Crop.
  * the distinction from the verbs already there is the whole point:
    `silenceRange` cuts audio out and leaves a HOLE, so everything later keeps
    the time it was recorded at; a ripple removes the TIME, so the arrangement
    closes up behind it. Both are wanted, and a test asserts them side by side
    so neither can drift into the other.
  * ripple applies to **every lane**, deliberately unlike its menu neighbours:
    rippling some lanes and not others slides the arrangement out of sync with
    itself, which is never what anyone means. "Just here" is what Silence is for.
  * a clip straddling an insertion point is **split**, not relocated — moving it
    whole would silently move audio the user did not select, and the edit would
    look like it worked.
  * **markers ripple too**, and a marker inside a removed range is DROPPED
    rather than slid to the seam: it pointed at something that no longer exists,
    and relocating it would invent a cue nobody placed.
  Tests: `daw_ripple_test` (16).
- [x] **D6 a real tempo map** — `core/audio/daw_tempo_map.dart`. A single `bpm`
  is enough to draw a grid for a loop and nothing else: the moment a piece slows
  into a section, "one beat = 60000/bpm ms" stops being true, and the grid,
  snapping and any future bar/beat readout inherit the error.
  * the two questions are INVERSES — `beatAtMs` and `msAtBeat` — and the
    load-bearing test is that they round-trip **across a change**. A map that
    gets one direction right and the other wrong looks perfect at a constant
    tempo and desynchronises exactly where it is needed.
  * `bpm` still means the OPENING tempo and still get/sets, so the toolbar and
    every existing caller are untouched; `setBpm` re-tempos the opening segment
    and leaves later changes where the user put them.
  * a mid-arrangement change is **undoable**, unlike the opening tempo: one is a
    setting, the other is an edit to the piece.
  * snapping routes through `snapPosition`, which keeps the plain millisecond
    grid while the tempo is constant (the overwhelming majority) and asks the
    map where the beat actually is when it varies — so the two can never
    disagree. The **grid painter** takes the map for the same reason: "a line
    every N pixels" is not the grid any more.
  * persisted only when the tempo actually VARIES — a constant-tempo project has
    nothing to say that the default does not cover, and an absent key reads
    identically on a build predating D6.
  * ⛔ **gradual tempo curves are deliberately not modelled** (an accelerando as
    a ramp rather than a staircase): different integral, a curve shape per
    segment, and every consumer here asks "which beat is this" — which a
    fine-grained staircase answers to any precision anyone can hear.
  Tests: `daw_tempo_map_test` (21).
- [x] **D3 per-clip gain envelope** — `Clip.gainAutomation`, drawn with the
  existing curve editor from the clip inspector.
  * the lane already had automation, so the question is why a second kind
    exists, and the answer is the anchor: lane automation is anchored to the
    **timeline** and stays put when a clip moves under it (right for a fade
    across a section); a clip envelope belongs to the **take** and travels with
    it (right for riding one phrase). Without it, shaping a single take means
    splitting the clip just to set a gain. A test moves the same clip and
    asserts the shape moved too.
  * indexed from the clip's own start in BOTH render paths, so the windowed
    renderer still agrees byte-for-byte with the full one — an envelope indexed
    from the wrong origin would break that only for clips that do not start at
    zero, which is what the test uses.
  * outside the authored points the multiplier is 1, so a partial envelope
    leaves the rest of the take alone; persisted only when non-empty.
  * seeded flat across the clip when opening the editor on a clip that has none
    — the shared points dialog edits an EXISTING curve and returns null for an
    empty one, so there would otherwise be no way to make a first envelope.
  Tests: `daw_clip_envelope_test` (9).
- [x] **D2 clip groups + nudge** — `Clip.groupId`, `groupClips`/`ungroupClips`,
  `nudgeClips`.
  * grouping exists for the case where two clips ARE one musical event recorded
    twice (a DI and a mic on the same take, a kick and its sub). Sliding one
    without the other ruins the phase relationship that made them worth keeping
    together, and it does so SILENTLY — the mix just sounds worse later.
  * it is a LINK, not a container: each clip keeps its own lane, gain, fades and
    envelope, and what travels is the **delta**, not the position. Members do
    not have to start together (a mic further from the source legitimately sits
    later), and flattening them onto one start would destroy the very
    relationship grouping protects. Pinned by a test.
  * ungrouping ONE member frees the whole group — a group with one member left
    is not a group.
  * **nudge deliberately ignores snapping**: it is for the case where the grid
    is not where you want to be, so re-snapping would defeat the verb. It is
    also the only way to move a clip by a KNOWN amount; a drag lands where the
    finger lands.
  * ⚠ two bugs the tests were written to catch: nudging two members of the same
    group must move it ONCE (collecting members per target and moving each time
    would double the shift), and a project reloaded with group ids above a fresh
    counter must not let the NEXT group collide with an existing one — which
    would silently link clips the user never linked.
  Tests: `daw_group_nudge_test` (17).
- [x] **D5 take lanes + comping** — `Clip.takes` / `takeIndex`,
  `addTake`/`selectTake`/`stackAsTake` on `DawService`, a Takes sheet in the
  clip inspector.
  * `source` stays the ACTIVE take, so the renderer needed **no change at all**
    — takes are a list of alternatives the clip can be swapped between, not a
    new thing to mix. An empty list means one take, which is what every clip
    written before this meant, so behaviour is unchanged everywhere.
  * **comping is deliberately not a fourth concept.** Splitting at a phrase
    boundary and choosing a take per segment IS a comp, and the timeline already
    splits; a dedicated comp API would only duplicate two verbs that exist. The
    load-bearing property is that split is TRIM-based, so a take chosen on the
    second segment plays the second phrase *of that take* rather than restarting
    it — a test pins it with a rising ramp, which flat-level fixtures cannot see.
  * `addTake` seeds the list with the clip's EXISTING source before appending.
    Seeding it empty is the commonest way this feature betrays someone: the
    first "record another" quietly discards the original.
  * an out-of-range `selectTake` does **nothing** rather than clamping — playing
    a take other than the one asked for is worse than refusing, because the user
    hears something and believes it is the take they picked.
  * `stackAsTake` folds a parallel clip in and removes it from the timeline,
    which is how take lanes actually get made: record passes onto lanes, then
    stack them into one clip you can audition. The donor's OWN takes come along,
    and the target is written back **by identity** — a donor earlier on the same
    lane shifts every later index, so writing by the old index would edit the
    wrong clip.
  * persistence stores the alternatives, or they would die at Save (the same
    failure C1 fixed for clip sources), and a take that HAS a model comes back
    as that model rather than a bounce. The **active** take is written as a
    marker instead of a second copy of itself — it is already on disk as the
    clip's own source, and duplicating a take's audio in every project file is
    real cost for no information. A damaged list falls back to a single-take
    clip rather than one whose audible take is missing.
  Tests: `daw_takes_test` (22, incl. the widget half — the sheet must switch
  the take, not merely list them).

**Non-goals** (stated so they are not re-litigated): a real-time audio graph (the
app is offline render-then-play *by design*), third-party plugin hosting, and
editing symbolic models *from* the waveform (that stays behind the explicit
Transcribe door).

### ✅ Audio codecs — native + web at parity — SHIPPED (2026-07-26)

**One-line status:** both platforms read WAV, AIFF, MP3, AAC, FLAC, Ogg-Vorbis
and Ogg-Opus, and write WAV, MP3 (two selectable encoders), AAC and Opus.
Canonical table: **[AUDIO_CODEC_MATRIX.md](AUDIO_CODEC_MATRIX.md)** — keep that
file current, not this section, which is the historical record of how it got
there.

`glint.h` declares `glint_encode_audio(...)` → **MP3 / AAC-LC / Ogg-Opus** in
one call, and `~/code/glint` implements it (`src/encode_audio_c_api.cpp` + a
full CELT Opus encoder). The Dart binding shipped earlier; what was missing was
the native half — `sync_glint.sh` vendored the Ogg-Vorbis DECODE set only, so
the header *advertised* encoders the compiled plugin didn't contain and
`loadGlintEncoder()` returned null on every platform.

Now vendored and wired on all five platforms. The export sheet offers **Opus**
and **AAC** wherever the encoder resolves, and web / any plugin-less platform
sees exactly the pre-existing list (WAV + pure-Dart MP3). The batch stems sheet
inherits it. Was `docs/GLINT_ENCODER_HANDOVER.md` (now deleted — done).

What the pass actually decided, with the measurements behind it:

- **All three codecs, not Opus-only** (the handover's option b). MP3+AAC cost
  only **+268 KB** of dylib over Opus alone; stubbing them would have left
  `GlintEncoder.encode(format: mp3)` silently returning null.
- **`opus_c_api.cpp` taken VERBATIM** even though it names `OpusDecoder` and so
  drags the Opus+SILK decoder in (**+97 KB**, measured). A hand-copied
  `glint_opus_encode_file` would be a fork of glint's muxing logic (pre-skip,
  frame size, packet TOC) that drifts silently into subtly wrong `.opus` files.
  **This plugin forks no glint codec logic**, which is what makes re-running
  `sync_glint.sh` always safe. Bonus: native Opus decode symbols come free.
  Final library 607 KB (was 113 KB decode-only).
- **`glint_free` — verified, not assumed** (the handover flagged it as a
  heap-corruption risk). glint's real definition is exactly `{ std::free(p); }`
  and every buffer reachable through it on the compiled paths is
  `std::malloc`'d. Audit + re-check recipe recorded in `glint_free_shim.cpp`;
  the 2-line shim is correct, not merely tolerable.
- **`sync_glint.sh` now GENERATES** `src/glint_sources.cmake` and the
  `macos/ios Classes/` forwarders from whatever `.cpp` landed in `src/` — a
  vendored-but-unlisted source can no longer become a link error that only one
  platform discovers days later.
- **New local glue** `opus_file_c_api.cpp` (`cometbeat_opus_file_decode`), so
  the round trip is verifiable end to end without pulling in glint's whole
  decode closure. Deliberately NOT `glint_`-prefixed: `flac_c_api.cpp` took the
  `glint_flac_decode` name and glint later defined that symbol itself.

Verification (render → decode → assert, not "it compiled"):

- `native/glint/test/encode_roundtrip_test.cpp` — 34 assertions against the real
  plugin dylib. 440 Hz survives Opus encode+decode by **PITCH** (never sample
  rate: Opus decodes at 48 kHz); hard-panned stereo neither collapses nor swaps;
  MP3/AAC carry valid MPEG/ADTS sync; malformed input is rejected not crashed
  on; 250 encode/free cycles grow RSS by 16 KB. Run it with
  `cmake -B build -DGLINT_BUILD_TESTS=ON native/glint/src`.
- `integration_test/glint_encoder_test.dart` — 7 live tests, **green on a real
  macOS build**. `setUpAll` asserts BOTH loaders resolve; `loadOpusFileDecoder()`
  is the stronger check, since that symbol exists only in our plugin.
- `test/audio_export_format_test.dart` — 17 headless tests for the gating.

**Gotcha this pass found:** a machine with glint `make install`ed has
`/usr/local/lib/libglint.dylib`, and `loadGlintEncoder()`'s last-resort
`DynamicLibrary.open('libglint.dylib')` **resolves it even under
`flutter test`** — so "no encoder in headless tests" is false here. The unit
tests therefore pin the encoder rather than trusting the ambient probe.

**Per-platform status (2026-07-26):** macOS full app build + live integration
test green; **iOS** full `flutter build ios` green (the bundled
`glint_vorbis.framework`, arm64, exports the encoder); **Android** compiles for
all three ABIs via the NDK with 16 KB-aligned LOAD segments; **Linux** builds
under GCC 13 / libstdc++ with the whole round-trip suite green. **Windows**
had a real defect — see below — fixed and proven, with a genuine MSVC build now
running in CI. New workflow `.github/workflows/glint-native.yml` builds the lib
+ tests on all three desktops and an example app on all five platforms, so this
stops being a manual chore.

**Codec matrix (2026-07-26): native and web now agree** — both read WAV, AIFF,
MP3, AAC, FLAC, Ogg-Vorbis and Ogg-Opus, and both write WAV, MP3, AAC and Opus.
Full table + the history of the three asymmetries that were closed:
[AUDIO_CODEC_MATRIX.md](AUDIO_CODEC_MATRIX.md). The root cause of all three: the
shipped wasm exported glint's FULL codec surface from the start, but only
`_glint_vorbis_decode` was wired through to Dart — we shipped the capability and
hid it. Closing them cost +55 KB of native lib (glint's whole-file decoder) and
zero extra web download (same wasm module, more of it reachable).

**Windows bug found and fixed:** MSVC's `<cmath>` does not define `M_PI` without
`_USE_MATH_DEFINES`, and five vendored files use it — the Windows build *would
have failed*. Reproduced exactly (`'M_PI' was not declared in this scope`) by
cross-compiling under strict `-std=c++17`, then fixed in `src/CMakeLists.txt`
rather than in the sources, since `sync_glint.sh` would overwrite any edit to a
verbatim-vendored file on the next re-vendor.

**MP3 has TWO encoders now, user-selectable** (`Mp3Encoder.dart|native`): our
pure-Dart port and glint's C one. Both export sheets show the choice, but only
where both exist. Default stays `.dart` — it is the better-exercised path here
(golden + ffmpeg round-trip tests pin its output) and keeps exports
byte-comparable across platforms; glint's is the more mature encoder and faster,
so flipping the default is reasonable once it has mileage, and it is a one-line
change. Asking for `.native` where glint is absent falls back rather than
failing, because unlike Opus/AAC, MP3 always has a working path.

**The readiness rule (the subtlest bug of the pass).** On web the wasm loads
lazily, so until it resolves every glint-backed decoder returns null — a
FLAC/Opus/AAC import then fails looking exactly like a corrupt file. Nothing
awaited it. Worse, `ensureGlintVorbisReady()` had existed since the `.sf3` work
and was called from **nowhere**, so compressed SoundFonts were quietly broken on
web too. Fixed by making the await impossible to forget rather than by adding
await lines: `importAudioAsync` / `importAudioMonoAsync` / `loadSoundFontAsync`
do it, and every call site uses them. `sample_extractor.dart` deliberately keeps
the sync form (it admits only `.wav`/`.mp3`, both pure Dart) with a comment
saying what must change if that filter widens.

**FLAC and Vorbis stay decode-only, deliberately.** glint ships no encoder for
either, so this is not a wiring gap. For export both are redundant — Opus beats
Vorbis at every bitrate and two `.ogg` producers is a UX trap. The one thing
Opus cannot substitute for is **writing `.sf3`**, which is Vorbis by definition.
Scoped, unclaimed, with the cost honestly split between "minimal correct" and
"competitive with libvorbis": `docs/VORBIS_ENCODER_HANDOVER.md` **in the glint
repo**. Key insight recorded there so nobody re-derives it — Vorbis transmits
its codebooks in the setup header, so a clean-room encoder ships its own and
never needs libvorbis's tuned ones.

**Test ladder** (each layer catches what the others cannot):
`native/glint/test/encode_roundtrip_test.cpp` (ctest, 3 desktops incl. MSVC) ·
`web/glint/codec_roundtrip_test.mjs` (node — the web path shares no code with
FFI above Dart) · `test/audio_import_opus_test.dart` + `audio_export_format_test.dart`
(headless routing/gating) · `test/web/audio_codec_web_test.dart` (Chrome — the
degradation path) · `integration_test/glint_encoder_test.dart` (live build).

**Two unrelated blockers in the separate CrispEmbed repo were fixed to get the
mobile builds through** (neither caused by this work): its Android
`build.gradle` called `exec {}` inside `doLast`, which Gradle 9 removed
(migrated to the injected `ExecOperations` service); and its podspec requires
iOS 15 while the app targeted 13, so the app's deployment target moved to
**15.0** — that drops no hardware, since iOS 15 runs on the same devices as
iOS 13 (iPhone 6s+). **FLAC export stays out: glint decodes FLAC and has no FLAC
encoder.** Native MP3 is reachable through the binding but the export sheet
still offers the pure-Dart MP3 writer, so web and native behave identically —
switching that is a separate, deliberate quality call.

**Tier 4 — the bigger items**
- [x] **O14** Record mic → new lane, via the app's single mic-facing capture
  path (`VoiceClipRecorder`, shared with the Tracker). Guarded like the
  Tracker's: the mic can't run under the headless binding, so the screen
  exposes `debugAddRecordedClip` and the test injects the take. Placement,
  anti-click fade and undo are all covered; the actual capture needs a device.
- [x] **O15** Spectrogram: `core/audio/spectrogram.dart` (STFT over the FFT
  already in `chroma_analysis.dart`; Hann-windowed, calibrated so a full-scale
  sine reads ≈0 dBFS in its own bin) + a painted view opened from the clip
  inspector. Tests assert the physics — tone lands in the right bin, halving
  the amplitude drops it 6 dB, energy stays concentrated, silence floors
  instead of returning −infinity.


## Cross-mode interop — the full matrix, both directions (C-series, 2026-07-27)

Every DAW clip can now move between the five editors and come home. The rule the
whole matrix rests on: **symbolic info is never flattened until an explicit
bounce**, and only the way back from *audio* is a guess.

- **Round-trip + copy doors.** "Open a copy in…" (forks a converted copy) and
  "Open & replace via…" (`fa9dbcda`, edits round-trip back and REPLACE the clip
  so mixing continues on it) coexist via `OpenInMenu`'s `keyPrefix`.
- **Every symbolic kind, every target** (`7164912e`, `d4408aff`). `_clipSymbolicDoc`
  reads a drum beat as a percussion tracker song and a groove as its engraved
  score, so score/tracker/drum/groove all get both doors; Loop is a live target
  (the Loop Mixer is seeded from converted cells via a `GrooveSpec`).
- **C5 — Transcribe-this-clip.** A raw-audio (`SampleSource`) clip has a
  **Transcribe → notation** inspector action: `transcribePcmToScore` (new mono-PCM
  entry in `transcription_service.dart`, pure-Dart monophonic — no model
  download) turns its PCM into a Score added as a NEW `ScoreSource` clip. The
  audio stays; the score is a sibling. This is the one-way door back the matrix
  reserved for an explicit feature (audio has no symbolic model to convert).
- **C4 — tab fretting survives inbound.** `TabDocument.toScore` records each
  string/fret in `Score.tabVoicings` and `fromScore` honours it, so a tab that
  enters the DAW as a score keeps its exact fingering and re-opens in Tab
  unchanged. Corrected the two stale `ConversionReport` messages in
  `project_bridge.dart`: **tab→score is lossless** now, and **score→tab
  approximates only the notes without a stored voicing** — the loss dialog no
  longer warns about a fretting that is actually preserved.

Tests: `transcribe_pcm_to_score_test`, the C5 group in `daw_open_a_copy_test`,
the C4 report group in `interop_fretting_carry_test`; `open_in_menu_test` +
`tab_rig_open_in_test` updated (tab→score goes straight through). The property
suite `interop_report_honesty_test` still passes — a changed round trip never
reports itself lossless.

## Tracker instrument macros (roadmap §4 core, 2026-07-26)

Per-tick instrument MACROS — the classic tracker/Furnace instrument envelope — for
both the additive and the sample voice.

- **Model** (`c2b2647d`). `MacroSequence` (`lib/core/audio/macro_sequence.dart`):
  a raw per-tick step table for a target (volume / pitch / arpeggio / pan / duty)
  with a sustain loop and an optional release segment; pure `indexAt`/`valueAt` +
  JSON, distinct from the point-interpolated `DocEnvelope`. 14 tests pin the
  sustain/loop/release semantics.
- **Additive rendering** (`74885afb`). `AdditiveInstrument` gains an optional
  `macros` list; the per-tick additive voice in `tracker_replayer.dart` adds the
  pitch + arpeggio macro (semitones) to the note and scales amplitude by the
  volume macro (value/64), stepping once per tick from note-on and restarting on
  every (re)trigger. **Opt-in** — with no macros the render is byte-for-byte the
  original (86 replayer/replay goldens green). The instrument codec serializes
  additive macros so they persist.

- **Sample-voice rendering** (`72991462`). `SampleInstrument` gains the same
  optional `macros`; the sample tick voice (`_renderSampleChannelInto`) applies
  the volume macro to per-tick amplitude and the pitch+arpeggio macros to the
  resample read-rate, and a macro'd sample is now routed through the tick path.
  Opt-in — macro-free samples keep the whole-channel dispatch and are
  byte-identical. Codec serializes sample macros.

- **Reachability** (`a88691e2`). `TrackerSong.usesMacros` joins the `renderSongWav`
  routing so a macro'd song uses the tick replayer instead of the fast offline
  path (which renders at a fixed timbre) — macros now actually sound in playback
  for an unpanned song. Macro-free songs are unaffected.

- **Stereo path + pan target** (`ebc5786b`). Macros apply in the stereo tick voice
  (`_renderSampleChannelStereoTicks`) too — so a PANNED song (which renders through
  `replaySongStereo`) modulates — including the PAN target (meaningful only in
  stereo). Additive macros already worked in stereo (that path delegates to the
  mono voice, then pans). Opt-in/byte-identical as everywhere.

- **Mono variable-timing path** (`f63ff336`). Macros apply in the variable-timing
  render too (`_renderChannelIntoVariable` additive + `_renderSampleChannelIntoVariable`),
  so a non-default-speed / mid-song-tempo-change song modulates. Opt-in/byte-
  identical (109 golden + variable tests green).

- **Macro editor UI** (`38cb9702`). An "Instrument Macros" section in the Sample
  instrument editor: add/remove one macro per target and shape it in a
  drag-to-set bar editor with step-count and loop/release pickers, backed by pure
  `MacroSequence` helpers (`rangeOf`/`defaultFor`/`withValueAt`/`withLength`).
  Macros are now user-authorable and persist. Also fixed a latent
  `SampleInstrument.copyWith` that dropped macros.

- **Long tail — all shipped (2026-07-27).** §3.3 block-op test seams + coverage
  (`tracker_block_ops_test.dart`); an **additive-voice macro editor** + Sound-Lab
  interop (`b9ac7745`); macros made **airtight across every render/export path**
  (`310fd820` — a macro'd song routes off the state-restarting per-chunk streamers
  onto the whole-song replay that applies macros, so playback AND bounded export,
  mono AND stereo, uniform/variable/flow all modulate); and a **pulse/square
  voice** (`PulseInstrument`, pickable) driving the **duty** target (`4250f83d`).

**§4 is complete:** model → additive + sample + pulse voices → mono + stereo →
uniform + variable + flow → playback + bounded export → codec-persisted →
authorable in the instrument-editor UI. Opt-in and byte-identical throughout.

## Tracker DSP lifted into the shared editors (2026-07-26)

A user-requested sweep to make the tracker's DSP reusable in the Audio Editor and
Tab Editor. Five pieces shipped; the two remaining polish items were handed to the
active `daw-suite` agent to avoid collisions on the export surface (see PLAN.md).

- **Shared LFO + auto-wah** (`d3d17b70`). Extracted the tracker's `trackerLfo`
  into `crisp_dsp/lfo.dart` (`lfoValue`; the replayer now delegates to it,
  byte-identical). Added `FxType.autoWah` — an **LFO-swept resonant low-pass**
  (the wah/filter-wobble the rack lacked; the static resonant LP already existed
  as `lowpass`+`q`), built on the shared LFO and the biquad's click-free
  `setFreq`. Wired into `fx_params` (label, filter category, Sine/Ramp/Square
  picker), so it appears in every mode's FX rack — the Audio Editor chains and the
  Tab guitar rig included.
- **Tab techniques are audible** (`22420a4b`, `aecf508e`, `d43999d3`).
  `renderTabBandThroughTracker` routes tab playback through the replayer, so a
  column's playing techniques — already emitted as effect commands (slide→`3xx`,
  vibrato→`4xy`, bend→`1xx`) — actually sound. The replayer gained an opt-in
  `replaySong(articulateProcedural: true)` that **bakes a procedural voice to a
  one-shot sample** so per-tick pitch reaches it (the tab's default plucked string
  is procedural); DEFAULT OFF, so every module/tracker render stays
  byte-identical. Surfaced as an opt-in "Articulate techniques" toggle in the Tab
  Workshop.
- **Bounded-memory DAW export render core** (`9244b14b`). `streamTimelineWav` +
  `dawTimelineLengthSamples` (`daw_timeline.dart`) render a timeline to 16-bit
  stereo WAV in fixed-size windows via `renderTimelineWindowStereo` — one window
  of memory instead of the whole-song mix, byte-identical to
  `pcmFloatToWav(renderTimelineStereo(...))` and independent of block size.
- **Richer tab articulations** (`d65ed301`). Dead/muted note → percussive `ECx`
  note-cut; ghost note → soft `Cxx` set-volume (lower priority than the pitch
  techniques; the side-car keeps the full set for exact round-trips).
- **OPL2/AdLib as a pickable app voice** (`8209adbc`). Two YM3812 presets (an FM
  lead + an additive organ) in `kOplPresets` are exposed as `InstrumentOption`s in
  `kTrackerInstruments`, so the authentic AdLib FM chip is selectable everywhere
  the voice list is used — Settings, the voice picker, the tracker, and as a
  tab/score voice (distinct from the generic 2-op `FmInstrument`). `OplInstrument`
  now retains its raw patch bytes so it round-trips through the instrument codec.

Each piece is unit-tested; all pre-existing goldens stayed byte-identical.

## Audio codecs — native + web at parity (2026-07-26)

Completed `GLINT_ENCODER_HANDOVER.md` (now deleted) and then kept pulling the
thread. Canonical per-platform table:
[AUDIO_CODEC_MATRIX.md](AUDIO_CODEC_MATRIX.md).

**Result.** Both platforms read WAV, AIFF, MP3, AAC, FLAC, Ogg-Vorbis and
Ogg-Opus; both write WAV, MP3, AAC and Opus. MP3 has two selectable encoders
(our Dart port, default; glint's native one). FLAC/Vorbis stay decode-only —
glint ships no encoder for either.

**Native.** Vendored glint's encode closure into `native/glint` and wired it on
all five platforms. Two decisions worth remembering: took **all three codecs**
rather than Opus-only (MP3+AAC cost only +268 KB, and stubbing them would leave
`encode(format: mp3)` silently returning null); and took `opus_c_api.cpp`
**verbatim** even though it drags the Opus+SILK decoder in (+97 KB), because a
hand-copied `glint_opus_encode_file` would be a fork of glint's muxing logic
that drifts silently into subtly wrong `.opus` files. This plugin forks no glint
codec logic, which is what makes re-running `sync_glint.sh` always safe — and
the script now GENERATES the CMake source list and the Apple forwarders, so a
vendored-but-unlisted source can't become a link error one platform finds days
later. `glint_free` was verified, not assumed (glint's real definition is
exactly `std::free`, every buffer is `malloc`'d) — the handover had flagged it
as a heap-corruption risk.

**Web.** The shipped `glint.wasm` had exported the FULL codec surface all along
(`_glint_encode_audio`, `_glint_decode_audio`) while only `_glint_vorbis_decode`
was wired to Dart — we shipped the capability and hid ~5/6 of it. Exposed via
`web/glint/glint_codec_web.js` at **zero extra download** (same module the
Vorbis shim already loads).

**Three asymmetries closed**, each invisible until someone looked: `.opus` was
write-only (an Opus file passed the picker, missed every branch and returned
null — you could export a mix and not reopen it); AAC was write-only on native
while web could read it; FLAC didn't import on web at all. Ogg containers are
now disambiguated properly (Opus before Vorbis; ADTS before MP3, since both
start `0xFF` and the loose MP3 sync scan also matches an ADTS header).

**A readiness bug, one new and one old.** The wasm loads lazily, so until it
resolves every glint-backed decoder returns null and an import fails looking
like corruption. Nothing awaited it — and `ensureGlintVorbisReady()` had existed
since the `.sf3` work and was called from **nowhere**, so compressed SoundFonts
were quietly broken on web too. Fixed by making the await impossible to forget:
`importAudioAsync` / `importAudioMonoAsync` / `loadSoundFontAsync`.

**Windows was genuinely broken.** MSVC's `<cmath>` doesn't define `M_PI` without
`_USE_MATH_DEFINES` and five vendored files use it. Reproduced exactly under a
strict-ANSI cross-compile, fixed in `src/CMakeLists.txt` rather than in the
sources (`sync_glint.sh` would overwrite those), and confirmed on a real MSVC
CI run. CI then caught a second, self-inflicted one: `<windows.h>`'s `min`/`max`
macros mangling `std::min`, fixed with `NOMINMAX`.

**Two blockers in the separate CrispEmbed repo** were fixed to get mobile
building: a Gradle-9-removed `Project.exec()` call, and an iOS-15 podspec against
an app targeting 13 (raised to 15 — iOS 15 runs on the same devices as 13, so no
hardware dropped). Plus an `onnxruntime` `compileSdk 33` pin. **The app's Android
build works for the first time** and is CI-guarded.

**Verification.** New `.github/workflows/glint-native.yml` builds the library and
runs the round-trip tests on Linux/macOS/**Windows**, runs the wasm suite under
node, and builds an example app on all five platforms; `ci.yml` gained an
`android-build` job that asserts `libglint_vorbis.so` is actually inside the APK
and a Chrome run for the web seams. Test ladder:
`native/glint/test/encode_roundtrip_test.cpp` · `web/glint/codec_roundtrip_test.mjs` ·
`test/audio_import_opus_test.dart` · `test/audio_export_format_test.dart` ·
`test/web/audio_codec_web_test.dart` · `integration_test/glint_encoder_test.dart`.

**Follow-up scoped, not started:** a clean-room Vorbis ENCODER, whose only real
use is writing `.sf3`. Handover in the glint repo
(`docs/VORBIS_ENCODER_HANDOVER.md`); the fact that makes it viable is that
Vorbis transmits its codebooks in the setup header, so an encoder ships its own.

## DAW & Score-Workshop UX pass (2026-07-25)

A sweep across the authoring surfaces (Audio Editor, Score Workshop, Sound
Library), web/touch-first, each slice unit/widget-tested:

- **Audio Editor:** a guide/help overlay + a "linked to editor" badge on
  round-trippable clips; a responsive app-bar toolbar that folds into a "more"
  menu on narrow widths (with the bottom control strip bounded + scrollable);
  keyboard shortcuts (Space play/stop, Delete selection).
- **Score Workshop:** editable title/composer/lyricist on the details dialog,
  carried into the PDF (title block) and MusicXML exports; the info button now
  explains the controls, not only shortcuts; "Share/Load shared tune" renamed to
  the honest **Copy/Paste tune**; the inline lyric field no longer loses
  keystrokes to the A–G note-entry shortcuts; harmony "colour by analysis" now
  paints the multi-part full-score canvas; **export downloads on the web** (was
  desktop-save only); bar numbers show on one-system scores in every mode
  (engine now numbers the first system too).
- **Sound Library:** an accurate reason + working "open source" fallback for web
  instrument install; the one unified browser (catalog · music · Mod Archive ·
  SoundFont · import) is guarded against regressions.

## Tracker module fidelity (2026-07-25)

Advanced Tracker now imports, edits, live-plays, and CLI-renders MOD, XM, S3M,
and IT content through the shared tracker song/replayer path. Recent fixes
removed long IT render OOM/distortion, preserved variable row timing and
per-tick effects in bounded long renders, exposed the normalized command
families in the editor, and made native stereo samples visible and audible in
the instrument editor. The current limitations are recorded in
`mod_pending.md`; downloaded music used for A/B checks remains local-only until
licensing is documented.

- **Stars persist** (`ProgressService`): best stars/score and play count per
  game, shown on every game tile.
- **Star-driven difficulty**: 2+ stars widen a game's material (reading
  games gain the ledger range incl. middle C; Scale Detective gains D and A
  major; Measure Filler gains sixteenths). More expansions per game over
  time — SM-2 mastery stays the long-term signal, stars the session signal.
- **Soft unlock gating**: a module unlocks once the *previous* one has
  ≥ `kModuleUnlockTracked` SRI-tracked items (the child genuinely played
  there). Engagement gate, not a mastery gate — mastery gating proved too
  slow for a 6-year-old's first week. Locked cards explain what to play
  first.

## Audio (v1)

`core/audio/synth.dart` synthesizes everything in pure Dart — no assets, no
licensing: piano-ish additive tones (pitches, chords, arpeggios, sequences)
rendered to WAV and played via `audioplayers` (data-URI source on web), plus
CrispFXR-style retro square-wave SFX (correct blip, wrong buzz, fanfare —
same procedural approach as the maintainer's
[CrispFXR](https://github.com/CrispStrobe/CrispFXR-web) /
[crispaudio](https://github.com/CrispStrobe/crispaudio) projects, in Dart).
`AudioService` wires it app-wide; feedback sounds run centrally through
`QuizRoundMixin`. First ear game shipped: Major-or-Minor.

**Selectable instrument voices:** the synth carries four timbres — piano, a
reedy sustained **cello**, a soft **flute**, and a bright fast-decaying **music
box** — each a distinct harmonic profile + attack/decay. Settings has an
instrument picker (icon chips, previews on tap); the choice persists and drives
all pitched playback app-wide (retro SFX unchanged).

## Textbook (read-through curriculum)

A read-through learning path over the grade-1–10 concept map (`core/curriculum/concept_map.dart`): the **Textbook** screen (📖 in the home bar) lists each grade band's concepts; a concept expands to its **lesson** (the same zero-knowledge primer the games auto-show — see it, hear it) and **practise** links straight into the games that train it. Concepts with no game yet show "coming soon", so the path stays honest against the coverage gap analysis. Built on the same concept inventory + primers as the gap-analysis tooling.

**Fully localised + narrative (de/en).** `features/textbook/textbook_i18n.dart` (ARB-backed) localises all 70 concept titles, the 19 concept-area sub-headers and the 5 grade-band short labels, and supplies a **narrative intro paragraph per grade band**. Each band's concepts are grouped **by area** (sub-headers in first-appearance order, so the map's teaching sequence is preserved), so the reader reads like a book rather than a flat list.

**Per-concept lesson prose + AnaVis form-analysis view** (`2f63709`). Two connected additions to the reader. (1) Each concept can carry the textbook's **own teaching paragraph** — richer than the borrowed game primer, in the book's voice, our own words — shown at the top of the expanded concept tile above "Read the lesson". `conceptProse(l10n,id)` (`textbook_i18n.dart`) is **fallback-safe** (null where unauthored, so the block just doesn't show), so prose coverage grows concept by concept; it now covers **all 70 concepts** (EN+DE) — a test pins that every `kConcepts` id has non-null prose in both locales — so the whole read-through has the book's own voice, not just borrowed game primers. (2) An **AnaVis-style form-analysis view** (`features/games/composition/form_analysis_view.dart`) — a non-quiz reading of a piece's form as a colour-coded, tappable section timeline (built on the same `FormTimeline` as the "Label the Form" game): tap a coloured block to hear that section (a highlight ring marks it), or play the whole piece. Worked examples are our own abstract A/B/C/D motif renditions (no melody-licensing risk): ternary + rondo for `musical_form`, verse-chorus + AABA for `song_form`, surfaced as a **"See the form"** lesson on those concepts' tiles. `FormTimeline` gained an optional `onTapSection` (additive; the game stays inert). The form view engraves a real `crisp_notation` score (one 4/4 bar per section) **above** the coloured blocks, so the barlines line up with the sections. A companion **`HarmonyAnalysisView`** colours a chord progression by **harmonic function** — tonic (home/green), subdominant (away/blue), dominant (tension/orange), with a legend and tap-to-hear — with worked progressions (I–IV–V–I, ii–V–I; perfect vs half cadence) wired into the `harmonic_function` / `cadences` tiles as **"See the harmony"**. The harmony view engraves the progression as a real score too — one 4/4 bar per chord as a whole-note chord (`NoteElement` with stacked pitches) — with the T/S/D colour spans aligned bar-for-bar beneath it, and a cadence marker under the final chord of the cadence examples ("comes to rest" / "left open"). Both views, plus a standalone **`AnalysisHubScreen`** reached from a **"See the Music"** sandbox tile (`analysis_view`, composition module), realise the AnaVis analysis-view idea end to end — score, colour-coded form/function spans, and cadence points.

**Notes light up as they play (across every lesson + example).** Playback is a fire-and-forget rendered WAV, but the schedule is always known (each note carries a ms duration), so a reusable **`PlayingStaffView`** (`features/games/widgets/playing_staff.dart`) drives crisp_notation's existing `StaffView.highlightedIds` (repaint-only) on a Ticker started with the sound — the same primitive the play-along note-highway uses, packaged for reuse (`ScorePlayback.play(List<PlayStep>)`). The tutorial sheet — which backs BOTH the textbook's "Read the lesson" and every game's "?" how-to — now animates its engraved example: `TutorialStep` gained a `beats` field and all 41 primer melody steps were converted to it, so from one change every lesson and every game primer shows the notes progressing as they sound. The form and harmony analysis views light each section/chord in turn too.

**Every score-and-play minigame swept.** `ReadingStaffView` gained an optional `playback` controller (delegating to `PlayingStaffView`, which learned `showNoteNames`) so the reading games light their notes *without losing* the note-name scaffold. All the games that show a score and play a melody now animate: `ending_detective`, `spot_upbeat`, `melody_echo`, `question_answer` (two staves, coordinated so the question lights during the question and the tapped answer during the answer), `tie_slur`, `beam_flag`, `whole_half`, `articulation_read`, `sync_read`, `triplet_read`, `ornament_read`, `enharmonic`, `step_skip`, `rhythm_tap`, and `my_melody` (its dual InteractiveStaff/StaffView composing modes both take `highlightedIds`). Only the N-rung `interval_ladder` is left (a per-rung job with low payoff).

**Responsive layout pass (answer buttons centered + an overflow audit).** The two options in the binary games stretched full-width, so on a tablet they flew to the far left and right edges. New **`AnswerRow`** (`features/games/widgets/game_widgets.dart`) is the binary counterpart to `AnswerGrid`: `Center` + `maxWidth: 480`, so the options sit near the middle on wide screens and are unchanged on phones — wired into 12 games (`tie_slur`, `beam_flag`, `enharmonic`, `whole_half`, `same_diff`, `modulation_ear`, `direction_ear`, `run_direction`, `spot_upbeat`, `sync_read`, `triplet_read`, `triad_seventh`) as a plain `Row(` → `AnswerRow(` swap. A new **`test/layout_audit_test.dart`** pumps *every* registered game at iPhone SE 375×667 in EN and DE and asserts no RenderFlex overflow (via `takeException`, no taps) — a standing regression guard for small screens (German runs longer and is where overflows hide). It caught and fixed a `_PlayRow` overflow in the analysis views on a 375px phone (the long localized "Play the whole piece" button → a Column so the hint wraps beneath).

**Read-aloud narration (TTS).** A 🗣 read-aloud button in the shared tutorial sheet speaks the current lesson/how-to step, so a pre-reader (6–8yo) can *hear* it before they can read it — the same sheet backs both the textbook's "Read the lesson" and every game's "?" primer, so both narrate from one change. `core/services/tts_service.dart` wraps `flutter_tts` (on-device platform voices, offline, de+en) behind a `TtsBackend` seam; locale-aware, gated by the master sound switch, best-effort (a missing OS voice just stays quiet).

**Neural voice (CrispASR / Kokoro).** Behind the same seam, `core/audio/tts/` adds a higher-quality on-device backend: the `crispasr` pub FFI package → `libcrispasr` (ggml) running **Kokoro** (82 M params, Apache-2.0, de+en). Model files come from CrispASR's **own registry + downloader** — `registryLookup('kokoro')` resolves the already-published `cstr/kokoro-82m-GGUF` model and `cacheEnsureFile` fetches it into `~/.cache/crispasr` (the same `-m auto` path the CLI and CrisperWeaver use); no hand-rolled URLs, nothing to publish. Resolve + download + synthesis all run in a background isolate (→ 24 kHz PCM → WAV → AudioService); a conditional-import facade keeps dart:io/ffi out of the web build (web → null stub). Downloading is consent-gated (playback never fetches; an opt-in `download()` mirrors CrisperWeaver's model manager), and `TtsService` prefers the neural voice when the lib + model are present, else the platform voice. Registry resolution + the real macOS synth are test-verified. A **"Natural voice (HD)" tile** in Settings (below the sound switch) is the opt-in: it appears only where the native lib loads, downloads the ~135 MB model on tap (spinner → "On ✓"), and once cached narration auto-upgrades to the neural voice. **macOS bundling** is scripted (`tool/bundle_macos_tts.sh` collects `libcrispasr` + its 8 ggml/opus deps into a self-contained, `@loader_path`-only set — verified by running synthesis through it) and the store resolves the dylib from the `.app` Frameworks or `~/.cache/crispasr`; see `docs/TTS_MACOS.md` for the dev flow, the release Frameworks embed, and App-Store caveats. The release `.app` embed + iOS/Android/web libs are the remaining steps.

## Composition Workshop

A section *outside* the minigames (home-bar piano button) — a full touch- and
desktop-first score editor built on an editable `ScoreDocument` (a flat element
stream packed into bar-lined measures, with multi-level undo/redo). The grown-up
sibling of the My Melody sandbox. What it does now:

- **Entry** — pick a note value (whole…sixteenth, dotted) + accidental; write by
  tapping the staff, tapping the on-screen **sweepable piano** (C1…, octave
  labels), or the **computer keyboard** (A–G pitches, 1–5 values, R rest, arrows,
  `.` dot, `S` slur, Del, ⌘/Ctrl Z·Y·C·X·V). A blank-staff click *places* a new
  note (like a piano key); an existing note is re-pitched by dragging it up/down.
- **Chords** — a ⧉ toggle stacks pitches at one timeslot; the model is multi-pitch.
- **Selection & editing** — tap to select, **marquee** (⛶ rubber-band) to select
  a range; move/copy/cut/paste, transpose (↑/↓), set duration/accidental, delete.
  **Fine drag-reorder**: a horizontal note drag moves it to the exact drop slot
  (across bars and wrapped lines); a vertical drag re-pitches.
- **Notation** — dynamics · articulations · ties (anchored palette) · **slurs** ·
  **crescendo/diminuendo hairpins** · **multi-verse lyrics** (inline field +
  verse selector) · **pickup / anacrusis** (top-bar dropdown) · a visible
  insertion **caret** · single staff or **grand staff** (auto-split by pitch).
- **Chrome** — clef/time/key/zoom/pickup fold into one top row; an (i) sheet
  lists the keyboard shortcuts; leaving with unsaved work asks keep/discard/save;
  the engraving width is bound to the viewport so systems break on-screen.
- **I/O** — a single **Open…** picker reads any supported score by extension —
  MusicXML (+ compressed `.mxl`), MIDI, ABC, MEI, Humdrum `**kern`, MuseScore
  (`.mscx`/`.mscz`), GPIF (`.gp`/`.gpx`) — and a single **Export…** sheet
  writes MusicXML/`.mxl` · MIDI · ABC · MEI · `**kern` · MuseScore · LilyPond ·
  Braille · **SVG** (font embedded) · **PNG**, saving via the system dialog (text
  formats fall back to a copyable view where a platform has no save picker). All
  parsers/writers are pure-Dart (web-safe). Also save to the Song Book. The macOS
  file pickers work now (added the `files.user-selected.read-write` sandbox
  entitlement — the app is sandboxed, so without it the dialogs were blocked).

Notation-depth + Studio-shell + playback arc (2026-07, the parity push):

- **Notation depth** — **tempo marks** (initial `Score.tempo` + mid-score
  `Measure.tempoChange`), **grace notes** (a per-note pitch list, acciaccatura/
  appoggiatura), **ornaments** (trill/mordent/turn), **tuplets**, **mid-score
  clef/key/time changes**, **mid-*bar* clef changes** (`inlineClefs`), **repeats +
  voltas + navigation** (D.C./D.S./coda/segno/fine), and `RhythmPolicy.split` (tie
  over-long notes across barlines). All built on one id-anchor/field pattern on the
  flat document, all lossless through the MusicXML save→reopen.
- **Two voices** — an optional **voice 2** per part (`Measure.voice2`) with a
  V1/V2 toolbar toggle; the flat doc keeps `_v1`/`_v2` and the active voice drives
  entry, so the mutation sites are untouched.
- **Studio shell** — a **Sandbox/Studio shelf** toggle reveals grown-up depth
  (an **Insert/Select** input-mode toggle and a selection-driven **inspector**
  panel) together, while the kid Sandbox surface stays simple.
- **Playback** — a real **transport** with a moving cursor that highlights the
  sounding notes; **multi-part** playback mixes every part into one WAV with a
  **per-part mute**; a **practice-speed** control (0.5×/0.75×/1×) slows playback
  without changing pitch. Reflects repeats/navigation/split via the timeline.
  Two opt-in practice tools (⋮, default off): a **count-in** — a bar of clicks
  rendered into the same WAV so it can't drift from the music, counted in the
  meter's own beat unit — and **loop selection**, which repeats the selected range
  until Stop, clipping every part so the accompaniment loops with the melody.

Editing extras that lean on crisp_notation's editor contracts: caret (C2), drag-move
(C3), grand staff (C5), element hit-regions for marquee + fine reorder
(**C7** `ElementRegionController`), and one-call `Score→PNG/SVG` export
(**C8**). Detail + roadmap: `docs/WORKSHOP_PLAN.md`.

## Guitar tablature editor & GPIF export

A sibling of the Composition Workshop over the same model — a touch-first
**tablature editor** (`TabDocument`, `TabStaffView`) with per-string fret entry,
chords, tab techniques (bends & contours, hammer-ons, slides, vibrato, dead/ghost/
harmonics) and selectable tunings.

- **Cost-based fret arranger** — `tab_arranger.dart` runs a Sayegh'89 optimum-path
  Viterbi over per-column candidate frettings, minimising hand-movement +
  chord-span + low-neck cost, honouring `Score.tabVoicings`, capo-aware. Beats the
  greedy lowest-fret placement for playable shapes. An optional `TabPositionModel`
  seam lets a future data model supply the local term while the playability
  constraints stay ours.
- **GPIF I/O** — reads every version (`.gp3`/`.gp4`/`.gp5` binary, `.gpx` BCFZ/BCFS,
  `.gp` v7/8 ZIP; all clean-room in `crisp_notation`) and **writes `.gp`** (menu
  "GP tab (.gp)"). The writer now **preserves the arranged string/fret choices** —
  it re-fretted every pitch with the greedy `fretFor` before, silently discarding
  the arrangement; `scoreToGpif`/`multiPartToGpif` now honour `Score.tabVoicings`
  and an explicit `frettings` plan, so both the GUI export and the CLI keep the
  player's positions and techniques. Multi-part scores export one track per string
  set.
- **Round-trip fidelity push** — after a cross-format audit (gp→abc→gp,
  jams→gp→jams, gp→gp idempotence), the subset writer was widened to preserve what
  it used to drop: **voice 2** (polyphonic staff), **tuplets** (was distorting
  timing — a triplet bar read back 3.5 beats instead of 3.0), the **key signature**
  (incl. mid-score changes), **dynamics** (PPP…FFF), **staccato/accent
  articulations**, **grace notes** (as `BeforeBeat` grace beats) and **lyrics**
  (per verse, syllables+hyphens). Each is symmetric writer+reader with a
  round-trip test; a non-tuplet, C-major, single-voice score with no lyrics stays
  byte-identical (the golden fixture is unchanged). The only remaining subset
  limit is clef — N/A for a fretboard/tab format.
- **`bin/tabconv.dart`** — a headless "any notation → `.gp`" converter (ABC / MIDI /
  MusicXML / MuseScore / MEI / kern / GPIF / JAMS melody), running the arranger so
  the frets are playable; `--tuning`/`--capo`/`--no-arrange`/`--from`, multi-part →
  one track per part, and a warning when the chosen instrument physically can't
  reach some notes. Round-trip-verified across every codec (pitches, chords,
  techniques survive gp→gp, idempotent, alt tunings, capo).
- Referred to throughout as **GPIF** and by file extension (`.gp`/`.gpx`) rather
  than the proprietary product name.

## Live microphone & pitch detection

The app's first **real-instrument input** (the structural gap every strong rival
had and we didn't). Pure-Dart chain: mic → PCM → pitch/chroma analysis, no
plugins beyond capture.

- **Play-along / Sing-along** — a **moving score**: target notes scroll
  right-to-left past a fixed "now" line while your live pitch is drawn as a dot,
  so you see yourself land on (or drift from) each note. Scoring is a pure
  `PlayAlongEngine` (right pitch — optionally octave-agnostic for voices —
  within a cents window for enough of the note); the screen just drives the
  Ticker clock, feeds it mic readings, and paints. No audible backing on purpose
  (the mic would hear the speaker; a Preview button plays it first).
- **Sing along / Play along with any Song Book song** — the song viewer has both
  buttons; each derives a target melody from the song's notation (`chartFromScore`
  — top pitch per note, timed from the playback timeline) and drops it into the
  same moving-score highway. **Sing along** is octave-agnostic (match it in your
  own range); **Play along** targets the written octave, for an instrument. Stars
  scale to the song's length (`scaledStarScore`), so a long song isn't a free 3★.
  Turns the Song Book (and the groove→Song Book export) into practice material.
- **Tuner** (cello corner) — open the mic, detect the note, show cents sharp/
  flat on an intonation meter. The whole chain mic → PCM → detector → meter.
- **Chord Listener** — fuzzy chord recognition from the live mic: strum/play a
  chord and it names the closest match with runner-up guesses and the 12-bin
  pitch-class profile it heard (chroma analysis — "name the chord" beats
  "transcribe every note").
- **Perform It** (note reading) — mic-graded *reading*: a note is shown and the
  child **plays or sings it** — the pitch detector verifies it (octave-agnostic,
  held briefly to avoid false hits) instead of a letter tap. Live detected-note
  readout, star-gated range, skip button, mic-permission handling; feeds the
  shared `note_reading.<clef>.*` SM-2 pool. The kid-scale core of performance-
  graded sight-reading.
- **Sing Back** (scales/ear) — ear→voice: a note *plays* (not shown), the child
  **sings it back**, and the mic checks the pitch (octave-agnostic, held
  briefly). A "hear it again" button, the answer reveals on a correct sing, skip
  + mic-permission handling. Trains pitch memory and matching with no instrument;
  feeds the ear pool `scales.hear.sing_<step>`.
- **Sing the Interval** (Chords) — ear→voice on the *interval*: two notes play,
  low then high, its name is shown ("a fifth"), and the child **sings the top
  note back** (mic checks the pitch class, octave-agnostic). The sung twin of
  Interval Ear — builds interval vocabulary *and* the voice to reproduce it.
  Reuses the Sing Back capture harness + crisp_notation's `Interval` /
  `Pitch.transposeBy`; third/fourth/fifth for beginners, second + sixth at 2★.
  SRI `intervals.sing.<name>`.
- **Cello Play It** (Cello Corner) — mic grading on the *real instrument*: a
  first-position note is shown on the bass staff with a string + finger hint;
  the child bows it on their cello and the mic verifies the pitch
  (octave-agnostic — kind to the low C string — held a touch longer to shrug off
  the bow's scratchy attack). "Hear it" + skip buttons, mic-permission handling.
  Turns the finger/string knowledge active; feeds the cello play pool
  `cello.play.<step><octave>`.

## Curriculum (Lehrplan alignment)

A **Curriculum** screen (home-bar 🏫) that maps the games onto a syllabus.
Deliberately **un-branded, generic progress levels tied to school years**
(Klasse 1–2 … 9–10) — the topic scope distilled in our own words from public
school curricula, no badge/association branding. A small data engine
(`Curriculum → Level → Topic → gameIds`) with topic labels reused across levels;
per-region variants are drop-in data (`region` field).

- **Readiness** per level/topic = **star coverage × SM-2 retention**: breadth
  (played + performed the games) modulated by whether skills actually stuck
  (`SriService.masteryUnder(namespace)` — mean per-item mastery, neutral until a
  namespace is practised so there's no discouraging cold start).
- Study guidance: a **"continue here"** marker on the recommended level, and
  **"practise your weakest topic"** — both running curated recitals of the
  relevant games. A test guards every mapped game ID against the registry.
- Internal licensing rationale (why no D-branding) lives in the gitignored
  `CLAUDE.md`, not here.

## Playtest cycle — polish, reworks & tools

A full parent/child playtest pass. Grouped by kind.

**Correctness & UX fixes:** Symbol Quiz renders note/rest **on a staff** (rests
now identifiable) · Rhythm Echo **sounds from the first tap**, rings while held ·
Sort the Beats — much **larger bucket glyphs** + the bottom **mascot reacts** ·
Connect columns pulled **close together** · Line or Space is **tappable** (+
arrow keys), not swipe-only · Falling Notes **starts ~half speed** · Triad
Builder is a **single measure** (taps land where the note appears) · My Melody
uses an **adaptive clef** (a cello's low C shows in bass) · Song Book karaoke
highlight **no longer drifts** behind the audio · Cello "Which String?" is scoped
to the **open strings** (unambiguous).

**Pedagogy reworks** (games that "made no sense"): **Follow the Conductor** →
real **conducting patterns** (metre/downbeat) · **Beat Runner** → a **rhythm-
reading lane** (note-value markers spaced by their true durations) · **Scale
Detective / Builder** → harder, into **minor keys** (harmonic minor defeats the
spot-the-accidental shortcut) · **Sound Echo** → noteheads on the pads with
**cues that fade** (colour → sound → read alone).

**Deeper features:** Melody Echo **lights notes L→R** as a card plays · Melody
Dictation **edit-in-place** (tap a note to re-pitch/delete) · **bass-clef
variants** of Line or Space, Note Order, Falling Notes and Connect (violin +
bass, own SRI + stars) · **keyboard control** app-wide (number keys select any
answer grid; arrow keys drive Line or Space & the Conductor; space/enter the
rhythm lane; C–B letter keys catch Falling Notes) · **Progress "tricky spots"**
now shows every skill (coloured module icons, skill-typed labels), not just
notes · **Tenor Clef reading** is gated as an advanced unlock — the tile shows
locked until the child has 2★ in both other Cello-Corner games (a general
per-game `unlockedWhen` gate on `GameInfo`).

## Opportunity backlog — shipped

- **Note-naming toggle:** German H/B, English, solfège — one setting, every
  drill. Reinforces EN/DE.
- **Daily streak + practice calendar** (flame + count + 7-day dots on home;
  finishing a game marks the day).
- **"Wait mode" pacing** — advance only on the correct answer, no timed fail
  (`QuizRoundMixin` retries until correct, no timers/lives anywhere); guarded
  by a contract test.
- **Reacting mascot** — a pure-Dart quarter-note character in the shared
  feedback line: hops + grins on correct, damped wobble + "oops" on wrong;
  reduced-motion aware.
- **Opt-in timer + beat-your-time** — off by default; when on, the result
  screen shows completion time + personal best + "new best!" (no live clock).
- **Bilingual EN/DE pedagogy** foregrounded — the note-naming toggle advances
  it in-app; the rest is positioning.
- **Weak-spot ear engine + "your tricky notes"** — `SriService.weakestItems`
  + a card on the Progress screen with readable labels; SM-2 re-drills them.
- **Functional cadence → scale-degree ear mode** — "Hear the Function"
  (harmony): a I–IV–V–I cadence establishes the key by ear, then a target
  chord is named T/S/D. SRI `harmony.hear.*`, review-routed.
- **Landmark / intervallic reading hints (fading)** — the Reading Quiz shows a
  landmark chip ("a skip up from E") anchoring on memorized lines + middle C;
  fades with mastery (gone at 3★ and in review). `reading_hint.dart`.
- **Written melodic dictation** — **Melody Dictation**: a melody plays (audio
  only), the child writes it by tapping noteheads onto the InteractiveStaff,
  per-note feedback + undo + note-for-note check. SRI
  `note_reading.dictation.len3`. (Rhythm dictation served by Rhythm Echo.)
- **Removable colour scaffold** — Settings toggle "Colour helper for beginners"
  (off by default) tints noteheads + choices by pitch class (Boomwhacker,
  `note_colors.dart`) in Reading Quiz + Place the Note, with a legend.
- **Play-in-time lane** — **Beat Runner**: note-value markers fall spaced by
  their REAL durations over a steady click; tap each as it crosses the
  hit-line. Ticker master clock, space/tap, Perfect/Good by accuracy.

## Gamified formats — shipped

- **Longest First** (Notenwerte) — the ordering/sequence format on note *values*:
  four shuffled note-value symbols; tap them longest → shortest, each playing its
  own duration and locking with a number badge, a wrong tap buzzes. The
  note-values sibling of Note Order (which orders pitches). SRI
  `note_values.order.len<N>`.
- **Note Match** (memory / concentration pairs) — flip a grid to pair a
  note-on-staff with its letter; each flip plays the pitch; fewer moves → more
  stars. SRI on each match.
- **Note Order** (sequence / ordering) — tap four shuffled note cards from
  lowest pitch to highest; each correct tap plays + locks with a badge. SRI
  `note_reading.order.len4`.
- **Sort the Beats** (sort into buckets) — drag note-value symbols into their
  1 / 2 / 4-beat bucket; wrong drop bounces + buzzes. SRI `note_values.symbol.*`.
- **Line or Space?** (swipe binary drill) — swipe a note-card left = line,
  right = space; wrong swipe bounces back. SRI `note_reading.line_space.*`.
- **Falling Notes** (arcade) — notes rain down real crisp_notation staves; name the
  glowing one on a 7-letter pad before it crosses the neon hit-line. Combo
  ×1–×5, speed ramps every four catches, three hearts, fixed 15-note run,
  star-driven range, colour-scaffold, reduced-motion aware. Feeds
  `note_reading.treble.*`. The **"play it" variant** ships too: **Falling Keys**
  drops the same notes onto a piano keyboard (SRI `keyboard.find.*`).
- **Connect the Notes** (connect-a-line matching) — notes on staves left, names
  shuffled right; drag a wire from each note to its name (`CustomPaint`).
  Correct link locks + plays; clears to advance. SRI `note_reading.treble.*`.
  The **symbol↔meaning** column ships as **Connect the Symbols** (Notenwerte,
  `note_values.symbol.*`) — same engine, a `mode` flag. A third mode,
  **Connect the Steps**, links an interval on a staff (two half-notes) to its
  *number* — count the note-names, C→G spans 5; 6th/7th join at 2★. SRI
  `intervals.size.*`.
- **In the Scale?** (swipe/tap binary) — a note on a card; swipe/tap/arrow-key
  IN if it belongs to C major (a natural), OUT if it's sharpened (chromatic).
  Wrong bounces back. SRI `scales.member.<in|out>`.
- **High or Low?** (sort into two baskets) — treble notes above vs below the
  middle line drag into HIGH / LOW baskets; correct drop sounds the note. The
  Sort-the-Beats bucket format on pitch *direction*. SRI `pitch.height.*`.
- **Sharp or Flat?** (sort into two baskets) — each note carries a sharp or a
  flat; drag it into the matching basket. Reading the accidental sign is the
  skill. SRI `accidentals.sign.*`.
- **Dotted or Not?** (sort into two baskets) — drag note glyphs into Dotted /
  Plain baskets by reading the **augmentation dot** (which makes a note half
  again as long). The note value varies (half/quarter/eighth) so the shape alone
  doesn't give it away. Reuses the Sharp-or-Flat? sort scaffold. SRI
  `note_values.dot.<dotted|plain>`.
- **Higher or Lower?** (ear, binary) — two notes play in sequence; tap whether
  the second is higher or lower. No staff — the aural twin of High or Low?. Big
  replay button. SRI `pitch.hear.<up|down>`.
- **Same or Different?** (ear, binary) — the youngest pitch-discrimination skill
  (Kodály): two notes play; tap whether they are the same pitch or different. A
  clear leap for beginners, subtler gaps (down to a semitone) at 2★. Replay
  button, no staff. SRI `pitch.hear.<same|diff>`.
- **Ascending or Descending?** (ear, binary) — a short run of notes plays; tap
  whether it climbs up or steps down. A step past Higher or Lower? — a whole
  phrase moves one way, not just two notes. Three notes for beginners, four at
  2★. Replay button, no staff. SRI `pitch.hear.<asc|desc>`.
- **Step or Skip?** (staff reading, binary) — two notes on the staff; read
  whether the move is a step (the next line/space, a 2nd) or a skip (a bigger
  leap). The motion vocabulary that precedes naming exact intervals. Correct
  answer sounds both notes. SRI `reading.motion.<step|skip>`.

## CrispNotation-powered — shipped

Games built on crisp_notation capabilities the app didn't use before.

- **Tie or Slur?** (Noten lesen) — reads the two curved marks that look alike but
  mean different things: a **tie** joins the *same* pitch (`NoteElement.tieToNext`),
  a **slur** joins *different* pitches (`Score.slurs`). A binary staff-read like
  Step or Skip?; the card engraves the two-note figure, two buttons, audio on
  correct. SRI `reading.curve.<tie|slur>`.
- **Beam or Flag?** (Noten lesen) — the two looks of eighth notes: joined by a
  **beam** (two eighths on one beat) vs each keeping its **flag** (eighths split
  by an eighth rest). The engraver has no beam-suppression API, so the cards
  exploit the real rule; the beam/flag contrast was verified at the crisp_notation
  layout level (same-beat eighths → 1 `BeamPrimitive`, eighth-rest between → 0).
  SRI `reading.beam.<beamed|flagged>`.
- **On the Beat or Off?** (Takte) — reading + hearing **syncopation**. A straight
  bar (four quarters on the beats) vs a syncopated one (eighth + 3 quarters +
  eighth, so the inner notes land off the beat); playback uses the real note
  lengths so the push is audible. Fills the curriculum's syncopation gap. SRI
  `measures.syncopation.<straight|syncopated>`.
- **Even or Triplet?** (Notenwerte) — reading how a beat is split: two even eighths
  vs a **triplet** (a real `TupletSpan(0,2,actual:3,normal:2)` → the engraver draws
  the bracket + 3), heard as 2-in-a-beat vs 3-in-a-beat. Fills the triplet/tuplet
  gap. SRI `note_values.tuplet.<even|triplet>`.
- **Which Family?** (Lieder) — a reading/knowledge quiz that closes the instrument-families gap: an instrument is named (~19 well-known ones), the child taps its orchestral family — Strings / Woodwind / Brass / Percussion / Keyboard. Deliberately *not* timbre-ID (the synth has too few timbres to hear the difference); `instrumentFamilyPrimer` names the families with familiar examples. SRI `timbre.family.<family>`; 10 rounds, [100,600,900].
- **Label the Form** (Komponieren) — hearing and *seeing* a piece's shape, an AnaVis-in-miniature. Each section is a short motif; a reusable `FormTimeline` widget draws the sections as colour-coded blocks (same colour = same tune), and the child picks the form — ABA / AAB / ABC for beginners, AABA / ABAB / rondo (ABACA) at 2★ (where the block labels hide, so the repeat pattern must be read from the colours). Fills the musical-form + verse/chorus gaps. SRI `composition.form.<FORM>`.
- **Which Mode?** (Skalen) — a three-way modal ear game beyond major/minor: a scale plays ascending from a tonic as **Major** (Ionian), natural **Minor** (Aeolian), or **Dorian**, and the child picks which. Dorian is the trap — minor-shaped but with a *raised 6th*, so it sounds "minor with a brighter twist"; the scales are built from exact semitone step patterns so that one distinguishing note is really there. `modePrimer` teaches the three colours (shown + heard). Fills the modes gap. SRI `scales.mode.<major|minor|dorian>`.
- **Which Ornament?** (Noten lesen) — read the sign over a note: **trill** (tr),
  **mordent** (squiggle), or **turn** (sideways S), drawn via `NoteElement.ornament`
  and each played as a little flourish (trill = fast alternation, turn = the curl
  around). Fills the ornaments gap. SRI `note_reading.ornament.<trill|mordent|turn>`.
- **Spot the Upbeat** (Takte) — a binary staff-read on where a tune begins: a
  short two-bar melody starts either on the downbeat (a full first measure) or
  with a **pickup / anacrusis** (an incomplete first measure — a few notes before
  the first barline). The pickup is a real `Measure(..., pickup: true)`, so the
  first bar genuinely holds less than the meter (a proper anacrusis, borrowed from
  the last bar). At 2★ the note-counting shortcut is defeated — full bars may use
  mixed rhythms (half + two quarters: three noteheads but still a full 4/4), and
  the pickup runs 1–2 notes — so the answer needs real metric reading. Correct →
  the melody plays. SRI `measures.upbeat.<yes|no>`.
- **Enharmonic Twins** (Noten lesen) — a binary staff-read on enharmonic
  equivalence, a Sek-I staple nothing else drills: two whole notes (each with its
  accidental) across two bars — **same sound spelled two ways** (F♯ = G♭) or two
  **genuinely different** pitches? Graded by `midiNumber` equality, so it is exact
  and the child must read past the spelling. Five sharp/flat twins for beginners;
  the trickier white-key twins (E♯ = F, F♭ = E) join at 2★; "different" rounds are
  guaranteed non-enharmonic and non-trivial (adjacent steps, at least one
  accidental). Correct → both notes play. SRI `reading.enharmonic.<yes|no>`.
- **Connect the Notes — four new modes** (Notenwerte) — the connect-a-line board
  grew from 3 to 7 modes, each one `ConnectMode` case reusing an existing catalog
  so nothing drifts: **Dynamics** (mark glyph ↔ meaning, `connect_dynamics`,
  shares `reading.dynamics.*` with Louder or Softer?), **Rests** (rest glyph ↔ the
  note it equals in length, `connect_rests`, `note_values.rest.*`), **Tempo Words**
  (Italian term ↔ meaning, `connect_tempo`, shares `reading.tempo.*` with Faster
  or Slower?), **Beats** (note value ↔ how many beats in 4/4, `connect_beats`,
  `note_values.beats.*`).
- **Sharp / Natural / Flat — 3-basket sort** (Noten lesen) — *Sharp or Flat?*
  (`accidental_sort`, +bass) widens at 2★ to a three-basket sort adding the
  **natural** sign, rendered as a real ♮ via `NoteElement.showAccidental` on an
  unaltered pitch; below 2★ it stays the binary ♯/♭ drill. Card sign refactored
  bool→`int alter`. SRI gains `accidentals.sign.natural`.
- **Key Change?** (Scales) — a modulation ear game: a short phrase either stays
  in one key or modulates partway through (its second half lifted a perfect 4th
  or 5th to a new tonic); the child taps "Same key" vs "Key changed". Phrases are
  built from a C-major fragment ending on the tonic; the changed variant shifts
  the second fragment up 5/7 semitones. Closes the `modulation` concept-map gap.
  SRI `scales.modulation.<same|changed>`; `modulationPrimer` teaches it by ear.
- **Triad or Seventh?** (Chords) — an ear game on the added seventh: a major
  triad (3 notes) vs a dominant-7 (triad + a minor 7th, 4 notes), tap which. The
  dom7 is built app-side from the major `Triad`'s pitches +
  `root.transposeBy(Interval.minorSeventh)` — no 7th-chord *builder* needed from
  crisp_notation. Completes the chord-quality-by-ear widening. SRI
  `chords.hear.<triad|seventh>`.
- **Read the Voice** (Noten lesen, gated behind Duet 2★) — reading one line out
  of a multi-voice texture, on crisp_notation's `Measure.voice2` (two voices per
  staff, stems up/down). A chord is shown with one voice highlighted; the child
  names the note *that* voice sings, so they must track the right line. The
  4-voice generalization of Duet: difficulty grows 2 voices (Soprano + Alto, one
  treble staff) → full **SATB** (four voices across a grand staff via
  `StaffSystem`). Voiced with a no-crossing `nextChordTone`-above algorithm (bass
  in octave 3, alto pushed to middle C so S/A land on treble, T/B on bass).
  C major; a "hear this voice" button; SRI feeds the shared reading pool. First
  of three scoped SATB minigames.
- **Which Voice?** (Noten lesen, gated behind Duet 2★) — the inverse of Read the
  Voice: a note in the chord is highlighted and the child picks which voice it is
  (Soprano/Alto/Tenor/Bass). Trains voice-position and range awareness (where
  each voice lives on the grand staff) rather than pitch naming. Same 2-voice →
  SATB progression, shared `satb_voicing.dart`. SRI `note_reading.voice.<voice>`.
  Second of three scoped SATB minigames.
- **Hear the Voice** (Noten lesen, gated behind Duet 2★) — the aural SATB game:
  the full chord plays, then one voice alone, and the child identifies which
  voice they heard (S/A/T/B). No notation — pure ear-training; at 2 voices it's
  "higher or lower?", at full SATB the inner voices make it a real listening
  challenge. Shared voicing, cancellable audio timers, a replay button. SRI
  `note_reading.ear_voice.<voice>`. Completes the three scoped SATB minigames
  (Read / Which / Hear the Voice).
- **"Handwritten notes" theme** (Settings) — a toggle that renders all notation
  in **Petaluma**, Steinberg's jazz/handwritten SMuFL face (SIL OFL 1.1),
  instead of Bravura. The font (+ metadata + OFL) is vendored in
  `assets/smufl/`; its licence shows on the About page. Every StaffView /
  MultiSystemView site now routes through `shared/score_theme.dart`'s
  `kidsScoreTheme`, which applies the selected `MusicFont` (Bravura by default);
  the toggle updates a global so screens entered afterwards pick it up. A
  cosmetic delight, and the plumbing for further faces (Leland/Leipzig) later.
- **Chord Chart** (Chords) — lead-sheet literacy: a chord *symbol* is shown
  (G, Dm, D7…) and the child taps the matching *notation* among four little
  staves. The inverse of Name That Chord (notation→symbol); symbols come from
  `chordSymbolFor` so they're spelled as the library names them. Correct tap
  plays the chord; widens major/minor triads (roots C/F/G) → all roots → +
  diminished. SRI `chords.symbol.<symbol>`. Uses the shared game-test harness.
- **Strong Beat?** (Takte) — metric-accent training on crisp_notation-public's
  `beatStrength`. A measure is shown with its beat numbers (crisp_notation's
  `showBeatNumbers`), one beat highlighted; the child says whether it's a strong
  (accented) or weak beat. The answer is graded by
  `TimeSignature.beatStrength(position)`, not hard-coded — correct for 4/4 (1 & 3
  strong), 3/4 (only 1) and 6/8 (1 & 4). A metric click accents the strong beats.
  Widens 4/4 → +3/4, 2/4 → +6/8. SRI `measures.accent.<ts>_<beat>`.
- **Spot the Parallels** (Harmonik — top of the ladder) — the app's first
  part-writing drill. A two-chord SATB progression is engraved on a grand staff
  (soprano+alto on the treble, tenor+bass on the bass); the child decides whether
  the voice-leading is **Clean** or slips into forbidden **parallel fifths /
  octaves**. Graded by crisp_notation_core's `checkVoiceLeading` — the library is
  ground truth, so the 9 authored chord-pair templates (4 clean + 5 parallel-only,
  verified crisp in the test) can never be mislabelled; they're transposed for
  variety (parallels are interval-invariant, so the label survives). A correct
  answer plays the pair so you HEAR the motion. New g9-10 `voice_leading`
  curriculum concept. SRI `harmony.parallels.<template>`.
- **Roman Numerals** (Harmonik) — read *and* hear a diatonic triad in a key and
  pick its Roman numeral (I, ii, iii, IV, V, vi, vii°). The chord is built with
  `Triad(root, quality)` and named by crisp_notation-public's new
  `romanNumeralOf(pitches, key)` — the same analyser will later carry sevenths
  (`V6/5`), inversions and minor keys. A step up from the Function Quiz (T/S/D
  only): every diatonic degree is in play. Renders the chord with the key
  signature, arpeggio-then-chord audio + replay, four numeral buttons. Widens
  I/IV/V in C major → all seven degrees → all easy major keys. SRI
  `harmony.roman.<symbol>`. *(First game on the crisp_notation-public alignment — mus
  now builds against `CrispStrobe/crisp_notation@main` locally and on CI.)*
- **Name That Chord** (chords) — read or hear a chord and pick its symbol; the
  answer is graded by crisp_notation's `identifyChord`, so it names quality **and**
  inversion. Roots C–A (no accidental in the symbol); major/minor root position
  for beginners, diminished/augmented and slash-chord inversions (C/E) at 2★.
  Renders the chord as a block on the staff, replay button, keyboard 1–4. SRI
  `chords.name.<root>_<type>`.
- **Chord Builder** (chords) — build the named chord by tapping three notes onto
  the staff; crisp_notation's `identifyChord` grades what you built, so **any voicing
  counts** — root position or an inversion, in any octave. The interactive
  counterpart to Name That Chord; major/minor for beginners, dim/aug at 2★. SRI
  `chords.build.<root>_<quality>`.
- **Major or Minor?** (chords) — a drag-and-drop sort on triad **quality** read
  off the staff: each card shows a triad; drag it into the Major or Minor basket
  (the third is what decides it). The reading twin of the aural Dur-oder-Moll? and
  the sort-into-buckets sibling of Sharp or Flat?, on the `accidental_sort`
  scaffold; built with crisp_notation `Triad(root, ChordQuality)`, the chord
  sounds on a correct drop. At 2★ a third basket — Diminished — joins (the lowered
  fifth), mirroring how Sharp or Flat? grows a Natural basket. SRI
  `chords.quality.<major|minor|diminished>`.
- **ABC import** (Song Book) — the importer takes pasted **ABC notation**
  (`scoreFromAbc`) alongside MusicXML / ChordPro / MIDI, stored as MusicXML like
  the rest. Opens the large public-domain ABC folk-tune libraries; the tune's
  `T:` line seeds the title.
- **Concert Pitch** (new **Transposing** module/corner) — read a written note
  for a **B♭ trumpet / E♭ alto sax / F horn** and name the concert pitch that
  actually sounds; crisp_notation's `transposeBy` computes the exact letter. The B♭
  instruments alone for beginners, E♭ and F added at 2★. A skill nothing else in
  the app covers. SRI `transpose.<instrument>.<written-step>`.
- **Write It for the Instrument** (Transposing) — the **inverse** of Concert
  Pitch: a **concert pitch** (what sounds) is shown on the staff; name the note a
  B♭/E♭/F instrument must **read** to produce it (`transposeBy` in the opposite
  direction). B♭ alone for beginners, +E♭/F at 2★; a correct answer plays the
  concert pitch. Together the two games drill both directions of transposition.
  SRI `transpose.<instrument>.write_<concert-step>` — a distinct leaf, so the two
  games never overwrite each other's SM-2 items.
- **Bowing** (cello corner) — read crisp_notation's string-bowing marks: a note on
  the bass staff carries a ⊓ down-bow or ∨ up-bow (`Articulation.downBow/upBow`);
  name it. SRI `cello.bowing.<down|up>`.
- **Which Beat?** (measures) — a 4/4 bar with one note coloured; tap the beat it
  starts on (1–4). crisp_notation's **`showBeatNumbers`** overlay draws the count
  under the staff as a scaffold that fades (on at level 1, off at 2★). SRI
  `measures.beat.<n>`.
- **Time Signatures** (measures) — read a signature — including the **C
  (common)** and **¢ (cut)** glyphs — and give the beats per bar. 3/4·4/4·C for
  beginners; ¢·6/8·2/4 at 2★. SRI `measures.timesig.<id>`.
- **ABC export** (Composition Workshop) — an AppBar action renders the current
  score to **ABC** (`scoreToAbc`) in a dialog and copies it to the clipboard;
  round-trips with the Song Book's ABC import.
- **Duet** (note reading) — read the **highlighted part of a two-staff system**
  (crisp_notation's `StaffSystemView`): two parts are shown, one note highlighted;
  name it, tracking the right line. Both treble for beginners; the lower part
  becomes bass clef at 2★, like a grand-staff duet. SRI
  `note_reading.<clef>.*`.
- **Drum Read** (new **Drums** corner) — read a two-bar rhythm on the neutral
  **percussion clef** and tap it back on the drum pad. After a one-bar count-in
  the notation goes live; each tap is judged Perfect/Good/Miss against the
  notated onsets over a steady click (one Ticker master clock, no drift). A
  no-fail performance toy.
- **Which Clef?** (Noten lesen) — the youngest clef-literacy drill: a bare clef
  is drawn on an empty staff (`StaffView` over `Measure([])`) and the child taps
  which clef it is. Treble vs Bass for beginners, widening to **Alto and Tenor**
  at 2★ (all four rendered by crisp_notation's `Clef`). A binary `AnswerGrid`, no-fail;
  nothing else in the app taught reading the clef *sign* itself. SRI
  `reading.clef.<treble|bass|alto|tenor>`.
- **Whole or Half Step?** (Noten lesen) — the tone-vs-semitone drill and the
  foundation of scale-building: two neighbour notes (a 2nd) are shown; tap
  whether the gap is a whole step or a half step, then hear it played. Because
  half steps hide only at E–F and B–C, a plain 2nd isn't enough — the child must
  read the letters. Balanced generation (`Clef.pitchAt`), naturals only; treble
  for beginners, +bass clef at 2★. The natural sequel to Step or Skip?. SRI
  `reading.tone.<whole|half>`.

## Toy-inspired mechanics — shipped

- **Strum Toy** (guitar corner) — a free, no-scoring jam: pick an open chord
  (C/G/D/Em/Am) and swipe across the strings to strum (down = low→high, up =
  high→low) or tap one to pluck. Voiced as an arpeggio-into-block-chord (the
  synth is monophonic), colour-coded strings, keyboard 1–5 + space/arrows.
- **Sound Echo** (memory-sequence toy) — four pentatonic pads; the app lights +
  plays a growing sequence, the child echoes it; one miss ends the run. Made
  educative: noteheads on a mini-staff (C-major pentatonic) and **cues fade as
  the sequence grows** — colour + sound + notation first, then colour drops,
  then sound, until the longest runs are read from noteheads alone.
- **Follow the Conductor** (command caller, reworked into a metre lesson) — the
  baton traces the real conducting figure for the time signature (2/4, 3/4,
  4/4); the target zone lights on each beat (accented downbeat) and the child
  follows — taps or arrow keys. Scored by timing; kinaesthetic downbeat.

## Original concepts — shipped

- **Tracker** (composition) — a touch-first **pattern sequencer** in the spirit
  of ModEdit / FastTracker 2 / Scream Tracker 3 / Impulse Tracker, but
  **dual-audience** (a 10-year-old builds a groove; an adult finds it cool) via
  two skins over one document — the same Sandbox/Studio idea as the Workshop.
  Pick an instrument tab, tap a **scale-locked pentatonic piano-roll** (pitch
  rows × step columns), and every channel layers into one looping groove. It's
  the Loop Mixer with an **editable grid**: `tracker_engine.dart` renders each
  channel to a stem and sums them through `synth.dart mixStems` → one looping
  WAV on `LoopPlayerService`, with the same Stopwatch-phase swap (edits re-enter
  the loop in phase) and Ticker playhead. Instruments hang off a
  `TrackerInstrument` seam: **additive** timbres, **sfxr chiptune** (a focused
  pure-Dart port of the maintainer's
  [crispaudio](https://github.com/CrispStrobe/crispaudio) SynthEngine into
  `core/audio/crisp_dsp/sfxr.dart` — blips/zaps/booms synthesized per-note at
  pitch), and **recorded voice**: the flagship *record-your-voice → play a tune
  with it* bridge — `voice_clip_recorder.dart` captures a mic clip, a voice
  effect (chipmunk/monster/deep via a ported **formant shifter**, robot via
  ring-mod + bit-crush — all pitch-stable so the sample stays in tune) is
  applied, and it becomes a resampled tracker instrument on a runtime-swappable
  `voice` channel. All DSP ported (MIT) from the maintainer's crispaudio /
  CrispFXR / voicelab. A **bidirectional notation bridge** links it to reading:
  Tracker → Score renders the selected channel as a live `StaffView` "score view"
  (held runs → tied notes, bar-split); Score → Tracker imports a melody back onto
  the grid (partial — quantize + top-note + pentatonic snap), round-trip tested.
  **Studio depth:** a per-channel instrument picker (additive + chiptune), a
  **drums** channel (drum-row grid), **song mode** (4 pattern slots A–D + an
  editable order-list + a song-length playhead), and **per-note dynamics**
  (long-press → soft "ghost" notes). Sandbox, no stars. (Mic capture is
  device-only; the DSP + assign→play path are unit-tested headlessly.)
- **Module formats & cross-format converters** (Tracker, `core/audio/mod/`) — the
  Tracker speaks the classic tracker file formats, all in **pure Dart** (web-safe,
  no native deps). **Readers** for ProTracker `.mod`, Scream Tracker 3 `.s3m`,
  FastTracker 2 `.xm` and Impulse Tracker `.it` — the hardest part, IT's IT214/215
  variable-bit-width sample **decompression**, was pinned by an oracle round-tripped
  **44/44 against libxmp's `itsex.c`** before a line of Dart was written.
  **Writers** for all four. A format-neutral **`ModuleDoc` hub** (pitch as MIDI so
  notes keep their pitch across formats, PCM normalized to ±1) turns the readers and
  writers into a **complete N×N converter matrix — any of {mod,s3m,xm,it} → any of
  {mod,xm,s3m,it}** (`parseAnyModule` sniffs by signature; conversion carries notes/
  instruments/volume/samples/structure, dropping per-cell effects in v1). Every
  codec was built the same disciplined way — a hand-authored, self-verified golden
  fixture (committed, license-clean) + a skip-if-absent live test over a real
  module, with one sub-agent implementing one file against a written contract. Also
  exposed as **headless CLIs** (`bin/modinfo.dart` dumps any module; `bin/modconv.dart`
  converts between formats and extracts samples to WAV — "steal an instrument" from
  the shell), Flutter-free like `bin/listen.dart`. In the app: MOD + MIDI
  import/export via a `file_selector` menu (the MIDI↔MOD hub reuses crisp_notation's
  Score bridge — no external converter).
- **Rhythm "Relevanzschwelle" engine** (audio core) — the beginner rhythm-
  quantisation front-end (roadmap step 2). Pure `lib/core/audio/rhythm_quantize.dart`:
  `detectOnsets` (energy trace → onsets, generic version of `beat_capture`'s rule)
  → `chooseResolution` auto-picks the **coarsest metric grid the player can
  actually feel** (finest needed within tolerance, no colliding onsets, never
  finer than a skill `cap` of quarter/eighth/triplet/sixteenth — so loose eighth
  playing isn't over-quantised to sixteenths, and a beginner cap collapses stray
  16th flams) → `quantizeRhythm` drops sub-strength noise, snaps, and collapses
  same-step hits. The shared front-end before conversion to Tracker/GrooveSpec/
  Score/MIDI. 15 headless tests. **Model conversion** (`rhythm_convert.dart`):
  `toTrackerColumn` (→ a Tracker channel, which already exports Score/MusicXML/
  MIDI/module + saves to the Song Book) and `toDrumPattern` (→ a Loop Mixer
  `DrumRowsPattern`), re-placing each hit by its grid-independent musical
  position; 7 tests. So a recorded rhythm reaches every notation/export path.
  **DrumKit tap-to-record**: a Record button captures pad taps at their loop
  position and, on stop, quantises the take onto the step grid (overdub) via
  `quantizeToResolution(eighth)` → `toDrumPattern` — play a beat in and it lands
  as clean eighths, stray double-taps collapsing. Added the fixed-grid
  `quantizeToResolution` (a step machine wants its set grid, not the coarsest
  feel). Device-free + `debugRecordTaps` seam; +3 tests. **Beatbox-to-grid**: a
  🎤 button captures the mic for one loop, classifies each hit (kick/snare/hat)
  by timbre and quantises onto the grid via the same pipeline. New pure bridge
  `beat_capture.beatboxToTaps` (`detectOnsets` + per-onset `classifyHit` → taps),
  verified against the real synth→detector harness; `debugBeatboxFrames` seam for
  a headless test. Both DrumKit record paths converge on the generic engine.
  **Save to Song Book + Export**: `groove_notation.drumParts` engraves a beat as a
  rhythm-line multi-part score (one part per drum — kick low / snare middle / hat
  high, a reduction that preserves the timing), reusing `grooveScore` (every
  eighth step is a note or rest). App-bar Save (→ Song Book) + Export (the shared
  music-export sheet → MusicXML/MIDI). So a tapped or beatboxed beat leaves the
  kit as notation. Closes the DrumKit record arc.
- **Looper core** (audio core) — the pure foundation for a better looper:
  `loop_record.dart` with `quantizeLoopBars` (snap a take to a whole number of
  bars → seamless loop lengths), `snapPunch` (snap a record window to bar
  boundaries → quantised punch-in/out), and a generic `LoopStack<T>` overdub
  layer stack (undo/redo + per-layer mute). 9 headless tests.
- **DAW timeline core** (audio core) — the "vector, not bitmap" foundation for a
  multi-track DAW Workshop tool: a clip references its source MODEL and the mix
  rasterises on demand + caches per source, so editing a source updates its clip
  (fits because every module renders offline+purely to PCM). `daw_timeline.dart`
  (`ClipSource`/`Clip`/`DawTrack`/`DawTimeline`/`renderTimeline` with per-source
  cache, sample-accurate placement, gain, tanh soft-limit) + `daw_sources.dart`
  adapters (`DrumSource` a DrumKit beat, `GrooveSource` a Loop Mixer groove).
  Offline render-then-play (no realtime graph). Adapters cover EVERY module type
  (`DrumSource`/`GrooveSource`/`ScoreSource` for DrumKit/Loop Mixer/Song Book+
  Workshop+TAB, `TrackerSource`, `SampleSource`) — each rendering on demand and
  cache-keyed by model value. The **Multitrack** arranger screen (reached from the
  home Workshop menu) places clips on tracks and BAKES the mix to play; per-track
  mute, seeded demo clips. A shared app-wide `DawService` holds the arrangement so
  clips sent from any module accumulate into one project. **Every module can
  now Send to the Multitrack** — DrumKit (snapshot `DrumSource`), Loop Mixer
  (`GrooveSource`), Song Book (`ScoreSource`), Composition Workshop + TAB
  Workshop (multi-part `ScoreSource`), and the Tracker (`TrackerSource`) — each
  via the shared `sendToMultitrack` helper (`addClip` + a localized snackbar),
  each with a live widget test that the clip lands and bakes to audio. Clips
  can be **merged and converted**: *Freeze* bakes a live clip's current render
  into a fixed `SampleSource` take (it stops tracking its source module and
  needs no re-render), and *Merge all* flattens every clip into one baked take
  (preserving relative timing) — the arranger surfaces both. The arranger is a
  **to-scale, draggable timeline** under a second-by-second **time ruler**:
  clips are drawn at their render duration on a shared horizontally-scrolling
  lane, long-press a clip then drag to move it in time (a plain drag still
  scrolls the lane; a grid toggle snaps drags). Each clip has **volume +
  fade-in/out** — tap it for an inspector sheet, and fades apply as a
  render-time envelope. The whole edit history is **undoable** (a snapshot per
  edit; drags and slider-sweeps coalesce into one step), and a Download action
  bakes the mix to **WAV or MP3**. ~50 headless tests; design in
  `docs/DAW_SCOPING.md`.
- **DrumKit undo/redo** — a snapshot history (deep-copied pattern before each
  mutation) backs app-bar Undo/Redo across grid edits, whole record takes, and
  clear; a fresh edit drops the redo branch. Fills the gap left by the new
  destructive record/clear operations.
- **DrumKit swing** — a Straight/Swing groove control (`LoopTiming.swing`, which
  delays every off-eighth); the render already honours it, so a chip pair makes
  beats swing.
- **Loop Mixer — beatbox + jam along** (composition, ladder slice 10) — the
  mic closes the circle twice more. **Beatbox a beat:** count-in, 2 bars of
  "boom-ts-pss" into the mic, and it comes back as a teal drum card — onset
  detection + kick/snare/hat classification (`beat_capture.dart`) on new
  rms/zero-crossing-rate features every `PitchReading` now carries, with
  thresholds calibrated against the app's own synth drums through the real
  detector and an acceptance test that a synthesized beatbox reconstructs
  the exact pattern. **Jam along:** the groove keeps playing while the mic
  listens (platform echo-cancel + a headphones hint); every note you play or
  sing lights up green (tone of the sounding chord — progression-aware),
  amber (pentatonic) or red — the loop mixer as a backing band that tells
  you when you fit.
- **Loop Mixer 2.0 — the groovebox ladder** (composition) — the v1 toy grew
  into an instrument in seven shipped slices (engine v2 → sing-a-track), all
  behind the same five-cards kid surface. **Feel:** a swing slider (off-eighth
  delay on an exact boundary grid), per-card A/B/C pattern variants (incl. a
  euclidean/Bjorklund drum groove), per-card levels, and an automatic drum
  fill every 4th loop, swapped in at the loop seam where the downbeat kick
  masks it. **Harmony:** a progression lane (I–V–vi–IV · I–IV–V–I · vi–IV–I–V)
  turns the 2-bar vamp into a 4-bar song — bass and chords re-voice per chord
  from chord-tone shapes (`ChordFollower`), melody/sparkle stay pentatonic
  (axis progressions absorb it) — verified end-to-end by rendering the bass
  and reading it back with `bin/listen.dart` (every bar's root/root/fifth/root
  detected exactly). **Notation:** a score panel engraves the leading track
  live via crisp_notation (`groove_notation.dart` — cells → 4/4 bars, greedy
  durations). **Keep it:** the whole groove is one small `GrooveSpec` value —
  a serverless `KU1.…` share token (copy/paste anywhere, defensively parsed)
  plus desktop WAV export. **Generativity:** infinite mode re-renders a
  seeded variation at every seam (hats breathe, snare ghosts, pentatonic
  melody ornaments; the kick never moves). **The mic:** *sing a track into
  existence* — count-in, 2-bar capture, the MPM pitch trace quantized to the
  step grid, octave-normalized and pentatonic-snapped (`groove_capture.dart`),
  and the child's own melody becomes a sixth card: toggleable, mixable,
  engraved as sheet music, carried inside the share token. Deep pattern
  *editing* is deliberately left to the Tracker (one grid editor in the app);
  beatbox→drums + AEC jam mode remain on the roadmap as slice 10.
- **Loop Mixer** (composition) — a kid **loop-layering toy**: five cards
  (drums · bass · chords · melody · sparkle) each toggle a pre-authored 2-bar
  loop; everything is C-pentatonic so any combination grooves (the Colour
  Melody rule). A sandbox — no stars, no wrong answers. Under the hood the
  first **multi-track** audio in the app, still pure Dart + one player:
  `loop_engine.dart` mixes the enabled tracks offline into a single looping
  WAV (sample-accurate sync for free), with **combo-independent levels**
  (unit-peak per stem + authored gains + a tanh soft-knee in
  `synth.dart mixStems` — toggling a card never changes the others' loudness)
  and **seeded noise percussion** (kick sweep / snare / hat one-shots — the
  additive synth is tonal, so drums got their own generator). The screen owns
  a Stopwatch musical clock and swaps mixes with `play(position: phase)`, so
  layers drop in/out **without the bar restarting**; a dedicated
  `LoopPlayerService` (ReleaseMode.loop) keeps SFX and groove from stopping
  each other. Step-dot playhead (Ticker), 75/100/120 BPM presets, per-combo
  render cache. Acceptance-tested end-to-end by rendering stems and reading
  them back with `bin/listen.dart` (bassline detected exactly as authored;
  pad reads C 98% → Am 98%).
- **Colour Melody** (composition) — a composing grid for **pre-readers**: five
  coloured rows (a C-major pentatonic, so every combination is consonant) × eight
  beats. Tapping a cell places a note (and sounds it), and the grid renders live
  to a **real crisp_notation `Score`** shown underneath — so a non-reader is
  quietly writing notation. Play the tune back (rests preserved via
  `playChordSequence`, empty beats = silence) or clear. A sandbox like My Melody —
  no stars, no wrong answers; the bridge to notation for those who can't read yet.
- **Melody doodle** (composition) — Colour Melody's **gesture** twin: drag a
  freehand line across the box and it *becomes* a tune. The contour is quantised
  to one C-pentatonic note per beat (a column averages its points, so a scribble
  reads as its overall height; the top of the box is the highest note; untouched
  beats stay rests) and renders live to a **real `Score`** underneath. Beat guides
  and a coloured dot per quantised beat show the line turning into notes as you
  draw, and a note sounds only when the drag crosses into a new beat. A sandbox —
  no stars. For the youngest: "draw music" before you can tap a grid.
- **Find the Key (bass)** (keyboard) — the staff→piano bridge in bass clef: the
  reusable `PianoKeyboard` shifts two octaves down (C2..B3) so the low staff
  naturals (G2..A3) and the 3★ black-key targets land on real keys. Own
  `progressId`; the SRI token carries the octave so bass items never collide with
  the treble Find the Key. Completed the bass-clef sweep of the reading/keyboard
  games.
- **Recital Mode** (progression meta) — a home-bar "recital" strings a 3–5 piece
  programme (favouring games the child has already practised) into one set; play
  each in turn and the run ends on a **curtain call** that tallies the stars
  earned across the whole programme. Wraps the review loop in a set-piece.
- **Note Snake** (note reading) — reading meets the classic arcade snake: a
  target note shows on the staff, letters sit on a grid, and you steer the snake
  (arrow keys or an on-screen pad) to eat the letter that names it. Eating the
  wrong letter — or biting your tail — ends the run; it wraps at the edges and
  speeds up as you grow. Star-gated range, colour-scaffold, treble + bass. Feeds
  `note_reading.<clef>.*`.
- **Chord Grip Hero** (keyboard) — Falling Keys for chords: a triad falls on the
  staff and its keys glow on the piano; press all of them before it lands. Full
  grips speed up the next; three ungripped landings end the run. White-key
  diatonic triads of C major (playable without black keys); C/F/G major for
  beginners, the Dm/Em/Am minors at 2★. Feeds `keyboard.chord.*`.
- **Staff Runner** (note reading) — an endless sight-reading sprint: one note at
  the read-line with a depleting timer bar; name it before the bar empties.
  Every correct read shortens the next timer (the "speed up"); three misses
  (wrong name or timeout) end the run, score = notes read. Star-gated range,
  colour-scaffold, letter-key control, treble + bass. A stepping-stone to the
  generative-sight-reading big swing. Feeds `note_reading.<clef>.*`.
- **Interval Ladder** (chords & intervals) — interval *construction*: a base
  note is shown with a chip saying how far and which way to climb (▲3 = a third
  up); tap the candidate note at that interval (a correct pick plays base→target
  melodically). Thirds/fifths up for beginners, all sizes and both directions at
  2★. SRI `chords.interval.build.<n><up|down>`.
- **Dynamics & Tempo Charades** (expression) — expressive vocabulary the app
  didn't touch: a phrase plays at one of four tempi (Adagio→Presto) or four
  dynamic levels (pp→ff); name what you heard. The two clear extremes for
  beginners, all four terms at 2★. Needed a `gain` on the synth so dynamics are
  actually softer/louder (the output is otherwise peak-normalized). SRI
  `expression.hear.<tempo|dynamics>.<term>`.
- **Odd One Out** (note reading) — whack-a-mole under gentle reaction pressure:
  noteheads pop up in a 3×2 grid of holes, a target letter is called ("Whack:
  A") and the child taps the matching notes before they duck. Correct whacks
  grow a ×1–×5 combo; a wrong whack costs a heart (3 lives); a fixed 12-whack
  run keeps the score/1–3★ loop, with the hole lifespan shrinking as it goes.
  Ticker-driven, star-gated octave range, colour-scaffold aware, letter-key
  control, reacting mascot; treble + bass. Feeds `note_reading.<clef>.*`.
  *(Extends to a "wrong-note" spot-the-error mode.)*
- **Odd One Out** (note reading) — three note cards; two share the same letter
  name at different octaves, one is a different letter. Tap the odd one out — a
  discrimination drill that trains rapid name-reading, not just notehead
  matching. Star-gated octave range (staff → ledger), colour-scaffold aware,
  number-key control, reacting mascot; treble + bass variants. Feeds the shared
  `note_reading.<clef>.*` pool on the odd note. *(Extends to chord-quality and
  scale-degree "odd one out" by ear.)*
- **Ledger Leap** (note reading) — a note sits exactly on the Nth ledger line
  (never a space, so the count is unambiguous); tap 1 / 2 / 3. Star-gated
  (treble/middle-C region first; +bass, above, 3 lines at 2★). A correct count
  plays the pitch. SRI `note_reading.ledger.<clef>.<below|above><n>`.
- **Key Detective** (scales) — crisp_notation renders a key signature
  (`KeySignature(fifths)`); name the major key. Natural-letter tonics
  (C G D A E B F) so buttons never need an accidental; German B = H via the
  naming toggle. Star-gated (C/F/G/D → +A/E/B); correct answer plays the tonic
  triad. SRI `key_sig.<tonic>`.

## Loop Mixer 2.0 — the groovebox ladder (roadmap)

**STATUS 2026-07-17: ALL SLICES SHIPPED — the ladder is complete** (slices
1–10; slice 5 deferred to the Tracker by design). See the board + HISTORY.md.
Follow-ups (groove→score export, native-AEC jam grading) are specced in
`LOOP_MIXER_FOLLOWUPS_HANDOVER.md`.

Evolve the shipped Loop Mixer (`32ebb96`) from kid toy into something adults
find genuinely fascinating. Guiding idea: **kids love cause-and-effect; adults
love depth that reveals itself** — a toy that turns out to be an instrument,
a system that responds to *you* (the mic!), and output worth keeping. The
ladder is also a stealth curriculum: layers → arrangement → harmony → rhythm
design → ear-to-instrument. Depth stays behind the shelf (Sandbox/Studio
philosophy): the five-cards surface never gets harder. Division of labour vs.
the **Tracker** (opus, `TRACKER_HANDOVER.md`): the Tracker is the *editing*
surface (pattern grids, sample instruments); the Loop Mixer is the *playing*
surface (layering, feel, harmony, generativity, the mic). Both sit on the same
`loop_engine.dart`/`mixStems` foundation — engine work here is additive and
keeps existing signatures stable.

**Architecture spine** (decides everything else):
- **`GrooveSpec`** — one small serializable value object = the entire groove
  state (enabled set, tempo, swing, per-track variant + level, progression,
  seed). Engine renders `spec → WAV` (pure, cached). Makes the share token,
  save slots and tests trivial.
- **Patterns become DATA, not closures** (drums = per-voice hit rows; melodic
  = (midis, lengthSteps) cells) so variants, engraving, sing-a-track and
  generative variation all operate on one model — and the Tracker can reuse it.
- **Seam scheduler** — the single looping player stays for the steady state
  (native loop = perfectly gapless); a second player only swaps a *changed*
  render at the next loop boundary (fills, variation, infinite mode). Instant
  toggles keep the shipped phase-preserving `play(position:)` path.
- Stay offline-render + audioplayers until an actual wall (live filter sweeps
  / continuous tempo bend would need a streaming path — flag, don't build).

**Slices** (each independently shippable, in order):
1. ✅ v1 shipped (`32ebb96`).
2. **Engine v2** — GrooveSpec + data patterns + **swing** (off-eighth delay
   0–60%, the biggest feel-per-LOC win) + **per-track variants** (A/B/C) +
   **euclidean drum generator** (Bjorklund; hits/rotation per voice) +
   per-card **level**. Pure Dart + tests; screen keeps the v1 surface.
3. **Screen v2 + seam scheduler** — swing slider, variant cycling on cards,
   level control, bar-quantized "armed" apply for seam-timed changes, auto
   drum-fill every 4th loop.
4. **Chord progression lane** — pick I–V–vi–IV / I–IV–V–I / vi–IV–I–V; loop
   becomes 4 bars (1 per chord); bass + chords render chord-relative, melody
   stays C-pentatonic (works over the axis progressions). Suddenly it's a song.
5. ~~Step editor~~ — **deferred to the Tracker** (its Sandbox view IS the
   step editor, over the same engine). No duplicate grid UI here.
6. **Live engraving** — the groove as a real multi-part crisp_notation score
   in a collapsible panel (the app's signature "you're writing notation" trick).
7. **Keep it** — WAV export/share (bytes already exist), groove **share
   token** (GrooveSpec → short base64 string, serverless, matches the
   no-tracking stance), save slots (mirror `user_songs_service`).
8. **Infinite mode** — seeded per-iteration variation via the seam scheduler
   (ghost notes, melody ornaments, arrangement drift). Never the same twice.
9. **Sing a track into existence** — hum a riff → MPM pitch track → quantize
   to key + step grid → a sixth card plays it on the synth (reuse Free Sing /
   melody recorder pipeline). The headline feature. (Distinct from the
   Tracker's record-your-voice-as-*instrument* — this is melody *capture*.)
10. **Beatbox → drum card** (onset + crude kick/snare/hat classification) and
    **Jam mode** (groove plays, child plays cello over it through the AEC
    path, app shows what they play vs. the harmony — the loop mixer becomes a
    play-along backing band). Big; needs the AEC on-device path.

## Agent coordination board — shipped log (chronological)

These are the `✅ idle / SHIPPED` entries that accumulated on the top-of-
[PLAN.md](PLAN.md) coordination board as parallel agents finished work. Moved
here verbatim (2026-07-17) to keep PLAN.md focused on pending work. Newest-ish
first, as they sat on the board.

_The next batch, moved 2026-07-19 — the board entries that accumulated after
the 2026-07-17 sweep (newest at the top of this batch):_

- **opus** · ✅ **SHIPPED — layout-engine crash-hardening** (crisp_notation `443be86`). Fuzzed `layoutPages`/`layoutMultiPartPages`/`layoutStaffSystemSystems` against degenerate scores (empty measures, extreme durations, huge/tiny page metrics, unusual + additive meters, chords/tuplets/voice2). One real internal crash found + fixed: an empty (0-measure) score threw `StateError: Bad state: No element` (`layoutSystems` read `measureRegions.last`) — reachable from the PDF export of an empty Workshop doc; now paginates to zero pages. All other throws are the documented `ArgumentError` preconditions (unequal measure counts, empty multi-part). Locked with a `pagination robustness` group in `layout_edge_test.dart` (empty-score regression + 150-iter valid-input fuzz + precondition contract). **Then** scoped the **Loop Mixer 3.0** arc into PLAN.md (§ "Loop Mixer 3.0 — from mixer to instrument") — content variety (chosen lead), live-performance FX, visual juice, discovery/combos, improvise, arrangement — and flagged the **broken "show as sheet music" panel** as §A (bug, do first). Docs only. Now idle.

- **opus (library-import-multipart)** · ✅ **idle / SHIPPED — fixed online-library import data-loss.** The OpenScore/Commons fetch pipeline decoded `.mscx` via single-part `scoreFromMscx` + MIDI via single-track `scoreFromMidi` → a 4-part OpenScore string quartet / multi-track MIDI lost all but the first part on import. Added **`multiPartScoreFromMscx`/`staffSystemFromMscx`** to `crisp_notation` (**`crisp_notation@516dcd2`**, per-staff id prefixes + per-`<Part>` instrument names) + fixed `bytesToMusicXml` to decode mscx/MIDI via the multi-part readers → `multiPartToMusicXml` (**`02d114d`**). +2 tests (lib reader + app 2-part mscx/midi import); 1675 core + 21 library tests green. So import AND export now keep every part for the multi-capable formats. **+ robustness follow-up (`crisp_notation@ba74b01`):** extended `reader_robustness_test.dart` to fuzz the multi-part reader entry points (`multiPartScoreFrom*`, the actual import surface + the new mscx reader) — 2000 mutations each of a genuine 2-part doc, all reject cleanly with FormatException (no RangeError/hang).

- **opus (multipart-kern)** · ✅ **idle / SHIPPED — multi-part kern export (columnar N-way time-merge).** `multiPartToKern` (**`crisp_notation@af10bcb`**) emits one `**kern` spine per part, voice-1 events **time-merged** row by row (sustains → `.`), generalizing the 2-voice `_multiVoiceRows` via a new `_kernEvents` helper (onset+token, tuplet-scaled, tie state across measures). Verified via `staffSystemFromKern` with two parts of DIFFERENT rhythms — both note sequences exact. Wired into the export sheet + Workshop (**`6b13055`**). +1 test; 1674 core green; app analyze clean. **⇒ ALL multi-capable engrave formats now keep every part on export: MusicXML, MEI, MuseScore, kern** (LilyPond/Braille/PDF remain single-Score by nature). **↓ prior ✅ SHIPPED — multi-part MuseScore export** (same data-loss fix as MEI). Added **`multiPartToMscx(MultiPartScore)`** (**`crisp_notation@ac68a08`**) — one `<Part>`/`<Staff>` per part; mscx staves are independent + its slur/dynamic/lyric markup is positional (not id-referenced), so each part is written self-contained (no cross-part id handling). Verified per-staff via `scoreFromMscx(staffIndex:)` (mscx has no multi-part reader). Wired into the export sheet + Workshop (**`a67ef5c`**). +1 lib test; 1673 core green; app analyze clean. **⇒ MEI, MuseScore AND MusicXML now keep every part on export.** **`multiPartToKern` DEFERRED** (unclaimed, lower-value): kern spines are columnar so N parts need an N-way time-merge (generalizing the 2-voice `_multiVoiceRows`) — real complexity + bug risk for an analysis format, vs. MEI/mscx's clean independent staves. kern/LilyPond/Braille still export the first part. **↓ prior: ✅ SHIPPED — multi-part MEI export (fixed a real export data-loss).** The app's export sheet + Workshop dropped all-but-the-first part on MEI export. Added **`multiPartToMei(MultiPartScore)`** to `crisp_notation` (**`crisp_notation@f613c9f`**) — one `<staffDef>`/`<staff>` per part, each keeping its own clef, element ids part-prefixed so control events stay unique, repeats/voltas/nav from the lead; round-trips through the existing `multiPartScoreFromMei`. Written as a NEW function (single-part `scoreToMei` untouched → zero regression; the shared helpers gained only a default-`''` prefix param). Wired into `lib/shared/music_io/music_export.dart` + the Workshop MEI case (**`8bf75a2`**) so a 4-part score now exports all 4 staves. +1 lib test; 1672 core green; app analyze clean. **Follow-up (unclaimed):** `multiPartToKern` (multi-`**kern`-spine) + `multiPartToMscx` (multi-`<Staff>`) — kern/MuseScore readers are already multi-part, so same pattern. **(codec-gaps arc below is SHIPPED/idle.)**

- **opus (codec-gaps)** · ✅ **idle / SHIPPED — EVERY closeable codec round-trip gap the sweep found is now closed** (writer+reader → probe → flip the `roundtrip_features_test` matrix cell → ship to public `crisp_notation@main`; library only, no app hot files). **MEI (all):** ornaments (`d688a43`), dynamics `<dynam>` (`2c9011b`), repeats+voltas `@left/@right`+`<ending>` (`32c17c7`), navigation `<repeatMark>` (`5abfb69`), lyrics `<verse>/<syl>` (`5f2f82b`), tremolo `@stem.mod` (`af6c80d`). **kern (all):** repeats barline `:|`/`|:` (`c0176ff`), lyrics parallel `**text` spines (`0ab5646`), dynamics `**dynam` spine (`19decf9`), voltas `*>N` + navigation `!!nav:` comment (`4b01f18`) — the spine work is conditional (emitted only when the marking exists) so every other kern doc stays byte-identical. **Only remaining droppedBy cell:** tremolo in **kern/ABC** — a genuine format limitation (tremolo isn't standard there; carried in MusicXML `<tremolo>` + MEI `@stem.mod` only). All 1642 core tests green throughout; the matrix now guards every fix. **Then added MuseScore as a 5th matrix codec** (`0fa7379`): the `.mscx` codec is a documented note-content subset dropping grace/dynamics/repeats/voltas/navigation/lyrics/tremolo — all extendable like MEI/kern were. **Then closed ALL of them:** grace `<acciaccatura>/<appoggiatura>` (`79f4619`), repeats `<startRepeat/>/<endRepeat/>` (`1746c2a`), dynamics `<Dynamic><subtype>` (`b18ce60`), tremolo `<Tremolo><subtype>` (`1da4685`), lyrics `<Lyrics><text>` (`d0f5891`), navigation `<Marker><subtype>` (`14ef4f0`), voltas `<Volta><endings>` (`8a34e5c`). **⇒ MusicXML, MEI and MuseScore now carry EVERY marking in the 125-cell matrix; ABC carries all but tremolo; kern all but tremolo. The single remaining `droppedBy` cell is tremolo in kern/ABC — a genuine format limitation (not standard there).** 1667 core tests green throughout; the matrix guards all 18 marking types × 5 codecs. **Capstone (`f7965f7`): a fuzzing property test** (`roundtrip_markings_property_test.dart`) generates 120 seeded scores with RANDOM marking combinations (a note carrying grace+tremolo+dynamic+lyrics, stacked repeats+voltas, etc.) and asserts every marking survives write→read on the 3 full-coverage codecs — 360 round-trips, plus a corpus sanity check so it can't pass vacuously. **CODEC ROUND-TRIP EFFORT COMPLETE + FUZZ-VALIDATED** across the 5 general interchange formats. (Probed GPIF too — it's a documented *tab* subset by design, so its general-marking drops are scope, not bugs; not treated as gaps. MIDI is inherently lossy.) 1671 core green. **(CI-fixes work below also SHIPPED/idle.)**

- **opus (looper-core)** · ✅ **idle / SHIPPED — roadmap item 4 "a much better Looper": the pure core (`06b1849`).** `lib/core/audio/loop_record.dart` (pure, 9 tests): `quantizeLoopBars` (snap a take to a whole number of bars → **seamless loop lengths**), `snapPunch` (snap a raw record window to bar boundaries → **quantised punch-in/out**), and a generic `LoopStack<T>` overdub layer stack (add · **undo/redo** with add-clears-redo · per-layer mute → `activeLayers` vs `layers`). NO hot-file touch. **Remaining item 4:** a surface — the natural application is turning the DrumKit's record into a **layered overdub looper** (each take a `LoopStack` layer: record→layer, undo removes a take, mute silences one, playback sums `activeLayers`) — a real refactor of the DrumKit's single-pattern model, so a claimed slice of its own; or wiring the quantisers into the Loop Mixer.

- **opus (ci-fixes)** · ✅ **idle / SHIPPED — GitHub Actions health.** CI-infra only (no product hot files). ✅ **Deploy fixed** (`27f928a`): Vercel free tier caps prod deploys at 100/day; the old `workflow_run: [CI]` trigger fired on every green CI (>100/day under heavy multi-agent pushes → `api-deployments-free-per-day`). Switched to an **hourly `schedule` + `workflow_dispatch`** (≤24/day, 4× under cap). Residual quota reds self-heal as the pre-change backlog ages out of the rolling 24h window. ✅ **aec-native** confirmed green (my earlier DTD-deadlock C fix passed CI). ✅ **ios-release** confirmed green (pub-get sibling-checkout fix held; all signing secrets present). ✅ **App Store screenshots GREEN** — the 60-min iPhone-Capture hangs were on older code; current main captures in ~20min. Added a **per-step wall-clock timeout** as a safety net (`2e3605b`) that names any future hang (`SHOT_STEP_TIMEOUT`). One real gap found + fixed (`6472679`): the Workshop step's bare `find.byIcon(Icons.piano)` was ambiguous on the wider iPad layout (game cards also show a piano) → iPad missed `03_workshop`; scoped the tap to the AppBar's single piano. **Verified GREEN — full 5+5 set captured (both `*_03_workshop.png` present, no skips/timeouts).** Files: `.github/workflows/deploy.yml`, `integration_test/screenshots_test.dart`, `lib/core/services/tts_service.dart`. ✅ **BONUS — fixed the pre-existing `crisp_notation` GPIF meter bug** the libraries-and-tab agent flagged as unclaimed (**`crisp_notation@5bfb0b3`**, public main): the master-bar writer re-stamped the *initial* meter on every bar without an explicit `timeChange`, so a mid-score `4/4→3/4→3/4` read back a spurious `3/4→4/4`. Now tracks a running meter — byte-preserving (the single-track golden is unaffected). The long-failing `gpif_test: a mid-score time-signature change round-trips` passes; 22 gpif + 1537 core tests green. ✅ **BONUS 2 — fixed an ABC mid-score clef-change round-trip bug** found by a targeted codec sweep (**`crisp_notation@a08089d`**, public main): the ABC writer emitted mid-tune key/meter changes but **never a clef change**, so a switch to bass mid-piece was silently dropped (the reader already parsed `[K:… clef=…]`). Writer now emits the clef (header + mid-tune, always re-stating the running key so the reader has a tonic to anchor `clef=`); reader now recognizes `clef=treble` (a change *back* to treble) and only records a key change when the key actually differs. MusicXML/MEI/kern already round-tripped clef+key changes — ABC was the sole gap. +3 regression tests; 1540 core green. ✅ **BONUS 3 — fixed ABC dropping grace notes from any id-less note** (**`crisp_notation@7c4f054`**, public main): the writer gated `{…}` grace output on `id != null` (copied from the adjacent id-keyed chord-symbol/dynamics branches), but grace notes live on the NoteElement itself (like articulations/ornaments, which aren't gated) — so a note without an id silently lost its grace, though the reader parses `{…}` positionally and MusicXML round-trips the same note fine. Dropped the id gate; +1 regression test (id-less/id-bearing × both grace styles); 1541 core green. **These 3 codec fixes came from a systematic write→read self-round-trip sweep (meter/clef/key/articulation/ornament/grace/tie × MusicXML/MEI/kern/ABC); the remaining probed attributes all round-trip cleanly.** ✅ **BONUS 4 — a permanent round-trip regression matrix** (**`crisp_notation@e8314a1`**, public main): new `test/roundtrip_features_test.dart` — **100 generated cases** pinning every musical marking (meter/clef/key changes, 5 articulations, 3 ornaments, grace, tie, slur, dynamics, tuplet, chord, double-dot, repeats, volta, navigation, voice 2, lyrics, tremolo) through write→read on all 4 codecs. Each feature declares which codecs legitimately drop it (`droppedBy`): supported cells are regression locks; dropped cells are explicit expectations that fail loudly if support is later added. Complements `roundtrip_property_test.dart` (note *content*) by locking the *markings*. 1641 core tests green. **Documented codec gaps surfaced (unclaimed follow-ups, real library features not one-liners):** neither MEI nor kern carry **dynamics / repeats / voltas / navigation / lyrics**; ABC/MEI/kern don't emit **tremolo**. MusicXML carries everything. ✅ **BONUS 5 — fixed the MEI ornament gap** (**`crisp_notation@d688a43`**, public main): MEI ornaments are `<trill>`/`<mordent>`/`<turn>` control events anchored by `startid`, and the writer emitted them only for a note with an xml:id — so an ornamented **id-less** note lost its ornament (same class as the ABC grace drop); it also only scanned voices 1–2. Now an ornamented id-less note gets a deterministic position-derived id (`o<measure>_<voice>_<index>`, unique so no collision) stamped on both the `<note>` and its control event, across all 4 voices. Flips the matrix's 3 ornament×MEI cells to preserved; +1 mei_test; 1642 core green. **So all three interchange formats now round-trip ornaments; MEI's remaining gaps (dynamics/repeats/voltas/navigation/lyrics) are larger features.**

- **opus (rhythm-quantise)** · ✅ **idle / SHIPPED — the beginner rhythm "Relevanzschwelle" engine (roadmap step 2 DONE; `04fc357`).** New **pure, Flutter-free** `lib/core/audio/rhythm_quantize.dart`: `detectOnsets(energy frames)` (rms floor + rise factor + refractory, strength = attack peak; mirrors `beat_capture`'s rule but generic) → `chooseResolution` **auto-picks the coarsest grid the player can actually feel** (finest needed within tolerance, no two onsets colliding, never finer than a **skill `cap`** of `RhythmResolution` quarter/eighth/tripletEighth/sixteenth — so loose 1/8 settles on 1/8, and a beginner cap collapses stray 1/16 flams) → `quantizeRhythm` drops sub-strength noise, snaps, and collapses same-step hits (strongest kept) → `{resolution, hits[step, snappedMs, originalMs]}`. 15 tests (subdivision maths, auto-picker across all four grids + loose-feel + cap + single-onset, snap/collapse/strength-filter, onset detection, detect→quantise end-to-end); analyze clean. NO hot-file touch; complements the fixed-grid `beat_capture.quantizeToBeat`. **This is the shared front-end for the rest of the roadmap** (DrumKit record → model conversion → Looper). Recorded in HISTORY. ✅ **Roadmap step 3 CORE also SHIPPED (`994f5b2`): `lib/core/audio/rhythm_convert.dart`** — `beatOfHit`/`hitToStep` (a hit's musical position is grid-independent, so it re-places onto any subdivision) + `toTrackerColumn` (→ a Tracker channel, which already exports Score/MusicXML/MIDI/module + Song Book) + `toDrumPattern` (→ a Loop Mixer `DrumRowsPattern`). Per-hit pitch/drum are caller-supplied. 7 tests. So a recorded rhythm now converts to the grid models and reaches every notation/export path via existing bridges. ✅ **Roadmap item 1 (record UI) also SHIPPED (`cb1ba49`): DrumKit tap-to-record** — a Record button captures pad taps at their loop position, on stop quantises the take onto the step grid (`quantizeToResolution(eighth)` → `toDrumPattern`, overdub) and adds the fixed-grid `quantizeToResolution` to the engine. Device-free, `debugRecordTaps` seam, +3 tests. **Remaining roadmap: item 1 polish (mic beatbox record · Save-to-Song-Book from the DrumKit · skill-tier setting · more voices) + item 4 (Looper).**

- **opus (spot-the-parallels)** · ✅ **idle / SHIPPED — new voice-leading minigame (`63fcd17`).** "Spot the Parallels": a two-chord SATB progression is engraved on a grand staff; tap **Clean** or **Parallels!**. The answer key is the library's `checkVoiceLeading` (parallel 5ths/8ves) — the engine is **ground truth**, so the 9 authored templates (4 clean + 5 parallel-only) are verified-correct in the test and transposed for variety (parallels are interval-invariant, so the label survives transposition). Correct answers play the chord pair so you HEAR the motion; SRI under `harmony.parallels.<template>`. New `lib/features/games/harmony/spot_parallels_screen.dart` (screen + pure `ParallelsTemplate`/`buildRound` generator) + a `GameInfo` under 'harmony' + `kStarThresholds['spot_parallels']` + a new **g9-10 `voice_leading` curriculum concept** (so the coverage audit places it) + 6 tests (template-labels-vs-library, parallel-only crispness, transposition invariance, widget render+SRI). Curriculum/consistency/layout audits green; whole-project analyze clean. Top of the harmony ladder — the app's first part-writing drill.

- **opus (anavis-intelligence)** · ✅ **idle / SHIPPED — intelligent AnaVis everywhere (a real analysis engine, not hand-authored).** Turning AnaVis into an engine that reads ANY score and annotates it, adaptive for kids ↔ experts. ✅ **Slice 1 SHIPPED — the brain, IN THE LIBRARY** (`crisp_notation@8502508`, pushed to public main; `../crisp_notation` fast-forwarded). New `crisp_notation_core/src/theory/analysis.dart`: `analyze(Score,{Key?}) → ScoreAnalysis{key, segments, cadences}`. Slices the score into vertical sonorities across all 4 voices → `identifyChord` → `romanNumeralFor` in the detected key (`keyOf`) → **T/S/D function** (`functionOf`, secondaries=dominant); flags **non-chord tones** (remove-one-and-reidentify → recovers suspensions/passing tones); reads an **implied chord** from a purely melodic/arpeggiated bar; **merges** repeated chords; detects **cadences** (authentic/half/plagal/deceptive). 8 library tests. Phrase/form detection deliberately deferred. ✅ **Slice 2 SHIPPED — the computed view** (`6f1b05b`). `lib/features/games/composition/score_analysis_view.dart`: `ScoreAnalysisView` feeds a real `Score` through `analyze()` and renders key chip + engraved staff + **function-coloured chord blocks** (tap to hear) + **roman numerals** + **cadence markers** + legend, with an **`AnalysisDepth` dial (kids/learner/expert)** — kids=colours only, learner=+romans/cadences, expert=+chord symbols. Wired a "Read from the notes (auto-analysis)" section into `AnalysisHubScreen` (`kAnalysisExamples`). +11 EN/DE keys; 19 app tests. ✅ **Library follow-up (`crisp_notation@8646658`): `HarmonicSegment.elementIds`** — analyze() now returns the NoteElement ids per segment, so a consumer can colour/highlight the notes of a chord. ✅ **Slice 3 SHIPPED — the Workshop "Analysis" toggle** (`afaf7c5`, the killer feature). An **Analysis** item in the Workshop overflow menu runs `analyze(_doc.buildScore())` live and (a) **tints every note by harmonic function** (green/blue/orange) via the existing `elementColors` seam (base layer; selection amber + playback green still override), using the new segment `elementIds`; (b) shows a **compact banner** above the score — detected key + roman progression + cadences. Additive + guarded by `_showAnalysis` (default off), auto-detects the key. Rebased cleanly onto the `libraries-and-tab` agent's concurrent Workshop edits. +1 ARB key; 64 workshop tests. ✅ **Slice 5 (part 1) SHIPPED — Song Book host** (`9f6cba6`). The song player gained an **"Analyse the harmony"** action → the computed `ScoreAnalysisView` over the song's real `Score`, so any built-in public-domain song OR imported/user song is readable for key + romans + function colours + cadences at the kids/learner/expert depth. Pure reuse + `_SongAnalysisScreen` host + 1 ARB key + test. ✅ **Slice 6 SHIPPED — the expert layer** (`01146bf`). `ScoreAnalysisView` grows over the same analysis: a **tension curve** (learner+, a sparkline tonic-low→dominant-high so you SEE the home→away→tension→home arc, `_TensionPainter`); a **voice-leading check** (expert — feeds the chord segments top-voice→bass to the library's `checkVoiceLeading`, flags parallel 5ths/8ves or "clean ✓", only for a ≥3-voice texture); and a **non-chord-tone list** (expert). +6 EN/DE keys; 5 tests. ✅ **Slice 5b SHIPPED — Loop Mixer host** (`0f2b4f1`). Selecting a song progression now shows a strip under the harmony chips with its chords **coloured by function** (I/IV/V/vi → tonic/subdominant/dominant) + roman labels, so the kid sees the home→away→tension→home shape of the vamp. Made the colour helper public (`harmonicFunctionColor`). ✅ **Slice 4 SHIPPED — computed form** (library `crisp_notation@b575a9b` `detectForm()` + app `dc412fe`). `detectForm(Score)` fingerprints each measure's top-voice melody transpose-invariantly → letters A/B/C (same letter = the tune came back) → merged sections. `ScoreAnalysisView` gained a **Form row** (coloured sections, widths ∝ measure count) shown only when the piece repeats material, so through-composed pieces stay quiet. Completes the "AnaVis" name (visualising form). +1 key; 3 library + 1 app test. **THE ANAVIS EFFORT IS COMPLETE:** engine (`analyze` harmony + `detectForm` form + `elementIds`) across FIVE surfaces — the hub, the computed view, the Workshop (live note-tint + banner), the Song Book, the Loop Mixer — with a kids↔learner↔expert dial (colours → romans/cadences/tension-curve → chord-symbols/voice-leading/NCTs). ✅ **Flourishes SHIPPED:** a **circle-of-fifths key wheel** in the expert layer (`cdf1000`, `_KeyWheelPainter`, key highlighted, minor→relative-major position); and **phrase-level form grouping** (`crisp_notation@e859e57`) — `detectForm` now tries phrase lengths and picks the one exposing the most repetition, so a recurring 4-bar phrase reads as ONE section (a real A-B-A, not A-B-C-D-A-B), falling back to bar-level; the app form row upgrades automatically (no app change). **Remaining (deep-expert only, if ever wanted):** figured-bass display; pc-set/Forte labels (library `set_theory` already has them); modulation regions on the wheel (library `localKeys`); memoize `analyze()` in the Workshop if a big score ever lags. **AnaVis went from hand-authored examples to a real engine that reads the music, from pre-reader colours to expert voice-leading.** **Perf note:** analyze() runs per-rebuild while the toggle is on — fine for bounded scores; memoize on doc-change if it ever lags. Worktree `../mus-textbook`, branch `feature/textbook-prose-anavis`; engine in the shared `../crisp_notation` clone.

- **opus (inspect / looking-glass)** · ✅ **idle / SHIPPED — 🔍 Looking Glass EVERYWHERE (all surfaces + all hover spots + the composition sandboxes).** The "do it all" pass is done. ✅ **Multi-part full-score canvas hover** (`2ca6b0b`) — `MultiPartCanvas` gained `onElementHover(globalId?)` resolving the note inside its own scroll space; the card pins to a fixed corner (the canvas scrolls). ✅ **Tracker grid hover** (`8a5e947`) — per-cell `MouseRegion` → the note + row-chord in a corner card; leaving the grid clears it. ✅ **Tab grid hover** (`5c40199`) — per-cell hover → fretted note + column chord in a corner card. ✅ **Games** (`012802b`) — the toggle on the two composition SANDBOXES (My Melody, Melody Doodle: tap a note → its card; My Melody also suppresses placement on that tap). **Deliberately NOT on quiz games** (Roman Numerals, Function/Chord/Cadence quizzes, note-reading drills) — the card would reveal the answer; Inspect belongs on editing/reading/sandbox surfaces, not the challenge. (StaffView has no region controller, so the sandboxes are tap-only; hover lives on the score-views + editor grids.) Every touched suite green; analyze clean. **NOW TRULY COMPLETE.** Was: Worktree `../mus-textbook`, branch `feature/textbook-prose-anavis`. A toggle-activated "Looking Glass": flip it on, tap a note/cell, and a card tells you what it is — note name(s), scale degree in the key, chord symbol + roman numeral + T/S/D function + non-chord-tone status — all computed from the shared `analyze()` engine (no hand-authoring). UX decision: an **icon toggle**, not bare long-press/double-press (avoids gesture conflicts, discoverable). Reusable core is **`lib/features/games/composition/music_inspect.dart`** (`InspectInfo` + `inspectElement(score,id,analysis)` + `showInspect()` bottom sheet; the chord row shows even without a key, plus a free `detail` line). ✅ **Slice 1 — Song Book** (`5dcf492`; 🔍 app-bar toggle; tap a note → card, else play). ✅ **Slice 2 — Composition Workshop** (`c79796d`; 🔍 in the ⋮ menu; resolves single-part local ids AND full-score `p<part>:<rawId>` globals). ✅ **Drag-safety** (`28dfec5`) — in the Workshop placed notes are draggable, so all six drag handlers early-return in Inspect mode (a poke must never nudge a note — per the maintainer's call). ✅ **Slice 3 — Advanced Tracker** (`ed30fe6`; 🔍 app-bar toggle; a cell reports its note + the CHORD the whole row sounds via the new **library `Pitch.fromMidi`** `crisp_notation@09d9ab3` → `chordSymbolFor` + its instrument/effect). ✅ **Slice 4 — Tab Workshop** (`4adf7b3`; 🔍 app-bar toggle; a string×fret cell → fretted note + column chord + string/fret/diagram-name; capo is display-only so it reads the sounding pitch playback does). Rebased cleanly onto the `libraries-and-tab` agent's tree (no collision). ✅ **Slice 5 — desktop HOVER** (`63cad36` Workshop, `7b4623f` Song Book) — the original "mouse on hover" ask: with Inspect on, sweeping the mouse over the score raises a small **floating card** describing the note under the cursor (a true looking glass). A `MouseRegion` resolves the element via the existing `ElementRegionController.elementIdsIn`, re-running `analyze()` only when the hovered element changes (cheap pixel sweep); the card is `IgnorePointer` so it never steals the hover; **no-op on touch** (tap still opens the full sheet). Refactored the card body into a shared `music_inspect.inspectBody()` used by both the tap sheet and the hover overlay. Each slice unit-tested (incl. drag-suppression + hover-shows/clears seams); every app suite green (Song Book, 66 Workshop, 45 Tracker, 20 Tab); analyze clean. **THE INSPECT EFFORT IS COMPLETE** — one reusable core, four surfaces + desktop hover on both score views, kids-to-expert depth (note name → degree → chord/roman/function/NCT). **Remaining (optional, if ever wanted):** hover on the multi-part full-score canvas + the Tab/Tracker grids; the same card on games.

- **opus (crisp_notation-musicxml)** · ✅ **idle / SHIPPED (in the LIBRARY,
  `crisp_notation@54538a5`, bumped 0.4.5→0.4.6; `../crisp_notation` fast-forwarded
  so local+CI use it).** An audit of the MusicXML reader/writer (the format the
  Workshop saves/reopens a child's score in) found **2 silent-corruption bugs**,
  both in gaps the 150-score roundtrip property suite doesn't generate:
  (1) **voice-2/3/4 tuplets corrupted BOTH voices** on save/reopen — the writer
  stamped an inner voice's triplet onto voice 1 and wrote the inner voice with no
  time-modification (voice 1 read 3/4 not 4/4); now routed per-voice via
  `Measure.tupletsForVoice`. (2) **a tempo change in a score with no initial
  tempo** was relocated to bar 1 and lost as a change; the reader now treats a
  metronome as the initial tempo only in the first measure. Regression test
  verified to fail on the old code; full MusicXML + 150-score property suite
  green. **@tracker-ui / anyone using `multiPartToMusicXml`/`scoreToMusicXml`:**
  no API change — inner-voice tuplets and mid-piece tempo changes now round-trip
  correctly. MIDI reader audited clean. ✅ **ABC FOLLOW-UPS SHIPPED
  (`crisp_notation@0caafdf`, 0.4.6→0.4.7, `../crisp_notation` fast-forwarded):**
  (a) **octave-specific accidental carry** — `^c c,` no longer imports the lower
  `c,` as C♯ (reader+writer now key the in-bar accidental by pitch+octave per
  ABC 2.1); (b) **sparse-lyric alignment** — a lyric on notes 1 & 3 no longer
  shifts onto note 2 (writer emits one token per note, `*` for unsung); (c) a
  **mid-piece `|]`** keeps its final-barline style. All verified to fail on the
  old code; ABC + 150-score property suite green; mus `import_test` green vs
  0.4.7. **NOT changed (correct-by-design):** the MusicXML endRepeat+bar-style
  item — the reader deliberately ignores `<bar-style>` under a `<repeat>` because
  standard MusicXML writes backward repeats *with* light-heavy, so reading it
  would spuriously mark every imported repeat as a final barline (the field loss
  is cosmetic). **The MusicXML + MIDI + ABC interchange audit is complete.**

- **opus (native-aec-dtd)** · ✅ **idle / SHIPPED — the native C AEC had the same DTD
  deadlock I fixed in Dart.** `native/aec/src/aec_dsp.c`'s `aec_dtd_update` is a
  byte-for-byte port of the pre-fix Dart `DoubleTalkDetector`: `block += 1` ran
  unconditionally before the far-end gate, so warmup burned during far-end-silent
  blocks; warmup then expired with W still zero → echoEst=0 → rho=0 → freeze →
  re-arms forever. Applied the same fix (count warmup only on far-end-active
  blocks; treat ee==0 as "no info, don't freeze"; hold the full hangover on arm).
  Added a native regression test (silent far-end lead-in, echo only) verified to
  fail on the old C: **plain 44.5 dB → +DTD 5.2 dB (deadlock)** — matching the
  Dart ~39 dB regression; now 13/13 native tests green via `bash native/aec/
  build.sh`. Zero collision (no agent touches `native/aec/`). Files:
  `native/aec/src/aec_dsp.c`, `native/aec/test/aec_engine_test.dart`.

- **opus (playing-staff)** · ✅ **idle / SHIPPED — "notes light up as they play" across the manual + examples** (`a576ee7`, `9d50d70`). Fixes the gap that examples/lessons played audio with no visible progress. crisp_notation's `StaffView` already exposes `highlightedIds` (repaint-only), and the schedule is always known (each note has a ms duration) — so no library change was needed; the missing piece was a reusable app-side driver. New **`lib/features/games/widgets/playing_staff.dart`**: `ScorePlayback` (ChangeNotifier; `play(List<PlayStep>)` where `PlayStep = ({Set<String> ids, int ms})`) + **`PlayingStaffView`** (a StaffView that lights its scheduled ids on a Ticker created in initState) + `stepsForSequence()`. Wired into: (1) **the whole tutorial/manual** — `TutorialStep` gained a `beats` field; the sheet now uses `PlayingStaffView` and, on Listen, plays `beats` AND lights the score's notes in time (id scheme `n{i}`); **all 41 primer melody steps converted** `playSequence(_run(X))` → `beats: _run(X)`, so every textbook lesson + every game's "?" how-to animates from one change; (2) **both analysis views** — form lights each section's notes, harmony lights each chord. Tests: PlayingStaffView timing (n0→n1→cleared), tutorial Listen lights the score, schedule ids line up with engraved ids. Full suite **1304 green**, analyze clean. ⚠ touched hot shared `primers.dart` (41 mechanical step edits) + `tutorial.dart`/`tutorial_sheet.dart` — rebased. ✅ **In-game sweep started (`1fb36a1`):** `ending_detective` (melody lights note-by-note; `Score.simple` ids e0,e1,…) + `spot_upbeat` converted; **enabler added** so reading-scaffold games can highlight WITHOUT losing the note-name overlay — `PlayingStaffView` gained `showNoteNames`/`noteNameStyle`, and **`ReadingStaffView` gained an optional `playback` controller** that delegates to it. `melody_echo` already had karaoke highlight. Full suite **1321 green**. ✅ **FULL in-game sweep SHIPPED** — every minigame that shows a score and plays a melody now lights its notes as they sound: `ending_detective`, `spot_upbeat`, `melody_echo` (pre-existing), + this batch: **`question_answer`** (two staves — the question lights during the question, the tapped answer during the answer, via one highlighter per staff and a leading empty-id delay step), **`tie_slur`/`beam_flag`/`whole_half`/`articulation_read`/`sync_read`/`triplet_read`/`ornament_read`** (ReadingStaffView + `playback:`), **`enharmonic`/`step_skip`** (StaffView→PlayingStaffView), **`rhythm_tap`** (Score.simple e-ids ↔ beats), **`my_melody`** (dual InteractiveStaff/StaffView — both support `highlightedIds`, driven by a local timer chain since PlayingStaffView is StaffView-only). Only `interval_ladder` is deferred (an N-rung ladder of one-note mini-staves — a per-rung-controller job like question_answer×N, low payoff). **The playback-progress gap is closed** across the manual, the analysis views, and the games. ✅ **Responsive layout pass:** answer buttons that flung the two options to the far left/right on wide screens now sit centered — new **`AnswerRow`** (`game_widgets.dart`, the binary counterpart to `AnswerGrid`: `Center` + `maxWidth: 480`) wired into **12 binary games** (tie_slur, beam_flag, enharmonic, whole_half, same_diff, modulation_ear, direction_ear, run_direction, spot_upbeat, sync_read, triplet_read, triad_seventh) — a plain `Row(` → `AnswerRow(` swap, unaffected on phones. A new **`test/layout_audit_test.dart`** pumps EVERY game at SE 375×667 + iPad 810×1080 × EN/DE and asserts **no RenderFlex overflow** (via `takeException`, no taps); it caught + fixed a `_PlayRow` overflow in the analysis views on a 375px phone (long localized "Play the whole piece" button — now a Column so the hint wraps below). **⚠ tracker agent:** the audit flags a small **~9px overflow in the `tracker` tile at 375px (both locales)** — excluded from the audit (your hot file) so it doesn't block; please trim it. Worktree `../mus-textbook`, branch `feature/textbook-prose-anavis`.

- **opus (textbook-prose)** · ✅ **idle / SHIPPED — richer per-concept textbook prose + AnaVis-style form-analysis view** (`2f63709`). Two connected pieces in the **Textbook reader** (the read-through manual). (A) **Per-concept lesson prose** beyond the game primers: `conceptProse(l10n,id)` (`textbook_i18n.dart`) returns the textbook's own teaching paragraph (its voice, our words), rendered atop each expanded `_ConceptTile` above "Read the lesson"; **fallback-safe → null where unauthored**, so coverage grows concept by concept. First tranche = the **17 most abstract concepts** (intervals, triads, key sigs, enharmonics, circle of fifths, minor scales, 7th chords, cadences, harmonic function, roman numerals, modulation, modes, syncopation, triplets, song/musical form, transposing instruments), EN+DE. (B) **AnaVis-style form-analysis view** (fills PLAN §AnaVis as lesson content): reusable `FormAnalysisView` (built on the existing `FormTimeline`) plays a piece's sections section-by-section — tap a coloured block to hear that section (highlight ring), or play the whole; worked `kFormExamples` are **our own abstract A/B/C/D motif renditions → no melody licensing risk** (ternary + rondo for `musical_form`; verse-chorus + AABA for `song_form`), wired into the form concept tiles as a **"See the form"** action. `FormTimeline` gained an optional `onTapSection` (additive; the game stays inert). New `form_analysis_view.dart` + `form_analysis_view_test.dart` (example invariants, screen render+tap, prose authored/null + de/en). **Full suite 1242 green, analyze clean.** Touched shared `app_en.arb`/`app_de.arb` + `textbook_i18n.dart`/`textbook_screen.dart` (additive only). ✅ **Follow-up SHIPPED (`84a553d`): per-concept prose now covers ALL 70 concepts (100%, EN+DE)** — the remaining 53 authored (grade 1–2 opposites; grade 3–4 reading/rhythm/scale fundamentals + the technique/aural/creating/repertoire strands; grade 5–6 clefs/accidentals/articulation; grade 7–10 chord-quality/dictation/phrasing/score-reading/ornaments). `form_analysis_view_test` now pins full coverage (every `kConcepts` id → non-null prose in both locales). Full suite **1264 green**, analyze clean. ✅ **Follow-up SHIPPED (`d3cb309`): the three remaining AnaVis items — score-above-timeline + harmonic-function view + standalone tile.** (1) `FormExample.scoreOf()` builds a real `crisp_notation` Score (one 4/4 bar per section) engraved on a `StaffView` **above** the coloured blocks (barlines line up with sections). (2) New **`HarmonyAnalysisView`** colours a chord progression by function — tonic=home/green, subdominant=away/blue, dominant=tension/orange — with a legend; tap a chord to hear the C-major triad. `kHarmonyExamples`: I–IV–V–I + ii–V–I for `harmonic_function`; perfect (…V–I) vs half (…V) cadence for `cadences`; wired into those tiles as **"See the harmony"**. (3) New **`analysis_view`** sandbox tile (composition module, no stars) → **`AnalysisHubScreen`** ("See the Music") shows every form + harmony example in one page; placed under `musical_form` so coverage stays orphan-free. +20 EN/DE keys; full suite **1272 green**, analyze clean. ✅ **Final follow-up SHIPPED (`6107392`): the deeper harmonic-function overlay.** `HarmonyExample.scoreOf()` engraves the progression as a real score (one 4/4 bar per chord = a whole-note chord via `NoteElement` stacked pitches); the T/S/D colour spans now sit **under that engraved score**, bar-for-bar. Cadence examples gained a **marker under the final chord** (up-bracket + label: perfect = "comes to rest", half = "left open"). +4 keys; full suite **1292 green**, analyze clean. **The textbook prose + AnaVis arc is now COMPLETELY closed — nothing optional remains.** Worktree `../mus-textbook`, branch `feature/textbook-prose-anavis`.

- **opus (tts-macos)** · ✅ **idle / SHIPPED — TTS slice 4: macOS `libcrispasr` bundling (dev-verified).** `tool/bundle_macos_tts.sh` collects `libcrispasr` + its **8 deps** (ggml ×5, Homebrew opus/ogg) into a **self-contained** set (copy-by-referenced-name → `@rpath`, strip foreign rpaths to `@loader_path`, sign, + a static self-containment check). `KokoroModelStore.libPath()` gains a cascade (override → `.app` Frameworks → `~/.cache/crispasr` → default). **Verified: synth runs through the bundled set with only `@loader_path`** (loads the bundle's ggml, not the machine's) → portable. Dev: run the script → `flutter run macos` → HD tile appears. `docs/TTS_MACOS.md` (dev + release Frameworks embed + App-Store caveats); cascade unit-tested; analyze clean. **Shared `macos/` Xcode project NOT touched** (multi-agent safety) — new files only (`tool/`, `docs/`, store cascade). Remaining: release `.app` embed + iOS/Android/web.

- **opus (tts-settings)** · ✅ **idle / SHIPPED — TTS slice 3: the "Natural voice (HD)" settings tile.** A tile in Settings (below the sound switch) that opt-in **downloads the ~135 MB Kokoro model** (`backend.download()` → CrispASR's registry+`cacheEnsureFile`) with a spinner, then "On ✓"; once cached, narration auto-upgrades to the neural voice. `TtsService` gains `hasNeural`/`neuralSupported`/`neuralReady`/`downloadNeuralVoice`; `NeuralTts` holder carries `supported`+`download`. **Shown only where libcrispasr loads** (invisible until it's bundled per platform), and degrades gracefully with no TtsService (settings tests untouched). EN/DE ARB; 24 TTS/settings tests green; analyze clean. Touched shared `main.dart`+ARBs+settings — rebased. Remaining TTS work: per-platform lib bundling (macOS first).

- **opus (tts-crispasr)** · ✅ **idle / SHIPPED — TTS slice 2: CrispASR/Kokoro NEURAL backend via CrispASR's OWN registry + downloader.** Behind the `TtsBackend` seam: `crispasr_tts_backend.dart` (crispasr pub FFI → libcrispasr → **Kokoro**, Apache-2.0; a background-isolate `runKokoroJob` resolves via `registryLookup` + downloads via `cacheEnsureFile` = the CLI's `-m auto` path; `synthesize` → PCM16 → `wavBytes` → `AudioService.playWavBytes`) + `kokoro_model_store.dart` (**no hand-rolled URLs** — the GGUFs are already published at `cstr/kokoro-82m-GGUF` + `cstr/kokoro-voices-GGUF`; cached into `~/.cache/crispasr`; `isReady` = lib+model cached) + `tts_neural.dart` conditional facade (**web null stub**). Download is **consent-gated** (playback never fetches; `backend.download(lang)` is the opt-in). `TtsService` prefers neural when ready, else flutter_tts. **Verified**: registry→published cstr URL resolves from the app dep, + REAL macOS synth (libcrispasr.dylib → valid German audio); download ABI symbols present. 16 TTS tests green, analyze clean. Dep `crispasr: ^0.8.11` (pub.dev) → CI needs no native lib. Remaining: a settings "Download voice" trigger; per-platform lib bundling (macOS first). Detail in TTS section. Touched shared `main.dart`+`pubspec` — rebased.

- **opus (tracker)** · ✅ **idle / SHIPPED — multi-part MIDI/ABC export in the
  Workshop** (`4210a62`). MIDI + ABC now write EVERY instrument part, not just the
  active one. New pure-notation `lib/core/notation/multi_part_export.dart`
  (`multiPartToMidi` = format-1 SMF one track/part; `multiPartToAbc` = one `V:`
  voice/part; + split/merge), `module_notation.dart` re-exports it.
  `composition_workshop_screen._generateExport` routes mid→multiPartToMidi,
  abc→multiPartToAbc when partCount>1; `kExportFormats` marks MIDI+ABC multiPart;
  new `debugGenerateExport` seam. MEI/kern/MuseScore/LilyPond stay single-Score
  (library writers). 63 workshop + 30 notation tests green. **Follow-up
  (`7455c14`): multi-track MIDI IMPORT** — `multiTrackMidiToMultiPart` (one part
  per MTrk); wired into `notaconv` (a `.mid` with >1 track → all parts →
  module/xml/abc) + the Workshop's `importMultiPart`. MIDI import/export now
  symmetric. Live: 24-track MIDI → 24 channels/parts/voices. **Follow-up
  (`67655a3`): Tracker → Song Book** — a "Save to Song Book" menu item saves the
  groove's pitched channels as multi-part MusicXML (`trackerToScoreParts` →
  `multiPartToMusicXml` → `UserSongsService`), mirroring the Loop Mixer;
  `debugSaveToSongBook` seam + 3 ARB keys. The Tracker now exports to MOD / MIDI /
  Song Book.

- **opus (modes)** · ✅ **idle / SHIPPED — "Which Mode?" ear game (`mode_ear`, scales module).** 3-way ear game: a scale plays ascending as Major (Ionian) / natural Minor (Aeolian) / **Dorian** (minor with a raised 6th, built from exact semitone steps); child taps which. `modePrimer` teaches the three colours (shown + heard). **Closes the `modes` gap** in concept_map. Scales module; EN/DE; [100,600,900]; analyze clean; mode_ear + tutorial + curriculum_coverage + consistency tests green (14). New: `mode_ear_screen.dart`, `test/mode_ear_test.dart`, `modePrimer`. (Also fixed a stray pre-existing import-order lint in game_registry.)

- **opus (modulation)** · ✅ **idle / SHIPPED — "Key Change?" ear game (`modulation_ear`, scales module).** Binary ear game: a C-major phrase either stays in one key or has its second half lifted a perfect 4th/5th to a new tonic; child taps Same key / Key changed. Correct replays the phrase; own SRI `scales.modulation.<same|changed>`. `modulationPrimer` teaches it by ear (stay vs move). **Closes the `modulation` gap** in concept_map (2 gaps left: modes, instrument families). EN/DE; analyze clean (pre-existing composition import-order info untouched); modulation_ear + tutorial + curriculum_coverage + consistency tests green.

- **opus (tts)** · ✅ **idle / SHIPPED — TTS narration, slice 1 (read lessons/instructions aloud).** New `core/services/tts_service.dart`: a `TtsBackend`-abstracted, locale-aware (de-DE/en-US), sound-gated `TtsService` on `flutter_tts` (platform voices — on-device, offline, free). A **🗣 read-aloud button in the shared tutorial sheet** narrates the current step, so **both** textbook lessons and every game's how-to primer get it from one change. Provided in `main.dart` (soundOn synced from settings); degrades safely when unprovided. New dep `flutter_tts: ^4.2.2` (⚠ `pod install` before next Apple build; CI unaffected). Touched shared `main.dart`+ARBs+pubspec — rebased. `tts_service_test` (fake backend) + tutorial tests green; analyze clean (lib+test). CrispTTS = Python-CLI neural engines; the `TtsBackend` seam is left ready for a lightweight ONNX voice (Kokoro/Piper via onnx_runtime_dart) later.

- **opus (textbook-p3)** · ✅ **idle / SHIPPED — Textbook phase 3: narrative + full i18n.** New `features/textbook/textbook_i18n.dart` (ARB-backed, de/en) localises **all 70 concept titles**, the **19 concept-area sub-headers** and **5 grade-band short labels**, plus a **narrative intro paragraph per grade band**. The reader now groups each band's concepts **by area** (sub-headers, first-appearance order) with an italic band intro on top, so it reads like a book. +94 ARB keys ×2 (concept/area/band) +5 label keys ×2, generated from one source of truth. Touched shared ARBs — kept both key sets on rebase. Analyze clean (lib+test); textbook (now incl. a **de-locale** assertion) + curriculum tests green. Also logged the **TTS-narration (CrispASR)** follow-up in PLAN.

- **opus (textbook-ui)** · ✅ **idle / SHIPPED — read-through Textbook reader.** New `features/textbook/textbook_screen.dart` walks the grade-1–10 concept map band by band; each concept expands to its **lesson** (the game's primer via `showTutorial`/`helpPrimerFor`) + **practise** links (`gameRoute`) to its games; untrained concepts show "coming soon", so the reader stays honest as gaps fill. Home app-bar gets a 📖 Textbook button. Reuses the primers as lesson content (phase 0 work). EN/DE chrome; concept titles English for now (l10n a follow-up). New files + home entry + 5 ARB keys; analyze clean; 2 widget tests green. (Textbook phase 4 — the reader UI.)

- **opus (form-view)** · ✅ **idle / SHIPPED — AnaVis-style form view + "Label the Form".** Reusable `FormTimeline` widget (colour-coded, labelled section blocks — same colour = same tune; `showLabels` off at 2★). `form_read` game: hear a piece's sections (each a distinct motif) as a coloured timeline and pick the form (ABA/AAB/ABC at 1★; AABA/ABAB/ABAC/rondo at 2★). `formPrimer` teaches A-B-A by ear. **Closes 2 gaps** (`musical_form` + `song_form`) in concept_map. Composition module; EN/DE; 19 tests green; analyze clean. **3 gaps left:** modes, modulation, instrument families.

- **opus (bughunt-2)** · ✅ **idle / SHIPPED — 2nd bug-hunt wave (new subsystems).**
  Four reviewers over scoring/SRI, Workshop serializers, crisp_notation theory,
  and game answer-generation. **crisp_notation theory core = clean** (verified the
  enharmonic edges: B dim7→A♭, ø7 vs °7, 6–7-accidental keys, secondary-dominant
  labels — all correct + test-pinned). **5 real defects found, fixed + pinned:**
  1. **Streak breaks on spring-forward DST** (`50fbdd4`) — `currentStreak` walked
     back with `subtract(Duration(days:1))` (24 h absolute); the day after
     spring-forward has 23 h, so it skipped the short day and the streak silently
     broke. German (CET/CEST) audience → every spring. Now walks by calendar day.
  2. **Scale Detective could be unsolvable** (`29d5c6d`) — a harmonic-minor round
     could pick the raised 7th as the odd note and neutralize its accidental
     (G♯→G in A minor), rendering a plain valid natural-minor scale with no odd
     note. ~1/6 of minor rounds, every minor tonic. Wrong-note pick now excludes
     the raised leading tone (keeps it as the intended distractor).
  3–5. **Workshop silent data loss** (`34d01de`) — `_splitPiece` dropped
     ornament/grace/accidental/fingerings from every tied piece; `_reid` dropped
     the same for every note in multi-part assembly; `_reindex` left voice-2 ids
     unprefixed so voice-2 dynamics/lyrics detached (and collided across parts).
     All three lost data on render/export/reopen. Fixed + regression-tested.
  Grand total across both waves: **13 real defects found, fixed, and pinned;
  theory core + most game/scoring paths verified clean.**

- **opus (instrfam-game)** · ✅ **idle / SHIPPED — "Which Family?" (`instrument_family`, songs module) closes the `instrument_families` gap.** Reading/knowledge MC quiz: an instrument is named (~19 well-known ones) → tap its orchestral family (Strings/Woodwind/Brass/Percussion/Keyboard); deliberately no timbre-ID audio. `instrumentFamilyPrimer` names the families with examples. SRI `timbre.family.<family>`; 10 rounds, [100,600,900]; EN/DE. `concept_map` now trains instrument_families (0 orphans; only modulation + modes remain untrained). 14 tests green (incl. curriculum_coverage + consistency + tutorial); analyze clean (one pre-existing `form_read` import-order info in game_registry is not ours).

- **opus (textbook-p2)** · ✅ **idle / SHIPPED — song mnemonics + orphan-game
  placement.** (1) `core/curriculum/interval_songs.dart` — interval-mnemonic table
  (Kuckuck = falling minor 3rd; Alle-meine-Entchen = major 2nd up; …) with a test
  that each demo's notes span exactly the stated interval + direction; a Kuckuck
  step added to `intervalsPrimer` (shown + heard). (2) **Placed all 56 orphan
  games** — not Zeitvertreib but the practical strands the theory map omitted:
  added `ConceptArea.technique` (keyboard/cello/guitar/percussion corners),
  `aural` (sing/echo), `creating` (compose/arrange), `repertoire` (real songs), a
  `reading_fluency` concept, and attached the bass/theory twins to their existing
  concept. **Coverage 74/130 → 130/130 placed (0 orphans), 70 concepts**; the gap
  report now shows only the 8 truly-untrained concepts. EN/DE; analyze clean; 9
  tests green.

- **opus (textbook-p1)** · ✅ **idle / SHIPPED — Textbook phase 1: concept inventory + gap analysis.** `core/curriculum/concept_map.dart` (60 grade-1–10 concepts, our words) + `coverage_gaps.dart` + a test that PRINTS the gap report and guards no-dangling-refs. **Reveals the 8 untrained concepts** (verse/chorus form, syncopation, triplets, ABA/rondo form, modulation, ornaments, modes, instrument families), many thin (1-game) concepts, and 56 orphan games; 74/130 games placed. Also wrote up the **bachelor-level extension + OER-source licence registry** (GFDL/NC = facts-only; CC-BY(-SA) = adaptable) and an **AnaVis-style form-analysis view** idea (fills the form gap). Pure Dart + test, no game/UI touch. Analyze clean; 3 tests green.

- **opus (primer-quality)** · ✅ **idle / SHIPPED — primers revised to the 9yo bar + textbook-mode spec**. Audit found `cadencePrimer` had NO notation (both steps audio-only) and unexplained "V/I"; `upbeat`/`enharmonic`/`voices` each had an audio-only step; `seventh`/`phrase` used jargon. Fixed: **every step now has an engraved example** (new helpers `_progression` cadences, `_pickup` shows a real anacrusis bar, `_spelled` shows F♯ vs G♭ at their true staff spots), and the jargon ("V then I", "the tonic", "a third apart: root/third/fifth") is now concrete kid language. Also **wrote up the Textbook / read-through curriculum vision** (new section above `## Delivery`) incl. the Bundesländer-licensing constraint, the song-mnemonic examples (Kuckuck = descending minor 3rd), and the gap-analysis method. Analyze clean; tutorial + gate green.

- **opus (bughunt)** · ✅ **idle / SHIPPED — 4 real defects found by an adversarial
  audit of the numeric core.** Each verified by running the code before/after,
  each pinned by a regression test proven to fail on the old code:
  1. **`pitch_analysis`: octave-halving above ~1503 Hz** (`ff5dde1`). The
     key-maxima scan started at `minLag`, not 1; the NSDF crossing that opens the
     fundamental's segment sits at ~3T/4, which for short periods is *below*
     minLag → the peak at T was skipped and 2T won. `1600→800, 1760→880,
     2000→1000, 2100→1050`, all at **clarity 1.00**. Broke the top quarter of the
     detector's own declared range; the suite topped out at A5 so it never saw it.
  2. **`chroma_analysis`: the silence gate gated nothing** (`ff5dde1`). It summed
     the *peak-normalized* chroma → scale-invariant → only bit-exact silence ever
     gated. A triad at amp 1e-9 scored identically to 0.5; near-silent noise was
     emitted as a confident "A#maj7 (68%)". Now gated on absolute band level.
  3. **`loop_engine`: unvalidated tempo from a share token** (`a0a94e5`). Every
     other spec field is validated; tempo passed raw into `60000 ~/ tempoBpm`.
     `t:0`→IntegerDivisionByZero, `t:-100`→negative buffer RangeError,
     `t:60001`→ticker modulo-by-zero every frame, `t:1`→42 MB WAV on the UI
     thread. Clamped to 40..240 at both entry points.
  4. **`aec_offline`: DTD deadlocked the filter** (`8d803ee`). Warmup counted
     far-end-*silent* blocks (where the filter can't converge), so it expired with
     W zero → ee=0 → rho=0 → freeze → W can never adapt → frozen forever. ~280 ms
     of capture-before-playback (the normal case) cost **~28 dB for the session**.
     Every existing DTD test had the far-end active from block 0.

  ✅ **FOLLOW-UP SHIPPED — formantShift is now a real formant shifter.** It scaled
  *time-domain* indices (= a resample = a PITCH shift), breaking `voice_fx`'s
  pitch-preserving contract: a recorded C4 came back at chipmunk +608¢, monster
  −1893¢, deep −368¢, demon −1892¢. Time-domain resampling *cannot* decouple
  envelope from pitch, so it's now a real STFT method (Hann 75% overlap →
  cepstral-liftered envelope → warp → magnitude-only gain, phase untouched →
  harmonics stay put → pitch preserved; ifft → COLA overlap-add). All four are now
  **0¢** and the centroid moves the right way (dry 1130 Hz → +0.5: 1527, −0.5:
  755). Also fixed en route: a 0.7-peak voice came out at **2.12** (hard clipping
  in PCM16) → capped to the input peak, attenuate-only; and clips under 512
  samples returned **pure silence** (`frameCount = len ~/ hop` skipped the loop)
  → now processed. **Honest split recorded in the contract:** `robot`/`alien`/
  `cyborg` use ring modulation (f → f ± carrier), which *by construction* cannot
  preserve pitch — the old "ALL presets are pitch-preserving" doc was a lie about
  those three independently of this bug. New `kPitchPreservingVoiceEffects` makes
  the in-tune subset testable, and a test pins that every preset is classified.
  `sample_dsp_test` grew the pitch/centroid/level/short-input assertions it never
  had (the old "changes the content" check passed happily on a transposed
  signal); verified to fail on the old code ("shift 0.5 moved the pitch by 608¢").
  84 consumer tests green.

  ✅ **FOLLOW-UPS SHIPPED — the three smaller open items are all fixed:**
  • `siSdrDb` floored a silent estimate to **−120 dB** (was a false 0 dB that
    out-ranked a noisy-but-real estimate).
  • `LoopSend.delay/reverb` now **pre-roll one loop** so the render is the
    periodic steady state (was 36.9 %/5.5 % off; now 0.00 % vs a 3-copy
    reference) — no more "echo drops out on the downbeat".
  • Swing **snaps to the 10 ms grid** in `LoopTiming._swingMs`, so every stem is
    sample-exact at all tempos/swing (was ≤8-sample drift; the guarding test
    passed by luck). Slider gained `divisions: 12`. The swing test now sweeps the
    drift-prone tempo×swing grid; a new seam test pins the send steady state.
  **The core bug hunt is now fully closed — 8 defects found, all fixed + pinned.**

- **opus (aec-rate)** · ✅ **idle / SHIPPED (layers 1,2,3,4 of 4) —
  self-tuning AEC: Valin closed-loop rate + automatic tuner + REAL corpus**. The
  full automatic-tuning answer, end to end, now on real acoustics.
  **Layer 3 (real corpus) DONE**: `buildCorpusFromAssets` (corpus.dart) builds
  ground-truth scenarios from **real measured room IRs** (MIT IR Survey, CC-BY) ×
  **real cello** (U. Iowa MIS, unrestricted) — `--rir-dir/--cello-dir`. RIR
  truncated to its early field (~90 ms, the cancellable part), echo
  level-calibrated (measured IRs aren't normalized), near-end note DETECTED (not
  assumed). **On the real corpus (6 rooms × 3 cello runs, 54 notes): untuned
  adaptive 3.4 dB SI-SDR / 74% notes → tuned 9.0 dB / 94%** (+5.6 dB). Lower than
  synthetic (honest — real rooms are harder); rateGamma settles INTERIOR (0.36),
  not pinned. Assets on `/Volumes/backups/ai/aec_corpus/` (never checked in;
  eval-only). CI-safe loader test (synthetic WAVs in a temp dir).
  **Modelled loudspeaker nonlinearity (`--nonlin clip|tanh --drive N`)**: a
  memoryless Hammerstein distortion on the reference before the echo path (how
  the AEC Challenge synthesizes nonlinear echo; RMS-held so the cost is
  distortion not gain). AEC sees the clean ref → harmonics uncancellable by a
  linear filter. The CLI reports the cost + whether RES recovers it. **On the
  real corpus, hard-clip drive 4: note-survival 74% → 30% (SI-SDR 3.4 → 0.2 dB),
  then +RES recovers to 87% / 4.7 dB** — a concrete case for RES under a driven
  speaker. It's a MODEL not measured. 3 tests (passthrough, RMS-held+shape-
  changed, distortion-costs-then-RES-recovers). **Only realism gap left: MEASURED
  speaker/mic nonlinearity → a real device capture (on-device milestone (e)).**
  **Layer 4 (CMA-ES auto-tuner) DONE**: `bin/aec_tune.dart` + `bin/aec_tune/`
  (CLI-only, out of the app). A ground-truth corpus (`corpus.dart`, parametric
  rooms — measured-RIR swap is drop-in), a domain objective (`objective.dart` —
  note-survival + double-talk SI-SDR, NOT speech-MOS, per the handover's
  "judge by the decoded outcome"), and a separable CMA-ES (`cmaes.dart`,
  verified against sphere + ill-conditioned ellipsoid). Tunes the rate's own
  hand-picked constants (rateGamma/rateBeta0/rateMuMax — the paper leaves
  gamma/beta0 unspecified). **Result on the synthetic corpus:** untuned adaptive
  8.9 dB SI-SDR / 83% notes → tuned **20.4 dB / 100%** (+11.5 dB), also +10.5 dB
  over fixed-`mu`. gamma/beta0 pin to their bounds (corpus wants extremes → real
  corpus + wider bounds is the follow-up). 5 tests (optimizer correctness,
  corpus/objective sanity, end-to-end loop ≥ baseline).
  **Layer 2 (C port) DONE** (`610acb2`): `AecRate` in `native/aec/src/aec_dsp.c`
  mirrors the Dart `AdaptiveLearningRate`; attach via `aec_dsp_set_rate` (NULL =
  fixed-`mu` path, byte-identical — the property `aec_erle_test` pins). FFI
  binding + 2 new cross-check tests. NOT wired into `aec_shim`/`aec_engine`
  (on-device milestone (e)).
  Layer 1 detail: Instead of hand-picking
  `mu`, the filter derives its own step per bin per block from its live leakage
  estimate — Valin, "On Adjusting the Learning Rate in Frequency Domain Echo
  Cancellation With Double-Talk" (IEEE TASLP 2007, arXiv:1602.08044), written
  from the paper, not SpeexDSP (MIT-clean). New `AdaptiveLearningRate`
  (echo_canceller.dart): `mu_opt(k)=min(eta·|Yhat(k)|²/|E(k)|², muMax)` with eta
  (=1/ERLE) estimated by regressing DC-rejected error power on echo-estimate
  power. Opt-in via `EchoCanceller(rate:)` / `AecTuning(adaptiveRate:true)` /
  `--adaptive-rate`; the fixed-`mu` path (which the C port + `aec_erle_test`
  pin) is byte-identical when off. **Result:** on synthetic double-talk the
  *linear* canceller alone jumps 8.8→33.1 dB SI-SDR — beating fixed-`mu`+DTD
  (15.9 dB) by 17 dB with NO DTD/freeze/threshold, and the rate collapses on
  near-end (mean step 0.40→0.13) then recovers. Trade-off: slower convergence
  (~0.9 s vs ~0.1 s), hence opt-in. 6 new tests pin the behaviour (rate
  collapse, filter-survives-DT, subsumes-DTD, 1/ERLE identity, off-by-default).
  Files: `lib/core/audio/echo_canceller.dart`, `aec_offline.dart`, `bin/aec.dart`,
  `test/aec_offline_test.dart`. Worktree `../mus-aec-rate`, branch
  `feature/aec-adaptive-rate`. **Next in this arc:** port the rate control to
  `native/aec/src/aec_dsp.c` (keep `aec_erle_test` green); then a real corpus
  (record-separately-and-sum through the physical speaker→mic path, + measured
  RIRs / AEC-Challenge set) and a CMA-ES sweep over surviving constants scored on
  note-survival + SI-SDR (AECMOS as cross-check via the existing `bin/aecmos`).

- **opus (aec-tune)** · ✅ **idle / SHIPPED — AEC tuning knobs reachable from the
  CLI / pipe**. The pipe harness existed but only exposed `--delay/--rate/--dtd/
  --res`: `cancelEcho` and `StreamingEchoCanceller` built `EchoCanceller()`,
  `DoubleTalkDetector()` and `ResidualEchoSuppressor()` with hard-coded defaults
  and forwarded nothing, so a sweep over `mu`/`leak`/`blockSize`/DTD/RES meant
  editing source. New **`AecTuning`** (aec_offline.dart) mirrors all 16 stage
  knobs + `createCanceller/Detector/Suppressor()` + `describe()` (names only the
  non-defaults — every CLI run prints it, so a sweep's output says which point
  produced which number). Both entry points take `tuning:`; `blockSize` moved
  into it (the one caller updated). `bin/aec.dart` gained a flag per knob
  (`--mu`, `--block`, `--leak`, `--dtd-threshold`, `--res-gain-floor`, …) in all
  three modes (selftest/files/stdin). Verified over a real pipe: mu 0→0.0 dB,
  0.1→7.2, 0.3→12.7, 0.7→16.0, 1.5→15.6 (overshoot); `--block 256 --res`→20.4 dB.
  6 new tests pin that each knob *reaches* its stage (a knob that silently
  doesn't is worse than none) + streaming≡batch on a non-default tuning. Files:
  `lib/core/audio/aec_offline.dart`, `bin/aec.dart`, `test/aec_offline_test.dart`
  — no app/native code touched. Analyze clean, full suite green.
  **Not done:** the native Tier-3b path (`aec_shim.h`) still exposes only
  `set_period/set_dtd/set_res` — the C DSP keeps its own constants, so a tuning
  found here doesn't yet transfer to the on-device engine.

- **opus (coverage)** · ✅ **idle / SHIPPED — regression tests for untested parser
  branches** (test-only, no lib changes). Pinned confirmed coverage gaps in
  deterministic pure-logic parsers: `wav_io.dart` (non-PCM/non-16-bit rejection,
  no-data-chunk, stereo downmix, truncated-data clamp, word-aligned multi-chunk
  walk, channels<1 guard), `midi_import.dart` (SMPTE rejection, no-notes throw,
  monophonic overlap-drop, running-status, format-1 track selection, rest-gap
  insertion), `SriItemData`/`GameProgress` `fromJson` default-fill + roundtrip,
  and `parseAnyModule`'s unknown-format throw. 19 new cases across 4 new test
  files; whole-project analyze clean. **Follow-up shipped:** `mod_signature_test`
  closes the last item on that shortlist — `mod_reader`'s signature→channelCount
  map (the 4/6/8-channel tags, the generic `%dCHN`/`%dCH` regexes, the
  unknown-signature throw, and that the count shapes each pattern row); the
  golden fixture only ever covered `M.K.`/4ch. All mappings verified correct —
  no bug, now pinned. **The confirmed coverage-gap shortlist is now fully
  closed.**

- **opus (primers-mine)** · ✅ **idle / SHIPPED — per-game tutorial primers for 3
  games** (learnability §1). The games I shipped this session now teach their
  concept on first entry / via the "?": **spot_upbeat** → new `upbeatPrimer`
  (downbeat vs a pickup that leans in), **enharmonic** → new `enharmonicPrimer`
  (F♯ = G♭, one key/two names, incl. the German Fis/Ges twins), **major_minor_sort**
  → reuses `chordsPrimer` (already teaches major-bright / minor-soft). Both new
  primers hang on their game via `GameInfo.tutorial`, EN/DE, and are covered by the
  `tutorial_test` build/render loop. (`transpose_write` already had
  `transposePrimer`.) Analyze clean; tutorial + consistency suites green.

- **opus (spacing)** · ✅ **idle / SHIPPED — "Close or Open?" SATB spacing
  minigame** (scoped item #1's remaining suggestion — a *fresh* voice-leading
  skill). Read an SATB chord on the grand staff, tap **close** vs **open**
  position (soprano-tenor span ≤ vs > an octave). Own close/open voicing generator
  (consecutive chord tones = close; skip-one = open) over the reused
  `satb_voicing.dart` rendering; 1★ C-major primary triads, 2★ five keys × all 7
  diatonic triads. Per-game `spacingPrimer` (close/open primer), SRI
  `note_reading.spacing.<close|open>`, unlocks at `duet ≥ 2★`. Device-adaptive
  layout (staff scales into the available height, so open voicings never overflow
  the 800×600 smoke surface). `spacing_read_test` (voicing invariant × 200 seeds
  × wide/narrow + widget flow), registry-smoke + consistency green; analyze clean.

- **opus (tracker)** · ✅ **idle / SHIPPED — Score↔ModuleDoc bridge + full round-trips
  (§D)**. Filled the notation-conversion gaps end-to-end.
  (1) `lib/core/audio/mod/module_notation.dart` (Flutter-free, imports
  crisp_notation_core): module→Score (`moduleChannelToScore`) + module→multi-part
  (`moduleToMultiPart`, staff-per-channel, clef auto); reverse `scoreToModuleDoc`/
  `multiPartToModuleDoc` (chord split; rests survive via a new additive
  `DocCell.off`); `multiPartToMidi`+`splitMultiTrackMidi` (format-1 SMF the
  library can't write); module↔MusicXML via the lib's readers/writers.
  (2) `bin/notaconv.dart` now BIDIRECTIONAL by extension: module→(.mid/.xml),
  .mid/.xml→module, `--multi`=multi-track. Old in-CLI Score port removed.
  (3) note-off through the XM(97)/IT(255)/S3M(254) codecs (`module_convert.dart`)
  so a rest survives real module bytes; MOD can't (documented).
  16 round-trip tests (`module_notation_test`), N×N matrix unaffected.
  Commits `808dc74`+`efd4b6a`. Files: `module_notation.dart`, `module_doc.dart`
  (DocCell.noteOff), `module_convert.dart`, `bin/notaconv.dart`,
  `docs/TRACKER_IDEAS.md` §D. Remaining §D = app plumbing (Workshop↔Tracker
  handoff, module-pattern→tracker-grid import).

- **opus (tracker)** · ✅ **idle / SHIPPED — full converter matrix + Sampling §B**.
  (1) **Converter matrix** (`2946016`): `convertModule(bytes, target)` /
  `convertDocTo(doc, target)` is now the single MOD/XM/S3M/IT dispatch point
  (`module_convert.dart`; `bin/modconv.dart` funnels through it). Full 4×4 test —
  every golden → every target incl. S3M-as-source + identity cells the old suite
  never hit; invariant is source-agnostic (re-parse each output, compare title +
  note in MIDI space + sample peak). Live-verified an s3m→xm→it→mod chain.
  (2) **Sampling §B** (`9316b1f`): `sample_edit.dart` (non-destructive trim/
  trimSilence/normalize/fade/reverse) + `multi_sample_instrument.dart`
  (`MultiSampleInstrument`/`SampleZone` XM/IT keymap; `.mapped()` auto-splits key
  ranges; NEW file, tracker_engine.dart untouched). 57 tests green (matrix +
  sample_edit + multi_sample). Also corrected the stale LOOP_MIXER_FOLLOWUPS doc
  (both follow-ups were already shipped). Next candidate: §D multi-channel module
  → multi-part Score (reuses grooveParts' MultiPartScore + multiPartToMusicXml).
  Files: `lib/core/audio/mod/module_convert.dart`, `bin/modconv.dart`,
  `lib/core/audio/crisp_dsp/sample_edit.dart`,
  `lib/core/audio/multi_sample_instrument.dart` + tests + `docs/TRACKER_IDEAS.md`.

- **opus (tracker)** · ✅ **idle / SHIPPED — FX extensions** (all four). **Bell (FM)
  instrument** in the picker; a **multi-effect per-channel chain** (`TrackerChannel.
  effects` list + `applyChannelEffects` fold + multi-select FilterChip sheet); a
  **pitch envelope** on sampled instruments (`resampleGlide` + `Envelope.pitchStart/
  pitchTime`, scoop/fall); a **Loop Mixer master send** (`LoopSend{none,reverb,delay}`
  + `_applySend` on the mix + a `surround_sound` cycle button). Each its own commit
  + test; all engine/screen/loop suites green. **The whole FX effort — FX_HANDOVER
  §1–§5 + these extensions — is done.**

- **opus (smufl)** · ✅ **idle / SHIPPED — Leland + Leipzig notation faces**. The
  binary "handwritten notes" toggle is now a 4-way **Notation font** picker
  (Bravura / Petaluma / Leland / Leipzig), all SIL OFL 1.1. New `ScoreFont` enum +
  `musicFontFor` in `shared/score_theme.dart`; `SettingsService.scoreFont`/
  `setScoreFont` persist under `score_font` and **migrate** the legacy
  `handwritten_notes` bool → Petaluma (`handwrittenNotes`/`setHandwrittenNotes`
  kept as shims). Assets vendored under `assets/smufl/` (`.otf`/`.ttf` + metadata +
  OFL), declared in `pubspec.yaml`, OFL registered in `custom_licenses_registry`.
  ChoiceChip picker in `settings_screen`; ARBs `notationFont*`/`scoreFont*` (EN/DE).
  `notation_fonts_test` (6 cases, both alt metadata parse as valid SMuFL) + the 2
  settings widget tests green; whole-project analyze clean. ⚠ overlaps the
  workshop-inspector `showNoteNames` claim on `settings_service`/`settings_screen`/
  both ARBs — coordinate on rebase.

- **opus (aecmos)** · ✅ **idle / SHIPPED — AECMOS neural MOS scoring in the AEC
  eval CLI**. `onnx_runtime_dart` (pure-Dart, public sibling) gained the conv/GRU
  ops AECMOS needs, so the metric `AEC_TIER3B.md` rejected as "needs a native ORT"
  now runs in pure Dart. Wired **dev-only / headless** (zero app or web-bundle
  impact): `onnx_runtime_dart` as a **dev_dependency** (path `../onnx_runtime_dart`),
  the copied `AecmosScorer` + `MelFrontEnd` under `bin/aecmos/` (with an
  `ignore_for_file: depend_on_referenced_packages` — the dev-dep is the intended
  boundary), and `bin/aecmos.dart <model|run-id> <lpb> <mic> <enh> <st|nst|dt>`.
  The model is a **user-provided** Microsoft AEC-Challenge artifact (run ids
  1663915512/1663829550 @ 16k, 1668423760 @ 48k) in
  `~/.cache/onnx_runtime_dart_models/` — never bundled, so full scoring is a
  local/dev tool (not CI). `test/aecmos_smoke_test.dart` (model-free: mel
  front-end shape/finiteness + scorer rejects an unknown run id — the DSP is
  exhaustively tested upstream). CI + deploy check out `CrispStrobe/onnx_runtime_dart`
  as a sibling (every `pub get` resolves dev deps). `AEC_TIER3B.md` corrected.
  Full-project analyze clean (bar one pre-existing `roman_numeral_test` lint, not
  mine); smoke test green. NOT touching the app / native plugin / game registry.
  ✅ **Now turnkey:** the 16 kHz + 48 kHz models are mirrored (MIT, attributed to
  microsoft/AEC-Challenge) at <https://huggingface.co/cstr/aecmos-onnx> with a
  model card; the CLI's run-id shortcut resolves `aecmos_<run-id>.onnx` from the
  cache and its "model not found" message prints the `hf download` command. (Run
  id `1663829550` not mirrored — available upstream.)

- **opus (tracker)** · ✅ **idle / SHIPPED — FX remainder (FX_HANDOVER §1/§4/§5)**.
  **Swing** (`TrackerTiming.swing` + swing-aware onsets across every renderer + an
  app-bar toggle); **sfxr FM/LFO** (`crisp_dsp/sfxr.dart` fmDepth/fmRatio/lfoDepth/
  lfoSpeed, gated on depth>0 so presets stay byte-identical; a 'bell' preset);
  **per-note volume envelopes** (`crisp_dsp/envelope.dart` + `SampleInstrument`
  declick). Each its own commit + test; all engine/screen suites green.
  **FX_HANDOVER §1–§5 essentially complete** (only extensions remain). ⚠ avoid
  backticks in `git commit -m "…"` under zsh — they command-substitute (dropped a
  word in `651c2c2`).

- **opus (tracker)** · ✅ **idle / SHIPPED — record voice slow/fast (time-stretch)**.
  A Slow/Normal/Fast chip row in the record sheet applies the shipped `timeStretch`
  (pitch-preserving) to a clip before it becomes the voice instrument
  (`_voiceStretch` in `tracker_screen.dart` + tester seam `voiceStretch`/
  `setVoiceStretch`/`voiceSampleLength` + ARBs `trackerSpeed{Slow,Normal,Fast}`).
  Screen test: inject at 1.5× → voice sample ~1.5× longer. **FX_HANDOVER §3 complete.**

- **opus (tracker)** · ✅ **idle / SHIPPED — voicelab voice presets** (alien/cyborg/
  radio/demon). `VoiceEffect` in `voice_fx.dart` gains 4 presets composing formant +
  the shipped `ring_mod`/`distortion` + a 1-pole bandpass (radio); record-sheet icons
  + labels + ARBs (EN/DE). The applyVoiceEffect test (iterating `VoiceEffect.values`,
  now asserting length-preserving too) auto-covers them. **Record voice menu: Normal/
  Chipmunk/Monster/Deep/Robot/Alien/Cyborg/Radio/Demon.** 31 screen + voice tests
  green; analyze clean.

- **opus (workshop-inspector)** · ✅ **idle / SHIPPED — note-name reading scaffold**
  (`4052f00`, user-requested; the "showNoteNames" item was NO LONGER
  crisp_notation-blocked — `StaffView` supports the boolean). A persisted
  `SettingsService.showNoteNames` (default off, sibling of `colorScaffold`) + a
  Settings toggle; a shared `ReadingStaffView` wrapper (`features/games/widgets/`)
  reads the setting so games opt in with a one-line `StaffView`→`ReadingStaffView`
  swap. Wired into 9 games where the note's NAME is NOT the task (`whole_half`,
  `tie_slur`, `articulation_read`, `beam_flag`, `note_value_quiz`, `measure_fill`,
  `spot_upbeat`, `bowing`, `beat_count`) — **deliberately NOT the naming quizzes**
  (printing the letter reveals the answer) **nor the read-to-produce games**
  (`perform_it`/`cello_play_it` — the shown note IS what you must sing/play, so the
  name would reveal it). That's the safe+valuable set; the rest are unsafe or
  low-value (rhythm on a single repeated pitch). **Per-locale spelling now works**
  (`252acd6`): added a
  `noteNameStyle` param to `StaffView` in the **public crisp_notation lib**
  (`7b72632`, mirrors `MultiSystemView`; default `letter` → byte-identical for
  existing callers), and `ReadingStaffView` passes `noteNameStyleFor(context)`, so
  on-staff names honour the English / German-H / solfège setting. Library +
  app both green; `test/reading_staff_test.dart` asserts germanH → German. Rebased
  through the concurrent `ScoreFont` refactor of SettingsService/settings ARBs.
  Follow-up (optional): extend the wrapper to more name-safe games (one line each).

- **opus (tracker)** · ✅ **idle / SHIPPED — ring-mod + crunch in the channel FX
  picker**. DSP units `9b1b4c8`; `TrackerChannelEffect` now has `ringMod` (Robot) +
  `crunch` (distortion) with `applyChannelEffect` cases; labels + ARBs (EN/DE); the
  picker sheet + the engine test (now iterating the enum) auto-cover them. 50
  engine+screen tests green; analyze clean. **Channel FX menu: none/Echo/Chorus/
  Flanger/Reverb/Robot/Crunch.**

- **opus (majmin-sort)** · ✅ **idle / SHIPPED — "Major or Minor?" triad-sort
  minigame** (backlog §B — the *reading* counterpart to the aural
  `major_minor_ear`). A two-basket drag-sort on the `accidental_sort` scaffold:
  each card renders a **triad** on the staff; drag it into the Major / Minor
  basket (Diminished joins as a 3rd basket at 2★, mirroring accidental_sort's ♮).
  Built with crisp_notation `Triad(root, ChordQuality)`; the chord sounds on a
  correct drop. New `features/games/chords/major_minor_sort_screen.dart` +
  `GameInfo` (chords module) + tuning `[100,400,550]` + EN/DE ARBs (reuses the
  existing `majorLabel`/`minorLabel`/`diminishedLabel`) + `test/major_minor_sort_test.dart`
  (real drag gestures + the 2★ three-basket widen). SRI
  `chords.quality.<major|minor|diminished>`. Analyze clean; consistency + star
  suites green.

- **opus (enharmonic)** · ✅ **idle / SHIPPED — "Enharmonic Twins" minigame**
  (item 1, a genuine gap — nothing else drills enharmonic equivalence). A binary
  staff-read on the `tie_slur` scaffold: two whole notes are shown (each with its
  accidental) across two bars; same sound spelled two ways (F♯/G♭) or genuinely
  different? Graded by `midiNumber` equality (exact — the child must read past the
  spelling). Five sharp/flat twins at 1★; the white-key twins (E♯=F, F♭=E) join at
  2★; "different" rounds are guaranteed non-enharmonic and non-trivial (adjacent
  steps, ≥1 accidental). Correct → both notes play. New
  `features/games/note_reading/enharmonic_screen.dart` + `GameInfo` + tuning
  `[100,600,900]` + EN/DE ARBs + `test/enharmonic_test.dart` (3 tests incl. a
  per-round invariant `answerSame ⇔ notesShareMidi`). Analyze clean; consistency +
  star suites green.

- **opus (tracker)** · ✅ **idle / SHIPPED — per-channel FX chain (Tracker)**. The
  shipped DSP units (`crisp_dsp/modulated_delay.dart` + `reverb.dart`) are now wired
  in: `TrackerChannelEffect{none,delay,chorus,flanger,reverb}` + `applyChannelEffect`
  + a mutable `effect` on `TrackerChannel`, applied to the stem in
  `_renderWithDynamics` before `mixStems`; `setChannelEffect` invalidates the cache.
  UI: a `graphic_eq` app-bar button → an effect-picker bottom sheet (localized
  EN/DE). Engine test (applyChannelEffect: none=identity, each effect ≠ dry;
  setChannelEffect changes the mix, none restores it) + a screen tester-seam test.
  analyze clean; 50 engine+screen tests green.

- **opus (transpose-write)** · ✅ **idle / SHIPPED — "Write It for the Instrument"
  minigame** (remaining-work item 1). The inverse of Concert Pitch, doubling the
  thin Transpose corner: a **concert pitch** (what sounds) is shown on the staff;
  name the note a B♭/E♭/F instrument must **read** to produce it. B♭ only at 1★,
  +E♭/F at 2★; correct → the concert pitch plays. SRI `transpose.<instr>.write_<step>`
  (distinct leaf, never clobbers the forward game's SM-2 items). New
  `features/games/transpose/transpose_write_screen.dart` + `GameInfo` + tuning
  `[100,600,900]` + EN/DE ARBs (parameterized prompt) + `test/transpose_write_test.dart`
  (3 tests incl. a round-trip pinning the transposition inverse vs the forward
  maths). Built during the `CometBeat` rename window (held the push, rebased onto
  the renamed tree). Analyze clean; consistency + star suites green.

- **opus (rename)** · ✅ **idle / SHIPPED — responsive layout audit + 10 overflow
  fixes.** Pumped every registered game + home/curriculum/progress at iPhone SE
  (375×667), iPhone 6.9" (440×956) and iPad 13" (1024×1366), collecting RenderFlex
  overflows. **18 → 8 findings.** Fixed: `play_along_screen` button row → `Wrap`
  (the play button's label is the game title; overflowed 41px — hit **5** games:
  cello/guitar/sing/keyboard play-alongs + keyboard_ode); `chord_grip_hero` +
  `command_caller` unconstrained hint `Text` after a `Spacer` → `Flexible`+ellipsis
  (107/90px on SE, 42/25px on 6.9"); `_ModuleCard` title 2-line cap + card ratio
  1.15→1.05. iPad is clean at every screen. Analyze + affected suites green.
  ✅ **Layout audit — 0 overflows across 828 checks** (138 screens × SE 375×667 /
  6.9" 440×956 / iPad 13" × **EN + DE**). Every `kGamesByModule` screen + home/
  curriculum/progress verified clean in both languages. Fix patterns applied:
  • button/control Row→Wrap: 5 play-alongs, `chord_play_along`, `cello_play_it`,
    `tracker` body (tempo+Record/Clear);
  • unconstrained Text→Flexible+ellipsis: `chord_grip_hero`, `command_caller`,
    `note_snake`, `beat_runner`, `_curriculum` title, `_ModuleCard` title;
  • vertical fill-else-scroll (LayoutBuilder+ConstrainedBox(minHeight)+
    IntrinsicHeight+SingleChildScrollView): `accidental_sort`(+bass), `pitch_sort`
    (+bass), `roman_numeral`;
  • `tracker` app bar: Swing→overflow menu (~9 actions didn't fit 375px).
  KEY LESSON: **German amplifies overflows** — 6 findings only showed in de-DE on
  SE (`../testing_dart.md` §6); an EN-only audit misses them. `_curriculum` was
  NOT a false positive after all — a latent unconstrained Text that only fit in
  settled English. Also an **a11y audit** (tap-target/contrast/label) came back
  clean bar one fix (debug-title `excludeFromSemantics`). Re-run: pump
  `kGamesByModule` × sizes × locales, collect `takeException()` /
  `AccessibilityGuideline.evaluate`; probe file:line via `FlutterError.onError`.
  Full method: `../testing_dart.md`.

- **opus (rename)** · ✅ **idle / SHIPPED — full app rename `KlangUniversum` →
  `CometBeat`** (new working name; checked clear on app stores / web / TM search).
  Package id `klang_universum`→`comet_beat` (**342 Dart files, ~1,768 imports**),
  display names (iOS/macOS/Android/Linux/Windows/web/l10n `appTitle`), bundle ids →
  `com.crispstrobe.cometBeat` (app not yet published), XM-writer tracker stamp,
  README + this header + active docs. `flutter analyze` clean; rename-sensitive
  tests green (widget/home/about/settings/live-flow/xm). GitHub repo renamed
  `klang-universum`→**`CrispStrobe/cometbeat`** (remote + CI checkout `path:` in
  `ci.yml`/`deploy.yml` updated). **Only remaining external item:** rename the
  Apple provisioning profile in the Developer portal, then update
  `ios-release.yml:PROFILE_NAME` (still `Klang Universum AppStore CI`). `HISTORY.md`
  keeps the old name by design (historical log).

- **opus (upbeat)** · ✅ **idle / SHIPPED — "Spot the Upbeat" minigame**
  (remaining-work item 1). A binary staff-read (Takte module): a short two-bar
  melody starts either on the downbeat (a full first measure) or with a pickup /
  anacrusis (an incomplete first measure), and the child taps **Upbeat** vs **On
  the beat**. The pickup is a real `Measure(..., pickup: true)` so the first bar
  genuinely holds less than the meter (proper anacrusis — the pickup is borrowed
  from the last bar). At 2★ the note-count shortcut is defeated (mixed-rhythm full
  bars: half+quarter+quarter shows 3 noteheads but fills 4/4; pickup of 1–2
  notes). Correct → the melody plays. SRI `measures.upbeat.<yes|no>`;
  `kStarThresholds` `[100,600,900]`. `features/games/measures/spot_upbeat_screen.dart`
  + `GameInfo` + tuning + EN/DE ARBs + `test/spot_upbeat_test.dart` (3 tests, incl.
  a per-round structural invariant: upbeat ⇔ short pickup first bar). Analyze clean;
  registry/consistency + star-score suites green.

- **opus (workshop-inspector)** · ✅ **idle / SHIPPED — the last two voice-2 gaps:
  meter changes + cross-voice tap-select** (`9ceadac` model + `3da6ad2` model+screen).
  (1) **Meter changes desynced the voices** — a time change anchors to one element
  id, in one voice's stream, so the other voice's `reflow` never re-barred (a 2/4
  change gave bar 1 two quarters in v1 but three in v2). `_timeChangesFor(voice,
  scale)` re-keys `_timeChanges` onto each voice by cumulative onset, so a change in
  either voice re-bars both; identity for single-voice → byte-identical goldens.
  `test/voice2_time_change_test.dart`. (2) **Cross-voice tap-select** — crisp_notation
  hit-testing IS voice-agnostic (verified: `staff_view.dart:393`, regions from all
  voices), so `onElementTap` fires with v2 ids; but mutations resolve ids in the
  active voice only. Added `ScoreDocument.voiceOfId`; `_onElementTap` now follows the
  caret to the tapped note's voice (`setActiveVoice` then select). Inert on the
  single-voice Sandbox surface. `test/voice2_cross_voice_test.dart` + a widget test.
  **The voice-2 v1-limit arc is now FULLY CLOSED** — voice 2 is a first-class voice
  for render, persistence, and editing.

- **opus (workshop-inspector)** · ✅ **idle / SHIPPED — voice-2 mid-*bar* clef
  changes** (`5071194`). MODEL-only (`score_document.dart`). `_withInlineClefs`
  walked voice-1 elements only, so a mid-bar clef anchored on a voice-2 note was
  stored but never emitted — the **last voice-1-only harvest in `buildScore`**. Now
  collects the onset walk (`_collectInlineClefs`) from both voices, merged
  onset-sorted; `loadScore` recovers a voice-2 anchor whose onset has no matching
  voice-1 boundary (`_recoverInlineClef`, try v1 then v2). Empty-v2 → byte-identical
  (inline-clef + packing goldens hold). `test/voice2_inline_clef_test.dart`. **With
  this, `buildScore` harvests every voice-anchored attribute from BOTH voices**
  (dynamics, lyrics, tuplets, bar changes, mid-bar clefs). Only two voice-2 gaps
  remain, both niche/ambiguous: a **TIME change** anchored on voice 2 (feeds
  reflow's bar capacity by id — genuinely hairy) and **cross-voice tap-select**
  (screen; may be blocked on crisp_notation hit-testing returning v2 ids on tap).

- **opus (workshop-inspector)** · ✅ **idle / SHIPPED — voice-2 mid-score bar
  changes** (`27c8568`). MODEL-only (`score_document.dart`). A clef/key/tempo/
  repeat/volta/nav change anchored on a voice-2 note (the setters run on the active
  voice) was stored but never stamped — `_withMidScoreChanges` scanned voice-1 bars
  only. It now builds a per-bar voice-2 id list (`_v2IdsByBar`, same-grid so bar
  indices align) and `_anchoredIn`/`_anchoredInSet` fall back to it (voice-1 anchor
  still wins). Round-trips (reopen re-anchors to the bar's first voice-1 element).
  Empty-v2 → byte-identical (goldens hold). `test/voice2_midscore_test.dart`.
  **Out of scope (documented):** a TIME change anchored on voice 2 (feeds reflow's
  bar capacity by id) and mid-*bar* inline clefs on voice 2. This closes the
  voice-2 v1-limit arc except those two + cross-voice tap-select (screen).
  *(Also, in passing: fixed 6 files that raced the rename with stale
  `klang_universum` imports — landed upstream as `3a4d5db`, so my dup was deduped.)*

- **opus (workshop-inspector)** · ✅ **idle / SHIPPED — voice-2 tuplets** (`fdf1d6a`).
  MODEL-only (`score_document.dart`; no screen overlap). A tuplet made while voice 2
  was active was doubly broken — `_withVoice2`'s reflow omitted `durationScale`
  (triplet members overflowed the bar) and `_withTuplets` positioned only voice-1
  members (no bracket). Fix: v2 reflow now passes `durationScale: _tupletScale()`;
  the per-bar span emitter is factored to `_tupletSpansByBar(voiceBars, voice:)`,
  reused by `_withTuplets` (voice 0) and `_withVoice2` (voice 1, so crisp_notation
  brackets it as an inner voice — `layout_tuplets.dart:33`); `loadScore` recovers
  `span.voice==1` via a per-bar voice-2 id list. Empty-v2 fast path untouched →
  packing goldens byte-identical. `test/voice2_tuplet_test.dart` (packs scaled +
  emits a voice-1 3:2 span + save→reopen round-trip); 178 Workshop-model tests +
  analyze green. **Remaining voice-2 v1 gaps (unclaimed):** mid-score bar changes
  anchored on a voice-2 note don't stamp (bar-level stamps read voice-1 bars; note
  a *time* change anchored to v2 is extra-hairy — it also drives reflow bar
  capacity); cross-voice tap-select (screen).

- **opus (tracker)** · ✅ **idle / SHIPPED — "borrow a sample from a module"**
  (core `7dd8ab2` + UI). A "Borrow instrument…" item in the Tracker app-bar menu:
  pick a `.mod/.s3m/.xm/.it`, choose one of its samples from a dialog, and it
  becomes the selected channel's instrument (`sampleInstrumentFromModule` +
  `setChannelInstrument` → setState → `_syncPlayback`). Touched
  `tracker_screen.dart` (menu case + `_borrowInstrument` handler + picker) + both
  ARBs (`trackerBorrowSample`/`trackerBorrowEmpty`) + regenerated l10n. Core is
  pitch-accurate (MPM-detector acceptance); 17 tracker-screen tests + analyze green.

- **opus (workshop-inspector)** · ✅ **idle / SHIPPED — voice-2 dynamics + lyrics
  render and round-trip** (`9163d19`, closes a voice-2 v1-limit / silent-loss bug).
  MODEL-only (`score_document.dart`; no screen overlap). `buildScore` now harvests
  dynamics + lyrics from `[..._v1, ..._v2]`, and `loadScore`'s voice-2 loop applies
  `dynamics[el.id]` + records `remap[old]=new` so id-keyed lyrics/slurs re-anchor
  onto voice 2. crisp_notation resolves markings by id across voices
  (`layout_spans.dart:284`, `layout_annotations.dart:122`), so a v2 dynamic/lyric
  now renders on the v2 note and survives save→reopen. Empty-v2 fast path keeps
  single-voice goldens byte-identical (packing golden green). Snapshots already
  capture `_v1/_v2/_lyrics`, so undo is free. `test/voice2_markings_test.dart` (4
  tests); 187 Workshop-model tests + analyze green. **Remaining voice-2 v1 gaps
  (unclaimed):** tuplets / mid-score changes anchored while voice 2 is active still
  don't stamp (the `_withMidScoreChanges`/`_withInlineClefs`/`_withTuplets` passes
  read voice-1 bars only); cross-voice tap-select isn't wired (screen).

- **opus (studio-polish)** · ✅ **idle / SHIPPED — categorized ⌃ insertion palette**
  (remaining-work item 3, the palette half; `opus (workshop-inspector)` did the
  inspector Structure half). The flat property popup on the ⌃ button now reads as
  labelled sections — **Articulations & ties / Dynamics / Ornament / Structure** —
  via non-selectable `_menuHeader` rows; item labels dropped their redundant
  `Category:` prefix now a header names the group ("Ornament: Trill" → "Trill"
  under the ORNAMENT header, "Dynamics: mf" → "mf" under DYNAMICS). Reuses the
  existing `workshopStructure` key. Only `_paletteButton`/`itemBuilder` +
  `_menuHeader` touched (no overlap with the inspector work I rebased onto). 61
  workshop widget tests green (palette test asserts the section headers), analyze
  clean.

- **opus (workshop-inspector)** · ✅ **idle / SHIPPED — inspector "Structure" view;
  a rest is no longer a dead end** (`4a55600`, a slice of item 3). Added an
  id-anchored **Structure** section to `_inspectorPanel` in
  `composition_workshop_screen.dart`: for any single selection (note OR rest) it
  summarises the bar-anchored changes at the focused element (clef / mid-bar clef /
  key / time / tempo / repeat start-end / volta / navigation) as read-only chips
  (or "No change") and hosts **"Change from here…"** — moved out of the notes-only
  branch, so a rest can now anchor bar changes. Grace stays note-only. Additive,
  Studio-only (inspector opt-in, off by default) — Sandbox surface unchanged. New
  l10n key `workshopStructure` (de/en). Green (61 workshop widget tests +
  analyze clean). **@opus (studio-polish): please `git pull --rebase` onto this —
  the rest/bar-attribute inspector slice is now done; your remaining inspector
  work is the multi-select depth beyond note props + categorized insertion
  palettes. Small, self-contained diff to `_inspectorPanel`.**

- **opus (articulation)** · ✅ **SHIPPED — "Read the Mark" articulation minigame**
  (`cedf4da`, Noten lesen). Fills a real gap: ties/slurs + note values were
  covered, but the note-attached articulation marks had no reading game. A
  binary staff-read on the `step_skip` scaffold — one note carries an
  articulation glyph (staccato dot / accent wedge, drawn by crisp_notation
  `layout_marks`); the child matches it to its name. Binary at 1★ (Staccato vs
  Accent), full four-way (+Tenuto/Marcato) from 2★; a correct answer sounds the
  note (short for staccato). `GameInfo` in note_reading + `kStarThresholds`
  bracket + EN/DE ARBs. SRI `reading.articulation.<name>`. 4 tests (incl. an
  assertion that the rendered `StaffView` actually carries the glyph). Whole-
  project analyze clean.

- **opus (aec-res-c)** · ✅ **SHIPPED — residual echo suppression ported to the
  native C engine** (`b3bf617`). Completes the native AEC algorithm stack (DTD +
  RES, both now in the C engine, all headlessly verified). `src/aec_dsp.{c,h}`
  gained an `AecRes` (a port of the Dart `ResidualEchoSuppressor`, reusing the
  DSP's own `aec_fft`/`ifft` and the same overlap-save Wiener framing with a
  DTD-gated leakage estimate); FFI-bound as `AecRes` in `lib/aec_dsp.dart` with
  an offline cross-check (RES deepens echo-only ERLE >3 dB past the linear
  filter). Wired **opt-in** into the engine block loop (`aec_engine_set_res` /
  `AecEngineFfi.setRes`), its leakage gated on the DTD's single-talk decision;
  needs a distinct output buffer (can't run in place). Headless engine test +
  whole native suite 10/10 via `build.sh`. Remaining native AEC is on-device
  only (milestone e): app opt-in via `setDtd`/`setRes` + real-hardware tuning.

- **opus (aec-engine-dtd)** · ✅ **SHIPPED — DTD wired into the native engine
  block loop** (`c11ddc7`). The DTD was ported to the C DSP core (`f7487fd`) but
  nothing used it; now `aec_shim.c`'s `engine_run` (the shared core the realtime
  duplex callback AND the headless pump both run) drives it per block — read
  `aec_dtd_freeze` → `aec_dsp_set_adapt` → process → `aec_dtd_update`. Opt-in via
  a new `aec_engine_set_dtd()` (default off — a DTD hurts without a clean
  convergence window, so this keeps the existing continuous-double-talk engine
  test green); FFI-bound as `AecEngineFfi.setDtd(bool)`. Headless double-talk
  test in `test/aec_engine_test.dart` (converge→double-talk through the pump,
  DTD-on near-end error <0.7× DTD-off). Whole native suite 8/8 via `build.sh`.
  All in `native/aec/` (out of app CI). Remaining native AEC: port RES to C; app
  opt-in via `setDtd` (milestone e, needs on-device tuning).

- **opus (aec-res)** · ✅ **idle / SHIPPED — residual echo suppression**
  (`15a6d62`). **The patent-free AEC algorithm roadmap is COMPLETE (DTD + RES).**
  `ResidualEchoSuppressor` (`aec_offline.dart`): a Wiener-style spectral
  post-filter on what the linear filter leaves, reusing the canceller's own
  overlap-save framing (2·blockSize `[prev;cur]` frame, spectrally gained, keep
  the last block — no window/COLA bookkeeping). Per bin the residual echo is
  `λ(k)·|Ŷ(k)|²` with the echo leakage **λ learned only on far-end single-talk
  (DTD-gated)** — during double-talk the near-end inflates the residual and would
  drive λ, and the suppression, far too high; a `gainFloor` bounds attenuation.
  Opt in: `cancelEcho(residualSuppress:)` / `StreamingEchoCanceller` /
  `bin/aec.dart --res` (compose with `--dtd`). **Measured: echo-only segmental
  ERLE 39.3 → 54.6 dB (+15.3), double-talk SI-SDR unchanged (15.8 vs 15.9, −0.1)
  — deeper echo suppression without chewing the voice.** 25 tests (5 new). No
  app / Workshop / native plugin touched.

- **opus (aec-dtd)** · ✅ **idle / SHIPPED — double-talk detector** (`a10d6bd`,
  patent-free AEC roadmap item 1). The linear core kept adapting on near-end
  speech; a DTD freezes it while the near-end is present. **`DoubleTalkDetector`**
  (`aec_offline.dart`) uses a normalized-correlation statistic
  `corr(mic, echoEst=W·x)` — ≈1 on far-end single-talk, drops on double-talk —
  needing no echo-path-gain threshold (unlike Geigel); warmup guard + hangover.
  Additive **`EchoCanceller.process(..., {bool adapt = true})`** gates the NLMS
  update (default true ⇒ C port + existing callers untouched; `EchoCanceller` is
  CLI/test-only, jam uses the native engine). Wired into
  `cancelEcho(doubleTalkDetect:)`, `StreamingEchoCanceller`, `bin/aec.dart --dtd`.
  **Result: double-talk SI-SDR 8.8 → 15.9 dB (+7.1 dB vs linear)**, echo-only
  cancellation unchanged. 20 tests (4 new). No app / Workshop / native plugin
  touched.

- **opus (aec-metrics)** · ✅ **idle / SHIPPED — AEC quality metrics + thorough
  tests** (`1e0bc8c`). Patent-free metrics in `lib/core/audio/aec_offline.dart`:
  **segmental ERLE**, **convergence time**, **SI-SDR** (scale-invariant SDR,
  Le Roux 2019 — the gain-invariant double-talk fidelity metric), + an
  `AecMetrics.measure/report` bundle. Explicitly NOT PESQ/POLQA (license/patent
  encumbered); AECMOS is MIT but native-ORT-only (our pure-Dart
  `onnx_runtime_dart` lacks conv/GRU ops). `bin/aec.dart --selftest` reports the
  full set on the standard converge→double-talk scenario. **16 tests** (broadband
  convergence + exact delay, small block size, no-NaN, far-end-silence exact
  passthrough, SI-SDR identity/scale-invariance/monotonicity, streaming≡batch
  w/ refDelay, flush padding, empty-input). Docs: patent-free rationale in
  `AEC_TIER3B.md`. No app/Workshop/native-plugin touched.

- **AEC — what's left (unclaimed; verification now UNBLOCKED).** The patent-free
  *algorithm* roadmap is done (DTD `a10d6bd` + RES `15a6d62`), but **both live only
  in the Dart/CLI path** (`aec_offline.dart`); the app's jam mode runs the native C
  engine, which still has neither.
  ✅ **opus (next): fixed the native verify harness** (`native/aec/build.sh`
  `dart test` → `flutter test` — the tests import `package:flutter_test`, so
  `dart test` errored "Could not find package test"; the C build was fine). **The
  6-test ERLE cross-check now runs green on this Mac**, so the port below is finally
  verifiable. Two open items, in value order:
  1. **Port DTD (+ later RES) to `native/aec`** (`src/aec_dsp.c` + the shim's block
     loop) so the app's jam mode gets the +7 dB double-talk protection. Suggested:
     do **DTD first** (simpler, higher value), RES second. Add a `dtdEnabled` +
     hangover/block-counter to `AecDsp`, compute `rho = dot(mic, echoEst)/√(mm·ee)`
     (echoEst = the predicted echo `yRe[b+i]`), and gate the NLMS update
     (`aec_dsp.c` ~L209–231) when frozen. ⚠️ **Fidelity trap:** match
     `DoubleTalkDetector` (aec_offline.dart) EXACTLY — its `update()` runs the
     block-counter + hangover **decrement every block**, incl. far-end-silent
     ones, whereas `aec_dsp_process` **returns early** on the far-end VAD (L190–196);
     do the DTD state bookkeeping BEFORE that early return or the freeze timing
     drifts from the Dart reference. Keep DTD **off by default** so the existing
     default-`adapt` cross-check still matches; add a NEW test asserting
     native-with-DTD ≈ Dart-with-DTD on a double-talk scenario. Verify with
     `bash native/aec/build.sh`. Keep CI-safety (analyzer exclusion, app green
     without the plugin).
  2. **(e) on-device tuning** — the real duplex path on iOS/Android hardware
     (mic permission, AVAudioSession category, latency/ring). Needed before jam
     AEC is real at all; see `docs/AEC_TIER3B.md`.

  Verify either with the `bin/aec.dart` harness (`--selftest`, `--dtd --res`) and
  the BlackHole rig. Same patent-free family as SpeexDSP MDF / WebRTC AEC3 (read
  for technique, don't vendor unless licence + tree stay clean).

- **opus (aec-cli)** · ✅ **idle / SHIPPED — AEC streaming CLI** (`dafacb1` D1,
  `afbe4ea` D2). Test echo cancellation over files/pipes headlessly — the
  pure-Dart `EchoCanceller` the native Tier-3b core is a cleanroom port of, so
  no device/FFI needed. **D1:** Flutter-free `lib/core/audio/aec_offline.dart`
  (`estimateEchoDelay`, `cancelEcho(mic,ref)→cleaned+ERLE+delay`,
  `StreamingEchoCanceller` for interleaved stereo PCM16 → cleaned mono, running
  ERLE, buffers partial frames), 4 tests (tail ERLE >20 dB, near-end preserved
  under double-talk, delay recovery, streaming≡batch byte-equality). **D2:**
  pipe-first `bin/aec.dart` — `--selftest` (band+instrument+echo → PASS: ~48 dB
  echo-only ERLE, instrument survives), `--mic/--ref/--out` files, `--stdin`
  interleaved-stereo mic|ref → cleaned mono stdout (or `--detect` notes);
  deduped `bin/listen.dart`'s `--aec` onto the shared core. Verified over a real
  OS pipe (stereo gen → `aec --stdin` → `listen --stdin` reads the instrument,
  echo gone). Docs: streaming section in `AEC_TIER3B.md`. The offline analogue
  of the BlackHole rig, runnable in CI. **No app screens / ARBs / Workshop /
  native plugin touched.**

- **opus (parity)** · ✅ **idle / SHIPPED — keyboard-first nav in Select mode**
  (`b26a6b5`, last small Cause-2 item). Select-mode A–G keys jump the selection to
  the next note on that pitch (wrapping, accidental-insensitive) via
  `ScoreDocument.selectNextOfStep(Step)` — Insert enters notes, Select navigates
  them. **With this the WORKSHOP_PARITY arc + all its polish are shipped**; the
  only open items are "if ever wanted" (categorized insertion palettes; multi-
  select/rest inspector depth; grace-note LIST beyond one run — a library ask).
  ✅ **PDF export SHIPPED** (`e0954bd`, bucket G's last open
  item). **No library change** — `SystemLayout.layout` *is* a `ScoreLayout` and
  `renderLayoutToPng` takes one, so `layoutPages(score, settings, metrics:)`
  line-breaks + paginates, each `PositionedSystem` rasters to a PNG (through the
  app's painter → correct Bravura glyphs, 3× for print), and the `pdf` package
  places each at its exact staff-space position on an A4 box (staff-spaces →
  points via one spatium). Raster-per-system because the SVG path embeds
  `@font-face` text the pdf pkg can't parse + Bravura is CFF/OTF (TTF-only
  embedder). `+pdf ^3.11.0`, `lib/features/workshop/export/score_pdf.dart`,
  "PDF (print)" in `kExportFormats`, `test/score_pdf_test.dart` (valid header +
  real pagination + size scaling, under `runAsync`). Now: Select-mode letter keys
  jump the caret instead of no-op'ing.
- **opus (parity)** · ✅ **SHIPPED — value strip un-dual-purposed**
  (Cause 2's other grievance). The strip stays deliberately dual-purpose on
  **Sandbox** (arm the next note *and* fix the selected one — forgiving, what kids
  expect; unchanged, no regression). **Studio** honours the input mode instead:
  *insert* arms without silently rewriting the selection, *select* applies the
  pick to the selection. One `_pickAppliesToSelection` getter gates
  `_pickValue`/`_toggleDot`/`_pickAccidental`; arming always happens so the armed
  glyph stays in step. Widget tests pin all three behaviours (via barCount: a
  selected quarter → whole spills a bar). **Cause 2 is now fully addressed.**
- **opus (parity)** · ✅ **SHIPPED — inspector multi-select** (polish).
  The Studio inspector now edits a **multi-note selection**, not just a single
  note (the ⌃ palette's old Cause-3 limitation): articulation/tie chips reflect
  "all selected have it" and toggle the whole selection; dynamic/ornament
  dropdowns show the shared value (or blank when mixed) and set all; the
  single-anchor grace / change-here buttons disable for a multi-selection. Rests
  now read out instead of showing the empty hint. Widget test drives a 2-note
  selection into the inspector. `screens/composition_workshop_screen.dart` only.
- **opus (parity)** · ✅ **SHIPPED — Sandbox/Studio shelf toggle**
  (`5d467dc`, the two-shelves capstone). One `_Shelf { sandbox, studio }` switch
  (⋮ menu, default Sandbox): Sandbox hides the Studio-tier controls (V1/V2 voice
  toggle, Insert/Select mode toggle, inspector) → simple kid surface; Studio
  reveals them all together. Leaving Studio resets input mode→insert,
  inspector→off, active voice→0. **This closes the Studio-shell arc** — voice 2,
  the inspector (Cause 3), input modes (Cause 2) and now the shelf that unifies
  them. EN/DE; widget tests (Sandbox hides / Studio reveals; the depth-control
  tests enter Studio first). **The WORKSHOP_PARITY.md arc is now substantially
  complete** (A–G + the two shelves); remaining is polish — richer inspector
  (multi-select/rests/bar attrs), insertion palettes, keyboard-first nav in
  select mode, page/print view, PDF. Next agent: see `WORKSHOP_NEXT_HANDOVER.md`.
- **opus (parity)** · ✅ **SHIPPED — Studio shell Causes 2+3.** **Cause 2
  (input modes)** `8526bc0`: an `_InputMode { insert, select }` on the screen,
  default insert (= today). Select mode makes empty-staff taps deselect (not
  place) and letter keys no-op (`_onStaffTap`/`_onMpStaffTap`/`_handleKey` gate on
  it); tapping a note still selects, the piano still places. Insert⇄Select toggle
  (icon+label) in the top bar. EN/DE; widget test. **Remaining Studio work:** a
  real **Sandbox/Studio shelf toggle** (one switch that reveals the Studio-tier
  surfaces — inspector, mode toggle, future insertion palettes — instead of each
  being gated separately), richer inspector (multi-select / rests / bar
  attributes), and categorized insertion palettes. **The Workshop parity arc's big
  buckets (D notation-depth, F playback, Studio shell) are now all substantially
  shipped.** — Cause 3 (inspector) SHIPPED below:
- **opus (parity)** · ✅ **SHIPPED — Studio shell Cause 3 (inspector)**
  (`6306151`). A selection-driven properties panel (`WORKSHOP_PARITY.md` Cause 3):
  an **opt-in** side panel (⋮ menu toggle, OFF by default → Sandbox unchanged) that
  reflects/edits the selected note — articulations/tie (FilterChips), dynamic +
  ornament dropdowns, buttons to the grace + change-here dialogs; reuses the `_doc`
  mutators. Canvas `Expanded` became `Row[canvas, panel]`. The ⌃ palette stays.
  EN/DE; widget test (off-by-default → toggles on → shows controls). **Remaining
  Studio work — Cause 2 (input modes):** an explicit insert-vs-select state machine
  (today staff-taps always place; `_onElementTap` already selects, so the piece is a
  "select mode" that stops empty-staff placement + a status-line mode + keyboard-
  first entry). Also open: richer inspector (multi-select, rests, bar attributes),
  a real Sandbox/Studio shelf toggle. ✅ **voice 2 SHIPPED** (`bb6b7d0`):
  `Measure.voice2`, a sibling `_v2` stream sharing the bar grid via the `_elements`
  active-voice getter (mutation sites untouched); `_withVoice2` reflow+stamp
  (byte-identity fast path); V1/V2 toolbar toggle; MusicXML round-trips. ✅ **mid-bar
  clef SHIPPED, fully lossless** (`12404e1`/`854ab25` + crisp_notation writer
  `3c1b8bd`).
- **opus (next)** · ✅ **idle.** Worktree `../mus-next`, branch
  `feature/workshop-next`. All shipped & recorded in [HISTORY.md]: Workshop tempo
  marks · grace notes · playback bucket F · multi-part playback · voice-2 playback ·
  practice speed · count-in + loop-a-selection; Song Book **Sing along + Play along**
  (`chartFromScore`) with length-scaled stars; **Melody doodle** game; and the
  **native-AEC verify-harness fix** (`eba8c4d`, `build.sh` → `flutter test`) that
  unblocks the AEC C port (top item in the scoped block above). My feature lane is
  exhausted — remaining work is in the scoped "🎯 Remaining work" block at the top.

- **opus (groove-export)** · ✅ **idle / SHIPPED — Groove → Song Book / MusicXML**
  (`docs/LOOP_MIXER_FOLLOWUPS_HANDOVER.md` §A; `3c816ab` A1, `a7c3554` A2+A3).
  The Loop Mixer's share sheet now saves the groove as a **real multi-part
  score** — the payoff of the toy and the on-ramp to the Workshop. **A1:** pure
  `grooveParts()` in `groove_notation.dart` — enabled pitched tracks
  (voice·melody·chords·sparkle·bass) → one `Score` each (bass clef for bass) →
  `MultiPartScore`; drums/beat skipped (no percussion staff yet). **A2:** share
  sheet "Save to Song Book" → `multiPartToMusicXml` → `UserSongsService.addSong`
  (gated on a pitched track). **A3:** "Export sheet music (MusicXML)" desktop
  save. l10n de/en (`loopMixerSaveSongBook/ExportMusicXml/SaveTitle`). Tests:
  8/8 groove_notation + 12/12 loop_mixer (multi-part round-trip through the
  Song Book). **No Workshop files touched.** Only §B (native-AEC jam grading)
  of the handover remains unclaimed.

- **opus (jam-grading)** · ✅ **idle / SHIPPED — Groove jam: native-AEC grading
  ("the band listens back")** (`docs/LOOP_MIXER_FOLLOWUPS_HANDOVER.md` §B;
  `915a17a` B1, `5e99e84` B2+B3). This closes the Loop Mixer follow-ups handover
  — **both §A and §B done.** **B1:** pure-Dart `lib/core/audio/loop_reference.dart`
  (`LoopReferenceScheduler`: loop PCM → real-time reference windows, seam wrap +
  phase-preserving swap-at-downbeat, `barAt`), 6 tests. **B2:** jam mode picks the
  Tier-3b `AecEngine` (`createNativeAecEngine`) when present — the engine plays
  the loop PCM we feed it AND cancels it, so the jamFit colour grades the player
  not the speaker; a 50ms reference pump (2205 samples/tick = the 44.1k drain)
  keeps the ring fed; live edits re-feed the scheduler at its seam. Graceful
  fallback to the shipped `echoCancel` path when no plugin (web / device open
  fails). `aecFactory` injection drives it headless. **B3:** AEC start hint +
  a trust caption under the live note ("band cancelled — this grades you" vs the
  headphones reminder). CI-safe: `dart:ffi` stays out of web (conditional
  export), plugin stays analyzer-excluded, app green with plugin absent. Tests:
  14/14 loop_mixer (fake-AEC round-trip: reference pushed + synth A4 on the
  cleaned stream graded as A4) + 6/6 loop_reference; whole-project analyze clean.
  ⚠ **On-device pump tuning (ring latency) is milestone (e) — needs hardware, not
  verifiable headless.** Deferred-optional: "follow the melody" per-note grading
  via `PlayAlongEngine` (a moving-score highway over the groove) — its own effort.
  **No Workshop / AEC-plugin internals touched.**

- **opus (jam-follow)** · ✅ **idle / SHIPPED — Groove jam "follow the melody"
  (per-note grading)** (`9ff81c1` C1, `6af3d00` C2). Closes the last deferred
  bit of the Loop Mixer follow-ups (§B slice 3's optional). **C1:** pure
  `grooveChart()` in `groove_play_along.dart` (groove cells → `PlayAlongChart`,
  2 steps = 1 beat, chords→top voice, rests→gaps), 4 tests. **C2:** a "follow"
  toggle (track_changes icon) in jam mode builds a looping `PlayAlongEngine`
  over the leading track (`cellsFor(_engravedTrackId)`, no count-in, practice-
  loop re-arms each groove pass; `voice` grades octave-agnostic). Every jam
  reading now runs through `_onJamReading` → jamFit colour **and** the follow
  grade at the live clock → a per-pass accuracy meter ("🎯 Melody match: N%").
  Rebuilds on grid change, torn down on jam stop, works in either jam tier.
  `debugFeedFollow` seam grades deterministically (the live grade reads a real
  Stopwatch tests can't advance). l10n de/en (`loopMixerFollow` +
  parameterized `loopMixerFollowScore`). Tests: 24/24 loop_mixer + 4/4
  groove_play_along; whole-project analyze clean. **No Workshop / AEC internals
  touched.** The entire Loop Mixer follow-ups arc (§A, §B, follow-melody) is now
  done.

- **opus (parity)** · ✅ **idle / SHIPPED — mid-*bar* clef changes (`inlineClefs`)**
  (`12404e1` model + `854ab25` UI). Onset-addressed clef change *within* a bar
  (draws right before the anchored note), vs today's bar-*start* `clefChange`.
  Additive `_inlineClefs` id-anchor side-map → `Measure.inlineClefs`; the
  `_withInlineClefs` stamp accumulates each bar's tuplet-scaled onset and emits an
  `InlineClefChange` at the anchor (onset-0 skipped — that's a bar-start change);
  empty-anchor byte-identity fast path; `loadScore` recovers them (so **import**
  keeps mid-measure clefs). "Clef (mid-bar)" row in the change-here dialog, EN/DE.
  `test/inline_clef_test.dart` (9) + widget row-presence; affected suite green,
  analyze clean. ✅ **Fully lossless:** also taught the crisp_notation MusicXML
  *writer* to emit mid-measure clefs (`crisp_notation@3c1b8bd`,
  `fix(musicxml): emit inline (mid-measure) clef changes on export`, +1454-test
  core suite green) — the reader already parsed them, so **save → reopen** now
  round-trips (both in-memory and the MusicXML *file* path asserted). Closed the
  `workshop-musicxml-writer-gaps` blocker. **NB** tempo marks were
  shipped by **opus (next)** (`1f94a5c`) while I built an identical one; discarded
  the duplicate — a coordination collision.
- **opus (parity)** · ✅ **idle / SHIPPED — note ornaments (trill/mordent/turn)**
  (`194fa66` model + `5459e60` UI, suite **738 green**). Per-note `Ornament?`
  field on `EditorElement` (rides the element snapshot for free), emitted onto
  `NoteElement.ornament` (drawn by crisp_notation `layout_marks`); an
  "Ornament: …" row in the note palette. Round-trips. **The notation-depth
  surface is now broad:** mid-score clef/key/time, repeats, voltas+navigation,
  tuplets, discontiguous selection, RhythmPolicy.split, and ornaments — all on
  the flat model. **Remaining bigger gaps** (each its own effort): grace notes
  (a note carries a LIST of grace notes — a mini-editor), tempo marks (id-anchor
  stamp, feeds playback), mid-*bar* clef changes (`inlineClefs`), voice 2, the
  **Studio shell** (input modes + inspector, Causes 2+3), and **playback** (real
  transport + moving cursor). **A fresh agent should start from
  `docs/WORKSHOP_NEXT_HANDOVER.md`** — it scopes each
  remaining item, the id-anchor-vs-field pattern that built the batch, the
  byte-identity invariant, and the test conventions.

- **opus (tracker)** · ✅ **idle / SHIPPED — Tracker gaps filled (multi-agent).**
  3 pure-core sub-agents (against contracts + test suites I wrote) built
  `mod_bridge.dart` (Tracker↔MOD), `tracker_effects.dart` (arp/vibrato/slide DSP)
  and `tracker_notation.dart` (multi-part Tracker↔Score + chord split) — 22 tests,
  `ac12747`. I then integrated all shared-file wiring: **per-note effects** (cell
  menu) `28f2f83`, **MOD import/export UI** (file_selector) `ae484a9`, **multi-part
  score view** `d67cb56`, **gapless two-player swap** `df7e644`, and **MIDI
  import/export = the MIDI↔MOD hub** (via crisp_notation `scoreFromMidi`/
  `scoreToMidi`, no external converter) `8a80421`. ✅ **`.s3m` reader SHIPPED**
  `2860ce2` (golden oracle + real "Illustrious Fields"; agent-built against my
  contract+tests). ✅ **`.xm` reader SHIPPED** (`xm_module.dart` model+byte-spec +
  `xm_reader.dart` `parseXm` + golden oracle `test/fixtures/golden.xm` + real "The
  final support" 24ch/20pat/77ins live test; agent-built against my contract+tests;
  MSB-mask pattern unpack + delta-decoded 8/16-bit samples). ✅ **`.it` reader
  SHIPPED** (`it_module.dart` model+byte-spec + `it_reader.dart` `parseIt` + golden
  `test/fixtures/golden.it` + real "terrascape intro music" 8ch/17pat/12smp live
  test; agent-built against my contract+tests). Handles the mask-cache pattern
  unpack, uncompressed 8/16-bit (signed/unsigned/LE-BE/delta) AND **IT214/IT215
  compressed** samples — the variable-bit-width decompressor's exact algorithm was
  validated by a Python oracle round-tripped against **libxmp `itsex.c`** (44/44),
  and golden.it embeds validated compressed blocks so the hard path has a byte-exact
  target even though the real file is all-uncompressed. **Module reader set now
  complete: `.mod` · `.s3m` · `.xm` · `.it`.** ✅ **Cross-format converters —
  slice C1 SHIPPED** (`module_doc.dart` neutral hub model + `module_convert.dart`:
  `sniffModuleFormat`, `parseAnyModule` = unified importer, `docFrom{Mod,S3m,Xm,It}`
  adapters, `docToMod`/`convertToMod`). Any format → neutral `ModuleDoc` (pitch as
  MIDI, PCM normalized ±1, 1-based instruments) → `.mod`. v1 drops per-cell effects
  (cross-format effect table = follow-up); notes/instruments/volume/samples/
  structure convert cleanly. Test: 4 goldens through the hub + XM→MOD round-trip +
  live wild files. ✅ **XM writer + convertToXm SHIPPED** (slice C2): `xm_writer.dart`
  `writeXm` (byte-inverse of `parseXm`: header, MSB-mask packing, instrument/sample
  headers, delta-encoded 8/16-bit) + `docToXm`/`convertToXm` — now **mod2xm /
  s3m2xm / it2xm** work (xm2mod already did via convertToMod). Verified by
  write→parse round-trips (golden + hand-built multi-channel/16-bit) + mod→xm &
  it→xm hub conversions. ✅ **S3M writer + convertToS3m SHIPPED** (slice C3):
  `s3m_writer.dart` `writeS3m` (paragraph-aligned layout, parapointer patch pass,
  signed PCM, "what"-byte pattern packing) + `docToS3m`/`convertToS3m` → **mod2s3m /
  xm2s3m / it2s3m**. Round-trip verified (golden + hand-built loop/multi-channel) +
  mod→s3m & it→s3m hub conversions. ✅ **IT writer + convertToIt SHIPPED** (slice
  C4): `it_writer.dart` `writeIt` (sample-mode, absolute-offset layout + patch pass,
  uncompressed signed 8/16-bit, channelvar+mask packing) + `docToIt`/`convertToIt`.
  Compressed source samples write back uncompressed (PCM intact). **Converter matrix
  now COMPLETE — full N×N: {mod,s3m,xm,it} → {mod,xm,s3m,it}.** Verified by golden +
  hand-built round-trips + mod→it & xm→it hub conversions. **Next: "borrow a sample
  from a module"** (readers already expose normalized PCM — wire a module→sample→
  SampleInstrument picker); the headless **CLI tools** (§H — modinfo/modconv/render);
  optional IT214/215 *compressor* + a cross-format effect table (v1 drops effects).
  📋 **Full idea backlog —
  codecs, FX (crispaudio/CrispFXR/voicelab + OpenMPT), sampling, notation, Studio
  depth — in [`docs/TRACKER_IDEAS.md`](TRACKER_IDEAS.md); the FX effort in
  `docs/FX_HANDOVER.md`.**
- **opus (tracker)** · ✅ **idle / SHIPPED — `.mod` import/export codec.** Pure-Dart
  ProTracker codec in `lib/core/audio/mod/` (model+contract `mod_module.dart`,
  `parseMod` reader, `writeMod` writer — implemented by two sub-agents against the
  contract, then converged). **Byte-stable round-trip** verified against a
  hand-assembled golden oracle AND a real 224 KB wild module (locally; copyrighted
  mods aren't committed — `test/fixtures/golden.mod` is the license-clean fixture,
  and `test/mod_codec_test.dart` round-trips any `.mod` dropped in). 6 tests green.
  Next (unclaimed): a Tracker↔MOD **bridge** (map a module onto tracker patterns +
  `SampleInstrument`, and export the tracker song as a `.mod`) — lossy, needs the
  8-step grid ↔ 64-row mapping decisions. Below: the rest of the Tracker (shipped).
- **opus (tracker)** · ✅ **idle / SHIPPED — Tracker (pattern sequencer).** Dual-audience
  tracker (ModEdit/FT2/ST3/IT spirit, touch-first, Sandbox/Studio two-skins-over-
  one-model) built ON the shipped Loop Mixer engine (`mixStems` +
  `loop_engine.dart`). Full plan: `docs/TRACKER_HANDOVER.md`.
  Worktree `../mus-tracker`, branch `feature/tracker`.
  ✅ **Slice 0 SHIPPED** (`98cdb05`): pure-Dart `TrackerEngine` (additive), 13
  tests. ✅ **Slice 1 SHIPPED** (`775fe03`): the Sandbox grid screen (instrument
  tabs + pentatonic piano-roll + looping playback + playhead), registered sandbox
  `GameInfo 'tracker'` in composition, EN/DE, 4 tests. ✅ **Slice 2 SHIPPED**:
  sfxr chiptune instruments — focused pure-Dart port of `crispaudio`'s SynthEngine
  into **`lib/core/audio/crisp_dsp/sfxr.dart`** (+ `test/sfxr_test.dart`), a
  `SfxrInstrument` on the `TrackerInstrument` seam synthesized per-note at pitch,
  and a live `zap` chiptune channel in the default band. **Settled hot files:**
  `game_registry.dart`, both ARBs. ✅ **Slice 4a SHIPPED** (`449bd6f`): sample DSP
  in `crisp_dsp/` (resampler + granular pitch-shift + formant-shift ports from
  `crispaudio`) + `SampleInstrument` + `VoiceEffect` palette (chipmunk/monster/
  deep via formant, robot via ring-mod+bitcrush — pitch-stable so samples stay in
  tune). ✅ **Slice 4b SHIPPED:** the **record-your-voice bridge** — `record`-
  plugin `VoiceClipRecorder` (mic → Float64), a runtime-swappable `voice` channel,
  and a record/effect bottom-sheet in the tracker (EN/DE). ⚠️ **Mic path is
  device-only** — verified via the tester seam (inject a synthetic clip); real
  mic needs an on-device run. ✅ **Slice 5a SHIPPED (notation bridge,
  Tracker→Score):** `tracker_notation.dart` `trackerChannelToScore` (held runs →
  tied notes decomposed to standard values, split at 4/4 bar lines) + a StaffView
  "score view" panel toggled from the app bar (the selected channel as notation).
  ✅ **Slice 5b SHIPPED (Score→Tracker import):** `scoreToTrackerCells` (quantize
  durations to the grid, top-note-of-chord, merge tied notes, snap to pentatonic)
  + `TrackerEngine.setChannelCells` + a "Load a tune" app-bar action importing a
  built-in demo melody into the melody channel. Round-trip (Tracker→Score→Tracker)
  is unit-tested — the bidirectional bridge is complete.
  ✅ **Slice 3 SHIPPED (Studio instrument picker):** `kTrackerInstruments` palette
  (4 additive + 5 sfxr) + a `tune` app-bar action → bottom-sheet picker that
  re-voices the selected channel (`setChannelInstrument`), unlocking the chiptune
  presets. ✅ **Percussion SHIPPED:** `PercussionInstrument` (each cell = a
  one-shot drum hit, `midi` encodes the `Drum`) + a `drums` channel in the default
  band; the screen gained a **per-channel grid-row model** (drum rows w/ icons for
  percussion, pentatonic pitch rows otherwise). ✅ **Workshop↔Tracker handoff
  SHIPPED:** the "Load a tune" action is now a **song picker over the shared
  `kSongs` book** (Alle meine Entchen / Twinkle / …) — import a real tune's opening
  bar onto the grid to remix (via `scoreToTrackerCells`; partial by design). ✅
  **Arrangement SHIPPED (song mode):** `renderSong` concatenates pattern snapshots
  into one long loop; the screen gained **4 pattern slots (A–D)** + a **Play song**
  action chaining the non-empty slots. ✅ **Song mode v2** (`6afdaf2`): editable
  order-list (A A B A) + a song-length playhead. ✅ **Per-note dynamics**
  (`9b53b3e`): long-press a note → soft "ghost" note (a renderer-agnostic volume
  column). ✅ **FEATURE-COMPLETE for this pass** — every next-step done; only
  deliberately-deferred big items remain (`.mod`/`.xm` import, arp/porta/vibrato
  effect commands, gapless swap — each its own effort, see handover §4).
  **opus (tracker) → idle.** Handover:
  `docs/TRACKER_HANDOVER.md`.
- **opus (parity)** · ✅ **idle / SHIPPED — notation-depth batch (voltas/nav, tuplets, discontiguous selection, RhythmPolicy.split).**
  Working through the tracked roadmap in
  [`WORKSHOP_PARITY.md`](WORKSHOP_PARITY.md) §"Notation-depth roadmap": **(1)
  voltas + navigation** (D.C./D.S./coda; element-id anchors like clef/key), **(2)
  tuplets** (ids→`TupletSpan`), **(3) slice 3 discontiguous id-set selection**,
  **(4) slice 7 `RhythmPolicy.split`**. Each = its own commit + board update;
  each touches `score_document.dart` then `composition_workshop_screen.dart`
  (`_paletteButton`) + ARBs. **(1) voltas+nav SHIPPED** (`70bca0b`, suite 615 green); **(2) tuplets SHIPPED** (`e63730e`+`daaa443`, suite 650 green); **ALL FOUR SHIPPED** — (1) voltas+nav `70bca0b`, (2) tuplets `e63730e`+`daaa443`, (3) discontiguous selection `ca52d58`, (4) `RhythmPolicy.split` `7ffe193`+`5fda285`. The element-id-anchor + reflow work closed the whole notation-depth batch on the flat model; every add is byte-identity-guarded so the kid Sandbox surface is unchanged. **Idle.**
- **opus (parity)** · ✅ **idle / SHIPPED — repeat barlines (start/end), model +
  UI** (`959f99f` + `ad85a1a`, whole suite **599 green**). Fourth element-id-
  anchored bar attribute after clef/key/time; closes the "can't notate a repeat"
  gap and — since crisp_notation expands repeats in `playbackTimeline` — affects
  playback too. Booleans → two id **sets** stamped in `_withMidScoreChanges`
  (empty-set fast path keeps goldens byte-identical); UI = two toggle items in
  the note palette (⌃). Round-trips through MusicXML. `score_document.dart` +
  `composition_workshop_screen.dart` (`_paletteButton` only) settled again.
- **opus (games)** · ✅ **idle / SHIPPED — new-minigame + creative-mode sweep.**
  Whole suite green (verified in crash-dodging **batches** — the monolithic
  `flutter test` only SIGTERM-flakes under the machine's concurrent load, not a
  real failure; single-file/batched runs are all green). 11 units, each its own
  rebased-ff commit on `origin/main`: reading binaries *Tie or Slur* (`tie_slur`)
  + *Beam or Flag* (`beam_flag`, beam/flag verified at the crisp_notation layout
  level); four new **Connect** modes (`connect_dynamics` / `connect_rests` /
  `connect_tempo` / `connect_beats`); *Find the Key (bass)* (`key_find_bass`, the
  `PianoKeyboard` shifted two octaves down); mic-graded *Sing the Interval*
  (`sing_interval`, reuses the `sing_back` harness); the 3-basket
  **Sharp/Natural/Flat** widening of `accidental_sort` at 2★ (real ♮ via
  `NoteElement.showAccidental`); *Triad or Seventh?* (`triad_seventh`, the dom7
  built app-side, no library builder); and the **Colour Melody** grid composer
  (`grid_composer`) for pre-readers. **Hot shared files touched (all settled):**
  `game_registry.dart`, `core/tuning.dart`, the ARBs, `connect_line_screen.dart`,
  `accidental_sort_screen.dart`, `key_find_screen.dart`. **Next (unclaimed):** the
  **Loop mixer** — full handover in
  `docs/LOOP_MIXER_HANDOVER.md`.
- **opus (parity)** · ✅ **idle / SHIPPED — mid-score changes, model + UI** (whole
  suite **592 green**). The full clef/key/time mid-score-change family now works
  end-to-end on the flat model via **element-id anchors** (no bar-spine flip):
  model in `685ced2`/`0e0f736`/`3b78b1d`, UI in `81a38c7`. The UI is a "Change
  from here…" item in the note-property palette (⌃) opening a compact 3-dropdown
  dialog (clef/key/time, each defaulting to "No change", pre-filled from the
  note's bar). `score_document.dart` settled; `composition_workshop_screen.dart`
  touched only in `_paletteButton` + a new dialog. **What's next (unclaimed):**
  mid-bar clef changes (`inlineClefs`) aren't modelled yet; slice 3 (id-set
  selection) and slice 7 (`RhythmPolicy.split`) remain per WORKSHOP_PARITY.md.
- **fable (loop-mixer)** · ✅ **SHIPPED — slice 10, the groovebox ladder is
  COMPLETE** (`866350c`); idle, worktree removed. **Beatbox → drum card:**
  `PitchReading` now carries `rms` + `zcr` on every frame (additive, computed
  in the detector's existing silence-gate pass — useful to any future
  percussive/onset consumer); `beat_capture.dart` does onset detection +
  kick/snare/hat classification, thresholds calibrated by probing our own
  `renderDrum` one-shots through the real detector (kick zcr≈0.005
  pitched-low · snare≈0.45 · hat≈0.67), acceptance = a synthesized beatbox
  roundtrips to the EXACT rows. Gotcha for reuse: classify from the
  *brightest* loud attack frame, not the loudest — the onset window straddles
  leading silence, which dilutes zcr and disguises hats as snares. The
  capture row now has two buttons (sing / beatbox) over one harness; the
  beat is a teal card and rides the share token. **Jam along (headphones
  v1):** groove keeps playing, mic listens with platform `echoCancel` + a
  headphones hint (no native-AEC dependency), live note coloured by
  `engine.jamFit` (chord tone / pentatonic / outside; progression-aware via
  `chordAtBar`, vamp = C↔Am). Mic contention handled (capture stops jam).
  63 slice tests + smoke green pre-push (with pipefail), analyze clean.
  **Nothing of the ladder remains.** The two natural follow-ups (groove→
  Song Book/Workshop export · native-AEC full-duplex jam grading) are
  written up as a buildable handover:
  `docs/LOOP_MIXER_FOLLOWUPS_HANDOVER.md`
  — unclaimed, each is a session-sized effort.
- **fable (loop-mixer)** · ✅ **SHIPPED — Loop Mixer 2.0 complete, slices 2–9
  all on main** (final `f248ad4`); now idle, worktree removed. One session:
  **engine v2** (`5e5d81b`: GrooveSpec, data patterns, swing, A/B/C variants,
  euclid, levels) → **screen v2** (`74c5141`: swing slider, variant badges,
  level sliders, seam-timed drum fill every 4th loop) → **chord progression
  lane** (`799f2d5`: I–V–vi–IV/I–IV–V–I/vi–IV–I–V, 4-bar loop, chord-relative
  bass+chords via ChordFollower, listen.dart roundtrip reads every bar's
  root/fifth exactly) → **live engraving** (`5ad76a9`: groove_notation.dart,
  score panel via StaffView) → **share token + WAV export** (`91e9c24`:
  'KU1.' base64 GrooveSpec, serverless) → **infinite mode** (`b512be7`:
  seeded per-seam variation — breathing hats, snare ghosts, melody
  ornaments) → **sing-a-track** (`c405337`: count-in → 2-bar mic capture →
  pentatonic-quantized 'voice' card, groove_capture.dart; cells travel in
  the share token). Slice 5 stays deferred to the Tracker; slice 10
  (beatbox→drums, AEC jam mode) is the remaining unclaimed ladder rung.
  Suite: 77 tests green across the loop suites + tracker + smoke; analyze
  clean. ⚠️ Lesson for everyone: `flutter test … | tail` EATS the exit code —
  one red smoke slipped to main that way (fixed fwd `f248ad4`); use
  `set -o pipefail` when a push gates on a piped test run.
- **opus (parity)** · 🚧 **ACTIVE — Workshop editor parity.** ✅ **SHIPPED: the
  multi-part lag is fixed** (`1d9c804`, suite **513 green**, analyze clean).
  `22f9e5f` fixed single-part; multi-part still ran **~4 full engraving passes
  per rebuild × 2 frames**. The engine was never the problem — crisp_notation
  routes every interactive setter to `markNeedsPaint` and early-returns on a
  value-equal document; **the canvas defeated each guard**: (1) `MusicFonts.load`
  handed inline to `FutureBuilder` returns `Future.value(cached)` — a new
  instance every call → resubscribe → **double rebuild** (snapshot then ignored);
  (2) `PageMetrics` has **no `operator ==`**, so a fresh-but-equal instance
  forced `markNeedsLayout()` on *every* build — which also made the deep
  `document ==` walk pure waste; (3) the discarded probe `layoutMultiPartPages`
  ran per build — **measured ~155ms (4 parts × 32 notes) / ~247ms (4 × 64)**,
  i.e. *this was the lag*; (4) `buildMultiPart()` was the one un-memoized
  builder; (5) **`_onMpDragUpdate` was missed by `22f9e5f`** → ~4 layouts *per
  pixel* on drag. Verified with temporary counters through the real rebuild
  path: 60 idle rebuilds now do **0 probes / 0 geometry misses / 0 build
  misses** (was 60 each, doubled). `MultiPartCanvas` is now **stateful** (holds
  the font future + geometry cache) — mind that if you're mid-edit on it.
  · ⚠️ **Trap for every agent here:** running `dart format` in a **fresh
  worktree before `flutter pub get`** makes it default to the **new tall style**
  (no `.dart_tool/package_config.json` → can't read `sdk: ^3.5.0`), which
  reformats the *whole repo* and **adds trailing commas that the correct style
  then treats as force-split — so a second `dart format` cannot undo it**. It
  turned an 8-line edit into a 409-line diff on the hot screen file. **Always
  `pub get` first.**
  · **Next:** lossless save/round-trip + export honesty, then plan the
  measure-spine refactor. **Maintainer decision (2026-07-16): two shelves —
  Sandbox (kid surface, unchanged) + Studio (full capability).** So the
  measure-spine + inspector are green-lit, and any depth that can't hide behind
  the shelf toggle should be viewed with suspicion.
  · Concepts + order of attack: [`docs/WORKSHOP_PARITY.md`](WORKSHOP_PARITY.md) (conceptual layer above
  WORKSHOP_PLAN.md's phase log). Finding: the ~28 gaps vs. full notation programs
  reduce to **4 causes**, 3 of them ours — (1) **measures are derived, not real**
  (flat `EditorElement` list + `_packMeasures`) which alone blocks tuplets/voices/
  mid-score key-time-clef-tempo/repeats/measure-ops/cross-bar splitting *and*
  forces index-range selection; (2) no input-mode separation; (3) no inspector
  surface; (4) the canvas defeats crisp_notation's paint-only fast paths.
  **crisp_notation already models nearly all of it** — the block is app-side.
  · ⚠️ **@anyone touching the Workshop:** `22f9e5f` fixed single-part hover
  (now correctly **0 layouts**), but **multi-part is still ~4 full layouts per
  rebuild × 2 frames** — `MusicFonts.load` handed inline to `FutureBuilder`
  (fresh `Future` every build → double rebuild; snapshot then ignored),
  `PageMetrics` lacking `==` (forces `markNeedsLayout` on *every* build),
  a discarded probe layout, unmemoized `buildMultiPart()`, and **`_onMpDragUpdate`
  (`:511`) missed by `22f9e5f`** → ~4 layouts *per pixel* on multi-part drag.
  All small fixes; I'm taking them next in `multi_part_canvas.dart` +
  `composition_workshop_screen.dart` (hot — coordinate before you edit).
  · ✅ **SHIPPED — save → reopen is lossless + export honesty** (`20fa35e`, suite
  **528 green**). `loadScore` kept only `pitches.first` and dropped ties,
  articulations, dynamics and the pickup — all things `buildScore` already
  writes — so **Save → reopen silently destroyed work** (every chord collapsed to
  one note). It's now the exact inverse for everything the element stream can
  hold; the 5 new tests fail against the old code with exactly that data loss,
  incl. through MusicXML (the real Save/Open path, which turns out to preserve
  everything the editor can represent). Also: every export but MusicXML/`.mxl`
  wrote the **active part only** with no hint — crisp_notation has a multi-part
  *writer* for MusicXML alone though every text format has a multi-part *reader*,
  so the asymmetry is library-side and a real fix is a **crisp_notation ask**.
  Until then the export sheet says "All N parts" or "Only «part» — this format
  cannot hold several parts". Localized de/en.
  · 🚧 **NOW: the measure-spine refactor (Cause 1) — planned, slice 0 landed.**
  Design + slice list in [`docs/WORKSHOP_PARITY.md`](WORKSHOP_PARITY.md). Three
  corrections worth knowing if you touch the Workshop: (1) **the screen is
  already id-based** — `selectIndex`/`measureIndexOf`/`moveByIdToMeasure` have
  **zero callers in `lib/`**, so the refactor barely touches it; (2) it lands
  **on `main` in ~9 invisible slices, NOT a long-lived worktree** (353 commits/7
  days makes a long branch unmergeable; spine+reflow is byte-identical to
  `_packMeasures`, so each slice is externally invisible); (3) **no command/undo
  model** — instead lift the snapshot stack to `MultiPartDocument` (so removing
  an instrument stops being unrecoverable) and bound it. **Slice 0 = golden
  characterization tests** pinning today's exact packing
  (`test/score_document_packing_golden_test.dart`, 14 tests), including two
  **known-wrong** goldens (a whole note makes an over-full 3/4 bar; an
  overflowing note short-fills the previous bar instead of splitting+tying) so
  the refactor changing them is loud, not a silent test update.
  · ✅ **SHIPPED — slice 1: `_packMeasures` → pure top-level `reflow()`**
  (`b2df911`, model suite **134 green**, goldens byte-identical). The packer was
  an instance method reading `this.timeSignature`/`this.pickup`; it's now
  `reflow(elements, {timeSignature, pickup})` with all 3 call sites updated
  (buildScore + both grand-staff staves). This is the seam slice 2 builds on — a
  `RhythmPolicy.spill` document will reflow its stream through exactly this. New
  `reflow_test.dart` (10 tests) exercises it in isolation and locks the contract
  slice 2 needs: **reflow preserves element identity + order** (re-bars the same
  instances, never clones/reorders). Touched **only `score_document.dart`** + a
  new test.
  · ✅ **SHIPPED — mid-score clef changes; SLICE 2 RETIRED** (`685ced2`; 112
  focused tests green + goldens byte-identical + analyze clean — full suite not
  run to completion, the shared box was thrashing at load ~186 from concurrent
  Xcode + agents, OOM-killing test runs; the empty-map fast path makes a
  regression on untouched docs structurally impossible; CI runs the full suite).
  **The course-correction:** doing slice 1 revealed the planned slice 2 (flip
  `_elements` → `List<Bar>` source of truth) means rewriting **~60 index-based
  mutation sites at once** and is the *wrong* architecture for spill mode — bars
  are reflowed every edit, so they have no stable identity to anchor to. The
  low-risk mechanism is to **anchor bar-attributes to an element id** (side-map
  on the flat doc) and let `buildScore` stamp them after reflow; the id rides
  re-barring for free. Shipped that via clef: `_clefChanges: Map<String,Clef>` +
  a post-reflow pass, wired through undo/clearAll/loadScore (save→reopen keeps
  it).
  · ✅ **SHIPPED — mid-score KEY changes** (`0e0f736`, 71 focused tests green,
  goldens byte-identical). Same element-id-anchor mechanism as clef (no capacity
  impact); generalized the post-reflow pass to `_withMidScoreChanges` handling
  clef **and** key in one walk, shared `_anchoredIn<V>`, fast-path now checks
  both maps empty so byte-identity still holds. `setKeyChangeAt` + loadScore
  recovery mirror clef; test renamed → `mid_score_change_test.dart` (+6 key
  cases incl. clef+key coexisting on one bar). **Next: mid-score TIME changes —
  the one with a wrinkle:** `reflow` must switch bar capacity at the anchor
  (clef/key don't), so it's not a pure post-reflow stamp. A first-class `Bar` is
  deferred to slice 7 (`RhythmPolicy.split`, Studio), where bars keep identity.
  See the refinement box in [`WORKSHOP_PARITY.md`](WORKSHOP_PARITY.md).
  · ✅ **SHIPPED — wider meters + full circle of fifths + picker crash-guard**
  (`7d954be`, suite **549 green**). The time picker was capped at 2/4·3/4·4/4 and
  the key picker at ±4 fifths — but the packer sizes bars by
  `timeSignature.toFraction()`, the engine beams 6/8 as 3+3 via `beamGroups()`,
  and `KeySignature` accepts ±7, so both were **UI caps only**. Added 2/2, 3/8,
  6/8, 9/8, 12/8, 5/4, 6/4 and the full circle of fifths (collapsed dropdowns, so
  the kid Sandbox surface is unchanged). Also closed a **latent debug crash of
  the same class**: `DropdownButton` asserts its value is among items, so opening
  a file whose meter — or, via the now-lossless `loadScore`, an odd pickup —
  falls outside the offered set threw; both `_dropdown` and the raw pickup
  dropdown now self-heal by surfacing the current value. **32nd/64th deliberately
  NOT added** (they'd clutter the always-visible value strip → Studio, per the
  two-shelves design). · ⚠️ format-trap reminder still applies: **`flutter pub
  get` before any `dart format`**, and format only *your* files (a blanket
  `dart format test/` reformats the ~7 pre-existing non-canonical files and
  churns other agents' work).
  · ✅ **SHIPPED in crisp_notation — the large-score layout ceiling (G).** User
  confirmed scores reach 30+ bars, so I measured the layout cost curve: a 4-part
  × 100-bar score took **~12.8s per layout**, and the cost was **not** the
  per-measure "natural" pass (near-free) — it was **justification**, which
  bisected `spacingStretch` for a **fixed 24 full system-layouts per system**.
  Replaced all three copies (`layoutSystems`/`layoutGrandStaffSystems`/
  `layoutStaffSystemSystems` — the last is our multi-part path) with a shared
  Illinois regula-falsi solver: **3.19 layouts/system avg (worst 14) vs 12.24**,
  same accepted result. On `crisp_notation@main` **`198ef17`** (core 1446 +
  Flutter 301 green); 6 justified-system goldens re-blessed (<1.5%, visually
  identical, barlines stay aligned). **NB the app won't see it until the local
  `../crisp_notation` clone reconciles — it's behind origin with another agent's
  uncommitted work, so I did NOT pull it; mus CI (public `@main`) already has
  it.** This was the one remaining perf ceiling I couldn't fix app-side.
- **opus (workshop→games)** · **idle / SHIPPED — Workshop performance.** The
  editor "severely lagged" on desktop: the root cause was **`onHover` calling
  `setState` on every pointer-move pixel** → a full-screen rebuild (42-key piano +
  all rows) per pixel. Fixes (all in `composition_workshop_screen.dart`): (1)
  **guarded hover** — `_onHover` only rebuilds when the *quantized* `StaffTarget`
  changes (the ghost snaps to lines/spaces anyway, so pixel updates were pure
  waste; `StaffTarget` has value equality), cutting hover rebuilds ~10–50×; (2)
  **cached the piano widget** (`late final _pianoKeyboard`) — its config is
  constant, so Flutter now skips rebuilding all 42 keys on every editor setState;
  (3) **`RepaintBoundary`** around the canvas + the piano dock so live-drag /
  ghost / caret repaints stay local (don't repaint the whole screen). Analyze +
  23 workshop widget tests green, no behaviour change. · ⚠️ **@opus (g6)
  follow-up:** `MultiPartCanvas.build()` runs a full `layoutMultiPartPages` probe
  **+** `buildMultiPart()` (unmemoized) **+** `MultiPartView` re-layout **every
  build** — 3 layout passes per rebuild in multi-part mode. It has no `onHover`
  so it's per-interaction not continuous, but memoizing `buildMultiPart`
  (invalidate on edit) + caching the probe would make multi-part editing much
  snappier.
- **opus (workshop→games)** · **idle / SHIPPED — Workshop file I/O overhaul.**
  (1) **Fixed macOS pickers** — added `com.apple.security.files.user-selected.
  read-write` to both `.entitlements` (the app is sandboxed; without it the
  open/save dialogs were blocked). Verified in the built `.app`. (2) **Unified**
  the ⋮ menu to one **Open…** + one **Export…** (was one item per type). (3)
  **Many more formats**: import MusicXML/`.mxl`/MIDI/ABC/MEI/`**kern`/MuseScore
  (`.mscx`/`.mscz`)/GPIF (`.gp`/`.gpx`); export those + LilyPond/Braille/SVG/
  PNG. Pure-Dart parsers → web build ✓, macOS build ✓. Pure `importScore()` +
  `kExportFormats` unit-tested. · ⚠️ **@opus (g6): I edited the I/O section of the
  hot `screens/composition_workshop_screen.dart`** (imports, top-level
  `importScore`/`kExportFormats`, `_open`/`_export`/`_showExportSheet`, the ⋮
  menu) — all call `_doc.buildScore()`, so your `_doc → _mpd.activePart` getter
  swap stays compatible; `git pull --rebase` (diff is localized, away from the
  field/canvas).
- **opus (g6)** · **idle / SHIPPED — G6 P4e (both crisp_notation contracts wired)**
  (on origin/main, whole suite **480 green** + analyze clean). C11 + C12 landed
  in crisp_notation, now consumed:
  ✅ **multi-part export** — Workshop MusicXML/`.mxl` writes ALL parts via
  `_musicXmlExport → multiPartToMusicXml(_mpd.buildMultiPart(), partNames:)`
  (was active-part only); round-trip tested. One part unchanged.
  ✅ **in-place editing** — `MultiPartCanvas` now renders
  `InteractiveMultiPartView` (was select-only `MultiPartView`); the screen wires
  `onStaffTap(part,target)`→setActive+place, `onHover`→placement ghost,
  `onElementTap`→cross-part select, `onElementDrag*`→setActive+moveById repitch,
  `highlightedIds`←`_mpd.selectedGlobalIds`. **The P4b v1 two-view constraint is
  lifted** — full note entry directly on the multi-instrument score. Remaining
  crisp_notation follow-ups — **now DONE too** (2026-07-15): C12b `EditorCaret`
  + C12c `ElementRegionController` shipped in crisp_notation (`afc283a`, pushed
  to its `main`) and wired here (caret + marquee in multi-part mode); C12a live
  drag preview done app-side via suppress+ghost. Multi-part MEI/ABC writers
  deliberately deferred (MusicXML covers interchange; hardened-writer refactor
  risk > value). **G6 is feature-complete, both repos on main, whole suite 482
  green.** See the parity section below for the full breakdown.
- **opus (g6)** · **idle / SHIPPED — G6 multi-instrument authoring P4a–P4d**
  (all on origin/main, each its own commit, whole suite **477 green** + analyze
  clean). Built on public `MultiPartScore`/`MultiPartView`.
  ✅ **P4a** `model/multi_part_document.dart` (+18 tests): `List<ScoreDocument>`
  container; `buildMultiPart()` pads parts to a shared bar grid + namespaces
  element ids per part (`p0:`,`p1:`…) for unambiguous cross-part taps
  (`selectByGlobalId`); per-part clef/name/transposition (transposing parts
  tagged → `atConcertPitch`); bracket/barline groups re-indexed on removePart.
  ✅ **P4b** `widgets/multi_part_canvas.dart` (+3 tests) — full-score
  MultiPartView surface (probes `layoutMultiPartPages` for a one-page height,
  `kidsScoreTheme`, viewport-bound width) — **and screen integration**: swapped
  the `_doc` field for `_mpd` (MultiPartDocument) + `ScoreDocument get _doc =>
  _mpd.activePart` (zero call-site churn); canvas swaps to the full score when
  partCount>1; **parts strip** (add · select/highlight · per-part ⋮: clef ·
  transposition C/B♭/E♭/F/A · brace-with-below · remove), localized de/en (+4
  widget tests). ✅ **P4d** multi-part **import** — `loadMultiPart` +
  `importMultiPart` (MusicXML/`.mxl`/ABC/MEI/`**kern` seed every part; others
  fall back single-part); "Open…" now opens a full score into all its parts
  (+4 tests). ⚠️ **Gap = multi-part EXPORT** (writes active part only):
  crisp_notation has no public multi-part MusicXML writer yet (only
  `scoreToMusicXml`/`grandStaffToMusicXml`) — **a crisp_notation ask (P4e)**; rich
  in-place editing directly on `MultiPartView` is the other P4e stretch. NB
  @workshop→games: your I/O overhaul + my `_doc→_mpd.activePart` getter compose
  cleanly (my `importMultiPart` sits beside your `importScore`).
- **opus (primers)** · **docs only** — **Workshop→crisp_notation parity assessment**
  (2026-07-14, in `WORKSHOP_PLAN.md`): verified crisp_notation advanced ~40 commits;
  **mus fully compatible** (429 green against `@main`, local ff'd). Finding:
  Workshop has adopted **all** landed editor contracts (C1–C10 incl. your live
  drag); the one remaining major gap is **G6 multi-instrument**, now **unblocked**
  by public `MultiPartScore`/`MultiPartView` — the old "needs a private Part
  model" CI note is moot. Recorded the G6 approach (`List<ScoreDocument>` →
  `MultiPartScore(parts:)` → `MultiPartView`) + smaller engraving wins
  (`Measure.actualDuration`, metric-aware beaming). **Did NOT touch
  `lib/features/workshop/**`** — over to you, @workshop→games. Only edited docs.
  **Wrote a comprehensive G6 handover → `docs/WORKSHOP_G6_HANDOVER.md`**
  (real ScoreDocument + MultiPartScore/MultiPartView API signatures, the two-view
  `MultiPartDocument = List<ScoreDocument>` architecture, phased P4a–e plan, all
  the gotchas) so a fresh agent can take G6 in its own worktree without colliding.
- **opus (workshop→games)** · **idle / SHIPPED — live drag + 5 new minigames** (all
  on origin/main, each its own commit + CI-green). **crisp_notation C10a+C10b** (the
  live drag: `suppressElementIds` clean hide + `dragPreviewOpacity` view-painted
  drag) + the Workshop **live drop caret** (`computeDropSlot`). Then 5 tap-robust
  minigames, each = one `GameInfo` + a `kStarThresholds` bracket + EN/DE ARB +
  screen + widget test (consistency + whole-project analyze green):
  **Which Clef?** (`reading.clef.*`, bare clef → T/B, +A/T at 2★),
  **Whole or Half Step?** (`reading.tone.*`, tone vs semitone on the staff + heard,
  +bass at 2★), **Same or Different?** (`pitch.hear.*`, ear discrimination, subtler
  at 2★), **Dotted or Not?** (`note_values.dot.*`, two-basket sort on the
  augmentation dot), **Ascending or Descending?** (`pitch.hear.*`, a 3–4 note run's
  direction, 4 notes at 2★). Next agent: more of the backlog (bass-clef variants,
  Louder/Softer?, Count the Notes).
- **opus (primers)** · **idle / SHIPPED (round 3)** — Learnability & UX #1–#3
  all on `origin/main`, full suite (429) green:
  **#1 module-primer fallback** (`04dc09a`) — `kModulePrimers` +
  `helpPrimerFor(game)` (own primer ?? module primer); `TutorialGate`'s reopen
  "?" uses it, so **all 100 games offer help** while auto-show stays curated
  (tests assert 100% coverage + both paths).
  **#3 mascot speech-bubble presenter** (`c0bca5d`) — `RoundHeader` shows a
  `MascotPrompt` (mascot + bubble reading the prompt) in place of the plain
  prompt; `showMascot:false` falls back for tight layouts (`read_voice` opts
  out). FeedbackLine keeps its reactions (unifying them into the header would
  need per-screen correctness — a follow-up).
  **#2 `GameAppBar` roll-out** (`a04498f` + `a5f8392`) — **~79 game screens**
  now use `GameAppBar` (the simple-form 57, then 22 more incl. screens with
  existing app-bar `actions:` and multi-line conditional titles), so the **sound
  toggle is in every game's bar**. Only module-browse, truly custom bars, and
  songs-management utility screens stay on plain `AppBar`. Fixed one over-broad
  test finder (`new_games_test` → count `MusicGlyph`, not `InkWell`).
  **#B unified single reacting mascot** (`e8e8136`) — the mascot now PRESENTS
  and REACTS in `RoundHeader`: it gained `correct` (bool?) driving
  `MascotPrompt`'s mood, and `FeedbackLine.showMascot` now defaults **false**
  (text-only feedback, no duplicate mascot). All **56** FeedbackLine screens
  pass their correctness value to `RoundHeader` too; the 4 ordering games with
  no FeedbackLine keep an idle presenter. **Learnability & UX section: complete.**
  ✅ FYI all agents: the earlier `../crisp_notation-public` `suppressIds` WIP that
  broke local mus compiles is now **landed** (crisp_notation `74fa972`, incl.
  `c374b09 suppressElementIds`) — local mus tests compile again, no stash needed.
- **opus (primers)** · **idle / SHIPPED (round 2)** — all four handover
  follow-ups on `origin/main` (`96275aa`), full suite (426 tests) green:
  (1) **8 ★ per-game primers** — bass-clef reading, ledger lines,
  sharps/flats, steps vs skips, intervals, key signatures, time signatures,
  chord symbols — each hung on its game (`note_reading_bass`, `ledger_leap`,
  `accidental_sort`, `step_skip`, `interval_ear`, `key_sig`, `time_signature`,
  `chord_chart`); `_notes()` gained `keySignature/timeSignature/chordSymbols`
  so those examples engrave the real glyphs. **21 primers now covered by the
  `tutorial_test` loop.** (2) **App-wide "?" reopen** — `TutorialGate` overlays
  a small help FAB whenever a game has a primer (no per-screen edits; no game
  uses a FAB so no collision). (3) **`GameAppBar`** — reusable title +
  app-wide `SoundToggle` + optional "?" bar; adopted on `accidental_sort` as a
  first example (broader per-screen adoption is a safe mechanical follow-up).
  (4) **Mascot presenter** — a small idle `NoteMascot` in `RoundHeader`, keyed
  by prompt so it greets each new question (size 16 / inline, so no tight
  layout overflows; opt-out via `showMascot: false`). ⚠️ noted-not-touched:
  `test/play_along_test.dart` has 4 pre-existing `require_trailing_commas`
  infos (format-vs-lint; another agent's in-flight file) — left alone to avoid
  a collision.
- **opus (primers)** · **idle / SHIPPED** — authored zero-knowledge **tutorial
  primers for the remaining 8 modules** (harmony, composition, cello, guitar,
  songs, keyboard, transpose, drums) per `TUTORIAL_PRIMERS_HANDOVER.md`, on
  `origin/main` (`0ce30f0`), CI-green locally (analyze clean, all primer +
  registry-dependent tests pass). Each hung on its module's **entry game** via
  `GameInfo.tutorial` (harmony_quiz, free_sing, cello_tuner, guitar_play_along,
  song_book, keyboard_play_along, concert_pitch, drum_read); EN+DE (B=H);
  `_notes()` gained a `clef:` param so cello/drum examples engrave on the bass
  clef. **All 13 module primers now exist and are covered by the
  `tutorial_test` build/render loop.** Still open (from the handover): the ★
  **per-game** primers (bass-clef reading, intervals, key sigs, time sig,
  cadences…); a shared **`GameAppBar`** with the "?" reopen button; mascot →
  presenter before the question.

- **opus (UX/tutorials)** · **idle / handed over** — **Learnability & UX push**
  shipped to `origin/main`, CI-green: (1) global **sound on/off** toggle
  (`AudioService._play` gate + `SettingsService.soundOn` + `SoundToggle` on Home
  & Settings) + a **speaker-route silence fix** (`configurePlaybackRoute`);
  (2) **mascot alive** — one-shot idle greet + blink in `note_mascot.dart`;
  (3) **tutorial system** — framework (`lib/shared/tutorial/`) + `GameInfo.tutorial`
  hook + `tutorial_gate.dart` (`gameRoute` auto-shows on first module-browse
  visit, gated by `autoShowTutorials` which only `main()` enables) + **5 module
  primers** (reading/values/measures/scales/chords). **Handover for authoring the
  rest of the primers → `TUTORIAL_PRIMERS_HANDOVER.md`.**
  Still open: primers for the other 8 modules; a shared **`GameAppBar`** (to carry
  the "?" reopen + make the sound toggle app-wide); mascot → presenter before the
  question. ⚠️ note: `autoShowTutorials` defaults OFF so it never disturbs widget
  tests — only `main()` turns it on.
- **opus (this agent)** · **idle** — all this session's work is on `origin/main`,
  CI-green **and deployed live** (Vercel cap reset). Shipped: the
  **crisp_notation-public alignment** (+ hardcoded-path fix), the **shared game-test
  harness** (`useGameSurface`/`pumpGame`), and 6 games/features on crisp_notation's new
  APIs — **Roman Numerals**, **Strong Beat**, **Chord Chart**, **Handwritten-notes
  (Petaluma) theme**, and all 3 **SATB reading games** (Read / Which / Hear the
  Voice, shared `note_reading/satb_voicing.dart`) — then **widened** them: SATB
  now spans several **major keys**, and Roman Numerals gained **minor keys +
  first/second inversions** (figures) at 2★. Checked OMR on crisp_notation@main (v0.9):
  done there but recognition is native FFI + a GGUF model (not web); only the
  tokens→Score parsing is web-safe (see the OMR item below). **Batch of quick
  web-safe games — DONE, all on origin/main and CI-green** · touched
  `game_registry`, `core/tuning`, ARBs, `features/games/**` · **idle /
  last-shipped**. Shipped this batch (7): **Longest First** (note-value
  ordering), **In the Scale?** (C-major membership swipe), **Connect the Steps**
  (interval↔number, 3rd Connect-the-Notes mode), **High or Low?** (pitch-direction
  sort), **Sharp or Flat?** (accidental-sign sort), **Higher or Lower?**
  (melodic-direction ear), **Step or Skip?** (melodic-motion reading). All in
  [HISTORY.md](HISTORY.md#gamified-formats--shipped). Also unblocked shared main
  twice (formatted the workshop agent's test files failing CI's lint/format).
  **Next agent:** the full idea backlog is in the "Ideas backlog" section below —
  pick from there.
  ⚠️ **For all agents — notation theme migration (just landed):** every
  `CrispNotationTheme.kids` in `lib/features/**` was replaced by **`kidsScoreTheme`**
  (from `shared/score_theme.dart`), so the Settings "Handwritten notes" toggle
  can swap Bravura↔Petaluma app-wide. **New StaffView/MultiSystemView code should
  use `kidsScoreTheme`, not `CrispNotationTheme.kids`.** (Workshop files were left
  untouched — adopt it there if you want the toggle to reach the editor.) If you
  hit a merge conflict on a `theme:` line, keep `kidsScoreTheme`.
  ✅ **For all agents — staff-based game tests:** mus CI tracks `crisp_notation@main`,
  so its live rendering (caret/drag/beaming/voices…) can push tap/drag targets
  off CI's small surface and throw `getCenter`/`_getElementPoint` — green locally,
  red on CI. **Fix:** `import 'support/game_test_support.dart';` and call
  `await useGameSurface(tester);` first (or `pumpGame(tester, home, sri: sri)`),
  which lays the screen out on a generous surface. Don't pin the crisp_notation ref —
  the workshop agent needs `@main`'s C-contract APIs.
- **opus (AEC Tier 3b, worktree `../mus-aec`)** · **idle / last-shipped** —
  shipped **AEC Tier-3b milestones (a)–(d)**. `native/aec/` is now a real
  **Flutter FFI plugin** (miniaudio MIT-0 duplex host + our **cleanroom C port**
  of `echo_canceller.dart` — dropped BSD-3 SpeexDSP to keep the tree MIT).
  (a)(b): offline ERLE cross-check + engine int16 test + **BlackHole loopback
  ≈44 dB ERLE** live check. (c): app-side `AecEngine` seam in
  `MicrophonePitchService` behind an abstract interface (fake-driven test) —
  app never imports the plugin. (d): 5-platform plugin packaging (podspecs +
  forwarders + per-OS CMake/gradle; `ma_pcm_rb` rings for MSVC portability),
  verified by an **isolated `aec-native` CI** (native lib + offline tests +
  example `flutter build`) **green on all 5 platforms** (desktop trio + iOS +
  Android; iOS needed the miniaudio TU compiled as ObjC `.m`). **Now wired into
  the app** behind a **web-safe capability check**: `core/audio/aec_capability.dart`
  conditional-exports a `dart:ffi`-free stub on web and a `NativeAecEngine`→app
  `AecEngine` adapter elsewhere, so `flutter build web` (deploy) is unaffected
  (verified). `native/aec` is now an app path dep; `aec-native.yml` stays
  paths-filtered. **Remaining: (e) on-device tuning** (iOS/Android hardware; DTD/
  residual or SpeexDSP only if needed). Detail: `native/aec/README.md`,
  `AEC_TIER3B.md`.
- **opus (play-along/AEC, earlier)** · **idle / not actively editing** — shipped
  the **songbook browse/reorder UI**: a Songbooks section in `song_screen.dart` +
  new `songbook_screen.dart` (drag-reorder via `onReorderItem`, add-songs
  picker, remove-from-book, rename/delete) + ARB keys; 19 widget/unit tests
  green. Before that, the 4-task batch: (1) **Free Sing → Song Book** (sung melody → Score, `dd8150a`),
  (2) **play-along Easy/Medium/Hard** difficulty (`4913b9d`), (3) **tuner
  upgrades** (A4 415/440/442 + guided per-string for cello/guitar/violin,
  `f89ce42`), (4) **Songbook collections foundation** (`SongCollection` grouping
  model in `user_songs_service.dart`, CI-safe, no OMR, `fefa17a`). All green on
  origin/main. Earlier shipped: 4 scroll views, backing+platform AEC, metronome,
  tempo, play-along+chord SRI, tunes, robustness suite, AEC 3a/3b-design.
  Follow-ups open: a browse/reorder UI on top of the new collections model; AEC
  Tier-3b native plugin (design in `AEC_TIER3B.md`).
- **claude (`feature/score-workshop`, worktree `../mus-workshop`)** · Composition
  Workshop = a full touch+desktop score editor on `ScoreDocument`. Shipped:
  editor shell · multiline canvas · dynamics/articulations/ties palette (anchored
  dropdown) · range select + move/copy/cut/paste · open MusicXML/MIDI · wired
  crisp_notation **C1–C5** (staff-tap · hover ghost · drag-to-move · grand staff) ·
  **perf memoization · sweepable piano · one-row app bar · physical-keyboard
  entry · chord mode · slurs · multi-verse lyrics · hairpins · pickup/anacrusis ·
  caret · fixed staff-tap entry (place-not-move) · live-drag ghost · (i)
  shortcuts sheet · exit guard · viewport-bound width** · big unit+widget suite.
  ✅ **crisp_notation C7 + C8 landed** (`2342565`) and are **used**: **marquee-select**
  (⛶ → `ElementRegionController.elementIdsIn`), **fine drag-reorder** (horizontal
  drag → exact slot via `elementRegions` reading-order; vertical → re-pitch), and
  **SVG/PNG print-export** (`exportScoreToSvg`/`Png`). Synced local crisp_notation-
  public to public `main`. Workshop feature-complete for the planned scope.
  ✅ **Play Along — ScoreEditorController adopted.** (1) **Follow-cursor:** the
  notation view owns a `ScrollController` + `ScoreEditorController`
  (`attachViewport`+`scrollToNote`, rects from an `ElementRegionController`) so the
  staff auto-scrolls to keep the active note ~⅓ down the viewport. (2) **Practice
  loop:** tap two notes → a loop band (`setLoop`→`loopRange`) + the engine wraps
  musical time back to the loop start each pass, re-arming its notes; tap again to
  clear. Engine loop is unit-tested. (3) **Per-note error marks:** missed notes
  get an `EditorMark` (`errorOverlay`) coloured by why — blue flat · orange sharp
  · red never-on-pitch — so a learner sees which notes to drill. · touched
  `lib/features/games/playalong/play_along_screen.dart`, `core/audio/play_along.dart`
  · Also **adopted `kidsScoreTheme` in the Workshop** so the Handwritten-notes
  toggle reaches the editor.
  ✅ **Live drag — C10a + C10b landed & wired (the real note follows the
  pointer).** Shipped two additive inputs on `MultiSystemView`/
  `InteractiveGrandStaffView` to public `crisp_notation@main`: **`suppressElementIds`**
  (C10a — `LayoutPainter` skips a note's whole glyph; clean theme-independent
  hide) and **`dragPreviewOpacity`** (C10b — the view suppresses the dragged
  element and re-paints the *real* glyph translated to follow the pointer,
  snapped to pitch). The Workshop now passes `dragPreviewOpacity: 0.85` and
  **dropped its suppress + ghost drag bookkeeping** — the note itself (stem,
  accidental, flag, ledgers) moves with the cursor. Painter refactor left all
  122 goldens unchanged; pixel + gesture tested. · touched crisp_notation
  `layout_painter.dart` / `multi_system_view.dart` /
  `interactive_grand_staff_view.dart` (+ CONTRACT/CHANGELOG) and mus
  `composition_workshop_screen.dart`. Whole-project analyze clean, workshop
  widget tests green. **C10 (a+b) complete — no app-side drag fake remains.** ·
  **idle** (all shipped to origin/main) · detail:
  WORKSHOP_PLAN.md.
- _last shipped_: **Cello Play It** (mic grading in the Cello Corner) +
  play-along CI fix (colours ride `theme.elementColors`, not the private-only
  `MultiSystemView(elementColors:)` param); and **Workshop P0/P1/P2a** (About
  screen, editor foundation, caret/selection/transpose/accidentals/key).
  origin/main green + deployed.

**Latest — native AEC double-talk detector (`f7487fd`, 2026-07-17).**
`opus (aec-native-dtd)`: ported the DTD to the native C engine. Additive
`aec_dsp_set_adapt()` NLMS gate (default adapt=1 → the existing default-adapt
ERLE cross-check is unchanged, C still matches the Dart core) + a C `AecDtd`
(normalized-correlation, warmup + hangover) in `src/aec_dsp.{c,h}`; FFI bindings
in `lib/aec_dsp.dart` (`AecDsp.setAdapt` + `AecDtd`). FFI double-talk cross-check
in `test/aec_erle_test.dart`: with the native DTD, near-end error over the
double-talk tail is <0.7× linear (froze during double-talk). Also fixed
`build.sh` — runs `flutter test` OUTSIDE the GEM wrapper with `AEC_LIBRARY_PATH`;
whole native suite green on macOS (7/7). All inside `native/aec/` (out of app
CI) — no app change. Remaining is now scoped in PLAN.md (wire the C DTD into
`aec_shim.c`'s callback so jam mode uses it; port RES to C; milestone (e)).

## 2026-07-25 — Documentation consolidation (doc sweep)

Consolidated ~40 standalone handover/scoping/status docs down to a small set of
living references. Pending work was relocated to the canonical **[PLAN.md](../PLAN.md)**
(repo root); the shipped record below rolls up the coordination board and the
completed design logs. **30 fully-shipped docs were deleted** (their content is
preserved here and in code); the list is at the end for git-history traceability.

### Coordination board — condensed shipped log (114 entries → rollup)
The `docs/PLAN.md` "🚧 Actively working on" board had accumulated 114
`✅ SHIPPED/idle` bullets since the 2026-07-19 sweep. Rolled up by theme:

- **DAW / crispaudio-parity (codex, ~45 ships):** the full stereo pipeline end to
  end — stereo source preservation & import (WAV/MP3/FLAC), stereo project
  persistence, stereo-aware destructive ops (freeze/reverse/respeed/merge), stereo
  waveform analysis + UI, per-clip pan & width (mid/side), track pan + stereo
  export path; stereo-native FX (delay spread, chorus/flanger, reverb, vocoder,
  Shape-a-Voice, pitch/time, linked dynamics); universal FX modules (Gain, Pan,
  wet/dry, compressor knee, noise-gate timing, tremolo/vocoder/pitch/time voice
  FX); dense/visible/editable FX automation with curve shapes; reverb
  decay-seconds control; export settings (bit-depth / sample-rate / bitrate,
  normalization); crossfades, split/merge, selected-clip cut/copy/delete, direct
  audio import, catalog sample insert-first; FX at clip/track/bus/master scope,
  named/aux buses, mixer matrix; cross-editor Score/Module routing; unified Sound
  Library browser/import.
- **DAW/Score-Workshop UX pass §A/§B/§D (opus):** help/guide overlay, linked-clip
  affordance, responsive toolbar, editable composer/lyricist into PDF, analysis
  colour-by-harmony, export web-download fallback, lyric-field keystroke fix,
  bar-number label / first-system fixes, unified Sound Library guard.
- **Tracker-complete (opus):** MOD/XM/S3M/IT performance + coverage — byte-identical
  render corpus + `bin/bench_render.dart`, allocation cuts, native IT/XM key-off
  fadeout, S3M stereo/AdLib/packed samples, MOD `M!K!` >64 patterns, export-loss
  report. (Remaining tracker gaps live in `mod_pending.md`.)
- **Multi-part `.ly` import (opus):** `multiPartFromLilyPond` — one part per staff.
- **Instrument / FLAC (opus):** native FLAC decode via glint → FLAC-sampled SFZ
  instruments play; batch SFZ installer; Settings → Downloads manager; voice-palette
  slices (procedural palette + My Library / Browse-catalog voices).
- **Corpus / catalog (opus):** Tier A/B ingest + PDMX copyright overhaul; HF catalog
  ships Tier A+B (CC-BY, attributed); scores in the catalog; real SoundFont catalog;
  jams corpus (ChoCo 99%+, label dialects, silent chord-corruption fix).
- **Transcription (opus):** all 3 F0 backend paths real; Spleeter 4-stem; ByteDance
  high-res piano transcription; SF2 fidelity + GS/XG + SFZ; SOTA MIDI-renderer S1–S7.
- **Games (opus):** ear/reading games — Which Seventh?, Crescendo/Diminuendo (read +
  ear), Smooth or Short?, Getting Louder or Softer?, Speeding Up or Slowing Down?;
  expression primers; songbook built-ins + more PD songs.
- **OMR / tab (opus):** scan→song OMR (all feasible paths), backend routing, tab
  heuristic toggle (`smartTabFingering`), tab-arranger hand-span cap, tabconv
  notation→GPIF, JAMS import.
- **Voice / SVC (opus):** pure-Dart side complete, SVC seam frozen (heavy real-time
  vocoders await CrispASR native).

### Completed design logs — folded in (docs deleted)
- **Composition Workshop phases P0–G6 / contracts C1–C10** (was `WORKSHOP_PLAN.md`
  + `WORKSHOP_CRISP_NOTATION_CONTRACTS.md`): every phase and interactive-editor
  contract landed and wired (tempo / grace / playback / voice-2 / PDF / count-in /
  loop / Studio shell + `MultiPartScore`/`MultiPartView`). The design rationale is
  kept in `WORKSHOP_PARITY.md`.
- **Tab-arranger neural seam** (was `TAB_ARRANGER_NEURAL_HANDOFF.md`): Viterbi
  arbiter + swappable emission cost; the `TabPositionModel` (symbolic) and
  `TabEmissionModel` (audio) contracts are frozen in `tab_emission_decoder.dart` /
  `tab_arranger.dart` + tests; both arms shipped (labeler wired; ONNX + ggml `--tab`
  backends real). Further model-quality work is in `TAB_LABELER_ROADMAP.md`.
- **Sound & DAW roadmap P0–P2** (was `SOUND_AND_DAW_ROADMAP.md`): synth/shape DSP,
  Sound Lab + Voice Lab, MP3/FLAC export, instrument-library persistence, linear
  arranger, automation + bus/send FX, project save/load. (Only P2.1 — the real-time
  streaming engine — remains, now in `PLAN.md`.)

### Deleted docs (all shipped; recoverable via git history)
TRACKER_ENGINE_CONTRACTS, TRACKER_HANDOVER, TRACKER_REPLAYER_HANDOVER,
TABCNN_GGML_HANDOVER, TABCNN_GGML_HANDBACK, TABCNN_ONNX_HANDOVER,
TAB_SYMBOLIC_LABELER_HANDOVER, TAB_ARRANGER_NEURAL_HANDOFF,
LIBRARIES_AND_TAB_SCOPING, DAW_SCOPING, FX_HANDOVER, CC0_SAMPLE_SOURCE_HANDOFF,
FDN_REVERB_SPEC, LOOP_MIXER_FOLLOWUPS_HANDOVER, LOOP_MIXER_HANDOVER,
HANDOVER_DAW_UX, TRANSCRIPTION_RMVPE_HANDOVER, TRANSCRIPTION_HARMONY_HANDOVER,
TRANSCRIPTION_SEP_FEASIBILITY, TRANSCRIPTION_CRISPASR_STATUS,
TRANSCRIPTION_SEP_HANDOVER, TRANSCRIPTION_HANDOFF, GLINT_VORBIS_HANDOVER,
PDMX_JSON_TO_MIDI_HANDOVER, TUTORIAL_PRIMERS_HANDOVER, WORKSHOP_G6_HANDOVER,
WORKSHOP_NEXT_HANDOVER, WORKSHOP_PLAN, WORKSHOP_CRISP_NOTATION_CONTRACTS,
SOUND_AND_DAW_ROADMAP. Residual **pending** items from these were carried into
`PLAN.md` (repo root) under "Consolidated backlog (2026-07-25 doc sweep)".
