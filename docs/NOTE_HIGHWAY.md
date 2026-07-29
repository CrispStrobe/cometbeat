# Note Highway — falling-note play-along, one engine, many instruments

**Status:** first cut SHIPPED 2026-07-28, Song Book entry 2026-07-29
(`feature/note-highway`) — see §7 for exactly what is in and what is not.
Owner: idle.
**Short version:** we already ship a falling-note view; it is a private
`CustomPainter` inside one screen, monophonic, and pitch-axis only. This scopes
extracting it into a reusable **Note Highway** layer, then adding the two views
that matter most — *notes falling onto a real piano keyboard* and *notes running
down string lanes onto a fretboard* — plus an arcade (perspective) skin, and
wiring them to every score source we already have.

---

## 1. What the concept is

A **note highway**: the notes of a piece are drawn as blocks positioned on a
spatial axis that maps to the instrument, scrolling with the music toward a
fixed **hit line**. When a block reaches the line, that note sounds now. A
rendering of the instrument sits at the hit line (a keyboard, a fretboard, a set
of pads) so a block visibly lands *on the key/string/pad you must play*. Colour
separates voices (e.g. left/right hand); grid lines mark octaves and beats; keys
light up as their block arrives.

It is one visualisation with several jobs:

* **Read-free notation.** A beginner can play a piece before they can read a
  staff — the position of the block *is* the instruction.
* **A clock.** Distance to the hit line is time; the player sees what is coming.
* **A grader.** Hit / early / late / missed per note is a scoring signal.
* **A bridge.** It is the same data as our engraved staff, so a learner can flip
  between "the game view" and "the real notation" of the same bar — which is the
  pedagogical point of having both.

This is deliberately *not* a new music model. It is a **view + input mapping**
over data we already have.

## 2. What we already have (and why this is mostly plumbing)

| Piece | Where | Use here |
|---|---|---|
| Scrolling-score + falling-notes painters | `features/games/playalong/play_along_screen.dart` (`_HighwayPainter`, `_FallingPainter`) | the seed — extract, don't rewrite |
| Grading engine (target chart vs live pitch, cents window, coverage, hit/miss) | `core/audio/play_along.dart` (`PlayAlongEngine`) | scoring; needs a polyphonic sibling |
| Score → target chart | `features/games/songs/song_play_along.dart` (`chartFromScore`) | today: top note only → needs a polyphonic + hand-tagged variant |
| Playback timeline (repeats/navigation expanded) | `crisp_notation` `playbackTimeline` | the authoritative note timing |
| Tappable piano | `shared/widgets/piano_keyboard.dart`, `shared/widgets/scrollable_piano.dart` | the bottom rail + touch input |
| Tappable fretboard | `shared/widgets/guitar_fretboard.dart` | the bottom rail for fretted lanes |
| String/fret solver | `features/games/composition/tab_arranger.dart` (`arrangeTab`) | which string a note lives on = which lane |
| Left-hand digits | `core/notation/guitar_score_fingering.dart`, `core/notation/bowed_score_fingering.dart` | the digit printed on a block |
| Bowed position/finger solver | `core/notation/bowed_arranger.dart` | cello lanes |
| Mic pitch + chord detection | `core/audio/pitch_analysis.dart`, `chroma_analysis.dart` | monophonic grading (shipped) |
| Piano/multi-pitch transcription backends | `core/audio/transcription/piano.dart` + FFI stores | polyphonic mic grading (later tier) |
| Licensed score corpus + Song Book + import | Song Book, music-db catalog | the content, already rights-gated |
| Playback render | `core/audio/gm_song_render.dart`, `score_instrument_render.dart` | the backing track under the highway |

So the work is: **generalise the view, generalise the chart, add lane maps, add
touch input, add a second projection.** Every hard musical problem (timing,
repeats, fretting, fingering, rights) is already solved elsewhere in the tree.

## 3. Architecture — one highway, pluggable lanes

Proposed home: `lib/features/games/highway/` (pure-Dart model under
`lib/core/` where it is Flutter-free, so it stays headless-testable).

