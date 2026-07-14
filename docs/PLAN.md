# KlangUniversum — Curriculum & Game Plan

Music notation and harmony for children from primary school onwards (6+),
decomposed into exciting minigames. EN/DE, modularly extendable, running on
iOS/Android/Web/Windows/macOS/Linux. Notation rendering via the MIT
[partitura](https://github.com/CrispStrobe/partitura) library (our own).

This file tracks **what is pending and planned**. What's already built and live
is recorded in [HISTORY.md](HISTORY.md).

## 🚧 Actively working on (agent coordination — keep in sync with origin/main)

Live board so parallel agents don't collide. **Update this at every checkpoint
and push to origin/main** before/after touching shared files. Format:
`agent · task · files touched · status`.

- **opus (workshop→games)** · **idle / SHIPPED — live drag + 4 new minigames** (all
  on origin/main, each its own commit + CI-green). **partitura C10a+C10b** (the
  live drag: `suppressElementIds` clean hide + `dragPreviewOpacity` view-painted
  drag) + the Workshop **live drop caret** (`computeDropSlot`). Then 4 tap-robust
  minigames, each = one `GameInfo` + a `kStarThresholds` bracket + EN/DE ARB +
  screen + widget test (consistency + whole-project analyze green):
  **Which Clef?** (`reading.clef.*`, bare clef → T/B, +A/T at 2★),
  **Whole or Half Step?** (`reading.tone.*`, tone vs semitone on the staff + heard,
  +bass at 2★), **Same or Different?** (`pitch.hear.*`, ear discrimination, subtler
  at 2★), **Dotted or Not?** (`note_values.dot.*`, two-basket sort on the
  augmentation dot). Next agent: more of the backlog (bass-clef variants,
  Ascending/Descending?, Louder/Softer?).
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
  ✅ FYI all agents: the earlier `../partitura-public` `suppressIds` WIP that
  broke local mus compiles is now **landed** (partitura `74fa972`, incl.
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
  rest of the primers → [`TUTORIAL_PRIMERS_HANDOVER.md`](TUTORIAL_PRIMERS_HANDOVER.md).**
  Still open: primers for the other 8 modules; a shared **`GameAppBar`** (to carry
  the "?" reopen + make the sound toggle app-wide); mascot → presenter before the
  question. ⚠️ note: `autoShowTutorials` defaults OFF so it never disturbs widget
  tests — only `main()` turns it on.
- **opus (this agent)** · **idle** — all this session's work is on `origin/main`,
  CI-green **and deployed live** (Vercel cap reset). Shipped: the
  **partitura-public alignment** (+ hardcoded-path fix), the **shared game-test
  harness** (`useGameSurface`/`pumpGame`), and 6 games/features on partitura's new
  APIs — **Roman Numerals**, **Strong Beat**, **Chord Chart**, **Handwritten-notes
  (Petaluma) theme**, and all 3 **SATB reading games** (Read / Which / Hear the
  Voice, shared `note_reading/satb_voicing.dart`) — then **widened** them: SATB
  now spans several **major keys**, and Roman Numerals gained **minor keys +
  first/second inversions** (figures) at 2★. Checked OMR on partitura@main (v0.9):
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
  `PartituraTheme.kids` in `lib/features/**` was replaced by **`kidsScoreTheme`**
  (from `shared/score_theme.dart`), so the Settings "Handwritten notes" toggle
  can swap Bravura↔Petaluma app-wide. **New StaffView/MultiSystemView code should
  use `kidsScoreTheme`, not `PartituraTheme.kids`.** (Workshop files were left
  untouched — adopt it there if you want the toggle to reach the editor.) If you
  hit a merge conflict on a `theme:` line, keep `kidsScoreTheme`.
  ✅ **For all agents — staff-based game tests:** mus CI tracks `partitura@main`,
  so its live rendering (caret/drag/beaming/voices…) can push tap/drag targets
  off CI's small surface and throw `getCenter`/`_getElementPoint` — green locally,
  red on CI. **Fix:** `import 'support/game_test_support.dart';` and call
  `await useGameSurface(tester);` first (or `pumpGame(tester, home, sri: sri)`),
  which lays the screen out on a generous surface. Don't pin the partitura ref —
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
  partitura **C1–C5** (staff-tap · hover ghost · drag-to-move · grand staff) ·
  **perf memoization · sweepable piano · one-row app bar · physical-keyboard
  entry · chord mode · slurs · multi-verse lyrics · hairpins · pickup/anacrusis ·
  caret · fixed staff-tap entry (place-not-move) · live-drag ghost · (i)
  shortcuts sheet · exit guard · viewport-bound width** · big unit+widget suite.
  ✅ **partitura C7 + C8 landed** (`2342565`) and are **used**: **marquee-select**
  (⛶ → `ElementRegionController.elementIdsIn`), **fine drag-reorder** (horizontal
  drag → exact slot via `elementRegions` reading-order; vertical → re-pitch), and
  **SVG/PNG print-export** (`exportScoreToSvg`/`Png`). Synced local partitura-
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
  `InteractiveGrandStaffView` to public `partitura@main`: **`suppressElementIds`**
  (C10a — `LayoutPainter` skips a note's whole glyph; clean theme-independent
  hide) and **`dragPreviewOpacity`** (C10b — the view suppresses the dragged
  element and re-paints the *real* glyph translated to follow the pointer,
  snapped to pitch). The Workshop now passes `dragPreviewOpacity: 0.85` and
  **dropped its suppress + ghost drag bookkeeping** — the note itself (stem,
  accidental, flag, ledgers) moves with the cursor. Painter refactor left all
  122 goldens unchanged; pixel + gesture tested. · touched partitura
  `layout_painter.dart` / `multi_system_view.dart` /
  `interactive_grand_staff_view.dart` (+ CONTRACT/CHANGELOG) and mus
  `composition_workshop_screen.dart`. Whole-project analyze clean, workshop
  widget tests green. **C10 (a+b) complete — no app-side drag fake remains.** ·
  **idle** (all shipped to origin/main) · detail:
  [WORKSHOP_PLAN.md](WORKSHOP_PLAN.md).
- _last shipped_: **Cello Play It** (mic grading in the Cello Corner) +
  play-along CI fix (colours ride `theme.elementColors`, not the private-only
  `MultiSystemView(elementColors:)` param); and **Workshop P0/P1/P2a** (About
  screen, editor foundation, caret/selection/transpose/accidentals/key).
  origin/main green + deployed.

## Principles

1. **Minigames, not lessons.** Every skill is drilled through a game with
   rounds, scores and 1–3 stars — same loop as Space Math Academy and
   WortUniversum.
2. **SRI everywhere.** Every first-try answer feeds the SM-2 engine under
   `<module>.<skill>.<detail>`. The home-screen review button drills due
   items; the Karteikasten visualizes progress.
3. **Kid-first interaction.** partitura's kid theme (bold lines, ≥44 px hit
   targets), generous tap slop, no time pressure in level 1 of any game.
4. **Modular i18n.** All strings in ARB (EN/DE); a new module = registry
   entry + ARB keys + game screens. German conventions respected (B = H).
5. **Everything MIT** (font OFL). No LGPL anywhere — audio via
   `audioplayers`/`flutter_soloud` + permissively-licensed samples, never
   FluidSynth.

## Curriculum map

The module/skill structure and the games that fill it. Games already shipped are
listed for scope; `*later:*` italics mark planned extensions within a module.

| # | Module | Skills (SRI namespace) | Games |
|---|--------|------------------------|-------|
| 1 | **Notenwerte** (note values & lengths) | `note_values.symbol`, `.rhythm`, `.beats` | Symbol Quiz • Duration Duel • Rhythm Echo • Count the Beats • Sort the Beats • Connect the Symbols |
| 2 | **Noten lesen** (treble & bass clef) | `note_reading.treble`, `.bass`, `.place_*`, `.melody`, `.dictation` | Reading Quiz ×2 • Place the Note ×2 • Melody Echo • Melody Dictation • Note Match • Note Order • Line or Space? • Falling Notes • Connect the Notes • Ledger Leap |
| 3 | **Takte** (measures & meter) | `measures.fill`, `.meter` | Measure Filler • Meter Detective • Beat Runner • *later: percussion-backed meter, tempo ramps, syncopation* |
| 4 | **Tonleitern** (scales, Dur/Moll) | `scales.spot`, `.build`, `.hear` | Scale Detective • Scale Builder • Dur oder Moll? • Sound Echo • Follow the Conductor • Key Detective |
| 5 | **Akkorde & Intervalle** | `chords.triad`, `.build`, `.interval` | Chord Quiz • Triad Builder • Interval Detective |
| 6 | **Harmonik** (T/S/D) | `harmony.function`, `.cadence`, `.hear` | Function Quiz • Cadence Workshop • Hear the Function |
| 7 | **Cello-Ecke** (instrument corner) | `cello.string`, `cello.finger`, `note_reading.tenor` | Which String? • Finger Quiz (first position, 0–4) • Tenor Clef reading • *later: shifting/positions, string+finger combined ("play this note"), open-string ear tuning* |
| 8 | **Tasten-Ecke** (piano corner) | `keyboard.find`, `.name`, `.ear`, `.melody`, `.chord`, `.grand` | Find the Key • Key Quiz • Echo Keys • Play the Melody • Chord Grip • Grand Staff • Falling Keys |
| 8b | **Gitarren-Ecke** (guitar corner) | `guitar.string`, `guitar.fret` | Open Strings • Read the Tab • *later: bass tuning, fretboard-tap "find the fret", techniques (bends/slides/HO-PO), chord-grip diagrams* |
| 9 | **Liederbuch** (real songs) | `songs.tune` | Song Book (public-domain children's songs, real notation + lyrics, karaoke cursor) • Name That Tune • **Import**: MusicXML (paste or file pick), ChordPro, monophonic MIDI • *out of scope: polyphonic MIDI (transcription problem)* |
| 10 | **Komponieren** | `composition.closure`, `composition.answer` | Ending Detective • Question & Answer • My Melody (free-composition sandbox → saves to Song Book as MusicXML) • *later: melody completion with choices, cadence-based accompaniment* |

**Instrument corners** are the modular-extension pattern proven by the cello
module: a data table (string/finger map), instrument-specific games reusing the
shared machinery, and the right clefs (the library supports all four). The
**guitar corner** is the same recipe on **tablature** (partitura `TabStaffView` +
`Tuning`). A violin/viola corner is the same recipe again (violin: G/D/A/E
strings, treble clef; viola: alto clef); a bass corner reuses the guitar recipe
with `Tuning.standardBass`.

## Partitura capabilities → new ideas

The partitura library has grown well past what the app currently uses. **As of
2026-07-13 both the mus path-dep and CI resolve `partitura-public`
(`CrispStrobe/partitura@main`)** — pubspec points at `../partitura-public/...`
and the CI/deploy workflows check the public repo out to `partitura-public/`, so
local and CI are aligned and the new APIs are usable everywhere. (The older
`../partitura` = **partitura-private** clone is no longer the build target; see
the memory `partitura-public-vs-private-ci`.) Verified new capabilities and what
they unlock:

- **Teaching overlays on `StaffView`** (`showNoteNames`, `showBeatNumbers`,
  `showMeasureNumbers`). **Which Beat?** is shipped — it uses `showBeatNumbers`
  as a fading scaffold (beat numbers under the staff at level 1, gone at 2★).
  Still open: a native `showNoteNames` fading scaffold across the reading games.
- **ABC notation import/export** (`scoreToAbc`, ABC reader). **Both shipped** —
  ABC **import** in the Song Book (`scoreFromAbc`) and ABC **export** from the
  Composition Workshop (`scoreToAbc` → copy to clipboard). Still open: a
  "type-a-tune" mode.
- **Chord identification** (`identifyChord`, `chordSymbolFor`). **Name That
  Chord** and **Chord Builder** are shipped
  ([HISTORY.md](HISTORY.md#partitura-powered--shipped)) — the builder grades
  **any voicing** (root position or inversion, any octave) via `identifyChord`.
  Still open: chord symbols over the Song Book (low value — the built-in songs
  are monophonic).
- **`StaffSystemView`** (N-staff systems). **Duet** is shipped — read the
  highlighted part of a two-staff system (lower staff switches to bass clef at
  2★). Still open: SATB chorale reading, a richer Grand Staff.
- **Transposing instruments + concert-pitch toggle.** **Shipped** — a new
  **Transposing corner** with **Concert Pitch**
  ([HISTORY.md](HISTORY.md#partitura-powered--shipped)): read a written note for
  a B♭/E♭/F instrument, name the concert pitch that sounds (partitura's
  `transposeBy` does the maths). Still open: a written↔concert *toggle* on
  rendered scores.
- **Up-bow / down-bow articulations.** **Bowing** is shipped (cello corner):
  read the ⊓ down-bow / ∨ up-bow marks partitura draws.
- **Common/cut time (C, ¢) + pickup/anacrusis + measure numbering.** **Time
  Signatures** is shipped — read the signature (incl. C and ¢) for the beats per
  bar. Still open: spot the **upbeat (Auftakt)** with anacrusis measures.
- **Percussion clef** → **shipped**: a **Drums** corner with **Drum Read** — read
  a rhythm on the neutral percussion staff and tap it back on the drum pad in
  time (count-in, then Perfect/Good/Miss vs the notated onsets).
- **Figured bass** (SMuFL figbass) → Baroque continuo reading — advanced, later.

### New in partitura-public (aligned 2026-07-13) — next builds

Fresh capabilities now resolvable in mus, ranked by fit:

- [x] **Roman-numeral harmonic analysis** (`RomanNumeral` — `.symbol` → "V7",
  "ii°"). **Shipped: Roman Numerals** (Harmonik,
  [HISTORY.md](HISTORY.md#partitura-powered--shipped)) — read/hear a diatonic
  triad in a key, pick its numeral; the chord is built with `Triad` and named by
  `romanNumeralOf(pitches, key)`. SRI `harmony.roman.<symbol>`. Widens I/IV/V in
  C → all diatonic triads → **all major + minor keys** (harmonic-minor V/vii°)
  **and first/second inversions** (figures `V6`, `ii6/4`) at 2★. Still open:
  **7th chords** (`V7`, `viiø7`) — needs a partitura seventh-chord builder (the
  library has only `Triad`), a clean handoff.
- [x] **Metrical-accent hierarchy** (`beatStrength(Fraction) → double`).
  **Shipped: Strong Beat?** (Takte,
  [HISTORY.md](HISTORY.md#partitura-powered--shipped)) — a measure with beat
  numbers, one beat highlighted; strong-or-weak, graded by `beatStrength` (not
  hard-coded, so correct for 4/4, 3/4, 6/8…). Metric click accents the strong
  beats. SRI `measures.accent.<ts>_<beat>`; widens 4/4 → +3/4,2/4 → +6/8. Still
  open: a "conduct the metre" / tap-all-strong-beats variant.
- [~] **Structured chord symbols** (`chordSymbolFor`, `ChordSymbol` model).
  **Shipped: Chord Chart** (Chords,
  [HISTORY.md](HISTORY.md#partitura-powered--shipped)) — the symbol→notation
  matching game: read a chord symbol (G, Dm, D7…), tap its notation among four
  little staves. Lead-sheet literacy; the inverse of Name That Chord. SRI
  `chords.symbol.<symbol>`. Still open: chord symbols rendered over the Song Book
  chord sheets (in the play-along agent's songbook area).
- [~] **Voices per staff** (`Measure.voice2`, 2 voices rendered; 3–4 model-only).
  **Shipped all 3 scoped SATB minigames** (Noten lesen, gated behind Duet 2★,
  shared `satb_voicing.dart`, [HISTORY.md](HISTORY.md#partitura-powered--shipped)):
  **Read the Voice** (name the note a voice sings), **Which Voice?** (highlight →
  pick S/A/T/B), **Hear the Voice** (aural: chord then one voice → which?). All 2
  voices (S+A) → full SATB, and now **several major keys at 2★** (correctly
  spelled, no voice crossing — unit-tested over 400 draws). Remaining: chorale
  inversions/7ths (root position for now). (`beam subdivision` / `appoggiatura`
  grace notes are
  separate rendering-quality wins, still open.)
- [ ] **Import breadth**: MEI, Humdrum **kern/ekern**, LilyPond, GP3/4/5,
  compressed `.mxl`. All parseable in `partitura_core` today → wire into the
  Song Book import screen (web-safe, additive). Extends MusicXML/ABC/ChordPro/MIDI.
- [ ] **OMR ("photograph your sheet music")** — checked partitura@main
  (v0.9, 2026-07-13): OMR is **substantially built there**, but split by
  platform, which gates how mus can use it:
  - **Recognition (image → tokens)** = CrispEmbed **Sheet Music Transformer** in
    `partitura_cli/crispembed_omr.dart`: `dart:ffi` + `dart:io` + native
    `libcrispembed` + a **GGUF model**. **NOT web-compatible, not a mus dep,
    needs a ~100 MB+ model artifact.**
  - **Parsing (tokens → Score)** = `partitura_core/src/omr/` (bekern · semantic ·
    lilynotes → Score/GrandStaff/StaffSystem). **Pure Dart, web-safe, already a
    mus dependency** (0 ffi/io refs).
  - So a client-side photo→score in the **deployed web app is not a quick win**.
    Realistic paths: **(a)** web-safe **"import OMR tokens"** in the Song Book
    (reuse the core parsers; cheap; niche without on-device recognition);
    **(b)** a **native-only** photo flow (Android/iOS/desktop) on the AEC agent's
    pattern (native plugin + web-safe conditional-export stub) + camera + the
    GGUF model — a big swing; **(c)** server-side recognition (no infra yet).
- [x] **Alternate SMuFL fonts** (Petaluma / Leland / Leipzig descriptors).
  **Shipped: "Handwritten notes" theme** (Settings toggle,
  [HISTORY.md](HISTORY.md#partitura-powered--shipped)) — renders all notation in
  **Petaluma** (jazz/handwritten, SIL OFL 1.1, vendored in `assets/smufl/`,
  license on the About page). All ~50 StaffView sites now go through
  `shared/score_theme.dart`'s `kidsScoreTheme`, switched by the setting. Still
  open: Leland/Leipzig as further options; a live preview in Settings.

## Difficulty progression (within each game)

Games start at the easiest concrete slice and widen per level (driven by
stars + `kWinsRequiredForLevelUp`, tuning.dart):

- Reading/Placing: naturals on the staff → ledger lines (middle C!) →
  accidentals → mixed clefs.
- Measure Filler: 4/4 with h/q/e → 2/4, 3/4 → dotted notes → 6/8.
- Scale Detective: C/F/G major → all majors → natural minor → harmonic minor.
- Chord Quiz: major root position → minor (Dur/Moll!) → inversions →
  diminished/augmented.
- Function Quiz: C/F/G major → all keys → minor keys (with harmonic-minor
  dominant) → hear the function (audio).

## Delivery

- GitHub: `CrispStrobe/klang-universum` (app), `CrispStrobe/partitura` (lib).
- **CI** (`.github/workflows/ci.yml`): every push/PR runs format + analyze +
  test and uploads coverage (~85% of `lib/`). It checks out `partitura` as a
  sibling so the `../partitura` path dependency resolves on the runner.
  Analyzer is strict (`strict-casts`/`strict-raw-types`); the `build` symlink
  is untracked (it points at a dev-only SSD path and would dangle on CI).
- Web: Vercel (`mus` project), prebuilt `build/web`, same pattern as voc.
  A root `.vercelignore` drops the Flutter build's `*.symbols` debug maps
  (~8 MB, never fetched at runtime) from the upload; the served bundle is
  brotli (main.dart.js ~924 KB, canvaskit.wasm ~2.85 MB, fonts tree-shaken).
- pub.dev publication of partitura: deliberately **not yet** (maintainer
  decision); everything is consumed via path/git.

## Learnability & UX — zero-knowledge onboarding (P0/P1 shipped; content ongoing)

> **Status (shipped to origin/main, CI-green):** the **sound on/off toggle** +
> silence fix, the **mascot idle-greet**, and the **tutorial system** are live —
> now with **all 13 module primers + 8 ★ per-game primers** (21 total, covered
> by the `tutorial_test` loop), an **app-wide "?" reopen** (a help FAB overlaid
> by `TutorialGate` on any game with a primer), a reusable **`GameAppBar`**
> (title + app-wide `SoundToggle` + optional "?"; adopted on `accidental_sort`
> so far), and a **mascot presenter** in `RoundHeader` (idle greet per question).
>
> **Remaining follow-ups (this section, ranked by value ÷ effort):**
> 1. **Help on every game.** Only 21/100 games carry a primer, so the other 79
>    show no "?"/first-run help. **Fix without per-game edits or auto-show spam:**
>    give `TutorialGate` a **module-primer fallback** — a `kModulePrimers` map
>    (module → its general primer) so the "?" opens the module primer for any
>    game lacking its own, while **auto-show stays curated** (entry + ★ games
>    only, so a module's intro doesn't re-pop on every game). *(S · registry +
>    tutorial_gate.)*
> 2. **`GameAppBar` roll-out.** Adopt it across the ~84 remaining screens
>    (module-by-module) to put the sound toggle in every bar. Mechanical but
>    collision-prone (hot screen files); the reopen "?" is already app-wide via
>    the overlay, so this is now mostly about the in-bar toggle. *(L · sweep.)*
> 3. **Fuller mascot presenter.** Upgrade the idle presenter to a
>    `MascotPrompt` (mascot + speech bubble that reads the question) and default
>    `FeedbackLine.showMascot = false`. *(M · `game_widgets`/`note_mascot`.)*
> 4. **New-game hygiene (see backlog §G):** new games adopt the tutorial hook +
>    mascot API; audit the recent sort/arcade games for reduced-motion + the
>    sound toggle.

The bet: a child with **no** prior music knowledge should be able to open any
minigame, be taught the facts it needs (with heard + seen examples), and play it
through. Plus fix a sound regression and give sound a global switch. (Original
structural map, now mostly addressed: every screen built its own AppBar — a
shared `GameAppBar` now exists but isn't swept in yet; the mascot lived only in
`FeedbackLine` — now also presents in `RoundHeader`; the tutorial/help system is
built and live.)

### P0 — App-silence regression
Symptom: audio goes silent app-wide, suspected after play-along. Likely cause:
there is **no global audio-session / `AudioContext`** (`main.dart`, `AudioService`),
so the `record` mic flips the iOS/Android session to record/`playAndRecord` (routes
to the quiet earpiece) and does not restore it, muting `audioplayers` afterwards.
Fix: set a global playback `AudioContext` (speaker-routed, mixes/ducks) once at
startup; have `MicrophonePitchService.stop()` restore it; verify metronome +
backing + SFX are audible before **and after** using the mic. (No repro device
here — validate on macOS/web locally + reason from the session model; confirm on
hardware in (e)-style testing.)

### P0 — Global sound on/off toggle in the top bar
- **Behavior:** one chokepoint — gate `AudioService._play()` with `if (!soundOn) return;`
  (`core/services/audio_service.dart`). Mutes notes/chords/SFX/ticks/backing for
  all 97 games at once; the **mic is unaffected** (intonation games still work).
- **State:** add `soundOn` to `SettingsService` (SharedPreferences, mirrors the
  existing `showTimer`/`instrument` pattern), synced to `AudioService` at
  `main.dart` where `instrument` already is.
- **UI (app-wide):** there is no shared AppBar, so introduce a shared
  **`GameAppBar`** helper (a `PreferredSizeWidget`) that carries the speaker
  on/off action **and** the tutorial "?" button (below), and migrate game
  screens onto it module-by-module. Ship the toggle immediately on Home +
  Settings; the per-game top-bar icon lands as screens adopt `GameAppBar`.

### P1 — Mascot: from idle prop to guide
`NoteMascot` (`shared/widgets/note_mascot.dart`, moods idle/happy/oops) currently
sits in `FeedbackLine` (between the question and the 4 options, 53 screens) doing
nothing at rest. Move it to a **presenter** role: a `MascotPrompt` (mascot +
speech bubble that reads the question) inside `RoundHeader`, **before** the
question; default `FeedbackLine.showMascot = false` (feedback text stays). Give
the mascot a gentle **idle animation** (breathe/blink/sway) so it's alive, and
keep the happy/oops reactions. Editing the two shared widgets
(`game_widgets.dart`, `note_mascot.dart`) reaches every game uniformly.

### P1→P2 — Tutorials for every minigame (the big one)
Each game gets a short, **illustrated + playable** explanation of exactly the
musical facts it drills, so a zero-knowledge child can clear it.
- **Framework:** a `Tutorial` model = ordered steps, each with text + optional
  **notation** (`StaffView`/`kidsScoreTheme`) + optional **"listen" example**
  (`AudioService.playSequence`/`playMidiChord`/…). A `TutorialSheet` renders it.
  Shown **auto on first entry** (persist "seen" per game id) and reopenable via
  the **"?"** in `GameAppBar`. New optional hook on `GameInfo`
  (`game_registry.dart`), e.g. `Tutorial Function(AppLocalizations)? tutorial`.
- **Content:** author module-by-module (10 modules, 97 games), EN/DE in the
  ARBs, teaching the underlying knowledge — staff & clefs, note/rest values &
  beats, meter/measures, scales (Dur/Moll), intervals & chords, harmony (T/S/D),
  the cello/guitar/piano corners — each with a heard example and a shown example.
  Reuse one shared "primer" per module where games overlap, specialized per game.
- **Phasing:** (1) framework + "?" + first-run gating + `GameAppBar`; (2)
  author the note-reading + note-values primers (highest-traffic); (3) sweep the
  remaining modules. Coordinate ARB/`game_registry` edits (hot files) with the
  parallel agents.

## Competitive analysis & opportunity roadmap

Benchmarked against 30+ music-learning apps (mid-2026, four research sweeps:
gamified-instrument, theory/ear-training, kids-focused, and
sight-reading/composition + DACH). Competitor names are deliberately kept out of
this repo; the notes below describe capability *categories*, not products.

### The strategic read

- **Our real competition is not the big paid instrument-tutor apps.** Those are
  adult-first, treat notation as a display mode, and have no German-curriculum
  tie-in. In the DACH market we compete with a couple of free incumbents (a
  curriculum-aligned school platform and a public-broadcaster kids' site) plus a
  thin cluster of small theory/notation tools.
- **The children's notation-literacy niche is genuinely thin.** German teaching
  materials note that note-reading is required in every Bundesland yet there is
  little kindgerechtes Unterrichtsmaterial zum Notenlernen — that gap is the
  opening.
- **Two open moats:** explicit **Lehrplan alignment** (only the incumbent school
  platform claims it) and **genuinely bilingual EN/DE pedagogy** (rivals are
  German-only or English apps with translated strings — almost none are built
  bilingual).
- **Where we already lead** (rare among kids' apps): SM-2 spaced repetition,
  real four-clef notation, theory/harmony depth (T/S/D, cadences), a composition
  sandbox with MusicXML export, bilingual EN/DE — and now **live mic input**.
- **The structural gap that used to set the strong rivals apart — live
  real-instrument input — is now closed on the mic side** (play-along/sing-along,
  tuner, chord listener; see HISTORY). MIDI input remains open.

### Opportunity backlog (implement top-to-bottom)

Effort S/M/L; fit ♪–♪♪♪ (mission fit for a kids' notation/theory app). Source =
the app category the idea comes from. Shipped items live in
[HISTORY.md](HISTORY.md#opportunity-backlog--shipped).

**Strategic bets — extend the SM-2 / notation core**
- [ ] Parent view + multi-child profiles. *(kids' practice apps.) M · ♪♪.*

- [x] Lehrplan alignment + German framing. **Shipped**: a **Curriculum** screen —
  generic progress levels tied to **school years** (Klasse 1–2 … 9–10), each
  topic mapped to the games that drill it, with a *readiness* meter from the
  child's stars, a "continue here" marker on the recommended level, and
  per-level / weakest-topic practice runs. Readiness blends **star coverage ×
  SM-2 retention** (`SriService.masteryUnder(namespace)`), so it reflects both
  breadth and whether skills actually stuck. The engine (`Curriculum → Level →
  Topic → gameIds`) keeps per-region variants as drop-in data. *Open: optional
  per-Bundesland variants (rough matching is fine).*
- [ ] Sound-toy creative modes that feed notation (grid composer + geometric
  rhythm toy for pre-readers). *(browser music sound-toys.) M · ♪♪.*
- [ ] Color-coded kids' notation editor with MusicXML/MIDI export. *(kids'
  notation-editor apps.) M · ♪♪.* Closest to our existing sandbox.
- [ ] Teacher / LMS layer for school licensing (roster, assign-and-track, Google
  Classroom). *(classroom notation/DAW platforms.) L · ♪♪.* Schools buy per-seat.

**Big swings — category table-stakes, heavy lift**
- [x] Real-instrument input — **mic side shipped**: live pitch/chroma detection
  powers **Play-along / Sing-along** (moving-score grading), a **Tuner**, and a
  **Chord Listener** ([HISTORY.md](HISTORY.md#live-microphone--pitch-detection)).
  *Open: MIDI input; wiring mic grading into more of the corners.*
- [ ] Generative sight-reading + performance grading — endless non-repeating
  exercises scored for pitch & rhythm. *(generative sight-reading services.) L · ♪♪♪.*
  Answers the teacher-reported material shortage directly. *(Staff Runner is the
  kid-scale stepping stone; mic grading now exists to score the performance.)*

### Live-mic follow-ups (the mic pipeline is shipped — exploit it)

Now that live pitch/chroma detection, the `PlayAlongEngine`, and the moving-score
UI exist, these are high value ÷ effort because the hard infra is done:

- [x] **"Perform It" — mic-graded reading.** **Shipped**
  ([HISTORY.md](HISTORY.md#live-microphone--pitch-detection)): a note is shown;
  the child **plays or sings it** and the pitch detector verifies it
  (octave-agnostic, sustained-match), instead of tapping a letter. Feeds the
  shared `note_reading.<clef>.*` SM-2 pool. The kid-scale core of the
  generative-sight-reading big swing.
- [x] **Sing-back ear training.** **Shipped**
  ([HISTORY.md](HISTORY.md#live-microphone--pitch-detection)): a note plays; the
  child sings it back and the mic grades it (octave-agnostic). Target is *heard*,
  not shown — trains pitch memory & matching, needs no instrument. Feeds the ear
  pool `scales.hear.*`.
- [ ] **Play-along for the Song Book.** Extend play/sing-along to the real
  public-domain songs — play or sing Twinkle & co. against the moving score. *M · ♪♪.*
- [~] **Mic grading in the instrument corners.** "Play this note/string/finger"
  verified by the mic. **Cello shipped**
  ([HISTORY.md](HISTORY.md#live-microphone--pitch-detection)): a first-position
  note + string/finger hint, played on the real cello and graded by the mic
  (octave-agnostic, feeds `cello.play.*`). Guitar & piano corners still open. *M · ♪♪.*
- [ ] **Parent view + multi-child profiles.** *(kids' practice apps. M · ♪♪.)* A
  parent dashboard over the curriculum **readiness** — each child's school-year
  progress at a glance; per-child profiles. (Also listed under Strategic bets.)

Caveats: competitor prices/age-ratings drift; some DACH adoption/award figures
are self-reported — verify before external citation.

## Gamified formats (from the sibling-app survey)

New *interaction mechanics* surveyed across `../voc` and `../space_math_academy`.
Shipped formats (memory pairs, sequence, sort-into-buckets, swipe, falling-notes,
connect-a-line) live in [HISTORY.md](HISTORY.md#gamified-formats--shipped).
Sub-variant sweep **mostly done** (Jul 2026 batch): shipped **Longest First**
(note-value ordering), **In the Scale?** (swipe membership), **High or Low?** +
**Sharp or Flat?** (two-basket sorts on pitch-direction / accidental-sign),
**Higher or Lower?** (direction-by-ear), **Step or Skip?** (motion reading), and
**Connect the Steps** (interval↔number, a 3rd Connect-the-Notes mode). Details in
[HISTORY.md](HISTORY.md#gamified-formats--shipped). Still open from this survey:

- [ ] **Major/minor sort** — drag written triads into Major / Minor baskets by
  reading their quality on the staff. *Note: this reads quality visually (harder,
  ~9+); `major_minor_ear` already covers the aural version. Lower priority — a
  niche tile for the top of the age range.*
- [ ] **Falling-notes "catch the longest"** — a note-*values* mode of the arcade.
  *Caveat: `falling_notes_screen.dart` is ~930 lines of ticker/combo logic and
  its tests lean on the animation clock — a real lift, and less tap-robust than
  everything else in the batch. Budget accordingly.*
- [ ] **Melody-recall ear variant** of the sequence format — hear a 3–5 note
  tune, tap it back. *Check overlap first: `melody_echo`, `echo_sequence`, and
  `sound_echo` already exist; only build if it adds a distinct twist (e.g.
  tap-back on a staff rather than a keyboard).*

### Toy-inspired mechanics (electronic-toy lineage)

Classic hand-held electronic music/reaction toys, reimagined for notation & ear
training. Shipped: Sound Echo, Follow the Conductor
([HISTORY.md](HISTORY.md#toy-inspired-mechanics--shipped)).

- [x] **Strum toy** — swipe/strum across the screen to sound a chord or arpeggio;
  a free "air-instrument" jam built on the existing fretboard/keyboard widgets. *S–M.*
  **Shipped** ([HISTORY.md](HISTORY.md#toy-inspired-mechanics--shipped)).
- [ ] **Loop mixer** — tap/place cards that each trigger a synced musical loop
  (bass / chords / melody / drums), layering a mix in time. Creative sound-toy.
  *L — needs multi-track synced loop playback.*
- [ ] **Two-hand split** — left and right zones each run their own short
  sequence/beat to keep going at once (piano-hands coordination). *M–L, advanced.*
- [ ] **Move-to-the-beat caller** — a move/gesture is called on each beat; perform
  it in time (rhythm + reaction). *M.*

### New minigame concepts (original — not from the surveys)

Fresh ideas that fit the machinery we already have (partitura notation, pure-Dart
audio, the SM-2 engine, the falling/connect/reaction engines) and target skills
the curriculum doesn't yet drill.

**All shipped** — Ledger Leap, Key Detective, Odd One Out, Note Whack, Interval
Ladder, Staff Runner, Chord Grip Hero, Dynamics & Tempo Charades, Note Snake, and
Recital Mode all live now
([HISTORY.md](HISTORY.md#original-concepts--shipped)). New original ideas get
added here as they come up.

## Ideas backlog for the next agent (Jul 2026 handoff)

Brain-dump of every game/feature idea still on the table after the Jul-2026
web-safe batch, ranked roughly by value ÷ effort. **All are web-safe (no native
FFI) unless flagged.** Reuse the existing scaffolds — a new game is one `GameInfo`
in `game_registry.dart` + a screen + a `kStarThresholds` bracket in
`core/tuning.dart` + ARB keys (EN/DE) + a widget test. Follow the strict
`dart format` → `flutter analyze` (whole project) → `flutter test` → commit →
push → watch-CI loop, and keep the board above in sync (parallel agents!).

**Reusable scaffolds proven this batch (copy them, don't reinvent):**
- *Two-basket sort* — `pitch_sort_screen.dart` / `accidental_sort_screen.dart`
  (Draggable→DragTarget, `onWillAcceptWithDetails` gates the drop). Test drives
  real drags and tries each basket until one accepts (`pitch_sort_test.dart`).
- *Binary ear* — `direction_ear_screen.dart` (replay button + two answer
  buttons; `@visibleForTesting` tester interface exposes the correct answer so
  the test taps it).
- *Binary staff-read* — `step_skip_screen.dart` (staff card + two buttons).
- *Swipe/tap card* — `in_scale_screen.dart` (swipe + tap labels + arrow keys).
- *Connect-a-line* — add a `ConnectMode` case to `connect_line_screen.dart`.
- All staff-based tests **must** use `pumpGame`/`useGameSurface` (CI's 800×600
  surface throws `getElementPoint` otherwise — see the board's ✅ note).

### A. Tap-robust minigames that fill a real skill gap (best value)
- [x] **Whole-step or Half-step?** — **shipped** (Noten lesen): read a 2nd on the
  staff and tap tone vs semitone (half steps hide at E–F/B–C), and hear the
  interval; treble at 1★, +bass at 2★. SRI `reading.tone.<whole|half>`. See
  [HISTORY.md](HISTORY.md#partitura-powered--shipped).
- [x] **Same or Different?** (binary ear) — **shipped** (Tonleitern): two notes
  play → same pitch or different; clear leap → subtler gaps at 2★. SRI
  `pitch.hear.<same|diff>`. See [HISTORY.md](HISTORY.md#partitura-powered--shipped).
- [x] **Which Clef?** (binary) — **shipped** (Noten lesen): a bare clef on an
  empty staff; tap Treble or Bass, widening to Alto/Tenor at 2★. SRI
  `reading.clef.<name>`. See [HISTORY.md](HISTORY.md#partitura-powered--shipped).
- [x] **Dotted or Not?** (two-basket sort) — **shipped** (Notenwerte): drag note
  glyphs into Dotted/Plain baskets by reading the augmentation dot (value varies
  so shape alone doesn't give it away). SRI `note_values.dot.<dotted|plain>`. See
  [HISTORY.md](HISTORY.md#gamified-formats--shipped).
- [ ] **Ascending or Descending?** (binary ear) — play a 3–4 note run; is it going
  up or down overall? A step past Higher or Lower? (more than two notes).
- [ ] **Count the Notes** (ear) — how many notes did you just hear (2/3/4)? Builds
  aural attention; playable via `playPhrase`.

### B. Cheap depth — widen games that already exist (S effort each)
- [ ] **Bass-clef variants** of the new sorts/readers — `High or Low?`,
  `Sharp or Flat?`, `Step or Skip?`, `Connect the Steps` all hard-code
  `Clef.treble`; a `clef` constructor param + a second `GameInfo` doubles the
  content (mirror how `note_reading` / `place_note` ship treble + bass).
- [ ] **Step, Skip, or Leap?** — make Step or Skip? a 3-way (2nd / 3rd–4th / 5th+)
  at 2★ for a harder tier.
- [ ] **3-basket sorts** — the two-basket format extends to 3 (e.g. sharp / natural
  / flat once partitura can render an explicit natural glyph — verify the API).
- [ ] **More Connect modes** — note↔piano-key, rest↔note-value, Italian-term↔
  meaning, dynamic-mark↔meaning, instrument↔clef. Each is one `ConnectMode` case.

### C. Reading vocabulary the curriculum wants but we don't drill
- [ ] **Louder or Softer?** — read two dynamic marks (p / mf / f …), pick the
  louder. Binary or an ordering (Longest-First-style) drill. `charades` covers the
  *aural* side; this is the *reading* side.
- [ ] **Faster or Slower?** — read two tempo terms (Adagio / Allegro …). Same
  shape; Italian-vocabulary reading.
- [ ] **Tie or Slur?** — same-pitch tie vs different-pitch slur curve (needs
  partitura to render both; the Workshop already draws slurs/ties). Binary read.
- [ ] **Beam or Flag?** — beamed vs flagged eighths; a beaming-literacy binary.

### D. Ear-training expansion (mic infra is shipped — exploit it)
- [ ] **Sing/play the interval** — mic-graded: show/play an interval, the child
  matches it (extends the existing `perform_it` / `sing_back` mic grading).
- [ ] **Rhythm echo by tap** — hear a rhythm, tap it back in time (reuse the
  `beat_runner` timing engine). Grades against the pattern.
- [ ] **Chord-quality-by-ear widening** — major/minor exists; add
  augmented/diminished and dominant-7 at higher tiers.

### E. Creative / toy modes (higher ceiling, higher effort)
- [ ] **Loop mixer** — tap cards that trigger synced loops (bass/chords/melody/
  drums). *L — needs multi-track synced playback.* (Also in the toy list above.)
- [ ] **Grid composer for pre-readers** — a colour/emoji grid that renders to a
  real Score behind the scenes (bridge to notation for non-readers). *M.*
- [ ] **Melody doodle → hear it back** — freehand a contour, quantise to pitches,
  play it. Feeds the songbook.

### F. Infrastructure / platform (not kid-facing games)
- [ ] **Web-safe OMR-tokens import bridge** — `bekernToScore` / `bekernToGrandStaff`
  in `partitura_core/src/omr/omr.dart` are pure-Dart and exported. A "paste/typed
  bekern → playable Score" path turns text into a reading/play-along exercise and
  could power user-generated content. *The image→tokens recognition is native
  (dart:ffi + libcrispembed + a GGUF model) and NOT a web/mus dependency — do not
  pull that in.* M · genuinely new capability, but plumbing not a game.
- [ ] **`showNoteNames` scaffold** — an accessibility/beginner toggle overlaying
  letter names (or a colour key) on noteheads app-wide. Partly stubbed; finish it.
- [ ] **7th chords in Roman Numerals** — `roman_numeral_screen.dart` is ready for
  it but needs a partitura **seventh-chord builder** (V7/ii7…). *Partitura handoff
  — can't ship against an unreleased API since CI tracks public `partitura@main`.*
- [ ] **Leland / Leipzig font options** — extend the Bravura↔Petaluma switch
  (`shared/score_theme.dart`) with more SMuFL faces. *Partitura-side bundling.*
- [ ] **MIDI input** — the one real-instrument input still open (mic side shipped).
  *L, big swing.*
- [ ] **Parent view + multi-child profiles** and **Teacher / LMS layer** — see the
  Opportunity backlog above; both are product-level, per-seat monetisable.

### G. Polish / cross-cutting (small, always welcome)
- [ ] New games should adopt the just-landed **per-game tutorial** hook on
  `GameInfo` and the **mascot-as-guide** in `RoundHeader` (UX agent's work — check
  `game_widgets.dart` for the current API before wiring).
- [ ] Audit the new games for the **sound on/off toggle** + **reduced-motion**
  paths (the sorts/arcades animate).
- [ ] Consider grouping the fast-growing `note_reading` module (it's large) or
  surfacing the new binary drills as a "Warm-ups" strip for the youngest.
