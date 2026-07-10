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
| 1 | **Notenwerte** (note values & lengths) | `note_values.symbol`, `note_values.duration` | Symbol Quiz (name the glyph) • Duration Duel (which lasts longer) • *Rhythm Tap-Back (audio, later)* | 2 built |
| 2 | **Noten lesen** (treble & bass clef) | `note_reading.treble`, `.bass`, `.place_treble`, `.place_bass` | Reading Quiz per clef (name the staff note) • **Place the Note** per clef (inverse: tap the staff) | 2 built, 2 this phase |
| 3 | **Takte** (measures & meter) | `measures.fill` | **Measure Filler** (complete the measure so durations sum to the time signature) • *Meter Detective (hear the beat, audio, later)* | 1 this phase |
| 4 | **Tonleitern** (scales, Dur/Moll) | `scales.spot`, later `scales.build`, `scales.hear` | **Scale Detective** (tap the wrong note in a rendered scale) • *Scale Builder (drag notes to build one, next phase)* • *Major-or-minor by ear (audio, later)* | 1 this phase |
| 5 | **Akkorde & Intervalle** | `chords.triad`, later `chords.quality`, `chords.interval` | **Chord Quiz** (name a rendered triad) • *Triad Builder (drag, next phase)* • *Interval ear training (audio, later)* | 1 this phase |
| 6 | **Harmonik** (T/S/D) | `harmony.function`, later `harmony.cadence` | **Function Quiz** (a triad in a labeled key — Tonika, Subdominante or Dominante?) • *Cadence Builder (order T–S–D–T, next phase)* | 1 this phase |
| 7 | *Komposition (later)* | `composition.*` | Melody completion (finish the phrase), question–answer phrases, cadence-based accompaniment | design only |

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

## Module unlocking

For now all modules with games are unlocked (testing phase). Planned gating
(see `learning_module.dart` TODO): a module unlocks when the previous one
reaches ≥50% mastery in the SRI breakdown — visible on the Progress screen,
so the child always knows why something is locked and what to practice.

## Audio roadmap (the one missing subsystem)

Ear training is essential for Dur/Moll, intervals and meter. Plan: bundle a
small set of MIT/CC0 piano note samples (or synthesize with `flutter_soloud`,
zlib-licensed engine), an `AudioService` in core mirroring voc's, then:
Rhythm Tap-Back, Major-or-Minor by ear, Interval Detective, Meter Detective.

## Delivery

- GitHub: `CrispStrobe/klang-universum` (app), `CrispStrobe/partitura` (lib).
- Web: Vercel (`mus` project), prebuilt `build/web`, same pattern as voc.
- pub.dev publication of partitura: deliberately **not yet** (maintainer
  decision); everything is consumed via path/git.