### 3.1 `HighwayChart` (pure Dart, `core/`)

Polyphonic, lane-agnostic:

```
HighwayEvent {
  double startBeat, beats;      // musical time
  int midi;                     // pitch (nullable for pure-rhythm lanes)
  int voice;                    // 0/1 = left/right hand, or part index
  String? caption;              // fret number, finger digit, lyric syllable, kit piece
  bool sustained;               // tie/pedal continuation
}
HighwayChart { bpm, timeSignature, events, sections }
```

Built from a `Score` via a polyphonic sibling of `chartFromScore` — **all**
pitches of a chord, `voice` from the staff/part index, `caption` filled by the
instrument-specific builder. `playbackTimeline` stays the timing source, so
repeats and navigation behave exactly as playback does.

### 3.2 `LaneMap` — the one interface that makes this "as many ways as possible"

A `LaneMap` answers: *where on the X axis does this event live, and how wide is
it?* Everything else in the renderer is shared.

| LaneMap | X axis | Bottom rail | Caption on block | Feeds |
|---|---|---|---|---|
| `KeyboardLaneMap` | the actual key rectangle for that MIDI (black keys narrower, offset — blocks land exactly on their key) | `ScrollablePiano`, keys light on arrival | note name (optional) | piano, keys, mallets |
| `StringLaneMap` | one lane per string, from `arrangeTab` / `bowed_arranger` | `GuitarFretboard` / string strip | **fret number** + optional finger digit | guitar, bass, uke, cello |
| `ButtonLaneMap` | N abstract lanes (3–6), pitch collapsed to lane by contour | row of pads | — | arcade/beginner mode, one-finger play |
| `DrumLaneMap` | one lane per kit piece | pad grid (reuse `drumkit_screen`) | — | drums, beatbox |
| `PitchLaneMap` | continuous pitch (today's behaviour) | pitch ruler + live mic trace | note name | voice, bowed, wind — anything glissando-capable |

Adding an instrument later = one `LaneMap`, not a new screen.

### 3.3 `HighwayProjection` — flat vs perspective

The renderer takes lane coordinates in a unit space and projects them:

* `flat` — top-down rectangle. The default; readable, matches the piano rail.
* `perspective` — the same lanes as a receding trapezoid, blocks scaled and
  motion eased toward a vanishing point, hit line near the bottom edge. This is
  the whole of the "arcade look": **same data, one matrix**. Optional
  glow/particle layer on hit, behind a `reduceMotion` setting.

Both projections must be exercised by the same golden tests.

### 3.4 Input mapping — `HighwayInput`

Four sources, all reduced to "note N was played at time T (with velocity/confidence)":

1. **Touch** on the bottom rail (keyboard/fretboard/pads) — works on every
   platform today, no permissions, and is the default.
2. **Microphone, monophonic** — shipped (`PlayAlongEngine`); right for voice,
   cello, single-line guitar.
3. **Microphone, polyphonic** — piano/multi-pitch transcription backend, gated
   on model download; a later tier, and honest about its accuracy.
4. **None (watch mode)** — no grading, just the visualisation + backing track.

Grading is a polyphonic generalisation of the existing engine: per event a hit
window (early/on/late), chord tolerance (all notes of a chord within a window),
and the existing star mapping (`scaledStarScore`) so it fits the curriculum.

### 3.5 Practice controls (the part that makes it a *learning* tool)

Tempo scaling · loop a section/bar range · **wait-for-me** (playback pauses at
the hit line until the correct note arrives) · hands/parts separate ·
count-in · transpose · note-name and finger-digit labels on/off · left-handed
mirror for fretted lanes · metronome click.

## 4. Modes to ship (the "as many ways" list)

1. **Falling Keys — watch.** Any Song Book / Workshop / imported score → blocks
   onto the piano rail, both hands coloured, keys light up. No input needed.
2. **Falling Keys — touch play.** Same view, the rail is the instrument;
   wait-for-me on by default for beginners.
3. **Falling Keys — mic play.** Polyphonic tier when the model is present,
   monophonic (melody line) otherwise.
4. **String Runway — guitar/bass/uke.** Six lanes, fret number on each block,
   finger digit optional, chord grips shown as a stacked block group; strum
   arrows for down/up. Touch rail = fretboard. Ties directly into the tab
   arranger and the Tab Workshop.
5. **String Runway — bowed.** Cello lanes with position/finger from the bowed
   arranger; bow-direction arrows; mic grading (already accurate for cello).
6. **Arcade skin.** Perspective projection + `ButtonLaneMap`, 3–5 pads, contour
   mapping — the "just play along to the feel of it" mode for the youngest
   players and for pieces too hard to really play.
7. **Drum highway.** `DrumLaneMap` over the existing kit/tracker patterns.
8. **Sing-along.** Existing octave-agnostic chart on `PitchLaneMap`, with the
   live pitch trace drawn over the lanes.
9. **Two-way with the editors.** Any score opens in the highway from the Song
   Book/Workshop; a recorded highway performance can be pushed back as a
   Workshop take (we already record and quantise elsewhere).
10. **Curriculum wiring.** Each mode is a `GameInfo` with star thresholds, so it
    lands in the existing progress/curriculum ladder rather than sitting apart.

## 5. Legal footing — how we build this cleanly

Not legal advice; this is the engineering policy we hold ourselves to. Three
separate bodies of law, three different answers.

### 5.1 Copyright — the easy one

Copyright protects **expression**, not the idea of "blocks fall toward a line".
Our rules:

* Every line of code is ours, written from this document and from our own
  shipped painters. **No decompiling, no asset extraction, no pixel-tracing,
  no copying a colour set, icon, sprite, sound, or wording from any product.**
* Reference material for design decisions is limited to things that are ours or
  are open/public-domain prior art (see §5.3). Where we look at another product
  at all, it is to *avoid* resembling it, and that fact belongs in a review
  note, not in a commit message that reads like a copy instruction.
* Screenshots of other products never enter the repo, the tests, or the docs.

### 5.2 Trademark and trade dress — the highest *practical* risk

This is where a small app actually gets a letter, and it is entirely avoidable.

* **No product, band, or franchise names anywhere** — not in code, identifiers,
  comments, docs, ARB strings, screenshots, store listing, keywords, or ASO
  metadata. No "like <product>" claims, no compatibility claims. This repo's
  standing rule (never name contenders) already covers it; it now also covers
  store metadata.
* **No trade dress.** Trade dress is the distinctive overall look a consumer
  associates with one product. So we deliberately do *not* reproduce a
  recognisable arcade-game signature look: not a fixed row of coloured circular
  gems in a well-known colour order on a receding neck, not a branded
  power-meter, not their fonts, HUD arrangement, or announcer language.
  Our arcade mode is distinct by construction: **lanes are real strings with
  real fret numbers** (educational, and visually nothing like a five-gem
  arcade neck), with our own palette from the app's theme tokens and our own
  block geometry. A simplified pad mode uses our count and our colour ramp.
* **Mechanic names are ours and descriptive**: "wait for me", "streak",
  "hands separate", "count-in". Never adopt a branded name for a mechanic — a
  coined name is a signal that someone considers it protectable.
* **Our own names get a clearance check** before shipping (EUIPO + DPMA +
  USPTO free search, plus app-store name search) — cheap, and it protects *our*
  mark too. Prefer plainly descriptive in-app names (e.g. "Falling Keys",
  "String Runway") which are hard to confuse with anyone.

### 5.3 Patents — the question that actually needs care

* **The generic mechanic rests on deep prior art.** Notes as blocks on a
  time axis over a pitch/instrument axis is the *piano roll*, in commercial use
  since the 1880s and standard in MIDI sequencer editors since the 1980s.
  Light-up teaching keyboards, scrolling-notation practice aids, and hit-window
  timing scoring all have decades of published prior art. Broad claims over
  "falling notes + hit line + timing score" are not something anyone can newly
  obtain, and the well-known foundational rhythm-game patents from the late
  1990s / around 2000 have run their 20-year term and lapsed.
* **What can still be live is narrow and later-filed**: specific systems (a
  particular instrument-controller coupling, a particular network/streaming or
  monetisation flow, a particular adaptive-difficulty or camera/gesture method)
  from 2005-onward filings, plus **design patents / registered designs on a
  specific GUI appearance** (US design patents: 15 years from grant; EU
  registered Community designs: up to 25 years). This is a second reason §5.2's
  "no trade dress" rule matters — a distinctive screen appearance can be
  *registered*, not just claimed as trade dress.
* **Our design posture, therefore:**
  1. Build only from mechanics with obvious long prior art — scroll, hit
     window, lane-per-string, key highlight, tempo scaling, loop, wait-for-me.
  2. Do not implement any *named, branded, distinctive* feature bundle from a
     specific product; if a feature is only known to us via one product and has
     a coined name, treat it as a red flag and either drop it or re-derive a
     different solution to the underlying teaching need.
  3. No proprietary hardware coupling. Touch and microphone only; any MIDI
     input goes through open standards (Web MIDI / CoreMIDI / class-compliant
     USB-MIDI), never a vendor-specific instrument protocol.
  4. Jurisdiction reality-check: in Europe, Art. 52 EPC excludes programs and
     rules for games "as such", so a pure UI-and-scoring mechanic is very hard
     to hold as a patent here; the concentration of risk is US filings. We ship
     worldwide, so we design to the stricter (US) assumption anyway.
  5. **Independent-derivation record.** This document, the commit history, and
     the fact that our falling-note view *predates* this effort as a shipped
     feature over our own engine are the evidence that we built our own thing.
     Keep it that way: scope in the doc, then implement from the doc.
  6. If CometBeat ever takes real commercial revenue at scale, a proper
     freedom-to-operate search by a patent attorney before a marketing push is
     the correct next step. Cheap now, expensive later.

### 5.4 Music rights — the one people forget

A play-along app lives or dies on repertoire, and repertoire is the most likely
place to get into genuine trouble. Nothing changes here: the highway plays
**only** what already passes the corpus ship gate (`docs/CORPUS_LICENSING.md`) —
public-domain and properly-licensed symbolic scores from our registry, plus the
user's own imports (local to their device). No bundled arrangements of
in-copyright songs, no "popular hits" pack, no lyrics we do not have rights to.

## 6. Slices

Each slice is independently shippable and ends green (`dart format` →
`flutter analyze` → tests), per the repo's pre-commit rule.

* **S0 — extract.** `HighwayChart` + `HighwayRenderer` + `PitchLaneMap` +
  `flat` projection, lifted out of the play-along screen's private painters.
  The play-along screen becomes a caller. Behaviour identical; existing tests
  stay green; add golden/paint tests for the extracted widget.
* **S1 — Falling Keys (watch).** Polyphonic `chartFromScoreMulti` (all chord
  pitches, hand/part in `voice`), `KeyboardLaneMap`, piano rail with arrival
  lighting, octave grid + C labels, backing-track playback. Entry from the Song
  Book and the Workshop. *This is the picture that started the effort.*
* **S2 — Falling Keys (play).** Touch grading on the rail, polyphonic hit
  windows, wait-for-me, hands-separate, tempo/loop, star scoring, `GameInfo` +
  thresholds + de/en strings.
* **S3 — String Runway.** `StringLaneMap` from `arrangeTab` (+ bowed arranger),
  fret/finger captions, fretboard rail, chord-grip block groups, strum/bow
  arrows. Guitar first, cello and bass reuse it.
* **S4 — Arcade skin.** `perspective` projection, `ButtonLaneMap`, pad rail,
  hit feedback layer behind `reduceMotion`; `DrumLaneMap` on the same rails.
* **S5 — Depth.** Polyphonic mic grading (transcription tier, model-gated),
  accessibility pass (colour-blind-safe lanes, note names, high contrast,
  reduced motion), skins, performance → Workshop take, curriculum placement.

## 7. What shipped (2026-07-28)

Three tiles — **Note Highway** (keyboard), **String Runway** (guitar),
**Bow Runway** (cello) — all one screen, plus the layer underneath it.

**Core, pure Dart** (`lib/core/games/highway/`, headless-testable):

* `highway_chart.dart` — `HighwayEvent`/`HighwayChart`, polyphonic, voice-tagged.
  `highwayChartFromScore` keeps **every pitch of a chord** (the play-along
  builder keeps only the top note) and reads voices, tempo and meter off the
  score; `highwayChartFromParts` merges a grand staff into one chart with a
  colour per hand. `timedChords` renders a gap-accurate backing, optionally of
  one hand only.
* `highway_lanes.dart` — `KeyboardLaneMap` (real key rectangles, black keys
  narrower/raised/on the boundary), `StringLaneMap` (one lane per string, low
  string left so pitch still rises rightward), `PadLaneMap` (contour → N lanes),
  `PitchLaneMap` (continuous, for a live mic trace). All unit-space, so the
  falling blocks, the rail and the touch hit-test share ONE geometry.
* `highway_grading.dart` — five difficulties (windows in *beats*, so slowing a
  piece down does not secretly loosen the timing), polyphonic grading, a note
  judged once, streak multiplier, wait-for-me, and `gradedVoices` for
  hands-separate (the other hand keeps falling and plays itself).
* `highway_instrument.dart` — per-instrument profile: lane map, caption style,
  timbre, and the **preparation** step that runs `arrangeTab` (guitar/bass/uke →
  string + fret) or `arrangeBowed` (cello → string + finger) over the chart.
* `highway_library.dart` — built-in pieces per instrument, as a LADDER with a
  playable first rung (public-domain melodies + exercises written for the app).
  Level 1 is three notes in one hand at 56 bpm, or open strings with no left
  hand at all; the two-handed and chord pieces are levels 3–5. Tempos are the
  speed a piece can be LEARNT at, not the speed it is usually heard at — the
  tempo control goes up from there. Held to this by
  `test/highway_grooves_test.dart`, which checks every instrument has a level-1
  piece at ≤70 bpm and more than a handful to play.

**View** (`lib/features/games/highway/`):

* `highway_view.dart` — one painter for everything: musical grid (lane rules +
  bar/beat rules), raised-lane tints, trapezoid blocks with captions, far-end
  haze, hit line, hit ripples, and the instrument rail. `HighwayProjection`
  switches flat ↔ perspective through a perspective divide — same data, one
  matrix, so the arcade look is not a second renderer.
* `highway_theme.dart` — four skins (midnight / neon / sunrise / ink; `ink`
  separates voices by lightness for colour-blind and high-contrast use).
* `highway_strip.dart` — the optional reading strip: scrolling **tab** (string
  lines + fret digits) for fretted/bowed, **note names** for keys/pads.
* Wired into the app's learning systems like any other game: a **primer** on
  each tile (shown the first time it opens, reopenable from "?"), star scoring
  through `kStarThresholds`/`ProgressService`, a curriculum placement, and
  **spaced repetition** — every graded note's outcome goes to `SriService`, so
  what a learner keeps missing comes back in Review. Pitched notes share
  play-along's id scheme deliberately: a G3 missed here and a G3 missed there
  are the same fact about the learner.
* `note_highway_screen.dart` — setup (instrument · piece · watch/play ·
  difficulty · skin · flat/arcade · hands · tempo 50–125% · strip · backing),
  count-in, run, star-scored result via the existing progress/threshold path.

**Tests:** `highway_chart` · `highway_lanes` · `highway_grading` ·
`highway_instrument` · `note_highway_screen` — including a sweep that paints
every instrument × skin × projection, and a library check that every built-in
piece is actually reachable on every instrument it claims (it caught guitar
shapes claiming the ukulele, whose lowest string is C4).

**Deliberately NOT in this cut** — the honest list:

* **S0 half done (2026-07-29).** `play_along_screen.dart`'s vertical
  `_FallingPainter` is GONE — that view is now the shared `HighwayView` with a
  `PitchLaneMap` (no rail: the view is mic-graded, so a tappable instrument at
  the hit line would misrepresent how it is played), and the screen keeps its
  `PlayAlongEngine`, its cents-based grading and its other three views. −102
  lines of duplicate painter. ⚠ One deliberate non-inheritance: the highway
  tiers drop note names as a difficulty scaffold, but this screen has always
  drawn them and defaults to medium, so `showNoteNames` is forced on rather
  than silently removing labels from a shipped view. Still private here: the
  HORIZONTAL `_HighwayPainter` (time on X, pitch on Y) — a different geometry
  the lane maps do not model yet.
* ~~No Song Book entry yet.~~ **DONE 2026-07-29.** `SongScreen` and
  `MultiPartSongScreen` each carry a *Note Highway* action next to their
  existing ones, so the highway now plays the whole rights-cleared corpus and
  not just its nine built-in pieces. A single-part song goes through
  `highwayChartFromScore` (every pitch of every chord, both written voices); a
  multi-part one through `highwayChartFromParts`, which gives each PART its own
  colour — the case that view exists for. Both are disabled while the karaoke
  preview runs and for a song with nothing to play, matching the play-along
  launchers beside them. Still open on this axis: the Workshop has no such
  action, and an engraved-notation reading strip still needs the score threaded
  through (the strip is chart-driven today).
* ~~No microphone grading.~~ **DONE 2026-07-29 (monophonic).** The setup offers
  *Tap the keys* or *Your instrument*; choosing the microphone turns the rail
  into a picture rather than a control, because letting you tap it while
  claiming to play for real would make the score a lie. Two decisions worth
  keeping:
  - **A heard wrong note does NOT break the streak, a tapped one does.** A tap
    is a decision; a microphone is a measurement that also picks up string
    noise, the room and the player thinking out loud. `tap(breaksStreak:)`
    carries that distinction, and it is tested both ways.
  - **A held note is fed once.** The detector reports the same pitch on every
    frame it sounds, so a new note only counts when the heard pitch changes —
    otherwise one long note hammers the grader with something already answered.
  ⚠ It is honestly monophonic and says so in the UI: a chord is credited for
  whichever note is heard, and the piano's two hands cannot both be graded this
  way. Polyphonic grading needs the transcription backend and is still open.
* ~~No loop-a-section.~~ **DONE 2026-07-29.** A range slider picks the bars to
  drill; the clock returns to the start of the section and re-arms it, so every
  pass is graded like the first. `HighwayChart.section` does NOT re-zero the
  timing — a section keeps the piece's own beats, so its bar grid and any
  backing still line up with the whole. **A loop is practice and records no
  score**: eight bars twenty times is not the piece, and counting it would make
  stars measure patience.
* ⚠️ **Beat Highway v1 was not playable, and the fix is the lesson.** The
  maintainer's report: too fast at 100%, "rhythm extremely boring", "hat hits
  throughout", no keyboard. All four were the same root cause — I had reused the
  Drum Kit's four STARTER PRESETS as an exercise ladder. They are patterns for
  *building* a beat: every one runs hats on every eighth at 92 bpm, which as a
  thing to play is three hat taps a second on top of kick and snare before a
  beginner has finished a bar. Reuse is right when two surfaces want the same
  thing; these two wanted different things and I did not check.
  Fixed 2026-07-29: `highway_grooves.dart` is a real ladder — **28 grooves**,
  level 1 kick-and-snare only at 60 bpm, hats not appearing until level 3 and
  only on the quarters, eighth-hats at level 4, independence patterns (off-beat
  hats, shuffle, one-drop, bossa, ghost snares) at level 5. Tempo is per groove
  and slow at the bottom: a beat you can play at 60 teaches more than one you
  can watch at 92. Plus **number-key play** (1–5 = the lanes, digits shown on
  the pads, numpad too), because a pad game with no keyboard is unplayable on a
  desktop.
* ~~No drum-kit map.~~ **DONE 2026-07-29** — a fourth tile, *Beat Highway*
  (`beat_highway`, under the drums module). One lane per kit piece, hits with no
  pitch at all (the lane IS the instruction), real `renderDrum` one-shots under
  the pads and a `renderDrumPattern` backing. The grooves are the Drum Kit's own
  `kDrumPresets` rather than beats authored twice, so a preset added there shows
  up here too and the groove a child builds in the Drum Kit is the same music
  that falls here.
* ~~No engraved-notation strip.~~ **DONE 2026-07-29.** A song opened from the
  Song Book now carries its `Score` through, and the strip shows the REAL BAR
  being played — a `StaffView` of that one measure, its notes lit as they
  sound. One bar at a time, rebuilt only when the bar changes: a whole score in
  a 76-pixel strip is unreadable and engraving every frame would be absurd.
  During the count-in it shows the bar that is COMING, because that is exactly
  when a learner is looking at it. Without a score behind the chart (the
  built-in library, a drum groove) it falls back to the name chips rather than
  going blank. This is the pedagogical argument for the whole feature made
  concrete: the same music, as blocks and as symbols, at the same moment.
* **No chord-grip blocks or strum arrows.**
* ~~Not profiled.~~ **MEASURED 2026-07-29** (`test/highway_performance_test.dart`,
  relative assertions so it cannot flake on a loaded box). A 4,000-note piece
  (four minutes, two hands) costs the same per frame as a 128-note exercise —
  paint 5.7 vs 5.2 ms/frame headless, `advanceTo` 3.7 vs 3.4 µs/frame — because
  both now scan only what is live. Two real findings, both fixed: the grader
  scanned EVERY note on every frame and on every tap (a tap late in a long piece
  cost 493 µs → 140 µs), and `HighwayChart.totalBeats` is O(n) and was being read
  every tick by the screen. Still unmeasured: an actual low-end phone with the
  audio engine running — these numbers are a headless VM.

### A note on looking at it

Three defects in this feature were invisible to every test and obvious in a
screenshot, so: **render it and look before calling a visual slice done.**

* the instrument rail was dark-grey-on-dark for every non-keyboard instrument,
  so a player could not see which pad or string a block belonged to;
* the chord "grip" was drawn as a translucent panel BEHIND blocks that fill
  their lanes — completely invisible, so the thing it was meant to communicate
  was not communicated at all;
* falling blocks were coloured by voice while the rail was coloured by lane, so
  a guitar fell as one wall of blue over a six-colour fretboard.

The harness: a `RepaintBoundary` + `toImage()` widget test writing a PNG to the
scratchpad. ⚠ It writes the file and then hangs rather than completing, so run
it under `timeout` and take the file — the image is there. Also note the test
font renders every glyph as a filled box, so captions look like squares; that
is Ahem, not a bug in the painter.

## 8. Risks / open questions

* **Performance — measured, and the algorithmic half is closed** (see §7).
  Cost is now flat in the length of the piece for both paint and grading. What
  is still unknown is the constant on a real low-end phone with audio running;
  if it bites, the next lever is a static-layer + moving-transform split rather
  than more culling.
* **Keyboard range on a phone.** 88 keys will not fit legibly. Auto-range to the
  piece (with a stable, non-jittery window) and let the rail scroll; decide the
  auto-follow behaviour in S1, it is the main UX unknown.
* **Polyphonic mic grading honesty.** It will be imperfect; the UI must not
  punish a correct player for a transcription error. Bias the windows toward
  forgiving, and keep touch as the default graded input.
* **Chart quality on imported scores.** Hand assignment depends on the source
  having sane staves/parts; needs a fallback (split at a pitch boundary) and a
  manual override.
* **Naming.** In-app names above are placeholders pending the §5.2 clearance
  check.
