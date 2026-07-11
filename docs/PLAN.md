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
| 1 | **Notenwerte** (note values & lengths) | `note_values.symbol`, `.rhythm`, `.beats` | Symbol Quiz • Duration Duel • Rhythm Echo (tap-back) • Count the Beats (dots + ties) | 4 built |
| 2 | **Noten lesen** (treble & bass clef) | `note_reading.treble`, `.bass`, `.place_*`, `.melody` | Reading Quiz ×2 • Place the Note ×2 • Melody Echo (ear↔staff) | 5 built |
| 3 | **Takte** (measures & meter) | `measures.fill`, `.meter` | Measure Filler • Meter Detective (accented downbeats by ear) | 2 built |
| 4 | **Tonleitern** (scales, Dur/Moll) | `scales.spot`, `.build`, `.hear` | Scale Detective • Scale Builder • Dur oder Moll? (ear) | 3 built |
| 5 | **Akkorde & Intervalle** | `chords.triad`, `.build`, `.interval` | Chord Quiz • Triad Builder • Interval Detective (ear) | 3 built |
| 6 | **Harmonik** (T/S/D) | `harmony.function`, `.cadence` | Function Quiz • Cadence Workshop (build T–S–D–T) | 2 built |
| 7 | **Cello-Ecke** (instrument corner) | `cello.string`, `cello.finger`, `note_reading.tenor` | Which String? (bass-clef note → C/G/D/A) • Finger Quiz (first position, 0–4) • Tenor Clef reading • *later: shifting/positions, string+finger combined ("play this note"), open-string ear tuning* | 3 built |
| 8 | **Tasten-Ecke** (piano corner) | `keyboard.find`, `.name`, `.ear`, `.melody`, `.chord` | Find the Key (staff→key, labels fade at 2★, black keys at 3★) • Key Quiz (key→name) • Echo Keys (ear→key, C anchor) • Play the Melody (sight-playing) • Chord Grip | 5 built |
| 9 | **Liederbuch** (real songs) | `songs.tune` | Song Book — public-domain children's songs (5: Alle meine Entchen, Hänschen klein, Twinkle, Mary Had a Little Lamb, Old MacDonald) as real notation with lyrics (partitura v0.4 MultiSystemView + lyrics), synth playback with a karaoke cursor, tap any note to hear it • Name That Tune (ear) • **Import**: MusicXML (paste **or file pick**, via partitura v0.5), ChordPro chord sheets (own parser; tappable chord chips play triads), simple monophonic MIDI (own SMF parser + sixteenth quantization; persisted as MusicXML) • *out of scope: polyphonic MIDI (transcription problem), guitar tablature (excluded from the notation library)* | 2 built + import |
| 10 | **Komponieren** | `composition.closure`, `composition.answer` | Ending Detective (does it sound finished?) • Question & Answer (antecedent/consequent) • My Melody (free-composition sandbox, no scoring; **saves to the Song Book as MusicXML** via partitura's writer — opens in MuseScore & co.) • *later: melody completion with choices, cadence-based accompaniment* | 3 built |

**Instrument corners** are the modular-extension pattern proven by the
cello module: a data table (string/finger map), instrument-specific games
reusing the shared machinery, and the right clefs (tenor for cello — the
library supports all four). A violin/viola corner is the same recipe
(violin: G/D/A/E strings, treble clef; viola: alto clef).

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

Benchmarked against 30+ music-learning apps (July 2026, four parallel research
sweeps: gamified-instrument, theory/ear-training, kids-focused, and
sight-reading/composition + DACH). Full teardown artifact archived separately.

### The strategic read

- **Our real competition is not Yousician / flowkey / Simply Piano.** Those are
  adult-first, treat notation as a display mode, and have zero German-curriculum
  tie-in. In the DACH market we compete with free incumbents **ANTON** (German
  Education Award 2022, the one rival that claims Lehrplan alignment) and **WDR
  Klangkiste**, plus a thin cluster of theory tools (Theoriesteine, TunyStones,
  Classplash Cornelius, Mussila).
- **The children's notation-literacy niche is genuinely thin.** A German
  publisher notes note-reading is required in every Bundesland yet "praktisch
  kein kindgerechtes Unterrichtsmaterial zum Notenlernen gibt."
- **Two open moats:** explicit **Lehrplan alignment** (only ANTON claims it) and
  **genuinely bilingual EN/DE pedagogy** (every rival is German-only or an
  English app with translated strings — only Opera Maker is truly bilingual).
- **Where we already lead** (rare among kids' apps): SM-2 spaced repetition,
  real four-clef notation, theory/harmony depth (T/S/D, cadences), a composition
  sandbox with MusicXML export, and bilingual EN/DE.
- **The one structural gap every strong rival has and we don't:** live
  real-instrument input (mic pitch-detection / MIDI).

### Opportunity backlog (implement top-to-bottom)

Effort S/M/L; fit ♪–♪♪♪ (mission fit for a kids' notation/theory app). Tick as
shipped.

**Quick wins — low effort, ship first**
- [ ] Note-naming toggle: German H/B, English, solfège, scale-degree — one
  setting, every drill. *musictheory.net / Music Crab. S · ♪♪♪.* Reinforces EN/DE.
- [ ] Daily streak + practice calendar. *Yousician / Duolingo. S · ♪♪.* Retention loop.
- [ ] "Wait mode" pacing — advance only on the correct answer, no timed fail for
  slow readers. *Flowkey. S · ♪♪♪.*
- [ ] Reacting mascot — eats correct notes, comically pops on wrong (our biggest
  kid-engagement gap). *NoteWorks "Munchy" / Blob Chorus. M · ♪♪.*
- [ ] Hideable timer + beat-your-time replay — voluntary reps feed SM-2. *Note Rush. S · ♪♪.*
- [ ] Foreground the bilingual EN/DE pedagogy (positioning, not translated
  strings). *White space — no rival owns it. S · ♪♪♪.*

**Strategic bets — extend the SM-2 / notation core**
- [ ] Weak-spot ear engine + "your tricky notes" stats — auto-detect and re-drill
  missed intervals/chords. *EarMaster (category's best idea). M · ♪♪♪.*
- [ ] Functional cadence → scale-degree ear mode (hear I–IV–V–I, name the degree).
  *Functional Ear Trainer. M · ♪♪♪.* Grows "Dur oder Moll?".
- [ ] Landmark / intervallic reading hints (fading). *Note Rush / Music Crab. M · ♪♪♪.*
- [ ] Written rhythm & melodic dictation — tap the rhythm / place noteheads,
  reusing the MusicXML sandbox. *Teoria / EarMaster. M · ♪♪.*
- [ ] Removable color scaffold for pre-readers (color + solfège + number +
  hand-sign, peeled away as they learn the staff). *Prodigies "Chromanotes". M · ♪♪.*
- [ ] Play-in-time-to-music lane (tap-along rhythm / falling-note). *Rhythm Cat /
  Piano Maestro. M · ♪♪.*
- [ ] Parent view + multi-child profiles. *Piano Maestro / NoteWorks. M · ♪♪.*

**German-market moat — the thin-market opening**
- [ ] Lehrplan alignment + German framing (map minigames to Bundesland curricula;
  German terminology). *ANTON. M · ♪♪♪.* Strongest available moat.
- [ ] Sound-toy creative modes that feed notation (grid composer + geometric
  rhythm toy for pre-readers). *Chrome Music Lab / Groove Pizza. M · ♪♪.*
- [ ] Color-coded kids' notation editor with MusicXML/MIDI export. *Classplash
  Cornelius / TunyStones. M · ♪♪.* Closest to our existing sandbox.
- [ ] Teacher / LMS layer for school licensing (roster, assign-and-track, Google
  Classroom). *Flat.io / Soundtrap / ANTON. L · ♪♪.* Schools buy per-seat.

**Big swings — category table-stakes, heavy lift**
- [ ] Real-instrument input (mic / MIDI) — grade what the child actually plays;
  scope as opt-in cello & piano corners. *Yousician / Note Rush / TunyStones. L · ♪♪.*
- [ ] Generative sight-reading + performance grading — endless non-repeating
  exercises scored for pitch & rhythm. *Sight Reading Factory. L · ♪♪♪.* Answers
  the teacher-reported material shortage directly.

Caveats: competitor prices/age-ratings drift; some DACH adoption/award figures
are self-reported — verify before external citation.
