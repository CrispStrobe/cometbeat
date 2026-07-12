# KlangUniversum — Shipped history

The record of what's been built and lives in production
([mus-theta.vercel.app](https://mus-theta.vercel.app)). Forward-looking work —
what's pending and planned — lives in [PLAN.md](PLAN.md); this file is the
changelog it graduated from.

## Progression

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

## Composition Workshop

A section *outside* the minigames (home-bar piano button) — a small real score
editor. Pick a time signature (2/4 · 3/4 · 4/4, bar-lines drawn automatically),
pick a note value (whole/half/quarter/eighth), tap the staff to write, tap a
note to select it and re-pitch or delete it, hear it back with real durations,
and save to the Song Book as MusicXML. The Capella-like grown-up sibling of the
My Melody sandbox.

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
notes.

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
- **Falling Notes** (arcade) — notes rain down real partitura staves; name the
  glowing one on a 7-letter pad before it crosses the neon hit-line. Combo
  ×1–×5, speed ramps every four catches, three hearts, fixed 15-note run,
  star-driven range, colour-scaffold, reduced-motion aware. Feeds
  `note_reading.treble.*`. The **"play it" variant** ships too: **Falling Keys**
  drops the same notes onto a piano keyboard (SRI `keyboard.find.*`).
- **Connect the Notes** (connect-a-line matching) — notes on staves left, names
  shuffled right; drag a wire from each note to its name (`CustomPaint`).
  Correct link locks + plays; clears to advance. SRI `note_reading.treble.*`.
  The **symbol↔meaning** column ships as **Connect the Symbols** (Notenwerte,
  `note_values.symbol.*`) — same engine, a `mode` flag.

## Toy-inspired mechanics — shipped

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

- **Ledger Leap** (note reading) — a note sits exactly on the Nth ledger line
  (never a space, so the count is unambiguous); tap 1 / 2 / 3. Star-gated
  (treble/middle-C region first; +bass, above, 3 lines at 2★). A correct count
  plays the pitch. SRI `note_reading.ledger.<clef>.<below|above><n>`.
- **Key Detective** (scales) — partitura renders a key signature
  (`KeySignature(fifths)`); name the major key. Natural-letter tonics
  (C G D A E B F) so buttons never need an accidental; German B = H via the
  naming toggle. Star-gated (C/F/G/D → +A/E/B); correct answer plays the tonic
  triad. SRI `key_sig.<tonic>`.
