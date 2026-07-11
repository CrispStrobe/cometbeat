# KlangUniversum — Curriculum & Game Plan

Music notation and harmony for children from primary school onwards (6+),
decomposed into exciting minigames. EN/DE, modularly extendable, running on
iOS/Android/Web/Windows/macOS/Linux. Notation rendering via the MIT
[partitura](https://github.com/CrispStrobe/partitura) library (our own).

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

| # | Module | Skills (SRI namespace) | Games | Status |
|---|--------|------------------------|-------|--------|
| 1 | **Notenwerte** (note values & lengths) | `note_values.symbol`, `.rhythm`, `.beats` | Symbol Quiz • Duration Duel • Rhythm Echo (tap-back) • Count the Beats (dots + ties) • Sort the Beats (drag into buckets) • Connect the Symbols (drag glyph↔name) | 6 built |
| 2 | **Noten lesen** (treble & bass clef) | `note_reading.treble`, `.bass`, `.place_*`, `.melody`, `.dictation` | Reading Quiz ×2 (with fading landmark hints) • Place the Note ×2 • Melody Echo (ear↔staff) • Melody Dictation (ear→write on staff) • Note Match (memory pairs: note ↔ name) • Note Order (tap low→high) • Line or Space? (swipe) • Falling Notes (arcade: name before it lands) • Connect the Notes (drag note↔name) • Ledger Leap (count ledger lines) | 12 built |
| 3 | **Takte** (measures & meter) | `measures.fill`, `.meter` | Measure Filler • Meter Detective (accented downbeats by ear) • Beat Runner (tap-along rhythm lane) | 3 built |
| 4 | **Tonleitern** (scales, Dur/Moll) | `scales.spot`, `.build`, `.hear` | Scale Detective • Scale Builder • Dur oder Moll? (ear) • Sound Echo (memory-sequence toy) • Follow the Conductor (reaction toy) | 5 built |
| 5 | **Akkorde & Intervalle** | `chords.triad`, `.build`, `.interval` | Chord Quiz • Triad Builder • Interval Detective (ear) | 3 built |
| 6 | **Harmonik** (T/S/D) | `harmony.function`, `.cadence`, `.hear` | Function Quiz • Cadence Workshop (build T–S–D–T) • Hear the Function (I–IV–V–I context, name the target by ear) | 3 built |
| 7 | **Cello-Ecke** (instrument corner) | `cello.string`, `cello.finger`, `note_reading.tenor` | Which String? (bass-clef note → C/G/D/A) • Finger Quiz (first position, 0–4) • Tenor Clef reading • *later: shifting/positions, string+finger combined ("play this note"), open-string ear tuning* | 3 built |
| 8 | **Tasten-Ecke** (piano corner) | `keyboard.find`, `.name`, `.ear`, `.melody`, `.chord`, `.grand` | Find the Key (staff→key, labels fade at 2★, black keys at 3★) • Key Quiz (key→name) • Echo Keys (ear→key, C anchor) • Play the Melody (sight-playing) • Chord Grip • Grand Staff (read both clefs at once, 2★ widens into the middle-C ledger region — partitura `GrandStaffView`) • Falling Keys (arcade: play it before it lands) | 7 built |
| 8b | **Gitarren-Ecke** (guitar corner) | `guitar.string`, `guitar.fret` | Open Strings (read an open string on tab → name it, E A D G B E) • Read the Tab (fretted first-position note → name it) • *later: bass tuning, fretboard-tap "find the fret", techniques (bends/slides/HO-PO), chord-grip diagrams* | 2 built |
| 9 | **Liederbuch** (real songs) | `songs.tune` | Song Book — public-domain children's songs (5: Alle meine Entchen, Hänschen klein, Twinkle, Mary Had a Little Lamb, Old MacDonald) as real notation with lyrics (partitura v0.4 MultiSystemView + lyrics), synth playback with a karaoke cursor, tap any note to hear it • Name That Tune (ear) • **Import**: MusicXML (paste **or file pick**, via partitura v0.5), ChordPro chord sheets (own parser; tappable chord chips play triads), simple monophonic MIDI (own SMF parser + sixteenth quantization; persisted as MusicXML) • *out of scope: polyphonic MIDI (transcription problem)* | 2 built + import |
| 10 | **Komponieren** | `composition.closure`, `composition.answer` | Ending Detective (does it sound finished?) • Question & Answer (antecedent/consequent) • My Melody (free-composition sandbox, no scoring; enter notes by tapping the **staff, a piano, a guitar fretboard, or a cello fingerboard**; **saves to the Song Book as MusicXML** via partitura's writer — opens in MuseScore & co.) • *later: melody completion with choices, cadence-based accompaniment* | 3 built |

**Instrument corners** are the modular-extension pattern proven by the
cello module: a data table (string/finger map), instrument-specific games
reusing the shared machinery, and the right clefs (tenor for cello — the
library supports all four). The **guitar corner** is the same recipe on
**tablature** (partitura v0.8 `TabStaffView` + `Tuning`, once the library
shipped tab). A violin/viola corner is the same recipe again (violin: G/D/A/E
strings, treble clef; viola: alto clef); a bass corner reuses the guitar
recipe with `Tuning.standardBass`.

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

## Progression (shipped)

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

## Audio (v1 shipped)

`core/audio/synth.dart` synthesizes everything in pure Dart — no assets, no
licensing: piano-ish additive tones (pitches, chords, arpeggios, sequences)
rendered to WAV and played via `audioplayers` (data-URI source on web), plus
CrispFXR-style retro square-wave SFX (correct blip, wrong buzz, fanfare —
same procedural approach as the maintainer's
[CrispFXR](https://github.com/CrispStrobe/CrispFXR-web) /
[crispaudio](https://github.com/CrispStrobe/crispaudio) projects, in Dart).
`AudioService` wires it app-wide; feedback sounds run centrally through
`QuizRoundMixin`. Shipped ear game: Major-or-Minor. Next: Rhythm Tap-Back,
Interval Detective, Meter Detective; option to graduate to `flutter_soloud`
(zlib) if latency demands it.

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
  sandbox with MusicXML export, and bilingual EN/DE.
- **The one structural gap every strong rival has and we don't:** live
  real-instrument input (mic pitch-detection / MIDI).

### Opportunity backlog (implement top-to-bottom)

Effort S/M/L; fit ♪–♪♪♪ (mission fit for a kids' notation/theory app). Source =
the app category the idea comes from. Tick as shipped.

**Quick wins — low effort, ship first**
- [x] Note-naming toggle: German H/B, English, solfège — one setting, every
  drill. *(web theory trainers.) S · ♪♪♪.* Reinforces EN/DE. **Shipped.**
- [x] Daily streak + practice calendar (flame + count + 7-day dots on home;
  finishing a game marks the day). *(habit-loop learning apps.) S · ♪♪.* **Shipped.**
- [x] "Wait mode" pacing — advance only on the correct answer, no timed fail for
  slow readers. *(interactive sheet-music apps.) S · ♪♪♪.* **Already the design**
  (`QuizRoundMixin` retries until correct, no timers/lives anywhere); now
  guarded by a contract test.
- [x] Reacting mascot — a pure-Dart quarter-note character in the shared
  feedback line: hops + grins on correct, damped wobble + "oops" mouth on wrong;
  reduced-motion aware. *(note-eating mascot games.) M · ♪♪.* **Shipped.**
- [x] Opt-in timer + beat-your-time — off by default; when on, the result
  screen shows your completion time + personal best + "new best!" (no live
  clock, to keep the no-pressure default). *(flashcard reading apps.) S · ♪♪.*
  **Shipped.**
- [x] Foreground the bilingual EN/DE pedagogy (positioning, not translated
  strings). *(white space — nobody owns it.) S · ♪♪♪.* **Done by proxy** — the
  note-naming toggle advances this in-app; the rest is marketing, not code.

**Strategic bets — extend the SM-2 / notation core**
- [x] Weak-spot ear engine + "your tricky notes" stats — auto-detect and re-drill
  missed intervals/chords. *(leading ear-training apps.) M · ♪♪♪.* **Shipped**:
  `SriService.weakestItems` + a "tricky notes" card on the Progress screen with
  readable labels; SM-2 already re-drills these in review.
- [x] Functional cadence → scale-degree ear mode (hear I–IV–V–I, name the degree).
  *(functional ear-training apps.) M · ♪♪♪.* Grows "Dur oder Moll?". **Shipped**:
  "Hear the Function" in the harmony module — a I–IV–V–I cadence establishes the
  key by ear, then a target chord is named T/S/D. SRI `harmony.hear.*` (distinct
  from the notation `harmony.function.*`), review-routed on the home screen, and
  labeled in the "tricky notes" list.
- [x] Landmark / intervallic reading hints (fading). *(flashcard reading apps.) M · ♪♪♪.*
  **Shipped**: the Reading Quiz (all clefs) shows a landmark chip — "a skip up
  from E", "one step up from C" — anchoring on the memorized staff lines + middle
  C via diatonic arithmetic. It **fades with mastery**: always for beginners,
  only after a wrong attempt at 2★, gone at 3★ and in review tests. Pure hint
  engine in `reading_hint.dart`, unit-tested across clefs.
- [x] Written rhythm & melodic dictation — tap the rhythm / place noteheads,
  reusing the MusicXML sandbox. *(theory/ear-training apps.) M · ♪♪.* **Shipped**:
  **Melody Dictation** (note_reading) — a melody plays (audio only, nothing
  shown) and the child *writes* it by tapping noteheads onto partitura's
  InteractiveStaff (the composing-sandbox input), with per-note pitch feedback,
  undo, and a note-for-note check; SRI `note_reading.dictation.len3`. The
  production sibling of the multiple-choice Melody Echo. (Rhythm dictation is
  already served by Rhythm Echo's hear-then-tap-back loop.)
- [x] Removable color scaffold for pre-readers (color + solfège + number +
  hand-sign, peeled away as they learn the staff). *(color-coded early-years methods.) M · ♪♪.*
  **Shipped**: a Settings toggle "Colour helper for beginners" (off by default,
  parent-removable) tints noteheads and answer choices by pitch class
  (Boomwhacker-style, shared `note_colors.dart`) in the Reading Quiz and Place
  the Note, with a colour legend in Settings. Composes with the existing
  note-naming toggle for the solfège layer. *(Number + Curwen hand-sign layers
  remain as future extensions of the same scaffold.)*
- [x] Play-in-time-to-music lane (tap-along rhythm / falling-note). *(tap-along rhythm games.) M · ♪♪.*
  **Shipped**: **Beat Runner** (Takte) — markers fall and cross a glowing
  hit-line exactly on each beat of a steady bass groove; tap in time. The
  game's own Ticker is the master clock, so groove/markers/tap-timing never
  drift apart (no audio-latency sync problem). Taps score Perfect/Good by
  accuracy, with a rising-pentatonic sparkle on a hit; a no-fail toy (every run
  finishes), scored like Sound Echo. *(Extends to tempo ramps and off-beat
  syncopation patterns.)*
- [ ] Parent view + multi-child profiles. *(kids' practice apps.) M · ♪♪.*

**German-market moat — the thin-market opening**
- [ ] Lehrplan alignment + German framing (map minigames to Bundesland curricula;
  German terminology). *(the curriculum-aligned incumbent.) M · ♪♪♪.* Strongest available moat.
- [ ] Sound-toy creative modes that feed notation (grid composer + geometric
  rhythm toy for pre-readers). *(browser music sound-toys.) M · ♪♪.*
- [ ] Color-coded kids' notation editor with MusicXML/MIDI export. *(kids'
  notation-editor apps.) M · ♪♪.* Closest to our existing sandbox.
- [ ] Teacher / LMS layer for school licensing (roster, assign-and-track, Google
  Classroom). *(classroom notation/DAW platforms.) L · ♪♪.* Schools buy per-seat.

**Big swings — category table-stakes, heavy lift**
- [ ] Real-instrument input (mic / MIDI) — grade what the child actually plays;
  scope as opt-in cello & piano corners. *(instrument-tutor + flashcard apps.) L · ♪♪.*
- [ ] Generative sight-reading + performance grading — endless non-repeating
  exercises scored for pitch & rhythm. *(generative sight-reading services.) L · ♪♪♪.*
  Answers the teacher-reported material shortage directly.

Caveats: competitor prices/age-ratings drift; some DACH adoption/award figures
are self-reported — verify before external citation.

## Gamified formats (from the sibling-app survey)

New *interaction mechanics* (beyond our existing multiple-choice / tap-onto-staff
/ ear→pick / rhythm-tap-back / builder / sandbox), surveyed across `../voc` and
`../space_math_academy`. A small shared **note/rhythm card widget** unblocks most
of them. Ordered by value ÷ effort.

- [x] **Memory / concentration pairs.** *(voc `word_memory_game`; SMA has none.)*
  **Shipped**: **Note Match** — flip a grid of cards to pair a note-on-staff with
  its letter; each flip plays the pitch; fewer moves → more stars. SRI records a
  correct read on each match. *S–M.*
- [x] **Sequence / ordering.** *(voc / SMA `Launch Sequence`.)* **Shipped**: **Note
  Order** — tap four shuffled note cards from lowest pitch to highest; each
  correct tap plays the note and locks with a number badge, a wrong tap buzzes.
  SRI `note_reading.order.len4`. *(Still open: note-values longest→shortest, and
  a melody-recall ear variant.)*
- [x] **Sort into buckets** (Draggable→DragTarget). **Shipped**: **Sort the
  Beats** — drag note-value symbols into their 1 / 2 / 4-beat bucket; a card
  only drops into the right one, a wrong drop bounces back and buzzes. SRI
  `note_values.symbol.*`. *(Extends to major/minor, high/low, sharp/flat sorts.)*
- [x] **Swipe left/right** (binary drill). **Shipped**: **Line or Space?** — a
  note on a swipe card; swipe left = line, right = space; a wrong swipe bounces
  back to retry. SRI `note_reading.line_space.*`. *(Extends to in-the-scale? and
  major-or-minor-by-ear swipes.)*
- [x] **Falling notes** (arcade): notes fall to a staff/keyboard, name or play
  them before they land; combo + speed-up. Highest kid-appeal. *M–L.*
  **Shipped**: **Falling Notes** — the app's first arcade format. Notes rain
  down a starlit lane on real partitura staves; the child names the most urgent
  (glowing) one on a 7-letter pad before it crosses the neon hit-line. Catches
  throw pitch-coloured sparks and grow a ×1–×5 combo multiplier; the fall speed
  ramps every four catches ("Speed up!"). Three hearts, a fixed 15-note run so
  it keeps the rounds/score/1–3★ loop, star-driven range (naturals → middle-C
  ledger at 2★+), colour-scaffold pad, reduced-motion aware. Feeds the shared
  `note_reading.treble.*` SM-2 engine on every catch/miss. The **"play it"
  variant** ships too: **Falling Keys** (keyboard corner) drops the same notes
  onto a **piano keyboard** — tap the matching key before it lands (SRI
  `keyboard.find.*`), one engine, two input modes. *(Still open: a note-values
  "catch the longest" mode.)*
- [x] **Connect-a-line matching** (two columns + CustomPaint): note↔name,
  symbol↔meaning, interval↔number. *M — needs a line-drawing overlay.*
  **Shipped**: **Connect the Notes** — notes on staves down the left, their
  names (shuffled) down the right; drag a line from each note to its name. A
  correct link locks in colour and plays the pitch, a wrong drop buzzes and
  snaps back; clear all four to advance. A `CustomPaint` draws the wires +
  ports; distinct step letters keep every name unambiguous. Star-driven range,
  colour-scaffold aware, SRI `note_reading.treble.*`. The **symbol↔meaning**
  column ships too: **Connect the Symbols** (Notenwerte) matches note-value
  glyphs to their names (SRI `note_values.symbol.*`) — same engine, a `mode`
  flag. *(Still open: an interval↔number column.)*

### Toy-inspired mechanics (electronic-toy lineage)

Classic hand-held electronic music/reaction toys, reimagined for notation & ear
training. *(Generic names only — no product names in code or docs.)*

- [x] **Sound Echo** — memory-sequence toy: four coloured pads each play a
  pentatonic pitch; the app lights & plays a growing sequence, the child echoes
  it; one miss ends the run, score = longest sequence. **Shipped** in the scales
  module. *(Extends to swipe-direction pads and a rhythm-timed variant.)*
- [x] **Command caller** — rapid voice/text commands ("tap!", "hold!", "swipe
  up!", "clap the beat!"); do the matching gesture before the timer. Reaction +
  gesture vocabulary. *M.* **Shipped**: **Follow the Conductor** (scales) — the
  conductor calls a gesture (tap / hold / swipe in four directions); perform it
  before the countdown bar empties. Each correct cue sounds the next note of a
  rising pentatonic melody (so a good run plays a tune); a wrong move or a
  timeout costs one of three hearts. Combo multiplier + level-based shrinking
  window. A pure reaction toy — no SRI, scored like Sound Echo. *(Extends to a
  "clap the beat" tempo mode.)*
- [ ] **Strum toy** — swipe/strum across the screen to sound a chord or arpeggio;
  a free "air-instrument" jam built on the existing fretboard/keyboard widgets. *S–M.*
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
the curriculum doesn't yet drill. Ordered by value ÷ effort; effort S/M/L, fit ♪–♪♪♪.

- [x] **Ledger Leap** — the ledger-line drill kids trip on: a note sits above/below
  the staff; tap how many ledger lines (or its letter). Isolates the middle-C /
  high-A neighbourhood that reading games only brush. SRI `note_reading.*`. *S · ♪♪♪.*
  **Shipped** (note reading): a note sits exactly on the Nth ledger line (never a
  ledger space, so the count is unambiguous); tap 1 / 2 / 3. Star-gated —
  beginners get treble below the staff (the middle-C region), 1–2 lines; two
  stars adds bass, above, and 3 lines. A correct count plays the pitch. SRI
  `note_reading.ledger.<clef>.<below|above><n>`. *(Extends to naming the ledger
  note as a second step.)*
- [ ] **Key Signature Detective** — how many sharps/flats, and which key? Read a key
  signature and name it, with a fading circle-of-fifths hint. New skill
  `key_sig.read` — nothing covers signatures yet. *S · ♪♪♪.*
- [ ] **Note Whack** — whack-a-mole: noteheads pop up around the staff, a target
  name is called, tap the matching one before it ducks. Reading under gentle
  reaction pressure; reuses the reading pools. SRI `note_reading.*`. *S–M · ♪♪♪.*
- [ ] **Odd One Out** — three notes/chords (heard or shown); one is different (out of
  key, wrong quality, higher). Tap it. A discrimination drill that plugs into every
  module (reading, chords, scales). *S · ♪♪.*
- [ ] **Interval Ladder** — climb a ladder: from the current note, pick the note a
  called interval above/below (on the staff or by ear). Interval *construction*, not
  just recognition. SRI `chords.interval.build`. *S–M · ♪♪.*
- [ ] **Staff Runner** — endless generative sight-reading at kid scale: the staff
  scrolls and each note must be named/played as it hits the read-line; speeds up,
  ends after a few misses. A stepping-stone to the "generative sight-reading" big
  swing. SRI `note_reading.*`. *M · ♪♪♪.*
- [ ] **Chord Grip Hero** — Falling Keys for chords: a chord shape falls onto the
  piano; press all its keys together before it lands. Extends the falling engine to
  `keyboard.chord`. *M · ♪♪.*
- [ ] **Dynamics & Tempo Charades** — hear a phrase, pick its marking: loud/soft
  (p–f) or fast/slow (Adagio–Presto). Introduces expressive vocabulary the app
  doesn't touch. SRI `expression.hear`. *S · ♪♪.*
- [ ] **Note Snake** — a snake on a staff grid eats the note matching a called
  letter; a wrong note ends the run. Reading + a classic arcade loop. *M · ♪♪.*
- [ ] **Recital Mode** — a progression meta, not a new mechanic: string 3–5 *due*
  minigames into a themed "recital" with one combined score and a curtain-call star
  tally. Wraps the SM-2 review in a set-piece that boosts retention. *M · ♪♪♪.*
