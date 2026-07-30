# Backing band — chord charts that play themselves (scoped 2026-07-30)

**The ask (maintainer, 2026-07-30).** Make CometBeat a serious offering in the
*chord-chart backing-band* category: you enter a song's changes, pick a feel, and
a virtual rhythm section plays them back — in any key, at any tempo, looping —
so a player can practise comping, soloing or singing over real changes.

**No product names.** Not in code, not in docs, not in comments, not in commit
messages. This file describes a **capability class** and never an app. Where a
convention is genuinely musician-standard ("a lead sheet", "a chart", "a
setlist", "two-feel", "the head") the capability is named and no origin is.

**Clean-room, always.** Every rhythmic/harmonic rule below is written from
published music theory and pedagogy — voice-leading practice, walking-bass
construction, style conventions taught in method books. No file format is
reverse-engineered, no style bank is transcribed from a product, no sample comes
from anywhere but our Tier A/B registry. See auto-memory
`cleanroom-gpl-port-process`.

---

## 0. Decisions taken (maintainer, 2026-07-30) — settled, do not re-litigate

This file raised seven decisions. All seven are answered, and the ladder in
`PLAN.md` is written against these answers. **A card that contradicts one is
stale; the decision wins.**

| # | Decision | Consequence |
|---|---|---|
| 1 | **One engine, a beginner↔expert dial.** The *model* carries the full vocabulary; the *surface* is gated. | `BB-D1` is `M`; ladder **rule 5**; new card **BB-U6**. |
| 2 | **A document in the library, NOT a sixth mode** — with a real front door and **maximum Loop Studio reuse**. | `BB-U5` rewritten; `BB-U3` writes no new mixer; new card **BB-A0**. |
| 3 | **Import first, entry second, derived third.** | `BB-D4` split — **`BB-D4a`** (paste a text grid) joins the critical path; `BB-X1` moves last and gains a caveat. |
| 4 | **Local by default + hand-to-hand token. No hosted index, ever.** | §6 below is settled; `BB-U4` fully unblocked; **`BB-X10` CLOSED**. |
| 5 | **Windowed offline render, queued into SoLoud. D-RT stays closed.** | `BB-T1` renders **stems**, not a pre-mix; `BB-T3` pre-renders per pass. |
| 6 | **Six styles done properly, then widen.** | `BB-A7` `L` → `M`, and the six are named. |
| 7 | **Synthesise the chord anchor app-side.** | `BB-D3`'s 🔴 resolved; no crisp_notation API change. |

**The two that shape the work most, and why:**

- **(1) is the expensive-to-undo one.** Every ⛔ in §2 is a model narrowed for a
  good reason that is now the blocker — four chords in C, six diatonic degrees,
  `beatsPerBar` as a compile-time constant. Keeping the model full and gating the
  keypad costs one card size; getting it wrong costs what those three cost.
- **(2) + the BB-A0 dividend.** Reusing Loop Studio is not only a code saving: a
  chart that fits the *existing* engine's envelope can play through the *existing*
  band in a single session, which makes the document design testable against a
  real renderer before the arranger exists. That is why **BB-A0 sits fourth on the
  critical path** and why it is explicitly disposable.

## 1. What the category actually is

Stripped of branding, the capability class is six things. Everything in §3 is
scoped against this list.

1. **A chart document** — bars carrying chord *symbols* (not notes), grouped into
   named sections, with repeats, endings, codas and a form (intro · A · A · B ·
   solos · out).
2. **An arranger** — a rhythm section *generated from the symbols*, not authored
   per song. Change one chord and the bass walks into the new one, the drums keep
   the feel, the comp re-voices. This is the whole product; the rest is chrome.
3. **A style library** — dozens of feels, each a coherent whole-band behaviour
   (swing, bossa, shuffle, funk, ballad, waltz, country, reggae, gospel…), with
   intensity levels, fills and endings.
4. **A practice transport** — count-in, loop a section, jump to a chorus,
   transpose live, ramp the tempo each pass, mute the instrument you're covering.
5. **A library and setlists** — many charts, searchable, ordered into gig sets,
   shareable as a small token or file.
6. **A readable chart surface** — big type, a playhead, hands-free at a music
   stand, and chord entry fast enough that typing a 32-bar tune is not a chore.

## 2. Where we actually stand

Read from the code on 2026-07-30, not from docs. The pattern is the same one
`WORKSTATION_PARITY.md` found: **the engines are far ahead of the product**, and
here the *document* is behind both.

| Layer | Evidence | State |
|---|---|---|
| Sampled instrument playback | `sf2/`, `sound_library.dart`, 232 registry instruments | SFZ + SF2 + multisample + tracker voices, real recorded kits | ✅ far ahead of category norm |
| Rendering / mixing / FX | `midi_render.dart`, `fx/`, `daw_timeline.dart` | ~30 FX, buses, sends, stems, byte-identical windowed render | ✅ far ahead |
| Gapless looping | `gapless_loop_player.dart` | SoLoud, sample-accurate wrap, **in-phase hot swap** of the buffer | ✅ exactly what a chart needs |
| Shared transport | `core/services/transport_service.dart` | one position/play-state/loop-range/count-in, `advance(elapsedMs)`, `TempoMap` | ✅ reusable as-is |
| Harmonic analysis | `theory/analysis.dart:142` `analyze()`, `:431` `detectForm()` | key + chord segments + roman numerals + function + cadences; AABA form by transpose-invariant fingerprint | ✅ the chart *deriver* |
| Chord identification | `theory/chord_analysis.dart:170` `identifyChord`, `:216` all tonal readings | pitches → root/quality/inversion, enharmonic re-reads | ✅ |
| Voice-leading rules | `theory/voice_leading.dart:80` | parallels, hidden fifths, crossing, overlap, spacing | ✅ the comping cost function |
| Optimum-path arrangers | `core/notation/bowed_arranger.dart`, tab arranger | Sayegh/Viterbi over hand states — **the exact shape a comping arranger needs** | ✅ precedent to copy |
| Guitar grips | `composition/chord_db.dart` | MIT chords-db, real multi-position shapes, 18 qualities | ✅ |
| Chart interchange, partial | `songs/import/jams.dart` (865 l) | reads **and writes** chord annotations in 5 label dialects | ✅ surprising asset |
| Corpus | 45,930 score rows carrying `music`; 38,431 public catalog items | key · meter · bars · ambitus · incipit, rights-clean | ✅ the chart *supply* |
| Listening | `pitch_analysis.dart`, `chroma_analysis.dart`, `loop_reference.dart`, native AEC | detects what the user plays *while the backing plays* | ✅ nothing in the category does this |
| **Chart document** | `chord_progression.dart:46` `ChordChart` | flat list of `TargetChord`, **no bars, no sections, no repeats** | ⛔ |
| **Chord vocabulary** | `chord_quality.dart:28` (18), `element.dart:1542` (15 kinds) | no 11/13, no altered dominants, no 6/9, no `add`/`omit`, no text parser | ⛔ |
| **Arranger** | `loop_engine.dart:439` `ChordBar` | authored chord-tone indices `0..3` over **6 diatonic degrees of C**, triads only | ⛔ |
| **Style library** | `loop_engine.dart:1598` `kGrooveStyles` | **3** styles, authored track sets | ⛔ |
| **Meter** | `loop_engine.dart:81` `beatsPerBar = 4` (`const`) | **4/4 only, at compile time** | ⛔ |
| **Setlists** | — | does not exist | ⛔ |
| **Chart surface** | `chords/chord_chart_screen.dart` (234 l), `songs/chord_sheet_screen.dart` (103 l) | a drill screen and a lyric sheet with strummable chips; neither is a performance chart | ⛔ |

## 3. Diagnosis — five structural gaps

Adding features before these are closed means adding each one twice.

### G1 — There is no chart document, and the two candidates both refuse the job

`ChordChart` (`chord_progression.dart:46`) is a **flat list of chords in beats**.
It was built to *score* a player against a moving chart and it does that well,
but it cannot express a bar, a section, a repeat, a second ending, or a pickup —
so it cannot be the document.

`Progression` (`loop_engine.dart:356`) is worse-suited despite sounding right: it
is **exactly four chords, one bar each** (asserted at `loop_engine.dart:2158`),
drawn from **six diatonic degrees of C major** (`ChordDegree`, `:335`), each a
plain triad. It is a correct, deliberate design for a children's groovebox and a
dead end for a chart.

`ChordSymbol` (crisp_notation `element.dart:1603`) is the closest thing we own —
real `Pitch` root and bass, so it transposes correctly, and it already
round-trips through MusicXML `<harmony>`. But it is **anchored to a note element
by id**, which is exactly wrong for a chart: a chart bar has chords and *no
notes*. A chart cannot be a list of `ChordSymbol`s until there is something for
them to hang on.

### G2 — Comping is authored, not generated

`ChordBar.resolve` takes chord-tone *indices* (`0` = root, `1` = third, `2` =
fifth, `3` = root+octave) and maps them onto a degree's triad. That is the entire
harmonic vocabulary of the current arranger. It cannot voice a seventh, cannot
lead one voicing into the next, has no notion of a guide-tone line, no bass
*line* (only re-rooted bar shapes), no fills, and no intensity.

The good news is that the hard half is already written twice. `bowed_arranger.dart`
and the tab arranger both solve "choose a physical state per event, minimising a
transition cost, over an optimum path". Comping is the same problem with a
different state (a voicing instead of a hand frame) and a different cost
(`checkVoiceLeading` instead of hand geometry). **The third arranger should be
recognisably the same code shape as the first two**, not a fresh invention.

### G3 — 4/4 is a compile-time constant

`LoopTiming.beatsPerBar = 4` and `stepsPerBar = beatsPerBar * 2` are `static
const` (`loop_engine.dart:81-84`), and `kPatternSteps` derives from them. Every
pattern in the app is a 16-slot eighth-note string over two 4/4 bars. A waltz, a
6/8 ballad or a 5/4 vamp is not a data change — it is a timing-model change.

Worse, the model's *sample* invariant is tied to three tempi: 75/100/120 BPM keep
an eighth-step integral in both milliseconds and samples, which is what keeps
stems aligned and the loop seam click-free. A chart at 132 BPM does not. The
arranger therefore needs a step clock that accumulates fractional sample offsets
with error diffusion rather than rounding per step — otherwise long charts drift
and the seam clicks.

### G4 — Playback is render-then-play, and a chart is long

Every playing surface renders PCM offline and hands it to a player
(`WORKSTATION_PARITY.md` §8 — a deliberate architecture, and the reason the app
has no live audio graph). A two-bar loop renders instantly. A 96-bar chart with a
five-chorus form is ~4 minutes of stereo audio, and "make it 8 BPM faster" or
"jump to the bridge" re-renders all of it.

This does not require abandoning the architecture — it requires *windowing* it:
render bar-windows into a cache in an isolate (the pattern
`loop_mixer_screen.dart` already uses), play them back-to-back through the
existing gapless player, and invalidate only the windows an edit touches. The
in-phase buffer swap `gapless_loop_player.dart` already performs is the primitive
that makes a mid-playback tempo change land on a beat instead of a glitch.

### G5 — Nothing exists above one song

No setlist, no chart library, no chart-level share token, no per-set key/tempo
override, no gig mode. The groove share token (`KU1.` + base64 of a `GrooveSpec`)
is the precedent to follow — small, offline, no server.

## 4. Non-goals

- **Not a sixth top-level mode** (decision 2). The chart is a document that lives
  in `Project` (WS-W1) and plays through the shared transport (WS-W2). It does not
  grow its own clock, its own mixer or its own undo stack — that is the mistake
  `WORKSTATION_PARITY.md` exists to stop repeating, and §S1's diagnosis is that
  *five* unshelled documents is already the problem. Promotion to a top level is
  possible later; it is gated on the WS shell landing first (`BB-U5`).
- **Not a step editor.** The Tracker is the deep grid editor. A style's cells are
  authored data, not a user-facing sequencer surface (an *intensity* dial is).
- **Not a real-time synth engine.** Windowed offline render (§G4) is the answer
  unless and until the standing **D-RT** decision goes the other way.
- **Not a server.** No hosted chart index, no accounts. See §6.
- **Not a transcription product.** Chart-from-audio and chart-from-photo reuse
  the pipelines we already have; neither gets new model work in this arc.

## 5. Where we can exceed the category, not just match it

Matching item-for-item is a losing game and also the least interesting one. Five
things follow from assets the category structurally lacks.

1. **The backing band can hear you.** Every app in this class is deaf: it plays
   at you. We already run pitch and chord detection against a *live* mic while
   our own audio plays, with native echo cancellation and a reference scheduler
   (`loop_reference.dart`) built for exactly this. `LoopEngine.jamFit` already
   classifies a live note as chord-tone / scale-tone / outside **against the
   sounding chord**. Point that at a chart and you have real-time feedback on
   note choice and timing, plus a post-session report. Nothing else in the
   category can do it.
2. **The chart can explain itself.** `analyze()` returns roman numerals,
   harmonic function and cadences; the app already has a kids↔expert analysis
   view. "This is a ii–V–I in B♭", "these four bars are a turnaround", "try
   Dorian here", guide-tone lines, tritone-sub suggestions — pedagogy the
   category leaves entirely to the user.
3. **Thousands of charts arrive rights-clean, for free — but read the caveat.**
   `analyze()` + `detectForm()` over the licence-clean corpus derives a chart per
   piece, with per-file provenance already attached, where the category's
   libraries are user-entered chord data for in-copyright songs.
   ⚠️ **Do not oversell the yield.** The corpus skews to repertoire a rhythm
   section is not wanted for: 18,684 rows are Gregorian chant (unmetred,
   deliberately keyless — a backing track is meaningless), and much of the rest
   is classical polyphony. The genuinely backing-band-usable slice is the
   **folk/dance/hymn/kids** repertoire — the 1720 and Arendsee manuscripts,
   Dahlhoff's 672 dances, the German song collections, the tune books — which is
   thousands of charts and a real product for a folk or school player, but is
   **not** the standards-and-pop repertoire someone practising changes usually
   wants. The modern popular slice of the corpus is precisely the slice that
   fails the rights gate. Size BB-X1 against the usable subset, not the row count.
4. **It sounds like instruments, not like a GM module.** 232 registry
   instruments, real velocity-layered recorded kits, SFZ/SF2/multisample, a
   30-type FX rack, and stems. The category's floor is a MIDI sound set.
5. **The output is a project, not a bounce.** A chart can leave as MIDI, WAV/MP3
   stems, a notated lead sheet PDF, a tracker song, a DAW timeline, or a tab
   part — because every one of those bridges already exists.

## 6. Sharing — DECIDED 2026-07-30 (decision 4)

✅ **Settled: local by default, hand-to-hand token or file, and no hosted index —
not now, not later.** `BB-X10` is closed on this; `BB-U4` and `BB-D4` are fully
unblocked and nothing waits behind them. The reasoning is kept below because it is
the reasoning, and because a future "community chart library" proposal should find
it rather than a gap.

A chord chart of an in-copyright song is not a neutral artefact. The changes are
part of the composition; a community library of user-entered charts for current
repertoire is precisely the exposure this repo's whole corpus posture exists to
avoid (`docs/CORPUS_LICENSING.md`; auto-memory
`docs-no-control-archives-no-acquisition`).

The position, now adopted:

- **Charts we ship** come only from rights-clean sources: corpus-derived (§5.3),
  public-domain repertoire, or original material. Each carries the same per-file
  provenance every other asset row carries.
- **Charts a user enters** are theirs and stay **local by default** — no upload,
  no index, no title search across users.
- **If** sharing is enabled at all, it is a token/file the user hands to someone
  directly (the `KU1.` precedent), never a server-hosted, title-searchable
  catalogue we operate.

**And the strategic point, since this reads as caution and is not.** We are not
shipping a weaker version of a catalogue. A catalogue is content we could not
legally own; the arranger (§3 G2 → `BB-A1`–`A6`), the listening (`BB-X5`) and the
explanation (`BB-X6`) are capabilities a catalogue cannot copy. That is the bet.

## 7. Cross-references

- Executable tasks: **PLAN.md → "Chord-chart backing band — the executable
  ladder"**. That board holds the work; this file holds the reasoning.
- Shell, transport, project container: `docs/WORKSTATION_PARITY.md` (WS-W1/W2/W5).
- Rights posture and the ship gate: `docs/CORPUS_LICENSING.md`.
- Listening/grading precedent: `docs/LOOP_MIXER_FOLLOWUPS_HANDOVER.md` §B.
- Note-choice feedback precedent: `LoopEngine.jamFit`, `loop_engine.dart:3387`.
