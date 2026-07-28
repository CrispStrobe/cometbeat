# CometBeat — canonical plan & pending work

> **This is the canonical PLAN** (2026-07-25 doc consolidation). All pending and
> planned work lives here; everything shipped is recorded in
> [docs/HISTORY.md](docs/HISTORY.md). Detailed curriculum/roadmap planning and the
> per-agent coordination board are in [docs/PLAN.md](docs/PLAN.md); the remaining
> single-topic reference docs are linked from the "Consolidated backlog" section
> at the end of this file.

🚧 **Idle / Last-shipped (Agent checkpoint)**
- Shipped: Synth & FX Editor (embeds Sound Lab directly into Tracker via `instrument_editor.dart`).
- Shipped: Multi-Sample Groundwork (`MultiSampleInstrument` added to `tracker_engine.dart` with correct monophonic choking semantics).

## Cello fingering (string · position · finger) — arranger VALIDATED against printed method literature

> **2026-07-28 update — the numbers below this block are superseded.** A reading arc over
> four PD cello methods (Romberg 1840 · Tillière/Ikelmer c.1877 · Tillière/Danbé c.1905 ·
> Kummer ed. Hugo Becker) produced **~2,900 transcribed notes / 3,078 fingering digits**
> across sixteen pages and turned the arranger from "authored weights, one gold set" into
> something measured on **four axes**. All PD, four different routes (composer d.>70y ·
> anonymous-reviser 70y-from-publication · named reviser d.1905 · d.1941).
>
> | axis | before | now |
> |---|---|---|
> | finger (CC0 gold) | 50.3% | **53.9%** |
> | finger (Becker scales, new) | — | 56.3% |
> | string | 92.7% | 92.7% |
> | frame (neck vs extended) | unmeasured | **17/24** (was 0) |
> | shift (where the hand moves) | unmeasured | 35.3% / 40.0% |
>
> **Shipped fixes:** `thumbEntry` 12→10 (confirmed by three independent sources);
> `shiftBase 0.5` closing the "right fingers, wrong hand" defect with all three legs
> improving; cello position NAMES corrected at the UI edge (the games were teaching a
> third-position hand as "position 4", and a `const Text('\$p')` bug rendered every chip as
> the literal `$p`). **New fixtures:** `cello_fingering_gold_becker.json` (1,056 notes,
> per-page floors) and `cello_shift_gold_danbe.json` (15 printed position changes).
>
> **Ruled out with measurements** (do not retry): lowering `extension`; switching skill
> profile; a reshape/mode-change cost; raising `stringCross`. Each cost 4–5pp on one axis to
> buy another. **Still open:** an expressive "stay on one string / one hand shape per phrase"
> term — it needs a phrase signal the arranger does not receive, and is a design change, not
> a weight.
>
> **Corroborated from primary sources, not inferred:** `firstPositionOffset: 2` (three
> sources); `thumbFrame [0,2,4,5]` (Becker alters the printed PITCH to preserve the frame);
> the neck frame demonstrated 28 times in Romberg's Applicatur table; barred fifths; and
> Romberg stating this file's founding premise in 1840 — *"die Violinspieler haben zwei
> Terzen in den Fingern und der Violoncellist nur eine."*
>
>  **Reading method (2026-07-28):** the maintainer's *piece-at-a-time* protocol — give a
> reader ONE PIECE, have it write a complete rough draft from a downscaled view, then correct
> that draft against successive native-resolution crops (`methods/piece_cut.py`). Tested on
> Becker p.50 no.9: 24 bars, 110 events, 66 digits, 23 logged corrections, both self-checks
> passing. The transferable part is `methods/CONVENTIONS.md` → **the non-metric arguments**:
> every failure came from judging vertical position and every recovery from a musical or
> physical argument (a printed `0` can only be an open string; a ledger line through a head is
> categorical; a finger a hand cannot place refutes the reading). That is why "read it, don't
> OMR it" is a method and not merely a restriction.
>
> **Usable where? (2026-07-28)** — **GUI:** Song Book shows the full teacher's markup behind
> a toggle (`song_screen.dart` → `scoreWithBowedFingerings`, written into a COPY so a saved
> song never gains marks); Play-along has a "show fingerings" toggle; the two cello games
> drill positions 1–4 from the hand model; PDF export carries `extraFingerings`.
> **CLI:** `bin/fingerconv.dart` (new) — `dart run bin/fingerconv.dart <in> [<out>]`, reads
> everything `tabconv` reads, writes MusicXML/LilyPond/kern/ABC, `--skill first|neck|advanced`,
> `--instrument cello|bass`, `--part <n|name>`, `--list-parts`, `--stats`. Flutter-free.
> Verified against the composer: over our transcription of Romberg's own *Tonleiter in G dur*
> it emits `4 3 1 0 4 3 1 0 4 3 1` against his printed `4 3 1 0 4 3 1 0 4 2 1` — 10/11, the
> one difference being the E2 where he takes D–E–F♯ as a single 1‑2‑4 hand shape.
> **This unlocks the DB's ~2,650 cello scores, none of which carries a fingering** — a real
> decision rather than an obvious yes, since at ~54% agreement on expressive repertoire the
> output is a first draft for a teacher, not an edition.
>
> Detail, method and every negative result: `docs/PLAN.md` → *opus (cello-vision-read)*.


`lib/core/notation/bowed_arranger.dart` fingers a bowed line the way the guitar
tab arranger fingers a fretted one: same Sayegh/Viterbi optimum path, but the state
is a hand FRAME (mode × anchor) instead of a set of `(string, fret)` pairs, so the
finger falls out of the geometry. Cello + double bass (Simandl 1-2-4); extensions
and thumb position are frame modes with per-note costs; a `BowedSkill` profile caps
the technique with soft costs, so a learner's fingering stays in first position and
only the notes that force it reach higher. Untrained, no model asset.
`bowed_score_fingering.dart` is the score-level entry point (id-keyed side table,
like `Score.slurs`). Gates: `kCelloFirstPosition` re-derived from geometry
(`test/bowed_arranger_test.dart`) + agreement against printed CC0 editions
(`test/bowed_arranger_accept_test.dart`, 50.3% of 193 printed fingers).

**Where the ceiling is.** A 135-point weight sweep spans 38.3–50.3%, so ~50% is
what authored weights can do on that gold set. The violin literature says why:
string choice is nearly solved by geometry, hand POSITION is subjective (ten
professionals disagree; F1 ≈ .24–.31), and expressive position choice is exactly
what a learner doesn't need — which is why the capped profiles are the useful
product and the uncapped one is the research problem.

Pending, in order:
1. **Consumers — DONE.** Fingerings show on the cello play-along, on the song screen
   (a toggle) and on the cello "Play it" staff; the games drill positions 1–4; and a
   fingered part **prints** (Export… → PDF, marks passed as a layout argument so the
   saved song is untouched). **String indicator — DONE** (Roman numerals at
   crossings and on the opening stopped note, never on an open string, since an open
   pitch names its own string; rides in the same copy). **MusicXML-with-fingerings —
   DONE** (`Score.copyWith`/`NoteElement.copyWith`
   shipped in crisp_notation with a source-reading drift guard; the song screen
   exports a fingered copy through the standard export sheet). The `T` glyph this
   bullet once waited on is in the library now, so thumb position engraves too.
   **Everything in this bullet is shipped; what remains in the arc is 2 and 3.**
2. **More labels — CLOSED (measured 2026-07-26/27).** Both routes were tested to a
   number rather than argued about.
   **OMR: dead.** Our own OMR cannot carry fingerings by construction (SMT → `bekern`
   → Humdrum `**kern`, no fingering in that vocabulary). Audiveris 5.11 CAN — it
   exported real `<fingering>` from a PD 19th-c. Dotzauer print — but at **~20% recall**
   (4 of ~15–25 printed on the page) with a diagnosable precision failure (a harmonic
   circle read as finger `0`, which our own geometry rejects automatically). AGPL-3.0,
   so an offline tool only, never bundled.
   **Symbolic: exhausted.** Streaming-scanned the full PDMX release (`mxl.tar.gz`,
   **254,035 scores**): 1,538 carry a fingering → **236 bowed parts / 9,324 labels** →
   after the documented ship gate (`composer_name` → Wikidata death ≤1955 AND
   `license_conflict == False`) **51 parts / 1,282 labels**, of which **6 cello parts /
   121 labels**, and 2 of those were scores we already had. **Net: +55 cello labels
   (193 → 248).** The entire 254k corpus adds 28% to our gold set.
   **The gate is not ceremony:** it rejected Hozier, John Williams, Howard Shore, Toby
   Fox, Chrono Trigger, Pokémon and four in-copyright Kreisler pieces — all tagged
   `publicdomain`/`cc-zero` by their uploaders. PDMX's axis-2 is self-attested; a
   licence field is a claim, not a clearance (`docs/CORPUS_LICENSING.md`, PDMX OVERHAUL).
   ⚠ The gate under-clears in a fixable way: `"J.S. BACH"` and
   `"Luigi Boccherini (1743-1805)"` both come back UNKNOWN — string formatting, not
   copyright. A normalisation pass on `bin/pdmx_pd_composer.py` would recover rows
   across the whole catalog; flagged to its owner, not changed here.
   **What is left, and it is not a corpus:** a cellist annotating for a few hours, with
   the arranger pre-filling so they correct rather than type. That is how TNUA (violin,
   217k notes) was built, and it is the only route that produces dense expert labels.
   The 55 new labels ship as a second acceptance slice
   (`test/data/cello_fingering_gold_pd.json`, 58.2% agreement vs the first set's 50.3%).

2b. **The label landscape, measured (2026-07-27) — the pattern is structural.**
   Every licence-clean corpus we can reach is UNFINGERED, and every fingered corpus is
   not licence-clean. That is not bad luck: fingering is editorial labour, so whoever
   does it either sells it or uploads it under a licence they do not own.
   * **PDMX** 254,078 scores, CC0/PD-tagged → **55 net new cello labels** after the
     documented gate (which rejected Hozier, John Williams, Kreisler…).
   * **Mutopia** — licence-clean (CC-BY/PD) AND digital-native LilyPond, 157 cello
     `.ly` files: sampled 40, **exactly 1 carries fingering marks** (5 of them).
     Engravers of PD repertoire simply do not finger.
   * **`cellist/Lilypond-Sheet-Music`** — 4,979 `.ly`, cello-heavy, actively
     maintained… and **no licence at all** → all-rights-reserved by default, the
     ClassTab trap. Not usable, not even as a control we could publish about.
   * **SPD** — the one corpus with exactly the right labels (string+position+finger,
     ~10k cello notes) is **non-commercial and non-redistributable**. Dropped.
   * **PD teaching material is abundant and was never the blocker**: Dotzauer's
     *Violoncellschule* / 113 Études / Op.120, Lee Op.31, Kummer Op.57, Duport's 21
     Studies, Popper, Klengel, Werner — all PD by age, all *scans*. **Extraction is the
     blocker** (Audiveris ~20% recall, and our own OMR cannot represent a fingering at
     all).
   **Oracles that need no corpus at all**, in order of value:
   (a) **Self-generated labelled audio** — record a cello playing known (string,
   finger). Licence-free by construction, and we already ship the mic + pitch
   detector; string-from-timbre is a tractable MIR task since the same pitch has a
   different spectrum on each string. Half an hour of deliberate playing is thousands
   of labelled frames. (b) **GuitarSet, CC-BY 4.0** — 35k labelled (string, fret)
   columns for the *same decision structure*, already in our pipeline, legitimately
   licensed for shipped weights. (c) **Our own geometry as a validator** — already
   earning its keep (it rejected an OMR "finger 0" on F♯4 that no open string can
   sound).
   ⚠ **Not yet checked (VPS was down):** our own corpus's **1,220 `.ly`** files and
   **565 cello-bearing `.krn`** were never scanned for fingerings — every scan so far
   covered MusicXML/mscx only. LilyPond writes fingerings as `-1`…`-4` and Humdrum has
   a `**fing` spine. The Mutopia sample says expect little, but it is a real gap and
   cheap to close.

2c. **PD cello PEDAGOGY as a transcription source — scoped 2026-07-27.** The
   corpora are exhausted (2b), but the *teaching literature* is not: ~100 cello
   schools/methods exist, nearly all long-PD, and unlike repertoire editions they are
   **densely fingered** because fingering IS the content. Index:
   `de.instr.scorser.com/SS/Violoncello/Alle/Method.html` (a catalogue that links out —
   the entries are not direct downloads; it also has a `Für Anfänger` filter).
   **Best young-learner targets** (all long-PD composers): Kummer Op.60
   *Violoncell-Schule für den ersten Unterricht* (1839) · Dotzauer Op.126, same title ·
   Werner Op.12 (vol. 1 = first position only) · Schroeder *Practischer Lehrgang*,
   *Führer durch den Violoncell-Unterricht*, Op.31 *Die ersten Violoncello-Übungen* ·
   Lee Op.30 *Méthode pratique* · Kastner *Méthode élémentaire* · Cuccoli *Metodo
   elementare* · Benito Op.133 · Depas *Méthode Élémentaire* · Rachelle *Breve metodo*;
   behind them Romberg, Davydov, Piatti, Quarenghi, Stiastny, Tillière, Corrette Op.24.
   **⚠ The editor decides the status, not the composer** — and for us the editor's layer
   IS the data, so this is the crux (same lesson as PDMX/ModArchive/Ebersberger). On
   that index: Duport *Essai* **(Cassadó, d.1966)** → EU-copyright until 2037, and it is
   the fingered one; Ševčík Op.2 **(Feuillard, d.1953)** → EU-PD only since 2024;
   Bréval Op.42 and Baudiot Op.25 **(Grützmacher, d.1903)** ✓; Simpson **(Piatti,
   d.1901)** ✓; **Bazelaire** (d.1958) ✗ until 2029; **Alexanian** (d.1956) ✗ until
   2027; **Gardner** modern ✗. This matches the **dead-editor strategy** already in
   `docs/CORPUS_LICENSING.md` — take original prints, or editions whose EDITOR died
   >70y ago.
   **Access, measured:** IMSLP has everything but gates automated fetching (human
   attestation); **Internet Archive mirrors are ungated** and worked (Dotzauer Op.175,
   Kummer Op.60 = `imslp-fr-den-ersten-unterricht-op60-kummer-friedrich-august`, 103pp,
   1839). German library digitisations (ULB Münster and peers) are library-grade scans —
   better VLM input than user uploads — but sit behind a JS browser-check, including on
   the direct PDF path, so they need a human. Musopen: non-profit PD mission, 403s
   automation, catalogue overlaps IMSLP, its differentiator is recordings not scores.
   `violinsheetmusic.org`: footer states **ALL Rights Reserved** and the category is
   *arrangements* → rejected.
   **The find that matters:** Kummer Op.60 p.14 "Die Dur-Scalen" carries a fingering
   digit on **essentially every note**, above AND below the staff (two alternative
   fingerings per passage), plus octave/position labels and `+` for THUMB — hundreds of
   labels per page against ~20 on an étude page. Scales are also **self-validating**
   (a C major scale's pitches are known), so a transcriber only has to read digits and
   we can check the pitch axis ourselves. This is the right input for the vision route
   that `CORPUS_LICENSING.md` scored 9/9 on clean engraving; pilot in progress.
   **And the licence upside:** a transcription WE make of a PD print is our own work
   product — no NC clause, no attribution chain, no uploader's tag to distrust. It is
   the only route in this whole arc that ends with data we own outright.
   ⚠ Also unexplored: `nathanaelmeister` on GitHub is typesetting Lee Op.30/Op.70/Op.101
   in LilyPond (digital-native, fingerings would extract exactly) but **declares no
   licence** → unusable until asked. Asking is cheap and outward-facing.

3. **Learned emission — CLOSED with item 2.** 248 labels cannot fit transition/emission
   tables that beat authored weights, let alone train a neural emission model. The seam
   stays (`BowedPositionModel`, the bowed twin of `TabPositionModel`) so a model can
   drop in if dense labels ever exist; nothing else is worth building against 248.
   The literature's own numbers say why this is not a loss: hand position is subjective
   (ten professionals, F1 ≈ .24–.31), and the capped-skill profiles that the app
   actually uses are near-deterministic from geometry alone.

## Automatic play-along — live pitch detection (feature area)

Live pitch/chord detection from the mic, turned into real practice modes:
tuner, sing-along, play-along with a moving score, and games. Everything sits
on one pure-Dart detection core so it stays testable headlessly and from a CLI.

## Sound Library / Instrument / FX unification (ONE ITEM LEFT — see below)

Unify the places that currently drift apart: the Tracker instrument selector,
Workshop Score "Play with an instrument", Audio Editor track/clip voicing, and
Sound Library creation tools.

- **One Sound Library surface for instruments** — *partly done; the residue is
  `@codex (score-editor-web)`, see the board.* `showMyInstrumentsSheet` IS that
  picker and is already the one every "choose an instrument" surface opens:
  Workshop, both Trackers, Drumkit, Voice Lab, the settings voice picker and
  Audio Editor (`daw_screen.dart:2963`, `includeBuiltIns: true`). What is still
  open is the *other* direction — Advanced Tracker's parallel one-off entries
  (Mod Archive, Load SoundFont, catalog browsing) belong inside that picker, and
  the web-side install path needs to work or say why not.
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
- ✅ **Voice Shaping is an audio FX module — DONE (verified 2026-07-26).**
  `voiceShape` / `voiceChipmunk` / `voiceDeep` / `voiceRobot` / `voiceRadio` are
  `FxType` values with defaults in `fx_spec.dart`, and `daw_screen.dart`'s single
  `_clipEffectTypes` list feeds **all four scopes** — `_trackFxEditor`,
  `_masterFxEditor`, `_busEditor` and `_openClipInspector` — plus the marked-range
  FX action. So the voice-shaping DSP already processes any clip, track, bus,
  master or segment, which was the ask.

## Loop Studio consolidation (DONE — every bullet audited 2026-07-26)

> Audited against the code, bullet by bullet, because the IN-PROGRESS marker had
> outlived the work: ✅ **one loop document** — captured sung/beatboxed layers are
> symbolic (`MelodicPattern` / `DrumRowsPattern` via `setUserTrack` /
> `setBeatTrack`), never baked stems. ✅ **one transport** — `GaplessLoopPlayer`
> over flutter_soloud, seam-safe periodic buffers, boundary swaps without a
> restart. ✅ **one primary workflow** — the Beginner-Tracker hub tile is retired
> and `PerformScreen` is out of navigation (referenced only by its own file and
> tests), so the redundant entries are gone. ✅ **scannable controls** — BPM
> slider (`loop_mixer_screen.dart` ~3685) plus numeric field (~3702). ✅
> **notation is a view** — per-track staves following the selection, sharing the
> transport, with treble/bass/**grand** chosen from each track's actual range.
> ✅ **verification** — pure tests for periodic rendering, boundary swaps,
> editable per-track events and staff choice, plus widget tests for the
> workflow/transport.
>
> The one thing left is a judgement call, not code: whether to DELETE the archived
> `perform_screen.dart` (dead but still tested) now that parity is proven. The
> retirement map gates that on a sign-off, so it stays.

Live Looper / Perform, Loop Mixer, and Beginner Tracker currently expose three
overlapping but incompatible editing experiences. They must converge on one
musical loop document and one transport; the beginner view is a simpler skin,
not a second playback engine.

- **One loop document.** Every audible voice/track must have editable symbolic
  events (drums, pitched notes, chords, and imported material) plus its selected
  instrument. Editing a beat/tune must change those events and re-render the
  exact voice, never a black-box baked stem.
- **One transport.** Start, pause, stop, loop length, BPM, and playhead phase
  are shared. Loop swaps happen at a musical boundary without stopping and
  restarting the audio player. The loop buffer must be periodic and seam-safe.
- **One primary workflow.** Loop Studio opens in a focused beginner layout with
  direct track controls; an Advanced view reveals the full matrix, per-track
  instruments, sends, effects, and arrangement. Remove redundant mode choices
  where they only lead to different non-editable copies of the same groove.
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
- **Verification.** Add pure tests for periodic loop rendering, boundary swaps,
  editable per-track events, and clef selection; add widget tests for the
  beginner/advanced workflow and transport states before removing old surfaces.

## Five-mode product architecture (DECIDED)

The product has five top-level authoring modes. They are different musical
mental models over one shared project/document model, not five unrelated apps:

1. **Tracker** — a classic pattern-sequencer successor: pattern matrix,
   rows/channels, instruments, ticks, effect commands, macros, sample
   playback, pattern order, and tracker interchange (MOD/XM/S3M/IT/MIDI).
2. **Loop Studio** — a creator-to-professional loop workflow: record, capture,
   quantize, overdub, arrange sections, edit every voice, choose instruments,
   mix, and perform over loops. Simple and Advanced layouts edit the same loop
   document; they are not separate modes.
3. **Score** — multi-part conventional notation and engraving: voices, chords,
   lyrics, clefs, analysis, playback, and print/interchange exports.
4. **Tab** — guitar/bass/cello/string-instrument notation: tuning, strings,
   frets, fingering, chord diagrams, notation, and instrument-aware playback.
5. **Audio** — the DAW: clips, regions, recording, buses, automation, inserts,
   Voice Shaping and future FX, mixing, and final export.

> **Workstation parity (scoped 2026-07-27) → [docs/WORKSTATION_PARITY.md](docs/WORKSTATION_PARITY.md).**
> The maintainer ask is that Tracker, Audio Editor and Loop Studio become as
> powerful and as intuitive as a full professional workstation. That doc is the
> scoping: the engines are ahead of the product, and what is missing is a
> **shell** — one `Project`, one transport, one undo, one mixer, one keymap —
> plus **live links** instead of copies between modes. It cross-references the
> per-surface backlogs below rather than duplicating them, and it raises one
> decision for the maintainer (**D-RT**: whether to add a bounded real-time
> *preview bus* alongside the offline renderer). **The executable tasks live
> below** → *"Workstation parity — the executable ladder"*.

### Loop Studio UX contract

Loop Studio opens directly into an audible, editable project. The first screen
must make the following obvious without tutorials: what is playing, which tracks
are active, where the playhead is, how long the loop is, the BPM, and where the
user can change the actual notes/hits.

- The top transport bar is shared and stable: Start/Pause, Stop, loop length,
  BPM slider plus numeric field, undo/redo, Save, and Export.
- The first content band is the track lane. Each track exposes play/mute/solo,
  level, instrument, record/overdub, and an Edit button. Editing opens the
  actual symbolic events for that track, not a decorative preview or a baked
  audio blob.
- Simple layout shows one friendly event lane per track with large cells,
  piano/pad input, quantize, and a small number of safe controls. It is suitable
  for a child copying a performance video.
- Advanced layout adds the full matrix, exact event durations, velocity,
  per-track instruments, effects, sends, automation, section scenes, and
  arrangement. It remains the same project and transport.
- Settings use compact grouped bars like Score Workshop: BPM/loop, key/scale,
  swing, quantize, sound, and arrangement. Preset words such as Chill/Groove/
  Fast may remain as named starting points, but never as the only tempo control.
- Sheet Music is a synchronized projection of selected Loop Studio tracks:
  multiple voices are visible, clefs follow pitch range, grand staff is used
  for a genuinely mixed voice, and the same transport controls it.
- Record, import, and play-in actions always create editable track events first;
  rendering to audio is an explicit bounce operation into Audio mode.

### Loop Studio — sequencer-parity slices (scoped 2026-07-27)

Grounded in a read of `loop_mixer_screen.dart` + `loop_engine.dart`, not in the
docs — **correction first: the "Loop Mixer has no step editor by design" line in
CLAUDE.md and auto-memory is STALE.** Loop Studio has tap-to-build grids for
both pitched and drum tracks ("Edit the tune" / "Edit the beat", hold-for-ghost).
The Tracker is the DEEP editor, not the only one.

Already at sequencer parity, so do not rebuild these: transport with BPM slider
+ numeric field, undo, bar readout, count-in; per-track mute/solo/level/pan/
instrument/send; pattern **variants**; **scenes that store per-track variants**
(`GrooveScene(enabled, variants)` — a real session-grid scene, not just on/off);
scene chaining; arrangement bounce; master FX; quantize; global swing; sing/
beatbox capture into symbolic events; notation projection + MusicXML.

The gaps below are verified absent (grep counts of 0 where claimed). Ordered by
musical payoff per unit of work, which is NOT the order they are numbered in.

- ⬜ **L1 — per-track pattern length (polymeter).** *Do this first.*
  `LoopTiming.bars` is global and there is no per-track length anywhere. A short
  pattern against a longer one (3-step hat under a 4-step bass) is the signature
  groovebox move, is instantly legible to a child ("make it shorter — now it
  keeps changing"), and the renderer already tiles patterns to the loop length.
  **Design constraint a fresh agent must resolve, not skip:** the engine renders
  ONE loop buffer and repeats it gaplessly, so simply truncating a 3-step
  pattern at the loop boundary re-aligns the phase every cycle — that is a
  clipped tail, not polymeter. The rendered buffer has to span the lcm of the
  global length and the track lengths, **capped** (suggest ≤ 8 bars) with the
  cap reported rather than silently applied. Tests: a 3-against-4 render is NOT
  equal to the same pattern tiled at 4, and the cap is honoured.
- ⬜ **L3 — copy / duplicate.** Zero matches for duplicating a section, scene or
  pattern. "Copy A to B, change one thing" is how sequencer users actually work;
  without it every variation is built from nothing. Cheapest big workflow win.
- ⬜ **L2 — show the session grid.** The tracks × sections matrix ALREADY EXISTS
  in the data (each scene stores a variant per track) and is presented as a row
  of section buttons. Rendering the matrix exposes shipped power with no model
  risk. Pure UI.
- ⬜ **L5 — visible queued launch.** `_launchScene` applies state immediately
  while the audio swaps at the loop seam. The behaviour is right and the
  FEEDBACK is missing: no pending state, so correct musical timing reads as lag.
  Small, and it is what makes a performance surface feel professional.
- ⬜ **L4 — per-section repeat counts (real song mode).** Chaining advances one
  pass per section, so A×4 B×2 A×4 is unsayable. Extends `renderArrangement`.
- ⬜ **L6 — per-track swing, then automation.** Swing is global
  (`LoopTiming.swing`); no parameter movement over the loop. Both shipped since;
  "lower priority for this audience" was the wrong framing — see the audience
  correction below.

⚠️ **AUDIENCE CORRECTION (maintainer, 2026-07-27) — this invalidates several
"deliberately scoped down" calls below and elsewhere.** CometBeat is **not** a
6+ app that happens to be usable by others. It is a learning app that **scales
up to students and hobbyists**, and the stated model is **Scratch / TinkerCAD**:
a nine-year-old uses those to build genuinely useful, interesting things. They
are *approachable*, not *limited*. Anything justified here on the grounds that
"a young audience does not need it" was reasoned from the wrong premise and
should be re-read.

Concretely, three of my own calls flip:
- 🔶 **Add / duplicate / rename tracks — REOPENED; DUPLICATE shipped (engine).**
  `duplicateTrack(id)` adds a copy carrying level, pan, variant, pattern length,
  swing, automation, an edited pattern and a saved voice — a copy arriving at
  defaults would have to be rebuilt before it could be varied, which defeats the
  point. It starts enabled. `removeExtraTrack` refuses base-band tracks rather
  than hiding them, and drops the copy's settings so a reused id cannot inherit
  them. Automation lanes are deep-copied (same aliasing trap as section copy).
  10 tests. ✅ **UI shipped** — a chip per track in the inspector ("Add another
  track"): tap to copy, long-press a copy to remove it, so adding and removing
  live in one place. ⬜ Arbitrary add + rename still open.
  ⚠️ **Two things the first copy broke, because ids were assumed to be known
  ones:** `_trackColors[id]!` threw a null check and `_trackLabel` fell through
  its default, rendering every copy as "Sparkle". Copies now inherit their
  source's colour and read as "Bass 2" — strip the `-N` suffix until a known id
  is found, so a copy of a copy resolves too.
  ⚠️ Wiring remove to the CARD's delete button overflowed that row by 23px —
  the same row that broke 14 tests before — and widening the lane columns did
  NOT fix it. The control moved to the chip instead, which is the better design
  anyway. **Treat that row as full.**
  `kLoopMixerTracks` being a fixed curated band was justified above as
  "defensible for 6+". Under the Scratch model that is exactly backwards —
  Scratch lets a child add unlimited sprites, and the ceiling is the point.
  Start with *duplicate an existing track* (cheapest, no instrument tree) and
  then arbitrary add/rename.
- ⬜ **A pan-lane editor — no longer "does this audience want one".** It
  renders already (A3); it needs UI.
- ⬜ **Per-track filter + its automation — no longer out of scope for being
  "new DSP".** It is ordinary depth for this audience.
Still genuinely out of scope, for reasons that are NOT about audience: MIDI
clock and a full automation matrix belong to the Tracker and the Audio Editor,
which is a mode-boundary decision, not a capability ceiling.

### Loop Studio — DECIDED by the maintainer 2026-07-27 (✅ ALL FOUR BUILT)

Four open questions, answered. These are decisions, not suggestions — the
reasoning behind each is in the audience correction above (CometBeat scales up
to students and hobbyists; Scratch/TinkerCAD model).

**Shipped 2026-07-27** (`feature/mixer-d1d4`): D1 + D3 in the engine, all three
on screen, D4 restored. 85 new tests; both CI gates verified from the worktree
(`dart format --set-exit-if-changed .` exit 0, whole-project analyze "No issues
found"). What each turned out to need, beyond the scoping below:

- **D1** — `addRoleTrack` / `addEmptyTrack` / per-track names next to
  `duplicateTrack`. A role add deliberately does NOT inherit the playing
  instance's settings (that is what duplicate is for) but DOES take a variant no
  enabled track of that role is using — two tracks on the identical pattern are
  indistinguishable from one louder track, so "add a bass" would have read as a
  volume bump. `'track'` is now a real entry in `_trackColors` / `_trackLabel`,
  so an empty track is slate and reads "Track 2" instead of a grey "Sparkle".
  ⚠️ **The gap this exposed: added tracks did not SURVIVE A SAVE, and neither did
  copies.** Everything about a track is keyed by id and `applySpec` drops ids it
  does not know, so a saved groove came back with them gone and their settings
  silently discarded. `GrooveSpec` now carries the roster (id → role, or empty),
  the names and the filters, all omitted at their defaults so an unchanged groove
  tokenises byte-for-byte as before. `applySpec` rebuilds the roster BEFORE it
  takes its `known` set, and prunes length/swing/automation for tracks the loaded
  groove does not have so a reused id cannot inherit them.
- **D2** — one strip, a Volume / Left-right / Tone switch above it. The three
  cells are drawn differently on purpose: volume is one-sided (a bar off the
  floor), pan is a POSITION (a marker sliding left/right), tone is an AMOUNT (a
  bar out of the middle). One shared bar would have made a hard-left pan look
  like a fade-out.
- **D3** — `mixStems`/`mixStemsStereo` take an optional per-stem `inserts` list,
  run AFTER unit-peak normalisation and BEFORE gain: the same lesson the level
  lane taught, plus the console order (insert, then fader). Two non-obvious
  things inside: the stem is filtered TWICE and the second copy kept (a biquad
  starts with zero memory, but a loop's first sample follows its last — the same
  trick `_applySend` uses), and both a low-pass and a high-pass run on every
  sample when there is a lane, selected by position, because a lane can cross the
  middle and switching filters mid-loop would restart the memory. Measured with
  Goertzel band ratios, not "the bytes changed" — a filter wired backwards passes
  that.
- **D4** — **no port was needed.** Both files restore from `git show
  8a2c2d52^:<path>` and pass VERBATIM (22 tests). The "no longer compiles" note
  predates `9adc7b9b`, which restored the A7 generator code; `generateWave` /
  `GeneratorShape` and `traceChannel` / `protrackerMemory` are all present at the
  signatures the tests were written against. Editing those tests would have meant
  changing them to match code that had not moved.

✅ **Followed up (maintainer: "fix it all") — `GrooveSpec` is now a COMPLETE
snapshot.** Chasing the length/swing gap turned up a third and worse one:

- **Automation lanes never travelled either.** A1's slice was scoped as "lane
  type, `GrooveSpec` field, share-token and save round-trip"; the type and the
  codec were written and tested, and **nothing ever called
  `automationToJson`/`automationFromJson`** — grep found them only in
  `loop_automation.dart` and its own unit test. So a player could draw a fade
  across sixteen steps, save, and get back a groove with no fade **and no
  error**. Every A2–A4 slice built on top of a lane that could not be saved.
- Per-track **length** (polymeter) and per-track **swing** were the two already
  known.

All three now round-trip (`ts` / `tw` / `au`), each omitted at its default so a
groove using none of them tokenises byte-for-byte as before. `applySpec` REPLACES
them rather than merging — a loaded groove says what every track's length, swing
and lanes are, including "none", and merging would leave a shortened hat or a
drawn fade behind from whatever was on screen. A refused length (5, 7…) is
dropped rather than clamped, matching `setTrackSteps`: the allowed set is what
bounds the render buffer, and rounding a pasted 5 to a 4 would be a lie about
what plays. No UI change was needed — the screen saves and shares through
`encodeGrooveToken(_engine.spec)` — but there is a GUI test for the path a player
actually takes, because that is the one that was broken.

**The lesson worth keeping: a codec with a passing unit test is not a wired
feature.** `automationToJson` was correct, covered, and dead. When a slice says
"model + codec, round-trip", the round-trip that counts is the one through the
object the app actually saves.

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

### Loop Studio — automation lanes (scoped 2026-07-27, NOT started)

L1–L6 all exposed structure that already existed. **Automation is the first item
that adds a new dimension to the model — values that change over TIME within a
loop** — so it touches the model, the renderer, the share token, save slots and
the UI. Scoped here so it is picked up deliberately, not drifted into.

**Why the offline renderer helps.** Loop Studio renders `GrooveSpec → WAV` once
and loops it gaplessly. There is no real-time parameter smoothing to get right:
a lane is just a function of step, sampled at render time.

**Shape.** Per track, per parameter, one value per eighth-step of the loop;
absent = no lane. Same tiling rules as patterns (see `loop_track_length.dart`),
so a lane on a shortened track repeats with it.

**What to automate, and what NOT to.** Level, pan and the per-track filter —
all three are already per-track scalars applied in `_renderMix` / `_applySend`,
so automating them turns a constant into a lookup and adds no new DSP.
- ❌ **Not tempo.** It would change the loop length and break the
  sample-integrality invariant the whole engine rests on.
- ❌ **Not swing.** It is baked into `boundaryMs` before rendering, and per-track
  swing already documents why the final boundary must not move.

⚠️ **The one real engine problem, solve it first:** `mixStems` unit-peak
normalises each stem and THEN applies gain. A level lane applied before
normalisation is normalised away. It has to land AFTER unit-peak, as a per-sample
multiply — which is exactly where `applyCellVelocities` already operates. Reuse
that seam.

**Slices, smallest shippable first:**
- ⬜ **A1 — model + codec.** Lane type, `GrooveSpec` field, share-token and save
  round-trip. Pure, no audio, no UI.
- ⬜ **A2 — render ONE lane (level).** Applied post-normalisation. The guard
  test is the important one: a groove with no lanes must render **byte-for-byte**
  as before, exactly as polymeter had to.
- ⬜ **A3 — pan + filter** on the same seam, once level proves the shape.
- ⬜ **A4 — UI.** Draw the lane over the per-track row in the inspector.
  **Needs a product decision before starting:** per-eighth-step values (16 of
  them, blocky, matches the tune/beat grids the app already uses everywhere, one
  tap per value) versus a smooth breakpoint curve. **Per-step was chosen and
  shipped — but note the REASON, which I first wrote down wrongly:** it is
  direct manipulation on the grid the whole app is built from, the same argument
  as Scratch's blocks. It is NOT "curves are too hard for young users". Curves
  are therefore a legitimate ADDITION later (a mode switch on the same lane),
  not something ruled out.

### Integration and retirement map

- **Keep and integrate:** `LoopEngine` timing/pattern model, `LoopStack` undo /
  mute primitives, `BeatBridge` / `MelodyBridge`, groove capture and quantize,
  per-track instrument voicing, scene/arrangement concepts, periodic rendering,
  groove notation, and the shared Sound Library.
- **Refactor into Loop Studio:** Perform's recording/overdub flow, Loop Mixer's
  track cards, beat editor, tune editor, scene launcher, jam/follow tools, and
  the transport. Their symbolic data must become one editable track model.
- **Use as Tracker interop:** Beginner Tracker's approachable keyboard/grid
  ideas and Advanced Tracker's precise pattern/effect concepts. Tracker remains
  a separate top-level mode because tick/pattern authoring is a different job.
- **Replace:** duplicate Loop Mixer/Perform playback clocks, restart-based loop
  swaps, black-box tune/beat previews, hard-coded clef choices, and separate
  beginner/advanced persistence formats.
- **Archive behind a branch until parity is proven:** the current standalone
  Perform screen, current Loop Mixer screen, and Beginner Tracker screen. Do not
  delete them until Loop Studio passes transport, recording, editable-track,
  import/export, notation, and web smoke tests; then keep their useful pure
  primitives but remove their redundant navigation entries.

### Shared project boundaries

```
Project
├── Tracker patterns / instruments / effect commands
├── Loop Studio tracks / symbolic events / sections
├── Score parts / voices / metadata
├── Tab arrangements / tunings / fingerings
├── Audio tracks / clips / regions / automation
└── shared instruments, samples, FX, and export references
```

Interop is explicit: Tracker patterns can become Loop Studio tracks; Loop
Studio tracks can open in Tracker, Score, Tab, or Audio; Score and Tab can feed
pitched Loop Studio tracks; Audio can receive any mode as a clip and can return
through transcription/analysis with documented losses.

## Workstation parity — the executable ladder (scoped 2026-07-27)

The task breakdown of **[docs/WORKSTATION_PARITY.md](docs/WORKSTATION_PARITY.md)**.
That doc holds the *reasoning* (why the engines are ahead of the product, the
three structural gaps, the non-goals); this holds the *work*. Read the doc once
before pulling a task from here — several tasks below only make sense against
the gap they close.

**Audited against the code 2026-07-28** (`origin/main` @ `3a018344`). The D1–D4
Loop arc and the Audio swiss-army arc closed **12 of the original 39** between
the ladder being written and that audit, and narrowed three more — **27 remain
open.** Each closed item is marked where it sat, with the symbol that proves it.
(The audit first recorded WS-A6 as built-but-unpushed; `feature/daw-suite` has
since landed, so all 12 are on main.) **Re-audit before pulling anything
here** — this board moves under you, and half of what looks open may not be.

**How to read a task.** Every one is written so a fresh agent can pull it
without asking a question first: **Goal · Depends · Files · Build · Acceptance ·
Size**. Size is `S` (a session) · `M` (a day) · `L` (several days, split it).
Nothing here is claimed — take one, put your name on the board, push the claim
before you touch a shared file.

⚠️ **IDs here are `WS-`-prefixed on purpose.** This board already uses `L1`–`L6`
for the Loop Studio sequencer-parity slices, `A1`–`A4` for its automation
slices, `D1`–`D4` for the maintainer's Loop Studio decisions, and
`AUDIO_EDITOR_SUITE.md` uses `A1`–`A7`/`C1`–`C7` for its own ladders — all
different work. **`WS-L3` and `L3` are not the same task.** Grep with the
prefix.

**Two rules that apply to every task in this ladder, without exception.**
1. **The byte-identical guard.** Any task touching a render path must ship a
   test proving that a project *not* using the new feature renders byte-for-byte
   as before. This is the discipline that carried polymeter and automation
   safely; it is what makes an additive change provably additive.
2. **No mode loses its document.** `Project` (WS-W1) *wraps* the existing document
   types; it never absorbs or replaces them. A mode opened without a project
   must behave exactly as it does today.

### Phase 1 — the shell (fixes S1; everything after is cheaper)

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

- ✅ **WS-W2 — `TransportService`: one clock.** `M` · **SHIPPED 2026-07-28**
  (opus, workstation-parity). `lib/core/services/transport_service.dart`, 28
  tests. **The card below is the ORIGINAL, kept because its warnings still bind
  WS-W3 and the three migrations.** One decision it did not anticipate:
  - **The service does NOT own a clock — it is *advanced*.** `advance(deltaMs)`
    takes the elapsed ms from whoever is ticking. Forced by the code, not
    chosen: `loop_mixer_screen.dart` already documents the opposite as a
    problem ("the live grade reads a real Stopwatch, which widget tests can't
    advance"), and this card's own acceptance is a *headless* drive through
    play → loop wrap → stop. It also keeps each migration additive — a screen
    calls `advance` from the Ticker it already has, so no surface ever grows a
    second clock, which is the failure the ⚠️ below warns about. And the Audio
    Editor's playhead is deliberately driven by "the Ticker's own elapsed (NOT
    wall-clock)", which a wall-clock service would have silently contradicted.
  - **Meter lives here, not on `TempoMap`.** A TempoMap carries tempo only, and
    `bar` needs beats-per-bar. Adding meter to a model other surfaces persist
    would have been a change to shipped state for a derived readout, so
    `beatsPerBar` is on the transport. A real meter MAP is its own task.
  - `advance` returns a `TransportAdvance` (beats crossed, `looped`,
    `countInEnded`) rather than pushing a stream — the caller is already inside
    its tick and a metronome must click on *that* frame.
  - ⚠️ **Two traps found by writing the tests, both worth keeping:** a wrap must
    be **modulo**, not one subtraction (a dropped frame longer than the loop
    would otherwise leave the playhead past the end — visible only on a slow
    device); and beats either side of a wrap must be collected as **two runs**,
    or the metronome clicks on beats the playhead never visited.
  - ➕ **`syncTo(absoluteMs)` added 2026-07-28, and it is not a convenience.**
    The first migration found that the surfaces have not three clocks but two
    KINDS: the Tracker and Loop Studio own a monotonic **`Stopwatch`**, the
    Audio Editor uses the **Ticker's own elapsed**, explicitly "NOT wall-clock".
    `advance` ACCUMULATES deltas and therefore **drifts on every dropped frame**
    — pinned by a test where 500 frames of a 9.9 ms report against a 10 ms
    authority end 50 ms behind. A surface whose audio is a free-running
    pre-rendered WAV must TRACK its authority, not accumulate. Use `advance`
    when your own tick is the reference, `syncTo` when something else owns the
    phase.
  - ✅ **Tracker migrated (step 1 of 2) 2026-07-28.** `advanced_tracker_screen`
    publishes its Stopwatch phase and play/pause/stop into the shared transport
    (`_transport?.syncTo` / `play` / `pause` / `stop`), and `main.dart` now
    provides ONE app-wide `TransportService` + `UndoService`. Additive: the
    Stopwatch stays the authority, so tracker playback is unchanged and all 78
    of its tests pass. ⬜ **Step 2 — invert ownership** so the transport drives
    the tracker — is open, and only worth doing once a second surface is on it.
  - ✅ **Audio Editor migrated (step 1 of 2) 2026-07-28.** `daw_screen`
    publishes its playhead and play/seek/stop into the shared transport. It
    `pause()`s rather than `stop()`s, because this surface rests at the seek
    marker by design and the shared `stop()` rewinds to 0 / the loop start.
  - ❌ **CORRECTION — the rule written here on 2026-07-28 was WRONG.** It said
    "the Audio Editor is the one that needs `advance`, not `syncTo`". It does
    not. That was inferred from the comment "driven by the Ticker's own elapsed
    (NOT wall-clock)" without reading the tick body, which is
    `_seekMs + elapsed.inMilliseconds` — the Ticker restarts at 0 on play, so it
    is an **absolute read of an authority**, the same shape as the Tracker's
    Stopwatch. **The distinction is not Stopwatch-vs-Ticker; it is
    read-an-absolute vs accumulate-a-delta, and all three surfaces read an
    absolute.** So `syncTo` is the primary primitive and **`advance` has no
    consumer in the app today.** It stays because a caller holding only a delta
    is a real shape (a future real-time path), but nobody should reach for it
    now — and if the third migration also uses `syncTo`, `advance` is a
    candidate for deletion rather than a second-class citizen.
  - ✅ **Loop Studio migrated (step 1 of 2) 2026-07-28 — ALL THREE SURFACES NOW
    FOLLOW ONE CLOCK.** `loop_mixer_screen` publishes phase + play state via
    `syncTo`. Published **from the ticker, not from the play/stop sites**:
    `_clock` is started and stopped from five separate cascades in that file,
    and the ticker sees every state it can be in, so there is no site left to
    forget. The card's acceptance — "pressing play in the Tracker moves the
    Loop Studio playhead" — is now real rather than headless.
  - ❌ **I said I would DELETE `advance` if the third surface also used `syncTo`.
    It does, and I am NOT deleting it — the reason overrides the tidiness.**
    `advance` is the ONLY path that implements **count-in** (`_countInRemainingMs`
    is consumed there and nowhere else), and count-in is a named requirement of
    this card. Deleting it would have removed a required capability to remove an
    unused one. **The real finding is worse than an unused method and should not
    be lost:** the shared count-in is therefore **unreachable from any surface**,
    because all three publish through `syncTo`. ⬜ Either `syncTo` learns to hold
    for a count-in, or a migrating surface drives count-in explicitly — an open
    question for whoever does step 2.
  - ⬜ **Step 2 for all three — invert ownership** so the transport DRIVES the
    surfaces instead of mirroring them. Only now worth doing: with three
    publishers proven, the shape is known.

  **WS-W2 — the original card, for reference (NOT a task):**
  - **Goal.** Position, tempo, loop range, play/stop/record, count-in and
    metronome in one place every surface listens to. Today there are three
    clocks and none can follow another.
  - **Depends.** WS-W1 (for the project tempo map).
  - **Files.** New `lib/core/services/transport_service.dart`. `TempoMap`
    already exists and is the right seam — `daw_tempo_map.dart` gives
    `bpmAt`/`beatAtMs`/`msAtBeat`/`snapToBeat`/`beatTimes`.
  - **Build.** A `ChangeNotifier` owning position-in-ms, play state, loop
    range, record-arm and count-in; `beat`/`bar` derived through `TempoMap`.
    It **schedules**, it does not render — the offline render-then-play
    architecture is unchanged (see D-RT before assuming otherwise).
  - **Acceptance.** A headless test drives the service through play → loop
    wrap → stop and asserts bar/beat at each edge against `TempoMap`. Then the
    cross-surface one: **pressing play in the Tracker moves the Loop Studio
    playhead** — the assertion that proves the gap is actually closed.
  - ⚠️ Migrate the three existing clocks **one at a time**, each in its own
    commit, with that surface's tests green before the next. A big-bang clock
    swap is how playback regressions arrive invisibly.

- ✅ **WS-W3 — one transport bar widget.** `S` · **SHIPPED 2026-07-28**
  (opus, workstation-parity). `lib/shared/widgets/transport_bar.dart`, 18 widget
  tests. Play/pause · stop · record-arm · loop · bar.beat readout · tempo field ·
  undo/redo · metronome, all driven by `TransportService`; per-surface extras go
  in `trailing`. **The card below is the ORIGINAL.** Four things it did not say:
  - **The bar owns NO state**, so there is no `TransportBarState` — everything
    shown comes from the service and everything done is a call on it. That is
    what makes "two bars on one service agree" a test rather than a hope.
  - **Undo/redo are OPTIONAL CALLBACKS, not a `WS-W4` dependency.** The card
    says "driven entirely by WS-W2 + WS-W4", but blocking on an unbuilt W4 would
    have left three divergent bars standing for no gain. A surface passes its own
    undo today and passes W4's tomorrow; the widget does not change. A null
    callback HIDES the pair — a surface with no undo should not appear to have
    one.
  - **A tempo MAP makes the field read-only** rather than editable. An editable
    field over a multi-change map would throw away every tempo change the moment
    it was touched; instead it reports the tempo in force at the playhead.
  - **During a count-in the readout says so** instead of showing a frozen `1.1`,
    which reads as a hang.
  - ⚠️ **New l10n keys are `transport*`, deliberately neutral.** A shared widget
    cannot label itself `dawRedo`. Worth knowing what this replaces: the ARBs
    carry **six** redo keys (`daw`/`loopMixer`/`perform`/`tab`/`workshop`/
    `voiceLab`) for one button. Hosting the bar is what lets those be retired.
  - ⬜ **Not hosted in any screen yet** — same discipline as `WS-W2`. Hosting
    belongs with each surface's clock migration, one commit per surface.

  **WS-W3 — the original card, for reference (NOT a task):**
  - **Goal.** Kill three divergent transport implementations.
  - **Depends.** WS-W2.
  - **Files.** New `lib/shared/widgets/transport_bar.dart`; hosts are
    `advanced_tracker_screen.dart`, `daw_screen.dart`, `loop_mixer_screen.dart`.
  - **Build.** Play/pause · stop · record · loop toggle · position readout ·
    tempo field · count-in · undo/redo, driven entirely by WS-W2 + WS-W4. Per-surface
    extras go in a `trailing` slot, not in a fork of the widget.
  - **Acceptance.** A widget test mounts it once and asserts the controls drive
    `TransportService`; each of the three screens keeps its existing transport
    tests green after the swap.
  - ⚠️ The Loop Studio track-card row is **full** (a known 23 px overflow —
    see the audience-correction note above). Do not add controls to it.

- 🔶 **WS-W4 — one undo history.** `M` · **SERVICE SHIPPED 2026-07-28**
  (opus, workstation-parity), **fold-in still open.** `lib/core/services/
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
  - ⚠️ **The card's acceptance is NOT fully discharged.** It is worded at the
    screen level ("an edit made in Loop Studio is undoable from the Audio
    Editor's history list"). No screen is migrated, so that is proven headlessly
    with two adapters sharing one history. **The screen-level assertion lands
    with the migrations** — do not tick this card until then.
  - ⬜ **Fold-in, per surface, unclaimed:** `daw_service.dart`
    (`_undo`/`_redo`/`_Snapshot`, and its `_coalesceToken` maps onto
    `coalesceKey`), `loop_record.dart` (`LoopStack`), the tracker screen's block
    history. `maxEntries` defaults to 50 to match `DawService._maxUndo`, so that
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

### Phase 2 — the grammar (fixes S3; cheap, and every surface feels it)

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
- 🚧 **WS-L1 — keyboard support in Loop Studio.** `S` · **CLAIMED 2026-07-28 by
  opus (loop-d1d4).** Depends WS-T3.
  Space = play/stop, arrows = move the cell cursor, digits = velocity,
  Cmd/Ctrl+D = duplicate, Cmd/Ctrl+Z = undo. Acceptance: a widget test drives
  the grid entirely from the keyboard.

- ⬜ **WS-A3 — keyboard support in the Audio Editor.** `S` · Depends WS-T3.
  Four shortcuts today, on a surface that lives on shortcuts. Split · trim to
  selection · nudge · zoom · marker jump · solo/mute.

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
### Phase 3 — liveness (fixes the copy-not-link half of S1)

- 🔶 **WS-X1 — live links, not copies.** `L` · **STEP 1 SHIPPED 2026-07-28**
  (opus, workstation-parity). `lib/core/project/project_link.dart` + the Tracker
  using it; 5 tests in the tracker suite.
  - **The rule, and it is one line:** a **same-kind open needs no conversion at
    all.** The copy existed only because every "Open in…" went through
    `ProjectBridge.convert`, which is right for a KIND CHANGE and wrong for
    opening a tracker song in the Tracker. `ProjectLinker.open` returns the
    track's own document with `live: true`; `writeBack` puts the edit in the
    same track via `ProjectService.updateDocument`, keeping id, name and **mix**.
  - **A different-kind open is UNCHANGED** — still converts, still copies, still
    carries `ProjectBridge`'s loss report, and reports `trackId: null` so a
    caller cannot write a lossily-converted document back over the original.
  - An **unreadable** track (carried verbatim from a newer build) is refused
    with a readable reason rather than handed to an editor as raw JSON.
  - ⚠️ **Step 1 deliberately included WIRING, not just the seam** —
    `addSongToProject` / `openProjectTrack` / `writeBackToProject` on the
    Tracker. Shipping the seam alone would have made this the THIRD card
    complete-and-unreachable (see the count-in and `Project` findings).
  - ⬜ **Step 2 — the other surfaces + the UI.** Loop Studio, the Audio Editor,
    Score and Tab need the same three calls, and `OpenInMenu` should offer
    project tracks and say "editing the project track" versus "editing a copy"
    from `ProjectLink.live`. Nothing in the UI surfaces this yet.
- ⬜ **WS-X2 — drag between surfaces.** `M` · Depends WS-W1, WS-X1.
  One `DragTarget` protocol carrying `(kind, document)`: drag a tracker pattern
  onto the timeline, a loop track into the Tab editor, an instrument from the
  browser onto any track. Show the loss report **on drop** when kinds differ.
  Acceptance: a drop of each supported pair lands an editable track, and a
  lossy pair shows its report before committing.

### Phase 4 — the console

- ⬜ **WS-W5 — the mixer console.** `M` · Depends WS-W1, WS-W2.
  One strip per project track of **any** kind: level · pan · mute · solo ·
  inserts (the shared `FxRack`) · sends · meter. This is a generalization of
  shipped code, not new DSP — `daw_screen.dart` already has `_busMixerMatrix`,
  `_levelMeter` and the bus editor. Acceptance: a project with one track of
  each kind shows four working strips, and a solo is audible in the render.

- ⬜ **WS-W6 — the browser.** `M` · Depends WS-W1.
  One panel: projects · templates · instruments (shared Sound Library) ·
  samples · FX presets (chain strings) · the licensed asset catalog. Drag from
  it onto any surface (WS-X2). This is where the asset catalog finally meets the
  authoring modes.

- 🔶 **WS-X3 — the shared FX rack in the LAST mode.** `S` · **Narrowed by the
  audit: this is four-fifths done.** `shared/widgets/fx_rack.dart` is already
  hosted by Loop Studio, the Tab Workshop and the Tracker, and the Audio Editor
  has the equivalent through its own `DawClipEffectType` editor (68 sites). The
  one mode with **no** effect surface at all is **Score** — nothing in
  `composition_workshop_screen.dart` touches `FxRack` or `FxSpec`. Host the
  rack there, with the **chain string** as the interchange format so a chain
  travels with the part. (`AUDIO_EDITOR_SUITE.md` C7.)
  ⚠️ Worth a deliberate call while you are in there: the Audio Editor's own
  enum and the shared `FxSpec` are two vocabularies for one rack. Unifying them
  is a bigger job than this task and should not be smuggled into it.

> ✅ **WS-X4 SHIPPED** — `DawService.trackSend`/`setTrackSend` (plus
> `setTrackSendForTracks` for a multi-selection) send a whole lane to a bus, and
> `busSends` carries bus→bus. The item was written from
> `AUDIO_EDITOR_SUITE.md` C6, which was already stale when the ladder was
> drafted.

### Phase 5 — per-surface depth (pull in any order; all independent)

**Loop Studio** — see also the L/D backlogs above, which these do not duplicate.

> ✅ **WS-L3 · WS-L4 · WS-L6 · WS-L7 · WS-L8 · WS-L9 SHIPPED** (audited against
> `origin/main` 2026-07-28, after the D1–D4 arc landed). Session grid =
> `_sceneGrid` · queued launch = `_pendingScene` · per-track filter =
> `_trackFilters`/`setTrackFilter` **with `AutomationParam.filter` now
> rendering** · section repeats = `renderArrangement(repeats:)` · add/rename =
> `addEmptyTrack`/`renameTrack` + the role-add row · per-track swing =
> `trackSwings`. Six of the ten Loop items closed in one arc.

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

- ⬜ **WS-L2 — a timeline VIEW for Loop Studio, then zoom it.** `M`→`L` —
  **re-audited 2026-07-28 (loop-d1d4): the card assumed a ruler that does not
  exist.** Zoom is still 0 hits, but so is the thing it would zoom: Loop Studio
  has **no timeline** — one incidental `timeline` match in the whole
  5,600-line screen, which is cards, step grids and a session matrix. So this is
  not "add zoom to the ruler", it is "design a timeline view for a surface built
  out of grids, then zoom it", with a product decision in front of it (does the
  session matrix become a timeline, or sit beside one?). Do not pull it as an
  `M` of plumbing.
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

**Audio Editor**

> ✅ **WS-A2 · WS-A4 · WS-A8 SHIPPED and on `origin/main`** — time selection +
> ripple (`rippleDelete`/`rippleInsert` + a marked range in the screen), clip
> groups + nudge (`groupId`, `76a7411e`), per-clip gain envelope
> (`clipGainAutomation`/`clipEnvelopeAt`). Record:
> **[docs/HISTORY.md](docs/HISTORY.md) → "Audio Editor → swiss-army knife"**.
>
> ✅ **WS-A6 (take lanes + comping) and the SRC half of WS-A9 have now LANDED**
> — `feature/daw-suite` merged after its chunked full-suite gate came back
> green (5,475 pass / 0 fail across six chunks). The "built but not on main"
> caveat that stood here is discharged.

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
**Tracker**

> ✅ **WS-T5 SHIPPED** — `TrackerEngine.setChannelFxChain` + the screen's
> `channelFxChain`; a tracker channel carries a real `List<FxSpec>` chain.

- ⬜ **WS-T1 — eased playhead follow.** `S` — still open: `_playFrac` tracks the
  sub-row position but the follow scroll is `_vScroll.jumpTo` (two sites).
- ⬜ **WS-T2 — pattern-matrix overview.** `M` — a block-per-pattern bird's-eye of
  the order list with drag-to-reorder, so a 64-pattern song is navigable.
- ⬜ **WS-T4 — a piano-roll view of one channel.** `M` — the app still has **no**
  continuous piano roll anywhere (`pianoRoll`: 0 hits). The tracker grid is
  exact and unapproachable; `StepGridView` is approachable and quantized.
  One channel, one roll, same document. The biggest legibility win for a
  newcomer opening a module.
- ⬜ **WS-T6 — pattern-level time signature / groove templates.** `M`.
- ⬜ **WS-T7 — record into a pattern from the transport.** `M` ·
  Depends WS-W2, WS-X5.

### Phase 6 — reach

- ⬜ **WS-X5 — MIDI and controller input.** `L` — no MIDI input exists
  (`MidiDevice`: 0 hits). One MIDI-in seam feeding **any** surface's record
  path, plus a shared on-screen keyboard/pad widget for platforms without
  hardware. Prerequisite for WS-T7 and for D-RT option B.
- ⬜ **WS-X6 — one export sheet.** `M` — every mode exports differently. One sheet:
  stems · master · symbolic (MusicXML/MIDI/module) · project archive · share
  token. The codec matrix is already in `docs/AUDIO_CODEC_MATRIX.md`.
- ⬜ **WS-W7 — session ⇄ arrangement.** `L` · Depends WS-W1, WS-W5, WS-L3.
  Loop Studio's
  scenes are already a session grid and the Audio Editor is already a linear
  arrangement; make them two views of one project, and record scene launches
  into the arrangement.

### The decision that gates part of this ladder

- 🔶 **D-RT — do we add a bounded real-time *preview bus*?** **Needs the
  maintainer.** Full reasoning and the three-option table are in
  `docs/WORKSTATION_PARITY.md` §8. Short version: playback is offline
  render-then-play by design, which buys byte-identical renders, headless CLI
  tests and web parity — and costs input monitoring, play-in-context and live
  knob feedback. The recommendation is **option B**: an *additive* real-time
  path for monitoring and played notes only, while the timeline keeps playing
  its rendered buffer and mixing/export stay offline and exact. **Decide before
  Phase 3; build after Phase 4 if B.** Nothing in Phases 1–2 depends on it.

### Cheap wins — no phase, no dependency, pull any time

**WS-A1** (clip trim/fade handles) · **WS-T1** (eased playhead follow) ·
**WS-A5** (loudness view) · **WS-L5** (duplicate a scene or a pattern) ·
**WS-X3** (the rack in Score, the last mode without one).

*(WS-L3, WS-L4 and WS-L7 were on this list and all three shipped in the D1–D4
arc — which is the argument for the list.)*

## Cross-mode FX + interop consolidation (SHIPPED — all 12 items, `feature/fx-interop`)

**Why.** The five modes each grew their own FX vocabulary and their own
converters over what is already *one* shared DSP library (`lib/core/audio/
crisp_dsp/`, 20 modules) and *one* shared notation model (crisp_notation
`Score`/`MultiPartScore`). The result is four incompatible effect models, five
copies of `pitchFromMidi`, two copies of the duration ladder, and an interop
graph with holes (no Tab↔Tracker) where every edge silently drops whatever the
target model cannot express.

**Audit (2026-07-26, measured on `origin/main`).**

| FX model | Mode | Types | Params | Automation | Serialized | Chain |
| --- | --- | --- | --- | --- | --- | --- |
| `DawClipEffect` / `DawClipEffectType` (`daw_timeline.dart`) | Audio | 27 | ✅ `Map<String,double>` | ✅ | ✅ JSON | ✅ |
| `TrackerChannelEffect` (`tracker_engine.dart`) | Tracker | 7 | ❌ hardcoded | ❌ | name only | ✅ |
| `VoiceEffect` (`crisp_dsp/voice_fx.dart`) | Instrument | 9 | ❌ hardcoded | ❌ | ❌ | ❌ |
| `TrackEffect` (`daw_timeline.dart`, legacy) | Audio | 7 | via bridge | ❌ | ❌ | ❌ |
| — | Tab | **0** | — | — | — | — |
| ad-hoc sends (`loop_engine.dart`) | Loop | partial | ❌ | in `GrooveSpec` | ❌ |

`DawClipEffect` is a strict superset of the other three and is the only one with
params, automation, and persistence. It is therefore the **canonical model**;
the other enums become *preset name* lookups that resolve to a chain.

**Interop edges.** Present: Score↔Tracker (`tracker_notation.dart`,
`multipart_to_tracker.dart`), Score↔Module MOD/XM/S3M/IT (`mod/
module_notation.dart`), Score↔Tab (`TabDocument.toScore`/`.fromScore`),
Beat→Tracker (`beat_to_tracker.dart`), Loop→Score (`groove_notation.dart`,
`melody_bridge.dart`). Missing: **Tab↔Tracker**, **Loop↔Tab**, and a single
entry point with a **documented loss report**.

**Two design decisions that the whole arc rests on.**

1. *One FX rack.* `FxSpec { FxType type; bool enabled; Map<String,double>
   params; Map<String,List<FxAutomationPoint>> automation }` plus
   `applyFxChain` / `applyFxChainStereo`, living mode-neutrally in
   `lib/core/audio/fx/`. Every mode holds `List<FxSpec>`. Legacy enums survive
   as presets, so no persisted file breaks.
2. *Lossless side-car.* A converter that cannot represent something in the
   target model must not drop it. `SymbolicAnnotations` is a bag keyed by a
   stable event address (`track/channel/part` + `step/tick` + `voice`) carrying
   the un-representable payload (string+fret, technique, capo, tracker fx
   command, lyric, articulation). Round-trip identity then becomes a *testable
   property*, not a hope.

### Ordered work items

Each item is independently shippable and independently testable. Build in
order; A1 and B1/B2 unblock everything else.

#### A — one FX rack across all five modes

- **A1. Extract the FX engine into `lib/core/audio/fx/`.** *(unblocks A2–A6)*
  - New `fx/fx_spec.dart`: `FxType` (the 27 `DawClipEffectType` members, same
    names, same order), `FxSpec`, `FxAutomationPoint`, `FxPreset`,
    `defaultFx(FxType)`, `fxPresetChain(FxPreset)`, `toJson`/`fromJson`,
    `cacheKey`.
  - New `fx/fx_chain.dart`: `applyFxChain(Float64List, List<FxSpec>, int
    sampleRate)` and `applyFxChainStereo(...)`, moved verbatim from
    `daw_timeline.dart` (`applyClipEffectChain`, `_applyClipEffect`,
    `_applyStereoClipEffectChain`, `_applyAutomated*`).
  - `daw_timeline.dart` keeps the old names as aliases —
    `typedef DawClipEffect = FxSpec;`, `typedef DawClipEffectType = FxType;`
    (Dart allows typedefs to enums), `const defaultDawClipEffect = defaultFx;`,
    `const applyClipEffectChain = applyFxChain;` — and re-exports `fx/`.
    **No call site in `daw_service.dart` / `daw_screen.dart` changes.** This is
    deliberate: those files are hot with parallel DAW agents.
  - Done when: `daw_timeline.dart` contains no DSP dispatch; the DAW suite is
    green unchanged.
  - Tests (`test/fx_spec_test.dart`, `test/fx_chain_test.dart`): every `FxType`
    round-trips JSON; unknown type name → `null`, not a throw; `enabled:false`
    is bit-identical identity; an empty chain is identity; each type on a
    1 kHz sine is finite and within ±1.0; `cacheKey` is stable across equal
    chains and differs on any param change.

- **A2. Tracker channel FX become `FxSpec` chains.**
  - `TrackerChannel.fxChain: List<FxSpec>` alongside the existing
    `effects: List<TrackerChannelEffect>`; `fxForChannelPreset(e)` maps each of
    the 7 presets to the params currently hardcoded in `applyChannelEffect`.
  - `tracker_song_codec.dart` writes `fxChain` (full params) and still reads
    legacy `effects: ['reverb', …]`; a file written by the old codec loads to
    the equivalent chain.
  - Render path prefers `fxChain` when non-empty, else the legacy list.
  - Tests: for all 7 presets `applyFxChain(stem, fxForChannelPreset(e))` is
    **sample-identical** to `applyChannelEffect(stem, e)`; a legacy
    `.cbtrk` fixture loads and renders identically; chain length is preserved
    (the `mixStems` same-length invariant).

- **A3. Instrument / Voice FX become `FxSpec` chains.**
  - `fxForVoicePreset(VoiceEffect) → List<FxSpec>` for all 9 presets.
  - Instrument Builder (`instrument_editor.dart`) gains a free-form chain on
    top of the preset, persisted with the instrument
    (`tracker_instrument_codec.dart`).
  - Tests: for all 9, `applyFxChain(s, fxForVoicePreset(v))` is sample-identical
    to `applyVoiceEffect(s, v)`; `kPitchPreservingVoiceEffects` members still
    round-trip a pitch probe within 5 cents after the chain.

- **A4. One FX rack widget.** `lib/shared/widgets/fx_rack.dart` +
  `lib/core/audio/fx/fx_params.dart` (a descriptor table: per `FxType`, the
  param list with min/max/default/unit/l10n label key).
  - The rack renders add / remove / reorder / bypass plus one slider per
    descriptor — **driven entirely by the table**, so a new `FxType` needs no
    UI edit.
  - Hosts: DAW inserts, Tracker channel FX, Instrument Builder, Loop Studio
    sends, Tab track FX.
  - Tests: `fx_params_test.dart` asserts every `FxType` has a descriptor and
    every descriptor default equals `defaultFx(type).params`; widget test adds
    reverb → tweaks `roomSize` → reorders → bypasses and asserts the emitted
    chain.

- **A5. Loop Studio sends become `FxSpec`.** `GrooveSpec` gains a per-track
  chain; the `KU1.` share token stays backward compatible (absent key = no FX).
  - Tests: token round-trip with and without FX; a spec without FX renders
    byte-identically to today (regression guard on the seam-click invariant).

- **A6. Tab gets FX.** `TabTrack.fxChain`; tab playback routes
  `renderMultiPartWithInstrument` output through `applyFxChain`. Ship a guitar
  preset set (clean / crunch / overdrive / chorus / spring reverb / wah) as
  `FxPreset` entries, so this is data, not new DSP.
  - Tests: preset chains are non-empty and length-preserving; a tab with an
    empty chain renders byte-identically to today.

#### B — symbolic core DRY

- **B1. One `pitchFromMidi`.** `lib/shared/midi_pitch.dart` already holds the
  canonical version. Delete the copies in `mod/module_notation.dart`,
  `tracker_notation.dart`, `tab_document.dart`, `groove_notation.dart` and
  import it. Keep a per-file re-export only where the symbol is part of that
  file's public surface.
  - Tests: `midi_pitch_test.dart` covers all 128 MIDI numbers (step, alter,
    octave), and asserts the four ex-copies' call sites still spell identically.

- **B2. One duration ladder.** New `lib/shared/music/step_duration.dart` with
  `durationToSteps`, `durationLadder(stepsPerBeat)`, `decomposeSteps`. Delete
  the verbatim copies in `mod/module_notation.dart` and `tracker_notation.dart`;
  point `tab_document.dart`'s `kTabDurations`/`_stepsOf` at it.
  - Tests: golden decompositions for 1..64 steps at stepsPerBeat 1/2/4/8;
    `decomposeSteps` always sums back to the input; parity assertions against
    the pre-refactor outputs for both ex-copies.

#### C — the interop matrix

- **C0. `lib/core/interop/symbolic_annotation.dart` — the side-car.**
  - `EventAddress { int track; int step; int voice; }` (stable, comparable),
    `SymbolicAnnotations` = `Map<EventAddress, Map<String, Object?>>` with typed
    accessors for the known keys (`string`, `fret`, `technique`, `capo`,
    `fxCmd`, `fxParam`, `lyric`, `articulation`, `velocity`).
  - JSON round-trip; merge; `restrictToTrack`.
  - Tests: round-trip, address equality/hash, unknown keys survive untouched.

- **C1. Tab ↔ Tracker, direct and lossless.** `lib/core/interop/tab_tracker.dart`.
  - `trackerSongFromTabDocument(TabDocument) → (TrackerSong, SymbolicAnnotations)`
    — **one tracker channel per string**, which is the natural mapping and makes
    string/fret survive *natively* rather than via the side-car.
  - `tabDocumentFromTrackerSong(TrackerSong, {SymbolicAnnotations?}) → TabDocument`.
  - Technique mapping where a native tracker command exists: slide →
    portamento (`3xx`), vibrato → `4xx`, hammer/pull → legato (no retrigger),
    bend → pitch slide; everything else rides the side-car.
  - Tests: **round-trip identity** on a fixture `TabDocument` (columns,
    string/fret, techniques, tuning, capo) with and without annotations; a
    slide really becomes a portamento cell; a 6-string tab yields 6 channels.

- **C2. Loop ↔ Tab.** Via `Score` + annotations, reusing C0/C1 and the existing
  `groove_notation.dart`. Pitched loop tracks become a tab arrangement using
  `tab_arranger.dart`'s fretting plan; a tab becomes a pitched loop track.
  - Tests: a pitched groove → tab → groove preserves pitches and step grid.

- **C3. `lib/core/interop/project_bridge.dart` — one façade + loss report.**
  - `enum AppMode { tracker, loop, score, tab, audio }`.
  - `ConversionResult { Object? document; SymbolicAnnotations annotations;
    ConversionReport report; }` where `ConversionReport { List<String> lost;
    List<String> approximated; bool lossless; }`.
  - `convert({required AppMode from, required AppMode to, required Object doc})`
    dispatches to the existing converters (C1, `tracker_notation`,
    `module_notation`, `TabDocument.toScore`, `multipart_to_tracker`,
    `daw_sources`) — it **adds no new DSP or notation logic**, it is routing
    plus honest reporting.
  - Tests: a matrix test over all 25 `(from,to)` pairs — each either produces a
    document or reports `unsupported`; **no pair throws**; identity pairs are
    lossless; every lossy pair names what it lost.

- **C4. "Open in…" everywhere.** `lib/shared/widgets/open_in_menu.dart`, driven
  by `ProjectBridge`, shown in all five mode toolbars; it previews the loss
  report before converting ("Tab → Tracker keeps string/fret; bends become
  pitch slides").
  - Tests: widget test — the menu lists exactly the modes the bridge can reach
    from the current mode, and the report text renders.

### D — finishing the interchangeability map (SHIPPED, `feature/fx-interop`)

> D1–D3 done, and **E1–E4 wire it all into the screens**: the shared `FxRack`
> now hosts in the Tracker's channel-effect sheet (E1), a new per-track Tab
> guitar rig (E2) and the Loop Mixer's master bus (E3), and the shared
> `OpenInMenu` is in the Tab and Advanced Tracker toolbars (E4).
>
> Two things learned wiring it, worth keeping: (a) `OpenInMenu` needed a
> `targets` filter, because CONVERTING and OPENING are different problems — the
> bridge can produce a document for every reachable mode, but a screen can only
> offer a destination it has a route to push, and offering one it cannot open
> would convert the user's work and then drop it. (b) Every FX host is additive:
> the legacy preset path (7 tracker chips, 2 loop sends) stays as the quick
> path and still renders through the old code, so no saved project changes how
> it sounds.
>
> **Not wired, deliberately:** `daw_screen.dart` — daw-ux owns its FX UI and it
> already has one; and Loop's own "Open in…" (the Loop Mixer already has a
> hand-rolled "Open in Tracker" round-trip that auto-publishes on exit, which is
> richer than the generic menu — replacing it is that agent's call, not mine).

C1–C4 built the matrix, but two edges are still second-class and one section of
the Tracker roadmap below (§2 *Ecosystem Interchangeability*) is only half
wired. All three are the same shape: a converter exists in ONE direction, so the
reverse either does not exist or detours through a mode that distorts it.

- **D1. Direct Tracker <-> Loop, symbolically.** Today the Loop Mixer's "Open in
  Tracker" goes `Loop -> Score -> Tracker` (`trackerSongFromMultiPart`), and
  C3's `tracker -> loop` edge goes via **Tab** — which fret-maps everything onto
  six strings. That is fine for a guitar part and wrong for a piano or drum
  channel. Add `lib/core/interop/loop_tracker.dart`:
  `loopCellsFromTrackerChannel` / `trackerChannelFromLoopCells`, both symbolic
  (a `PatternCell` run <-> a channel's cells), and repoint C3's two tracker/loop
  edges at it.
  - Both models are already a monophonic-per-step grid, so the only real work is
    the grid ratio: a loop step is an eighth, a tracker row is
    `1 / timing.stepsPerBeat` of a beat. Whole-number ratios are exact; anything
    else quantizes and must say so.
  - Tests: round-trip identity at matching grids; a 4-steps-per-beat tracker
    song halving cleanly onto the loop grid; velocity and chords surviving;
    the report naming the quantization when the ratio is not integral.

- **D2. Tracker percussion -> DrumKit** (PLAN.md §2.2's missing half).
  `beat_to_tracker.dart` already turns a `SharedBeat` into percussion channels;
  nothing reads them back, so a beat edited in the Tracker cannot return to the
  Drum Kit. Add `sharedBeatFromTrackerSong` in
  `lib/core/interop/drum_tracker.dart` — the exact inverse, so round-trip
  identity is a testable property rather than a hope.
  - Tests: `beat -> song -> beat` is identity (rows, tempo, swing, per-drum
    voices); a song with no percussion channel yields null rather than an empty
    beat; a channel edited in the Tracker shows up in the returned rows.

- **D3. §2.3 is already done** — `tab_tracker.dart` (C1) is exactly the
  "translate plucked-string channels into Tab strings" item, and does it better
  than the roadmap asked (one channel per string, so the mapping is native
  rather than re-derived from pitch). Marked below.

### Collision policy for this arc

`daw_timeline.dart`, `tracker_engine.dart`, `tracker_song_codec.dart`,
`loop_engine.dart`, and `tab_document.dart` are all hot with parallel agents.
Every item above is therefore **additive with legacy aliases kept**: no call
site is rewritten in the same commit that moves code. Claim on the
`docs/PLAN.md` board before each item, and push after each.

## Tab Editor navigation (DONE)

- Add a three-dot overflow menu to the Tab Editor and move lower-frequency
  actions out of the crowded top bar.
- Keep transport, import, save, and primary editing controls immediately
  reachable; put inspect mode, clear/reset, and future utility actions in the
  overflow menu.
- Ensure every menu action has an explicit effect in the editable tab document,
  rather than only changing a label or preview.

Implemented in `7e05bd55`, `62efa301` and covered by `test/tab_workshop_test.dart`:
the overflow menu owns utility actions, chord picking changes voicing/playback,
and the no-op Demo riff action was removed.

## Architecture (done, `feature/pitch-detection-spike`)

```
mic (record plugin) ─┐
WAV file ────────────┼─→ StreamingAudioAnalyzer ─→ PitchReading  (mono, MPM/NSDF)
stdin PCM (CLI) ─────┘        (sliding window)   └─→ ChordReading  (chromagram+templates)
```

- `core/audio/pitch_analysis.dart` — McLeod Pitch Method detector → note + cents.
- `core/audio/chroma_analysis.dart` — FFT + chromagram + fuzzy chord templates.
- `core/audio/streaming_analyzer.dart` — pure-Dart windowing, shared by mic + CLI.
- `core/audio/microphone_pitch_service.dart` — the only plugin-facing file.
- `core/audio/wav_io.dart` — PCM16 WAV reader.
- `bin/listen.dart` — CLI: `--wav`, `--stdin` (live), `--selftest`, `--chords`.
- `core/audio/play_along.dart` — scoring engine for play/sing-along (see below).

Detectors are proven headlessly (synth-based unit tests, all green) and via the
CLI on real audio; the mic path is verified on macOS. Only the live *acoustic*
feel (latency, real-instrument chord accuracy) still wants on-device tuning.

## Modes & games

### 1. Tuner — DONE (real)
Chromatic/cello tuner: big note, cents needle, in-tune zone. Cello-first
(fretless intonation is where it matters). Keeper tile.

### 2. Play-along (moving score) — DONE
Target notes are scored against your live pitch (correct pitch within a cents
window for enough of a note's duration = hit); `PlayAlongEngine` is pure-Dart
and unit-tested. **Four switchable scroll views** (a menu in the app bar):
highway (piano-roll), falling (vertical), notation (real engraved staff +
moving cursor, via crisp_notation), and coach (big current/next note for beginners).
Cello/guitar/keyboard charts + count-in metronome.

### 3. Sing-along — DONE (v1)
The same engine + screen with a vocal-range melody preset. Voice is the same
monophonic detection; only the chart/labelling differs.

### 4. Chord listener — DONE (spike)
Names the chord you strum/play with runner-up guesses + a chroma bar chart.

### 5. Chord-progression play-along — DONE
A moving chord chart (C–G–Am–F): strum the progression as it scrolls; each
chord is scored by the fuzzy ChordDetector (`ChordProgressionEngine`, top-2
lenient match). Records to ProgressService + stars. Validated end-to-end via
the BlackHole loop — all four roots detected on real captured audio (the
7th/maj7 variants are expected overtone pickup, hence the lenient match).

## Songbook — scan sheet music into playable songs (DONE — audited 2026-07-26)

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

## Audio codecs — what remains

Import/export is **DONE and at parity across native and web** (shipped
2026-07-26; see [docs/HISTORY.md](docs/HISTORY.md) and the canonical table
[docs/AUDIO_CODEC_MATRIX.md](docs/AUDIO_CODEC_MATRIX.md)). What is left:

- **FLAC encode — not planned.** glint decodes FLAC and ships no FLAC encoder.
  Writing one is a real project, and nothing in the app asks to write FLAC.
- **Vorbis encode — scoped, unclaimed, probably not worth it.** Redundant for
  export (Opus wins at every bitrate; two `.ogg` producers is a UX trap). The
  ONLY genuine trigger is **writing `.sf3` SoundFonts**, which are Vorbis by
  definition — today we can only read them. Full handover with the clean-room
  affidavit, an 8-slice plan and an honest cost estimate lives in the **glint**
  repo: `docs/VORBIS_ENCODER_HANDOVER.md`. Do not start it unless SoundFont
  authoring is actually wanted.
- **AIFF is read-only.** We parse AIFF/AIFF-C and never write it. ~40 lines of
  pure Dart if the symmetry is ever wanted; nothing requests AIFF output today.
- **Native MP3 is not the default.** Both encoders ship and the export sheets
  let you pick; the default stays the pure-Dart one because its output is what
  the golden/ffmpeg tests pin and it is identical on every platform. Flipping it
  is one line once glint's has mileage here.
- **Per-platform builds are CI's job now**, not a manual chore:
  `.github/workflows/glint-native.yml` covers all five platforms plus the wasm,
  and `ci.yml`'s `android-build` asserts the codec is actually inside the APK.

## Known constraints / follow-ups (not yet done)
- **Tracker→editors sweep — 2 items handed to `daw-suite`** ✅ **BOTH DONE**
  (2026-07-27, per maintainer; the sweep itself is in
  [docs/HISTORY.md](docs/HISTORY.md)). They lived in the DAW/export surface, so
  they were handed off to avoid collisions, then implemented additively:
  - ✅ **DAW bounded-memory save (`6cc269ab`).** New web-safe `stream_save.dart`
    seam (io/stub conditional import); `showAudioExportSheet` gained an optional
    `WavStreamProducer`; `_exportAs` streams the WAV to disk via `streamTimelineWav`
    → `streamBytesToFile` for the plain full-mix WAV / native-rate / 16-bit /
    no-dither case (guarded on `!stem && !range && !normalize`), so *Save* stops
    calling `bakeStereo()`+whole-file-in-RAM there. Web + every other choice fall
    back to the in-memory bake (unchanged). Byte-identical output; seam-tested.
  - ✅ **Export dither (`128eec8c`).** Optional deterministic (fixed-seed) TPDF
    dither in `pcmFloatToWav` (default off → byte-identical) + a 'Dither' sheet
    toggle (WAV only), threaded through `build`/`_exportAs`. +4 tests.
- **Backing audio vs. mic (AEC):** see the dedicated section below — count-in
  metronome + optional backing (tiers 0/1) shipped; a Dart AEC core is the next
  step; a native full-duplex plugin is the production fix.
- **Localization:** DONE — the four modes have de/en `AppLocalizations` keys,
  and the tuner/chord/play-along note readouts respect the note-naming setting
  (German H, solfège) via `spelledMidiName`. Chart names + the Hz/clarity
  readout stay language-neutral.
- **Progress/stars:** DONE — play/sing/guitar/keyboard play-along record to
  `ProgressService` (score = notes hit) with `kStarThresholds` brackets and a
  `GameResultView` (stars + Play again) on finish.
- **Real-instrument tuning:** validated end-to-end through the real macOS audio
  stack via a **BlackHole loopback** self-test (sox plays a scale to the
  BlackHole *output* device; ffmpeg captures the BlackHole *input*; the CLI
  detects it). Recovered a full C-major scale within a few cents — thresholds
  held on real captured audio, no retune needed. Reproduce:
  ```bash
  ffmpeg -f avfoundation -i ":<BlackHole idx>" -t 8 -ar 44100 -ac 1 bh.wav &
  sox scale.wav -t coreaudio "BlackHole 2ch"          # non-intrusive; default device untouched
  dart run bin/listen.dart --wav bh.wav
  ```
  **Robustness characterized** headlessly (`test/pitch_robustness_test.dart`):
  the detector holds pitch through ±20-cent 5-6 Hz **vibrato** (within 25¢), never
  reports a WRONG note as **noise** rises (it gives up gracefully, surviving to
  ≥0.25 noise amplitude), detects soft (pp) dynamics while gating out silence,
  and stays on the fundamental for **rich/bright timbres** (no octave errors).

  **The real-acoustic-instrument-into-a-physical-mic pass is human-gated** (needs
  someone to actually play). On-device protocol:
  1. Cello/guitar/voice → open the **Tuner**; sustain each open string / a sung
     note. Expect the right note, needle steady, cents within a few of a
     reference tuner.
  2. **Play along** a slow chart (½× tempo); confirm hits register and the live
     dot tracks. 3. **Chord listener**: strum open chords; confirm the top guess.
  4. Note failure modes (bow noise, breath, room reverb, low SNR) for tuning
     `clarityThreshold`/`energyGate` against real signal.
- **Phase 3 (full polyphonic transcription):** still out of scope; would layer
  on the same chromagram.

## Backing audio & echo cancellation (AEC)

Goal: play audible backing through the speaker *during* play/sing-along without
the mic grading the speaker. Two corrections shape the design:
1. **Pitch-domain gating is self-defeating here.** In play-along the user
   *matches* the backing, so echo and desired signal share the same pitch — you
   can't gate "the backing's pitch" without gating the user. Real cancellation
   must be **waveform-domain** (subtract a reference-derived echo estimate).
2. **A pure-Dart AEC starves on alignment.** `audioplayers` (out) and `record`
   (in) are two plugins on two clocks — no shared timebase. The *algorithm*
   ports fine (we have an FFT); the *deployment* needs sample-accurate ref+mic,
   which only an OS-integrated or native full-duplex path provides.

### Tiers
- **Tier 0 — headphones (DONE).** No acoustic coupling → backing works with zero
  AEC and zero pitch loss. Backing toggle plays the melody at the downbeat;
  label says "use headphones". The clean answer for real practice.
- **Tier 1 — platform AEC (DONE).** Backing toggle also flips on
  `RecordConfig.echoCancel` (iOS VoiceProcessingIO / Android VOICE_COMMUNICATION
  / macOS voice-processing). Real OS AEC, but its AGC/NS reshape the waveform and
  cost pitch accuracy. **Needs on-device measurement** (can't be tested via the
  BlackHole digital loopback — no speaker→mic path).
- **Tier 2 — Dart pitch gate: SKIPPED** (self-defeating for play-along, per #1).
- **Tier 3a — Dart AEC core (BUILT + VERIFIED; blocked on 3b for deployment).**
  `core/audio/echo_canceller.dart`: a compact **constrained frequency-domain
  block-NLMS** echo canceller (the linear core of Speex MDF / WebRTC AEC3),
  reusing the FFT. Its stated verification exists — `test/echo_canceller_test.dart`
  asserts high ERLE on an echo-only mix and near-end preservation under
  double-talk (verified 2026-07-26). Nothing is left to write here: deployment
  needs Tier 3b to feed it aligned ref+mic, which is the real blocker.
- **Tier 3b — native full-duplex plugin (DESIGNED, not started in code).** One
  native audio engine that owns playback+capture on a shared clock and runs a
  real AEC. This is the production fix. Full architecture, Dart API, per-platform
  build, CI-safety rules and verification plan: **[docs/AEC_TIER3B.md](docs/AEC_TIER3B.md)**.
  Stack: **miniaudio** (MIT-0, full-duplex host) + **SpeexDSP** (BSD, the AEC).
  Days–weeks; must be built in an isolated branch and kept out of the app's
  pubspec until it compiles green on all 5 CI platforms.
- **Tier 4 — neural (IF NEEDED).** `DTLN-aec` (MIT, TFLite, tiny, on-device) or
  `DeepFilterNet` (MIT/Apache). Watch: speech-trained nets may not preserve a
  sung/played note's *pitch*.

### Permissive libraries (all BSD/MIT/Apache — usable or portable)
SpeexDSP echo canceller (BSD, port/FFI) · WebRTC AEC3 / webrtc-audio-processing
(BSD, FFI) · DTLN-aec (MIT, TFLite) · DeepFilterNet (MIT/Apache) · miniaudio
(MIT-0) · Oboe (Apache) · KISS FFT / PFFFT (BSD).

## Testing
- `flutter test` — unit tests for every detector + the play-along engine.
- `dart run bin/listen.dart --selftest --chords` — headless smoke test.
- `dart run bin/listen.dart --stdin` fed from `sox`/`ffmpeg` — live mic.
- macOS/iOS builds need the GEM-env wrapper (see CLAUDE.md / appstore.md).

## Advanced Tracker module: Feature Gap Analysis & Roadmap

To evolve our tracker into a world-class, perfect UX environment (drawing on
classic pattern-editor conventions without adopting a rigid hardware-emulator
path), we must focus on universal instrument support, seamless ecosystem
interchangeability, and power-user ergonomics.

### 1. Universal Instrument Ecosystem & Editing
**Current State:** 
Our `TrackerInstrument` hierarchy (`AdditiveInstrument`, `SfxrInstrument`, `SampleInstrument`) is robust but lacks a unified, deep editing UI. We want to support all kinds of sounds interchangeably without forcing hardware constraints.

**Implementation Steps:**
1. ~~**Instrument Editor Overlay:** Create `instrument_editor.dart` inside the Studio UI with a real-time testing keyboard.~~ (DONE)
2. ~~**Sample Editor:** For `SampleInstrument`, build a waveform viewer with draggable handles for `loopStart`/`loopLength`, ping-pong toggles, and base MIDI tuning.~~ (DONE)
3. ~~**Synth & FX Editor:** For `SfxrInstrument` or FM models, embed the existing `lib/features/sound_lab/sound_lab_screen.dart` to expose its rich slider UI directly in the tracker.~~ (DONE)
4. ~~**Multi-Sample Groundwork:** Enable `MultiSampleInstrument` to map different sample IDs across the keyboard (essential for complex DrumKits and realistic acoustic patches).~~ (DONE)

### 2. Ecosystem Interchangeability (Workshop, Looper, DrumKit, Tab) — DONE
**Current State:**
All three items shipped (C1, D1, D2). Every edge is symbolic and reversible, and
every conversion returns a `ConversionReport` naming what it could not carry;
`ProjectBridge` (`lib/core/interop/project_bridge.dart`) is the single entry
point. What remains open is UI: no screen hosts the shared `FxRack` or the
`OpenInMenu` yet — see the D-series note in the cross-mode FX section above.

**Implementation Steps:**
1. ~~**Looper / Loop Mixer Bridge**~~ (DONE, D1) — and done SYMBOLICALLY rather
   than as a baked stem, which is the stronger form: `lib/core/interop/
   loop_tracker.dart` converts a tracker channel to/from `PatternCell`s, so the
   result stays editable in the Loop Studio instead of arriving as audio. A
   baked `Float64List` is still available via `TrackerEngine.renderLoopFloat`
   when a clip really is wanted.
2. ~~**DrumKit Bridge**~~ (DONE, D2) — `beat_to_tracker.dart` already carried
   DrumKit → Tracker; `lib/core/interop/drum_tracker.dart` adds the inverse
   (`sharedBeatFromTrackerSong`), so the trip is now two-way and
   `beat → song → beat` is asserted to be identity.
3. ~~**Tab Editor Translation**~~ (DONE, C1) — `lib/core/interop/tab_tracker.dart`
   does this better than described: rather than mapping pitches onto strings
   after the fact, it puts **one channel per string**, so the fingering is
   native and survives a round trip instead of being re-derived.

### 3. Visual Excellence & Workflow (classic tracker ergonomics)
**Current State:**
The Studio UI (`tracker_screen.dart`) is functional but lacks the slick, real-time visual feedback and rapid navigation of elite modern trackers.

**Implementation Steps:**
1. ~~**Real-time Oscilloscopes & Meters:**~~ Tap the `_stem(channel)` cache in `TrackerEngine`. Pass this data to an `OscilloscopeWidget` using `CustomPainter` to draw vivid, real-time waveforms and VU meters per channel. (DONE)
2. **Smooth Scrolling Matrix:** PARTIAL — the playhead already tracks a
   FRACTIONAL within-row position (`_playFrac` in `advanced_tracker_screen.dart`,
   drawn sub-row), but the auto-scroll that follows it still `jumpTo`s at row
   granularity rather than easing. Genuinely-open remainder: ease the follow
   scroll + a block-by-block pattern-matrix overview. Low priority (cosmetic).
3. ~~**Advanced Keyboard Handling:**~~ (DONE — verified 2026-07-26, roadmap was
   stale.) `advanced_tracker_screen.dart` has `HardwareKeyboard.isShiftPressed`
   multi-cell selection (Shift+arrows), `_selectTrack`/`_selectPattern`,
   cross-channel block copy/cut/paste/paste-mix/transpose/clear (a Block menu +
   shortcuts, `_clipboard`), and value interpolation (`_interpolateBlock` volumes,
   `_interpolateNotesBlock` chromatic, `_fillInstrumentBlock`). Test GAP: the
   block ops have no unit coverage (the screen test covers only trim/env math) —
   a documented follow-up.

### 4. Deep Instrument Modulation (Macros & Envelopes) — CORE DONE (2026-07-26)
**Current State:**
Per-tick instrument MACROS ship for the additive voice (see
[docs/HISTORY.md](docs/HISTORY.md)). Sample-voice macros + a macro editor UI
remain.

**Implementation Steps:**
1. ~~**Macro Data Model:**~~ (DONE) `MacroSequence` (`lib/core/audio/macro_sequence.dart`)
   — a per-tick step table for volume/pitch/arpeggio/pan/duty with a sustain loop
   and a release segment; pure + exhaustively tested.
2. ~~**Tick-level Rendering (additive):**~~ (DONE) `AdditiveInstrument` carries an
   optional `macros` list; the additive tick voice in `tracker_replayer.dart`
   applies volume (amplitude), pitch and arpeggio (semitones) per tick from
   note-on. OPT-IN — absent macros keep every render byte-identical. Codec
   serializes them.
3. ~~**Sample-voice + reachability:**~~ (DONE) macros apply in the sample tick
   voice too, and `TrackerSong.usesMacros` routes a macro'd song through the tick
   replayer so `renderSongWav` actually sounds them (was silently taking the fast
   offline path).
4. ~~**Stereo path + pan target:**~~ (DONE) macros apply in the stereo tick voice
   (`_renderSampleChannelStereoTicks`) — used for PANNED songs — including the PAN
   target (meaningful only in stereo); additive stereo already worked via the
   mono-delegate-then-pan path.
5. ~~**Mono variable-timing path:**~~ (DONE) macros apply in the mono
   variable-timing render (`_renderChannelIntoVariable` additive loop +
   `_renderSampleChannelIntoVariable`), so a non-default-speed / mid-song-
   tempo-change song modulates.
6. ~~**Macro editor UI:**~~ (DONE) an "Instrument Macros" section in the Sample
   instrument editor — add/remove one macro per target + a drag-to-set bar editor
   with step-count and loop/release pickers. Macros are now user-authorable and
   persist. (Fixed a latent `SampleInstrument.copyWith` macro-drop along the way.)
7. ~~**Long tail — ALL SHIPPED (2026-07-27):**~~
   - ~~**§3.3 block-op tests**~~ (DONE) — `debugMarkBlock`/`debugCellVolume`/
     `debugCellMidi` seams + `tracker_block_ops_test.dart` (interpolate ramp,
     copy-paste, transpose).
   - ~~**Additive macro editor + Sound Lab interop**~~ (DONE) — an
     `AdditiveInstrument` gets its own macro editor; a "Sound Lab" button reshapes
     it into a sample carrying the macros (`macrosOf`).
   - ~~**Macros on every render/export path**~~ (DONE) — the whole-song
     stereo-variable + flow paths already applied macros via
     `_renderChannelIntoVariable`/`_renderChannelIntoStereo`; `songCanStreamFlow­Variable`
     + `writeSongWavStreaming` now route a macro'd song off the state-restarting
     per-chunk streamers onto those paths, so a macro sounds on playback AND
     bounded export, mono AND stereo, uniform/variable/flow.
   - ~~**DUTY target**~~ (DONE) — new `PulseInstrument` (pickable) + a pulse tick
     voice sweeps duty/volume/pitch from its macros.

   **§4 is complete:** model → additive+sample+pulse voices → mono+stereo →
   uniform+variable+flow → playback+export → codec-persisted → authorable UI.

### 5. Comprehensive Effect Command Set & Flow Control
**Current State:**
`TrackerCell` holds hex `fxCmd/fxParam`, but we currently only process volume commands. 

**Implementation Steps:**
1. **Unify Pitch Effects:** Move arpeggio/porta/vibrato from the `TrackerEffect` enum into the hex pipeline, evaluating them tick-by-tick during `renderChannel`.
2. **Flow & Groove Commands:** Support Speed (`Fxx`), Pattern Break (`Dxx`), and Position Jump (`Bxx`). Rewrite `renderSong` as a dynamic state machine that respects these navigation commands.
3. **Sub-row Timing:** Implement Note Delay (`EDx`) and Note Cut (`ECx`) directly in the offline renderer to allow complex swing and ghost notes.


### 5. Replay fidelity — gaps found by comparing against an independent player

Read across to **savage_modplayer** (Daniel Müller, Swift/macOS, WTFPL) — like
ours an **independent replay engine rather than a libopenmpt wrapper**, covering
MOD/S3M/XM/IT. It is player-only (no editing, no writers, no conversion), so the
comparison is only useful on the *replay* axis; on scope we are the larger
system. Two places we are already ahead and should not "learn" backwards:
**Catmull-Rom interpolation** (they use linear) and **module writing** (they
never attempt it — which is where most of our recent effect-mapping bugs lived).

⚠️ **Take approaches and hardware facts, not expression.** WTFPL permits literal
copying, but a Paula clock constant is a fact and "compare spectra as well as
RMS" is a method; lifting Swift into Dart would buy nothing and muddy provenance.

✅ **G1 — DONE (`d6186fd2`). Metrics built, and running them found four defects.**
`test/support/audio_compare.dart` = level · envelope correlation · lag ·
spectral similarity, each isolating one fault, as a LIBRARY with 19 tests of
its own against synthesised signals (the A/B is opt-in and never runs on CI).
What running it exposed: **the A/B had never actually run** (gated on a
licence-restricted file absent from every checkout — now gated on a fixture we
own); **the reference was non-deterministic** (`openmpt123` defaults to
`--dither 1`, and dither is random — the same inputs gave lags of 21504 and
29696; now `--dither 0`, and our own render is verified byte-identical run to
run); **the old RMS check peak-normalised before differencing**, so it could not
see a level error by construction — it rated `golden.mod` "-0.8 dB" where the
real delta is **-16.4 dB**; and **our `golden.mod` render is nearly silent**
(RMS 0.00037). ✅ **Those anomalies are RESOLVED as fixture artifacts** (investigated
2026-07-26). The golden.* files are far more degenerate than "minimal" suggests
— they are **a single note playing a five-sample waveform**:

| fixture | channels | note triggers | sample lengths |
|---|---|---|---|
| golden.mod | 4 | 2 | 8 |
| golden.xm | 1 | 1 | 5 |
| golden.it | 1 | 1 | 5, 10, 10 |
| golden.s3m | 1 | 1 | 8 |

So: golden.mod's "near silence" is 2 notes × 8 samples spread over 7.68 s of
mostly nothing (peak 0.072, RMS 0.00037); the ±16 dB level spread is two engines
disagreeing about interpolating a 5–8 sample source and about per-channel
scaling; the 17%-short XM/IT renders are end-of-song/tail handling on a 4-row
single-note pattern. **None of it is evidence about musical fidelity**, which is
exactly why they stay report-only.

✅ **DONE — and it found a real bug on its first run.** `test/fixtures/musical.mod`
(generated by `tool/make_musical_fixture.dart`, so it is reproducible and
licence-clean because we author it): 4 channels, 2 patterns × 64 rows, 15.4 s,
a **looped** 256-sample band-limited saw, a melody spanning two octaves with the
four voices moving at different rates. Verified `openmpt123` reads it as
ProTracker M.K. Deliberately effect-free — it answers "do we play the right
notes, at the right pitch, at the right level?", the narrowest useful question,
so a failure localises.

On its first A/B it exposed **a one-sample rounding error that silently disabled
sample LOOPING** for ordinary modules (`module_instrument_bridge.dart`): loop
points were rescaled onto the engine rate but rounded independently of the
resampled buffer, so a whole-sample loop landed one sample past the end,
`SampleInstrument.loops` went false, and every held note became a ~30 ms click.
Fixed + swept by `module_loop_rescale_test.dart` (13 rates × 6 lengths). The
fixture measured the repair: **spectral similarity 0.746 → 0.920** and level
−14.20 dB → +3.76 dB against OpenMPT.

🟡 **INVESTIGATED (2026-07-27, opus tracker→editors) — a REAL note-level loudness
fault, and NOT the two things it looked like.** Measured `musical.mod` ours vs
openmpt123 + micromod + xmp with `audio_compare` + `reference_players`:

| block | ours↔openmpt | ours↔micromod | **openmpt↔micromod (refs)** |
| --- | --- | --- | --- |
| 512 (12 ms) | 0.233 | 0.238 | **0.971** |
| 2048 (46 ms) | 0.310 | 0.295 | **0.973** |
| 8192 (186 ms) | 0.161 | 0.160 | **0.982** |

The X0 baseline settles it: the independent references agree on the loudness
CONTOUR at 0.97–0.98 at every timescale, and **we** are the outlier at ~0.23 —
so it is a real fault, not metric noise. Two hypotheses RULED OUT by measuring:
(1) it is **not a lag artifact** — `bestLagSamples` is 0. (2) it is **not the
per-note attack transient** (the 4 ms declick ramp / soft-start): that would wash
out at coarse blocks, but our gap is if anything WORSE at 186 ms (0.16). So the
divergence lives at the **note-and-above** timescale, i.e. per-note length/sustain
or per-channel mixing levels, NOT the note edges. It is also **separate from the
level**: we sit ~+2.5 dB (the known 4/3 gain-convention item), which envelope
correlation is amplitude-invariant to.

🟢 **RESOLVED as a NON-BUG (2026-07-27, further pass) — it's inter-voice phase,
not a fidelity fault; the metric should not gate it.** Ruled out the two remaining
suspects by measuring, and found the cause: **(3) NOT panning/mono-fold.**
`usesPan=true`, channel pans `[-0.67,+0.67,+0.67,-0.67]` (the correct L-R-R-L,
matching openmpt123's 0.75/0.25 split), and `renderSongWav` already emits STEREO
— the mono-fold and stereo-fold envelope correlations are identical (~0.22), so
panning is right. **(4) NOT per-voice dynamics or note length.** Soloing each of
the 4 channels (`toggleSolo`) shows every voice is individually FLAT at ~0.135
RMS the whole song — no voice rests, decays or over-sustains; they all play the
looped saw continuously, exactly as a MOD should (empty cells sustain, there is
no note-off effect). So the notes, their lengths and their per-voice levels are
right. What differs is the FULL-MIX fine structure: with several voices at
unison/octave, the summed loudness is set by their **relative phase**, and ours
differs from the references' because the references share a sample-retrigger
phase convention we don't reproduce. This is a **sub-perceptual DSP detail**
(interference between phase-locked voices), not notes/timing/level/pan — so on
`musical.mod` the envelope-correlation residual is NOT a red and should not be
gated as one. The only lever is sample-retrigger phase; the audible payoff is
≈nil, so it is documented and closed rather than chased. *Original finding:*
`test/tracker_audio_regression_test.dart` renders through our pipeline and
`openmpt123` and compares **duration + RMS deltas**. Their `reference_compare.py`
compares duration, **envelope correlation**, **onset/lag alignment** and
**spectral similarity**. That gap is not academic for us: we convert Amiga
periods to MIDI notes (`periodToMidi`/`midiToPeriod`) and render via
`_freqOfMidi`, i.e. **A440 equal temperament rather than the Paula clock**. A
systematic tuning offset from that choice leaves duration identical and RMS
nearly identical — our harness would pass it. We have not measured whether we
actually drift; the point is that **our current metrics cannot tell us**.
*Do this first: the other gaps are hard to evaluate without it.*

**G2 — No stated cross-platform determinism policy.** They document theirs and
measured it: `tanh` in the limiter rounds differently in glibc vs Darwin libm →
LSB shifts in ~0.01% of samples, ~115 dB down, inaudible. We have the same
exposure (`tracker_replayer.dart` `_tanh` is built on `exp()`, still platform
libm). **We are safe today** — our byte-identical gates compare two renders
*inside one run*, and `mod_codec_test`'s golden compare is module **bytes**
(parse→write, pure integer), not audio. The trap is ahead of us: if anyone
commits a golden *rendered* WAV compared byte-exactly it will be intermittently
red between macOS dev and Linux CI.

✅ **G2 — DECIDED + ENFORCED (`tracker_render_determinism_test.dart`).** The
policy, in one line: **the render is deterministic PER PLATFORM, and that is
all we claim.**

* **Guaranteed, and now tested** for all four formats: rendering the same module
  twice on the same machine gives byte-identical audio. Several suites already
  leaned on this without stating it — every "byte-identical with the feature
  added" gate compares two renders and would pass or fail spuriously if the
  renderer wobbled — so it is the foundation those gates stand on and it has a
  test of its own. A companion test proves the comparison can separate two
  genuinely different modules, so the suite cannot pass vacuously.
* **Not guaranteed:** bit-identical audio across platforms. `_tanh` is built on
  `exp()`, which is platform libm. We have NOT measured our own divergence; the
  reference measurement is ~0.01% of samples at ~115 dB down, i.e. inaudible.
* **⚠️ The operating rule:** never commit a golden RENDERED WAV and compare it
  byte-exactly — we develop on macOS and CI runs Linux, so it is an intermittent
  red waiting to happen. Compare two renders made in the SAME run, or compare at
  signal level with `test/support/audio_compare.dart`. Committing golden module
  BYTES stays fine (`mod_codec_test`): parse→write is integer work with no libm
  in it.

🔶 **G3 — HALF DONE.** ✅ The **LED low-pass filter** is shipped by 
(tracker-complete): `E0x` (MOD/XM) and `S0x` (S3M/IT) drive a `_HardwareLowPass`
with a per-sample on/off schedule — flagging it here is what routed it to them,
since `E0x` IS that command. ⬜ **Still absent: the Paula clock.** No PAL
(3,546,894.6 Hz) / NTSC switching, and no pitch derived from clock ÷ output rate;
ours stays a pure c5speed/finetune model, which is why MOD playback is tuned to
A440 rather than to the hardware. **MEASURED: we render 17.1 CENTS SHARP of OpenMPT** ⚠️ (I first wrote FLAT — the sign was mine, not the metric's: `AudioComparison.of(ours, openmpt)` reports how far the SECOND is sharp of the first, so −17.1 means OpenMPT is flat of us) on
`musical.mod` (`detuneCents` in `audio_compare.dart`, verified to ±3 cents
against synthesised offsets). So the Paula-clock hypothesis is confirmed, with a
size attached: not a rounding wobble, but not gross either — about a sixth of a
semitone, consistent across the piece. The degenerate `golden.*` fixtures report
`n/a` rather than a number, which is the metric refusing to guess.

🔶 **BUILT BEHIND A GATE — `--dart-define=PAULA_CLOCK=1`** (`kPaulaClockPitch`
in `module_convert.dart`), because a change to every module render should be
checkable before it is committed to. The arithmetic: the Amiga plays the
reference period 428 at `3546895 / 428 = 8287.1 Hz` while the conventional
reference is 8363 Hz — **−15.8 cents** — so pitching from the reference sits
~16 cents SHARP of the hardware, accounting for the measured 17.1 to within
~1.3 cents (ProTracker's period table is not exactly geometric).

**A/B, same fixtures, gate off → on:**

| fixture | detune | spectral | envelope |
| --- | --- | --- | --- |
| musical.mod | −17.0 → **−1.3** | 0.922 → **0.962** | 0.233 → **0.619** |
| effects.mod | −25.4 → **−5.3** | 0.862 → **0.882** | 0.188 → **0.363** |

Every metric improves and the tuning error essentially disappears. The envelope
jump is a side effect worth noting: once the pitches agree the two renders stop
beating against each other, so their loudness contours line up too.

⬜ **Flipping the default is the remaining call** — it changes how every module
sounds, in @opus (tracker-complete)'s area. The evidence is now one command
away: run the A/B with and without the flag.

✅ **G4 — NON-GOALS, DECIDED.** What we refuse to chase, so the replayer can be
finished rather than approached forever. Written from what the code already
does, not from ambition; revise freely, but revise it *deliberately*.

1. **We are not a hardware emulator — we emulate what was AUTHORED FOR.** The
   LED low-pass (`E0x`/`S0x`) and OPL2/YM3812 FM are in scope because composers
   wrote music that depends on hearing them. Paula's incidental artifacts are
   not: 8-bit DMA quantisation, its aliasing signature, per-chip mixing quirks.
   We render offline at the engine rate with Catmull-Rom interpolation, which is
   *better* than the hardware and deliberately so — this is a music-education
   app, not a preservation emulator.
2. **No bug-emulation of other players.** No pre-1.17 OpenMPT swing, no legacy
   pattern-loop quirks, no proprietary envelope release nodes. A module that
   depends on another player's bug is out of scope; we play the format.
3. **Not bit-identical to any other player, ever.** We target *musical*
   equivalence, measured by `test/support/audio_compare.dart` against OpenMPT —
   same notes, same pitches, same levels, same timing. Sample-exact parity is
   not a goal and would forbid our own interpolation and limiter. (See also the
   determinism policy above: per-platform only.)
4. **MPTM is refused, not half-read.** `ModuleFormat` is mod/s3m/xm/it. An
   OpenMPT-extended module should be rejected with a clear reason rather than
   silently mis-parsed.
5. **No VST/AU hosting and no external MIDI out.** IT MIDI macros are in scope
   only where they map onto our own filter (`Zxx` cutoff/resonance); macros
   addressing outboard gear are carried as data and ignored.
6. **Writers target round-trip fidelity, not authoring parity.** We write what
   we can read back losslessly. A COMPRESSED IT stays compressed on a same-format
   round-trip — the reader retains the IT214/215 blocks in `ItSample.rawData` and
   the writer re-emits them verbatim (Flg 0x08), with `ItModule.createdWith`
   carrying the module-wide 214/215 delta stage (verified byte-for-byte,
   `it_writer_test`). What is NOT implemented is a fresh IT214 *bit-packer*, so a
   synthetic or edited sample (no retained blocks) writes uncompressed — correct,
   just larger.

**The test of a good non-goal is that it closes an argument.** If one of these
starts costing real musical accuracy — a module people actually want to hear
sounding wrong because of it — that is a reason to revisit the entry, and the
A/B is now able to tell us so with numbers.

✅ **Loose end RESOLVED (2026-07-26, @opus tracker-complete).** `s3m_reader.dart`'s
comment claimed "We do NOT emulate the OPL chip" — wrong: `tracker_song_module.dart`
builds an S3M type-2 sample into a real `OplInstrument` (YM3812) for playback,
while the reader keeps a PCM approximation (`synthesizeAdlibWaveform`) as a
sample-path fallback and preserves the register block for byte-identical
re-export. Comment rewritten to describe both intended paths accurately.

✅ **G5 — DONE (`d6186fd2`).** `_kOpenMptPath` was pinned to one Cellar version,
so a routine `brew upgrade` silently skipped the whole audit. Resolved from
`PATH` now, with the Homebrew prefix as a fallback.


#### Open follow-ups from the arc (recorded 2026-07-26, none claimed)

The A/B **gates** now — on `musical.mod`, at spectral > 0.85, |level| < 8 dB,
|detune| < 35 cents. Thresholds come from measured values and are set so they
would have caught the loop-rescaling bug (spectral 0.746, level −14.2 dB). Its
remaining numbers are the follow-up list:

| what | measured | reading |
| --- | --- | --- |
| spectral similarity | 0.920 | we play the right notes |
| detune | −17.1 cents (**we are SHARP**) | G3, Paula clock — now BUILT behind a gate |
| **level** | **+3.76 dB** | **we are consistently LOUDER** |
| **envelope correlation** | **0.222** | **loudness CONTOUR disagrees** |

🔶 **Loudness parity — DIAGNOSED, and the main cause was a MISSING FEATURE.**
The density sweep (1/2/3/4 active channels: +4.01 / +3.76 / +3.54 / +3.22 dB)
ruled out summation — the gap is ~4 dB at a SINGLE channel and shrinks as
channels are added, the shrinkage being our `tanh` limiter compressing the
larger sum. A volume sweep (64/48/32/16) held it at 4.01–4.17 dB with both
engines scaling linearly, so the volume MAPPING was right too.

Comparing L and R separately found it: **openmpt123 pans MOD channels L-R-R-L at
3:1, and we panned everything dead centre.** Full amplitude went into both
channels instead of being split across them, and the arithmetic closes exactly —
their mono downmix (0.1502+0.0501)/2 = 0.1002 against our 0.1588 is a ratio of
1.586, i.e. **+4.00 dB**, the measured gap.

✅ **Fixed** (`_protrackerPan` in `tracker_song_module.dart`): MOD now gets the
Amiga layout, which is a real feature — a `.mod` stores no panning, so without
it every module rendered mono-in-stereo and lost the wide ping-pong image the
format is known for. Level gap **+4.01 dB → +2.68 dB**.

⬜ **Residual ~2.7 dB is a GAIN CONVENTION, and is a product decision.**
`_channelGain` uses a `0.6` base; matching the reference exactly would mean
re-calibrating it, which changes how every module sounds in the app. Not a bug —
neither convention is canonical — so it is recorded rather than quietly tuned.
A smaller loose end: our measured split came out 3.6:1 where the reference is
3:1, so something applies a little extra separation; worth a look if anyone is
in that code.

⬜ **Envelope correlation 0.222.** The one number the loop fix barely moved
(0.103 → 0.222). We now agree about *which* pitches sound and much less about
*how loud, when* — so it points at note envelopes or volume ramping rather than
at pitch or mixing. Worth chasing after loudness, since a level error would
muddy any envelope measurement.

✅ **Effect-coverage fixture — DONE.** `test/fixtures/effects.mod` (same
generator): one effect family per CHANNEL — arpeggio `0xy` · vibrato `4xy` ·
portamento `1xx`/`2xx` · volume slide `Axy` — each working on ONE long note, so
the effect has something to modulate. Bends go up then back down within each
16-row run, so a one-sided error cannot hide. It GATES (spectral > 0.80; the
threshold is per-fixture because pitch-bending material honestly diverges more
than plain notes, and one shared number would be too loose for `musical.mod` or
too tight for this).

✅ **First finding from it, since EXPLAINED: effect material is ~8 cents further out.**
`effects.mod` measured **−25.4 cents** against `musical.mod`'s −17.0. The guess
was that portamento and vibrato, which compute pitch, amplify the base offset —
and the Paula-clock A/B confirmed it: with the gate on, effects.mod moves
−25.4 → **−5.3** alongside musical.mod's −17.0 → **−1.3**. Same root cause.
**Detune stays ungated on this fixture** until the gate's fate is decided.


### 6. Replay-fidelity AUDIT LADDER — scoped tasks (opened 2026-07-27)

**Why this exists.** A listening test on `~/Desktop/mod-tuning-ab/raw/` found that
BOTH our renders — default and Paula-clock — diverge audibly from libopenmpt,
libxmp and micromod on the SWEEPING effects, in a way the Paula switch does not
explain. The measurements agree and I had under-read them:

| effects.mod | spectral | envelope |
| --- | --- | --- |
| libopenmpt ↔ libxmp (*the references agreeing*) | **0.926** | 0.630 |
| ours B (paula) ↔ libopenmpt | 0.882 | 0.363 |
| ours B (paula) ↔ libxmp | 0.869 | 0.301 |
| ours A (default) ↔ libxmp | 0.851 | 0.078 |

⚠️ **Calibration lesson: my gate was set against the wrong baseline.** I gated
`effects.mod` at spectral > 0.80, so 0.87 PASSED — while the two references
agree at 0.93 and our envelope correlation is half theirs. The right reference
point is *how well the independent engines agree with each other*; anything
materially below that is our deviation. **Re-set the gates that way (task X0).**

**What this section is not:** one bug. Effects are several independent
mechanisms (per-tick rate, depth scaling, waveform, memory/recall semantics,
tick-0 handling), so "effects are off" has to be split before it can be fixed.

#### Oracles now available (all verified working this session)

| tool | formats | gives us |
| --- | --- | --- |
| `openmpt123` (libopenmpt) | MOD/XM/S3M/IT | audio; the de-facto standard |
| `xmp` (libxmp) | MOD/XM/S3M/IT | audio; independent codebase |
| `mod2wav` (micromod) | MOD | audio; accuracy-focused |
| `xm2wav` (ibxm) | MOD/XM/S3M | audio; same author, different engine |
| MultiPLAY | MOD/XM/S3M/IT/MTM | audio; **uses the 8363 convention** — outlier on MOD tuning, still useful elsewhere |
| pt2-clone | MOD | SOURCE only (GUI, no headless render) — authoritative on ProTracker semantics |
| **NodMOD** (Python) | MOD/XM/S3M | STRUCTURE + an independent flow/timing model (`iter_playback_rows` → pattern/row/start_sec/speed/tempo). No audio, no IT. |
| `test/support/audio_compare.dart` | — | level · envelope · lag · spectral · detune |

Build/run notes: `xmp` via Homebrew; MultiPLAY `make bare`; micromod
`cc mod2wav.c micromod.c`; ibxm `cc xm2wav.c ibxm.c`; NodMOD `PYTHONPATH=<clone>/src`.


#### X1 RESULT (2026-07-27) — the effects that deviate, named

13 per-effect fixtures (`tool/make_effect_fixtures.dart` → `test/fixtures/fx/`),
one effect on one sounding channel each, rendered through our A and B and
through libopenmpt / libxmp / micromod. **Deviation is judged against how well
the three references agree with each other** (task X0's rule), not an absolute.

| effect | refs agree | ours (B) | gap | verdict |
| --- | --- | --- | --- | --- |
| `9xx` sample offset | 1.000 | **0.000** | 1.000 | **BROKEN — we render SILENCE** |
| `1xx` porta up | 1.000 | 0.549 | 0.451 | **deviates** |
| `2xx` porta down | 1.000 | 0.689 | 0.311 | **deviates** |
| `ECx` note cut | 0.990 | 0.859 | 0.131 | **deviates — the note is not cut** |
| `5xy` porta + vol slide | 1.000 | 0.918 | 0.082 | deviates |
| `3xx` tone porta | 1.000 | 0.963 | 0.037 | suspect |
| `0xy` arpeggio | 0.984 | 0.994 | −0.010 | ok |
| `4xy` vibrato | 0.999 | 0.979 | 0.020 | ok |
| `7xy` tremolo | 0.999 | 0.999 | 0.000 | ok |
| `6xy` vibrato + vol slide | 0.999 | 0.977 | 0.022 | ok |
| `Axy` vol slide up/down | 1.000 | 1.000 | 0.000 | ok |
| `EDx` note delay | 1.000 | 0.999 | 0.000 | ok |

**So the "sweeping" a listener heard is PORTAMENTO, not vibrato** — vibrato and
tremolo are fine, and the whole pitch-slide family is not.

✅ **B1 — FIXED (ungated; a plain bug). spectral 0.000 → 0.986** out-of-range,
**0.994** in-range, against three references that agree at 1.000.

**It was NOT `9xx` in general — only offsets past the sample end.** Splitting
the fixture proved it: in-range already worked (0.156 rms vs refs 0.112, i.e.
only the known gain convention), while out-of-range was digital silence. Those
would have been different fixes, which is why the in-range fixture came first.

**Cause:** `tracker_engine.dart` guarded the whole render block with
`offset < source.length`, so an out-of-range offset skipped it entirely. The
boundary was exact — with a 1349-sample buffer `9x00` sounded and `9x01`
(start 1350, ONE past the end) was already silent.

ProTracker does not refuse: it clamps the play length to one word
(`pt2_replayer.c` sampleOffset, `else { ch->n_length = 1; }`) and on a LOOPING
sample Paula's loop takes over, so the note keeps sounding — which is why all
three references render it at full level. The fix wraps the offset into the loop
when there is one, and **leaves the guard in place for one-shot samples**, where
silence remains correct. That asymmetry is the fix, not an oversight in it.

⚠️ **Two ways I nearly got this wrong, both caught by measuring:**
1. I reasoned from `tracker_replayer.dart`'s read loop, which HAS a wrap and
   should have handled it — my source reading predicted working audio and
   contradicted the measurement. The offline note-run path in
   `tracker_engine.dart` is what actually renders here. When source reading and
   measurement disagree, the code being read is probably not the code running.
2. The first regression test asserted on the render's PEAK, which cannot tell
   two offsets apart on a looping sample (both halves play either way). It
   passed vacuously until rewritten to measure the START of the note, which is
   the only place the read pointer's origin is visible.

✅ **B2 — FIXED (ungated; a plain bug, not a design choice). spectral
0.859 → 0.996**, which is closer to the references than they are to each other
(0.990). Residual level is +2.6 dB, i.e. only the known gain convention.

**Cause: the cut was per-tick, not persistent.** ProTracker's `ECx` sets the
CHANNEL volume — `ch->n_volume = 0` (`pt2_replayer.c` `noteCut`) — and it stays
zero until something restores it. We set only the per-tick `effVol`, which is
recomputed from `volume` on every tick, so the note went quiet for the rest of
its own row and came back on the next one.

⚠️ **The first version of this fix was WORSE than the bug, and the measurement
caught it.** Setting `volume = 0` persistently silenced the channel for the rest
of the song: nothing ever restored it, because a new note did not reset channel
volume at all. Spectral looked excellent (0.994) while RMS fell to HALF the
references — content right, level wrong. ProTracker reloads `n_volume` from the
sample whenever a note names one, so the fix needs both halves: `ECx` sets
`volume = 0`, and a note carrying an instrument restores it.

**A note without an instrument number deliberately keeps the current volume** —
that is the ProTracker rule, and it is what makes `Cxx` followed by bare notes
behave. Getting this half-right in either direction is silent: too sticky and
the song fades out, too eager and every `Cxx` is forgotten on the next note.

✅ **B3 — FIXED (gated `--dart-define=PORTA_PERIOD=1`). The whole slide family
now matches all three references EXACTLY.**

| effect | before | after |
| --- | --- | --- |
| `1xx` porta up | 0.549 | **1.000** |
| `2xx` porta down | 0.689 | **1.000** |
| `3xx` tone porta | 0.963 | **1.000** |
| `5xy` porta + vol slide | 0.918 | **1.000** |

**Cause: we slid PITCH where the hardware slides PERIOD.** ProTracker does
`period -= param` per tick, clamped to [113, 856] (`pt2_replayer.c`
`portaUp`/`portaDown`), and period↔pitch is logarithmic — so a linear period
step is not a constant semitone step. It accelerates as the period shrinks, and
how far a param bends depends on where the note started, which a fixed
`kPortaSemitonesPerUnit` can only get right at ONE point. Over the X1 fixture
(param 4, 48 ticks from period 428) ProTracker bends **10.3** semitones; the old
model bent a flat **12.0** — 1.7 st adrift at the end and wrong in SHAPE
throughout, which is what a listener hears as the sweep being off.

Gated rather than switched, because the semitone model was a DELIBERATE choice —
"chosen for a pleasant musical feel" in `tracker_replayer.dart`. Flipping it
changes every module's slides, so it gets the same A/B treatment as the Paula
clock. Arithmetic pinned by `test/mod_porta_period_test.dart`, which runs
everywhere (the audio A/B needs external players and only runs opt-in).

The hypothesis in the original entry held: `3xx` and `5xy` WERE downstream of the
same step — no separate diagnosis was needed, only the same conversion applied
to the tone-porta path. Worth remembering when B1/B2 are picked up: measure the
family, fix the shared mechanism, re-measure before splitting into more bugs.

⚠️ **Fixture-design lesson, worth keeping.** The first `porta_up` run showed the
three references agreeing with each other at only **0.555**, which looked like
"even the references disagree". They do not — holding the bend for all 31 rows
slides the note off the end of the period table, so the fixture was measuring
each engine's CLAMP policy. Bounding the bend to 8 rows moved inter-reference
agreement to **1.000** and our gap from 0.158 to 0.451. A fixture that pushes an
effect past its legal range measures the edge, not the effect.

ℹ️ Our peak is consistently 1.333× the references on these single-channel
fixtures (0.2424 vs 0.1818) — that is the known open gain-convention item, not
a new finding, and it is why these verdicts use SPECTRAL similarity rather than
level.


#### X1 CLOSED (2026-07-27) — every effect fixture now agrees with the references

Re-swept all 14 fixtures with the three fixes in force
(`--dart-define=PAULA_CLOCK=1 --dart-define=PORTA_PERIOD=1`):

| fixture | refs agree | ours | gap |
| --- | --- | --- | --- |
| `1xx` / `2xx` / `3xx` / `5xy` portamento | 1.000 | **1.000** | 0.000 |
| `9xx` offset, in-range and past-the-end | 1.000 | 1.000 / 0.999 | ~0 |
| `ECx` note cut | 0.990 | **0.996** | −0.006 |
| `EDx` note delay | 1.000 | 0.999 | 0.000 |
| `0xy` arpeggio | 0.984 | 0.994 | −0.010 |
| `7xy` tremolo · `Axy` volume slides | 0.999 / 1.000 | 0.999 / 1.000 | 0.000 |
| `4xy` vibrato · `6xy` vibrato+volslide | 0.999 | 0.979 / 0.977 | **0.020 / 0.022** |

On several fixtures we now sit CLOSER to each reference than they sit to each
other, which is the most that can be asked of a fourth implementation.

✅ **X2 (vibrato) — FIXED. (This paragraph said "MOSTLY FIXED, gated
`--dart-define=PORTA_PERIOD=1`" until 2026-07-28; that gate no longer exists and
the remaining gap was the LFO RATE, closed separately below.)** The depth-scale/space
hypothesis held: vibrato was applied in SEMITONES with a flat depth, exactly like
portamento before B3. ProTracker modulates PERIOD — `(vibratoTable[pos]·y) >> 7`,
table peaking at 255, so peak wobble ≈ `255/128·y` period units — which is
shallower than the old `y/8` semitone model AND correctly-shaped (a period wobble
is not a constant-semitone wobble). Fixed the ONE apply site in
`tracker_replayer.dart` (`kVibratoPeriodPerDepthUnit`, `kVibratoPeriodAccurate`
aliased to the porta gate so the whole pitch-effect family flips together);
default byte-identical, 111 tracker tests green. Measured against openmpt123 +
micromod (which agree at 0.999), PAULA_CLOCK=1:

| fixture | refs agree | ours default | ours PERIOD |
| --- | --- | --- | --- |
| `vibrato.mod` | 0.999 | 0.981 / 0.979 | **0.989 / 0.986** |
| `vibvol_6xy.mod` | 0.999 | 0.981 / 0.977 | **0.989 / 0.987** |

Arithmetic pinned by `test/mod_vibrato_period_test.dart` (runs everywhere; the
audio A/B is opt-in). ⚠️ The rate was already correct — pt2 advances
`n_vibratoPos += hi<<2` and looks up `(pos>>2)&31`, i.e. index `+= hi` per tick,
a full 32-step cycle in `32/speed` ticks, which is exactly `kVibratoRadPerSpeedUnit
= 2π/32`. Only depth + space were wrong.

⬜ **Residual: vibrato ~0.011** (was 0.020). Halved but not gone, and `6xy`
still tracks `4xy` exactly (one shared LFO). The remaining candidate is the
WAVEFORM TABLE: `trackerLfo` is a continuous sine, ProTracker a 32-entry
quantized table (`vibratoTable`), so the harmonic content differs slightly. Tick-0
is NOT it — `_vibPhase` resets to 0 on a new note and sin(0)=0, so applying on
tick 0 adds nothing. Depth-scale is spent. Worth a table-shape pass if the number
matters; it is comfortably inside the "ok" band now.

✅ **X2 CLOSED (2026-07-27) — it was the RATE, and none of the guesses above.**
See the X2 section below; the residual is gone in both configurations.

**Method note for whoever picks this up.** All three bugs were found by
measuring one effect at a time against three independent players, then reading
`pt2-clone`'s source for the authoritative rule — not by reading our code first.
Twice my source reading actively contradicted the measurement and the
measurement was right. Fix the mechanism, then re-measure the whole family
before splitting anything into separate bugs; `3xx`/`5xy` needed no diagnosis of
their own once `1xx`/`2xx` were right.

#### X0 CLOSED (2026-07-27) — the gates now measure against the other engines

`test/tracker_audio_regression_test.dart` no longer gates on a constant. It
renders each fixture through every reference it can find — openmpt123 (required)
plus `xmp` and `mod2wav` when installed — measures the **worst pairwise spectral
agreement among the references**, and requires that our own worst deviation from
any of them stay within 0.08 of that. With only one reference present it falls
back to the old absolute thresholds and says so on stdout, so a machine without
the extra binaries still runs a meaningful (if blunter) audit.

The bar this replaces was 0.80 absolute. On `effects.mod` the references agreed
at 0.926 while we sat at 0.87 — comfortably passing a gate the maintainer's
listening test failed. That is the exact hole the relative baseline closes.

Result with the X1 fixes in force and three engines present:

| fixture | refs agree | ours | gap |
| --- | --- | --- | --- |
| `musical.mod` | 0.963 | **0.962** | **0.001** |
| `effects.mod` | 0.910 | **0.903** | **0.007** |

We now differ from the reference players about as much as they differ from each
other, on both real fixtures.

The `golden.*` parser fixtures print inter-reference agreements of 0.246, 0.452,
0.440 and — on one — 0.000 comparable frames. They are minimal parser fodder,
nearly silent, and the references cannot agree on them either; they stay
report-only rather than gated, and their numbers are now visibly self-explaining
instead of looking like a failure of ours. On one of them we agree with the
references BETTER than they agree with each other (gap −0.384).

**Caveat worth keeping.** The 0.08 slack is itself a constant, chosen so the two
real fixtures pass with the current fixes. It is a much better constant than 0.80
— it rides the material instead of ignoring it — but if a future fixture makes
the references disagree wildly, the gate goes slack with them. That is the right
failure direction (never a false red), not a free lunch.

#### X2 CLOSED (2026-07-27) — the vibrato residual was a doubled LFO rate

The PLAN guessed depth scale, waveform table, or the period-vs-pitch question,
by analogy with portamento. All three guesses were wrong. Reading ProTracker's
replayer instead: it adds `x*4` to an **8-bit** position each tick and indexes a
32-entry table with `(pos >> 2) & 0x1F`, taking the sign from `pos < 128`. The
position wraps every 256 units, so a full cycle is 256/(4x) = **64/x ticks**. We
used 32/x — **every vibrato in every module ran at exactly twice its intended
rate**. No reading of the format yields 32/x; this was a plain bug, not one of
the deliberate musical approximations.

Three more findings fell out of the same read:

- **Tremolo's depth is `>> 6` where vibrato's is `>> 7`** — ~4 volume units per
  depth-unit, not the 1.0 we used. Every tremolo swung a quarter as far as it
  should, and `7xF` should cover almost the whole 0–64 range.
- **Neither LFO runs on tick 0.** ProTracker reads the row and triggers voices on
  tick 0 and runs the per-tick effect handler only on ticks 1..speed−1, so a
  vibrato'd note sounds unbent for its first tick and the LFO neither applies nor
  advances. We ran it on every tick, adding a tick of phase per row.
- **Bit 2 of the waveform select is a "don't retrigger" flag** (`E44`–`E47`,
  `E74`–`E77`) — which is why the nibble runs 0..7 for three shapes. We reset
  unconditionally, so a module using it had its LFO restarted on every note.

Also: ProTracker's RAMP, expressed in period space, is a *rising* sawtooth,
where our general-purpose `lfoValue` ramp falls. Reusing it would have inverted
`E41`, so vibrato/tremolo now go through a `protrackerLfo` that matches the
hardware; `trackerLfo` is unchanged for panbrello and the FX rack.

**Panbrello was deliberately left alone.** It rode the vibrato constant, but
ProTracker has no panbrello — the 64/x finding is not evidence about it, and
IT's own rule is different again (256/x). It got its own constant preserving its
existing behaviour rather than letting a ProTracker finding silently change an
untested effect. ⬜ Still unverified against any reference.

**Measured, full sweep, three engines** (`tracker_effect_reference_sweep_test`):

| fixture | before | shipped default | `PORTA_PERIOD=1` | refs agree |
| --- | --- | --- | --- | --- |
| `4xy` vibrato | 0.979 | **0.994** | **0.999** | 0.999 |
| `6xy` vib+volslide | 0.977 | **0.994** | **0.999** | 0.999 |
| `0xy` arpeggio | 0.976 | 0.976 | **0.994** | 0.984 |
| `EDx` note delay | 0.983 | 0.983 | **0.999** | 1.000 |
| `9xx` offset | 0.986 | 0.986 | **0.999** | 1.000 |

Under `PORTA_PERIOD=1` **every one of the 14 effect fixtures now sits at or
inside the spread of the reference players** — arpeggio and note-cut are closer
to each reference than the references are to each other. In the shipped default
only the four portamento fixtures remain adrift, and that is the documented
semitone-model decision below, not a defect.

**Method note.** The same discipline as X1 paid again, and the PLAN's own
hypothesis list was the thing that was wrong: measuring named the family
(vibrato AND `6xy`, one shared LFO), and reading the authoritative source named
the cause. Guessing from our own constants would have sent me to the depth
scale, which was fine.

⚠️ **Metric caveat worth remembering.** Spectral similarity is a cosine of
magnitude spectra and is therefore **amplitude-invariant**, so it read tremolo
at 0.999 while its depth was four times too shallow. A pure amplitude effect
needs the envelope correlation; the spectral number cannot see it. ⬜ Tremolo
depth is fixed but has NOT been re-measured with an envelope-based metric.

#### New instrument: `test/tracker_effect_reference_sweep_test.dart`

X1's per-effect measurements were ad hoc. They are now a committed opt-in
sweep — one line per fixture, refs-agree vs ours vs gap, over every reference
binary present — plus `test/support/reference_players.dart`, which both audit
harnesses share instead of keeping two copies of a WAV chunk walker.

```
flutter test --dart-define=OPENMPT_AB=1 test/tracker_effect_reference_sweep_test.dart
flutter test --dart-define=OPENMPT_AB=1 --dart-define=PORTA_PERIOD=1 \
  --dart-define=PAULA_CLOCK=1 test/tracker_effect_reference_sweep_test.dart
```

It reports per effect and asserts once, so a reference-player upgrade cannot
redden the suite over a third decimal. The four portamento fixtures are exempt
from the assertion when the gate is off, by name and with the reason attached.

#### X9 partly DONE (2026-07-27) — one song, four formats, two bugs

The effect fixtures all live in one pattern and are all MOD, so they cannot see
the order list or anything format-specific. `tool/make_flow_fixtures.dart` emits
the opposite: almost no effects, a real jump/break, written out as **MOD and XM
and S3M and IT**. Because it is the same song four ways, the reference players
agree with each other across all four — which turns "do we match a reference"
into the much sharper "do our four formats agree the way theirs do".

It found two bugs in its first run.

**IT's pattern-break row is HEX; everyone else's is decimal (X6/X7).** Our
canonical `Dxx`/`Cxx` parameter is decimal-coded into the two nibbles — row 16
is 0x16 — which is what MOD, S3M and XM store, what `setPatternBreak` writes and
what the replayer decodes. The IT converter passed the parameter through
untouched in BOTH directions, so an IT we wrote said 0x16 and every other player
read that as hex 0x16 = row 22.

It was invisible to round-trip testing *because* it was wrong in both
directions: our reader undid our writer's mistake and every doc→IT→doc test
passed. Only an external reader could see it. libopenmpt rendered our MOD, S3M
and XM to 13.541 s each and our IT to 12.821 s — 0.72 s short, exactly the six
rows between row 16 and row 22; libxmp agreed (13.440 vs 12.720). Both
references model the split explicitly, libxmp giving IT its own effect
(`FX_IT_BREAK`, commented "like FX_BREAK with hex parameter").

Fixed in `module_convert.dart` at the two IT conversion sites, with
`decimalBreakParam`/`breakRowOfDecimalParam`. The shared writer flag
`directPan` — which already meant "is this IT" — is now `isIt`, because naming a
format flag after one of its consequences is how the second consequence came to
be missed. ⬜ Note the canonical form cannot express a break to a row above 159
(the nibbles hold tens and units); only IT can name one, and it clamps.

**XM channels were polyphonic (X8).** Our XM importer built each instrument as
`MultiSampleInstrument(polyphonic: true)` — the flag whose own doc comment reads
"notes are not choked by subsequent notes on the channel (drum kit mode)". Every
note in every XM rang on forever and SUMMED with its successors. FastTracker II
has no NNA — that is IT's addition, which is why the IT pool sets
`nativeVoiceSemantics` alongside `polyphonic`.

MOD, S3M and IT sat at 0.999 spectral against the references while the XM sat at
**0.731**, at the same duration — so a content bug, not a flow one. Our XM
render measured 3.4x the RMS of our own MOD render of the same song and 6x
libopenmpt's, saturating the limiter hard enough that the envelope correlation
against both was 0.09. With the flag removed, XM joins the others at **0.999**.

**Two methodological notes, both of which cost a wrong conclusion first.**

1. *"The same song in two formats must render at the same LEVEL" is not a real
   invariant.* Per-format mixing volume is implementation-defined and the
   references disagree with each other substantially — libopenmpt renders our
   S3M at 0.493 of the MOD level, libxmp at 0.353; XM is 0.676 against 0.901.
   My first regression test asserted cross-format level equality and failed on
   IT for a reason that was not a bug. What IS invariant is that voices must not
   ACCUMULATE.
2. *A before/after experiment can be invalidated by the stale test-kernel
   cache.* Flipping the flag and re-running reported the OLD behaviour twice,
   which read as "the flag does not matter" and nearly buried a confirmed bug.
   Print the value under test and check it changed. (My flip script also used
   BSD `sed` with `\|` alternation, which silently matches nothing on macOS —
   two independent ways to run an experiment that never ran.) The regression
   test was then verified red-then-green by hand, and a first version that used
   a REPEATED note passed with the defect in place: the channel walker appears
   to fold consecutive identical triggers into one run, so the notes must
   differ.

#### ⚠️ X2 was done TWICE, in parallel, by two agents (2026-07-27)

Both of us picked X2 off this ladder without claiming it on the board, and both
of us changed `tracker_replayer.dart`'s vibrato. That is the same failure this
board already warns about — *"flagging work here without CLAIMING it invites two
agents to do it"* — and it cost a rebase conflict in the hottest file in the
subsystem. **Claim a ladder item on the board before starting it.**

The work was complementary rather than wasted, and the merge kept both halves:

- The other agent found the **depth** half — vibrato is a period wobble, gated
  behind `PORTA_PERIOD` as `kVibratoPeriodAccurate` / `kVibratoPeriodPerDepthUnit`.
  Their `slidePitchByPeriod` reuse is cleaner than my open-coded clamp and
  survived the merge.
- I found the **rate** half, plus tremolo depth, tick 0, the retrigger flag and
  the ramp shape.

Worth reading their conclusion though: their commit states *"Rate was already
correct"* and books the leftover **~0.011 as waveform-table precision**. The
rate was not correct, and that residual WAS the rate — it is 0.000 now. A
plausible-sounding attribution for a leftover is how a real bug gets closed as
"expected noise"; the fixture sweep is what settled it, not either analysis.

One genuine inconsistency the merge had to fix: their two branches disagreed
about direction. The period branch bends DOWN on a positive lobe (correct — a
longer period is a lower pitch) while the semitone fallback still added to the
pitch, so flipping the gate reversed which way every vibrato started. Both
branches now bend down.

#### X5 CLOSED (2026-07-27) — and it found row timing drifting without bound

`test/mod_flow_timeline_test.dart` compares our `resolveTimingMap` against
**NodMOD** (github.com/erodola/nodmod, MIT), which walks a module's order list
in Python and yields every visited row with its onset, speed and tempo. Frozen
into `test/fixtures/flow/nodmod_timeline.json` by
`tool/nodmod_timeline_oracle.py` rather than shelled out to at test time — which
is the point: **this is the first piece of the replay audit that runs on CI.**
Everything else needs `openmpt123` / `xmp` / `mod2wav` and is opt-in, so the
numbers that found the vibrato rate and the IT break never guard a push.

Six order-list shapes × three formats: `Dxx` break to row 16, `Dxx` break to row
0, `Bxx` jump interacting with a break, `E6x` pattern loop, mid-song speed
change, mid-song tempo change.

**The find: our row onsets accumulated rounding, without bound.** A row lasts
`speed * 2.5 / bpm` seconds, which is a whole number of milliseconds only at
convenient tempos — 125 BPM at speed 6 is exactly 120 ms, but 160 BPM is 93.75
and 80 BPM is 187.5. `_rowMsFor` rounded EACH row and the callers added the
rounded values, so the error only ever grew in one direction:

| | ours | libopenmpt / libxmp / NodMOD |
| --- | --- | --- |
| `tempo_change_Fxx.mod` render | 20.720 s | **20.670 s** |
| last row onset | 20.532 s | **20.483 s** |

+0.25 ms on each of 24 rows at 160 BPM, +0.5 ms on each of 88 rows at 80 BPM =
the 50 ms measured. It is **unbounded** — 4000 rows at 160 BPM drift a full
second — and it reached BOTH the audio and the playhead, because the sample
counts were derived from the rounded millisecond value rather than from the tick
duration. So a long module at an awkward tempo rendered the wrong LENGTH and its
playhead slid against its own audio. 125 BPM at speed 6 happens to be exact,
which is why the default fixtures never showed it.

Fixed with one shared `rowOnsets(played, defaultBpm, perSecond)` that accumulates
the exact duration and rounds only at each boundary — error below half a unit
forever, whatever the length. Verified red-then-green by restoring the old
arithmetic: it fails at row 23 of `tempo_change_Fxx.mod`.

`_rowMsFor` — the round-a-single-row-to-whole-milliseconds helper — is **deleted**
rather than left available, since its rounding was the bug. Every row boundary,
in milliseconds or samples, now comes from the one accumulator.

⚠️ **Converting the FIRST four call sites left a fifth, and the suite caught it.**
The mono variable render path had its own copy of the accumulate-rounded loop, so
for a while the stereo renderer was exact and the mono one was not. It surfaced
as `midsong_timing_acceptance_test` failing on render-vs-`songTotalSamples`
(135 samples apart), not as anything that looked like timing — a half-converted
invariant reads as an unrelated inconsistency. `songTotalSamples` was also
derived as `songTotalMs * rate / 1000`; a millisecond is 44.1 samples, so the
transport sat up to a millisecond from the render it describes. It now shares
the accumulator too, and the two agree to the sample.

**⚠️ The oracle is not ground truth everywhere, and checking it first paid.**
Two entries are deliberately excluded, with reasons recorded in the generator:

- `pattern_loop_E6x.s3m` — NodMOD's S3M walker handles A/T/B/C/SE but **not
  `SBx`**, S3M's pattern loop, so it reports 128 rows where the loop makes it
  146. Both audio references render 17.5 s, agreeing with 146 — i.e. **we are
  right and the oracle is incomplete.** Pinning our correct behaviour to it would
  have been a self-inflicted bug.
- `pattern_loop_E6x.xm` — libopenmpt renders 16.66 s, libxmp 17.52 s. The
  **references disagree with each other** about FT2's loop-counter semantics, so
  there is no ground truth to freeze. ⬜ Open question, not a defect of ours.

IT has no NodMOD walker at all, which is exactly why the ladder calls it the
highest-risk reader: fewest oracles, most features. Its flow is covered here only
indirectly, through the audio sweep.

#### X3/X4 CLOSED (2026-07-27) — effect memory is per-COMMAND

The 14 original effect fixtures all restate their parameter on every row, so
none could see a memory bug. Four new ones state it ONCE and then send the bare
zero-parameter form, which is where ProTracker and FastTracker part company.

From `pt2_replayer.c`, the rule is **per-command**, not a blanket per-format one:

| command | ProTracker | XM / S3M / IT |
| --- | --- | --- |
| `1xx` / `2xx` porta up/down | reads `ch->n_cmd` — **no memory**, `100` slides 0 | latch |
| `Axy` volume slide | reads the row's parameter — **no memory** | latch |
| `3xx` tone porta | **latches** | latch |
| `4xy` vibrato | **latches**, per nibble | latch |

We latched everything. Measured against three engines agreeing at 1.000:

| fixture | before | after |
| --- | --- | --- |
| `mem_porta_up` | **0.270** | **1.000** |
| `mem_porta_down` | **0.531** | **1.000** |
| `mem_volslide` | 0.994 | 1.000 |
| `mem_tone_porta` (control) | 1.000 | 1.000 |

The control carried the diagnosis: `3xx` — the command that genuinely does
latch — was ALREADY perfect, which is what identified the fault as the blanket
RULE rather than a broken mechanism, and why the fix leaves `3xx`/`4xy` alone.

**Implementation, after the first design failed.** The rule needs the source
format at replay time, and `ReplayVoice` has no song reference. The obvious
route — thread a flag through the render helpers — cascades: what looked like
seven functions and ten call sites turned into thirty-five and still growing,
because the private helpers call each other several layers deep. I tried to
automate the conversion, the script mis-parsed, and the site count doubled every
round (35 → 874) until I reverted the file. **A cascade that grows under you is
the design telling you it is wrong.**

The flag rides `TrackerChannel` instead. Every render path already receives a
channel, so it reaches all ten `ReplayVoice` sites with **no signature changes
at all** — the three chunk-state classes needed a constructor parameter and
nothing else did. It is an odd home for a song-level format rule and the field
comment says so, but reach beat purity here.

The latch itself is a one-token change per command and needs no change at the
apply sites: `if (_param != 0 || protrackerMemory) _mem… = _param;`. Storing the
parameter unconditionally reproduces ProTracker exactly, so nothing downstream
has to know which rule is in force.

`traceChannel` gains an optional `protrackerMemory` (default false, so every
existing caller is untouched), which is what lets
`test/mod_effect_memory_test.dart` assert BOTH rules on CI without audio.

**The exemption announced its own obsolescence.** `mem_porta_up`/`mem_porta_down`
sat in the sweep's `_kKnownOpenDefects` while this was diagnosed-but-unfixed, and
the flag inverts to *"KNOWN OPEN now passing? drop the exemption"* — which is
exactly what it printed when the fix landed. The list is empty now and the
mechanism stays.

⚠️ **A threshold I invented failed on correct code.** The first regression test
asserted the bent pitch was `< 61.0` and it measured 61.25 — which is right, since
one row of `104` over five effect ticks bends 1.25 semitones. The test now
compares a bare command against NO command (they must be equal under ProTracker)
rather than against a number someone guessed.

⚠️ **This write-up was itself a casualty of the stale-tree clobber, and I did
not notice for a day.** `8a2c2d52` reverted the X3/X4 fix along with its PLAN
section; when I restored it I verified the four `lib/` files and the test file
against the reference players and never checked the DOCS. So this section read
"DIAGNOSED, NOT FIXED" while the fix was live on main — a doc that would have
sent the next reader to redo finished work, which is exactly how X2 came to be
built twice. **Restoring code is not restoring a commit.** Diff the whole
clobber, not just the parts you remember writing.

#### X10 (2026-07-27) — the sample layer is sound, except 16-bit loop UNITS

Five fixtures, one property of the playback layer each, all **XM** (MOD samples
are 8-bit forward-loop only, so a MOD fixture cannot exercise ping-pong or
16-bit at all). That drops micromod and leaves libopenmpt + libxmp — two
engines, still enough for the relative baseline.

The waveform is a RAMP, not a sine, on purpose: read forward and wrapped a ramp
is a sawtooth (every harmonic), bounced it is a triangle (odd harmonics, falling
much faster). So a wrong loop TYPE cannot quietly resemble the right one.

| fixture | refs | ours |
| --- | --- | --- |
| `loop_forward` | 1.000 | 0.999 |
| `loop_pingpong` | 1.000 | 1.000 |
| `loop_short` (32-frame loop after a 256-frame lead-in) | 1.000 | 1.000 |
| `oneshot_held` (no loop, held past the end) | 0.960 | 0.974 |
| `sample_16bit` | 1.000 | **0.207 → 0.999** |

**The loop arithmetic itself is fine** — forward wrap, ping-pong bounce, a short
loop inside a longer sample, and a one-shot that must stop all land on the
references. The one failure was **16-bit loop UNITS**.

XM stores sample length AND loop points in **bytes**, so a 16-bit sample's frame
counts are half the stored numbers. Our reader already handled the length (the
delta decoder yields `available ~/ 2` frames) but passed the loop points through
verbatim, so a 16-bit sample looped over twice its intended range — off the end
of its own buffer. libxmp states the rule outright (`xm_load.c`, under
`XM_SAMPLE_16BIT`: `len >>= 1; lps >>= 1; lpe >>= 1`).

⚠️ **The writer had the matching bug**, emitting frame counts where the format
wants bytes — so `parseXm(writeXm(x)) == x` held perfectly while the FILE meant
something else to everyone else. Verified by asking the references whether our
16-bit fixture and our byte-identical 8-bit one were the same music: **they said
0.21.** After fixing both sides they say **1.000**.

**This is the THIRD bug of exactly this shape in this audit** — a format unit or
encoding convention wrong in both directions, self-consistent, invisible to
round-trip testing (IT's hex pattern-break row was the first, XM's loop units the
third). The lesson has earned its place: **`parse(write(x)) == x` cannot catch a
misunderstanding the reader and writer SHARE.** Only a foreign reader can, and
the cheap version of that is asking a reference player whether two files you
believe are equivalent really are.

⬜ Left open: `oneshot_held` shows the references only agreeing at 0.960 with
each other — they disagree about what a one-shot does after its end (fade vs
hard stop). We sit inside that spread at 0.974, so nothing is wrong, but it is
another case where there is no single right answer to gate on.

#### X9 continued (2026-07-28) — envelopes, and two ways to lose a pan sweep

The shaping layer: XM/IT volume and pan envelopes plus fadeout. Both directions
already supported them, so this was a fidelity question rather than a feature
gap — and **volume envelopes turned out to be sound.** Shape, rate and per-note
RESTART all land on the references (spectral 1.000, envelope 0.94–0.99), which
matters because the structural worry going in was that the importer folds each
instrument's envelope onto the CHANNEL, and a channel has nowhere to put
"restart". It restarts correctly; that worry was unfounded.

**Panning was lost twice over, in two different layers.**

*1. An early return made correct code unreachable.* `_renderChannelIntoStereo`
has a proper pan-envelope path — base pan plus the envelope offset, per sample,
per note. Above it sits a fast path for channels with no per-tick effect, and an
envelope is not a command, so **every** channel carrying a pan envelope and no
effects returned from the fast path with the sweep silently dropped. We rendered
dead centre in both formats while both references swept hard left to hard right.
⚠️ **Same shape as the `8xx` set-pan bug** — shaping implemented, correct, and
never reached. Two for two now: when a pan feature measures as *exactly*
centred, suspect the dispatch before the arithmetic.

*2. The neutral model was not neutral.* IT stores a pan envelope **signed**,
−32…+32 with 0 as centre; XM (and our neutral model) use 0…64 with 32 as centre.
`_docEnvFromIt` copied the points through verbatim for both, so an IT pan
envelope arrived meaning 32 less than it said — IT's centre read as hard LEFT.
It round-tripped perfectly, because the writer made the matching assumption. The
sweep caught it as correlation 1.00 with a mean position a full 1.00 out: the
shape was right and sitting half a range too far left. ⚠️ **Only a CROSS-FORMAT
comparison can see this class:** the same authored `DocEnvelope` written to XM
and to IT must come back meaning the same thing, and neither format's own round
trip can tell you it doesn't. That is now a CI-able test needing no reference
players at all (`envelope_shape_test.dart`), and it fails on the old code.

That fix reaches further than the replayer: `_xmEnvFromDoc` copies the neutral
points straight into an XM envelope, so **converting an IT module to XM used to
write the signed values into a field XM reads as 0…64** — every pan envelope
arriving half a range left in the converted file, quite apart from how we play
it. One conversion, two consumers, and only the neutral model in the middle was
wrong.

⚠️ **The fixtures here are the least independent in the audit, and it paid for
itself immediately.** An effect is a byte — write the wrong one and the
references do something visibly different. An envelope is a SHAPE: encode it
wrongly and both references read the same wrong shape, agree with each other,
and our replayer reads the same file back, so the error cancels and the sweep
goes green. So before comparing anything to us I checked the reference render
against ARITHMETIC — a ramp whose length in ticks is known in advance. That
check immediately caught **every IT fixture rendering silent** (an IT keymap is
1-based; I had filled it with 0, meaning "no sample"). A silent file we also
rendered silent would have "agreed" perfectly.

#### X9 continued (2026-07-28) — tremor, and the byte that said KEY OFF

Tremor was the last effect with no audio fixture. It is a pure VOLUME effect, so
the spectral gate is blind to it by construction and it could not be measured at
all until the envelope metric existed.

**The gate restarted every row.** Our implementation was `k % (x + y)` on the
tick index WITHIN the row; the real counter is per-channel and free-runs for as
long as the command is held. The fixture is `I32` at speed 6 on purpose — five
does not divide six, so a row-locked reading cannot coincidentally agree.
Envelope correlation 0.33 against two references agreeing at 1.00; now 0.97.

**Then the XM fixture failed for a different reason: the file was wrong.** XM's
effect numbering IS ours from `10h` up — that is why `G`/`H`/`P`/`R` pass
straight through — with one exception, and the exception was mapped backwards.
XM `14h` is **key off**; tremor is `1Dh` (libxmp `src/effects.h`: `FX_KEYOFF
0x14`, `FX_TREMOR 0x1d`). We rewrote tremor↔`14h` in BOTH directions, so
`parseXm(writeXm(x)) == x` held perfectly while openmpt123 rendered our tremor
fixture as one unbroken tone — a key-off on an instrument with no envelope does
nothing at all. Key off already had a home in the neutral model (the note column
carries it as note 97), so the effect spelling now lands there. The same
expression also wrote `kFxSetSpeedFull` — which is `14h` in OUR numbering — out
as a key-off; it maps to XM `F` with a clamp now, since XM's `F` splits its
range at `20h` and has no full-range speed. ⚠️ **Fourth both-directions format
bug in this audit** (IT hex break row, XM 16-bit loop units, the fine-porta
reverse map). A reader and writer that share a misunderstanding agree with each
other perfectly; only a foreign reader can see it. `test/xm_effect_numbering_
test.dart` therefore asserts the BYTES ON DISK, not the round trip.

**Reading the source was not enough — dumping the per-tick gate was.** libxmp
has two tremor functions and a suppress bit, and my first cut collapsed the
difference into one boolean, which measured no better than no fix at all. What
made the rules legible was printing each reference's on/off pattern tick by
tick:

    IT   ###..###..###..            x on, y off
    S3M  ####...####...             x+1 on, y+1 off  (ST3's off-by-one)
    XM   #####....#####...          FT2: no advance on tick 0, gate suppressed
                                    after a note — its beat against the 6-tick
                                    row is what makes the period irregular

All three are reproduced EXACTLY, tick for tick, by `TremorModel` on the profile.
The XM pattern in particular is not a rounding artefact, which is what it looks
like until you have the state machine.

**A second fixture, `I00`, settled a rule the unit tests had only assumed.** Our
trajectory test asserted that a tremor with both nibbles zero "leaves the note
fully on" — a cycle of nothing to gate. It is wrong: outside FT2 a zero nibble
is incremented to ONE, so `I00` alternates every single tick (`#.#.#.` in both
references, which our render now matches exactly). I nearly fixed that from the
source alone; the fixture cost one line and turned a source reading into a
measurement, which is the same order that caught the counter bug.

⬜ **`tremor_I00.xm` is a KNOWN OPEN defect, and it is not the tremor rule.**
Our gate matches openmpt character for character for 136 ticks and the per-tick
levels agree within 2% — then both references go silent and stay silent while
our note plays on to the end of the pattern. Isolated by measuring the last
audible tick of every fixture in both engines: this is the ONLY one where they
part (them 136, us 176; everything else runs to ~180), so it is specific to FT2
with a zero parameter. libxmp's own note points at the mechanism — *"Tremor
likely just overwrites the channel volume in FT2"* — i.e. FT2's tremor writes
the channel volume rather than gating a copy, so a degenerate parameter can
latch the channel at zero. ⚠️ I first explained this as a metric resolution
limit (a 40 ms gate against a 10.7 ms envelope block) and was about to exempt it
on that basis; **varying only the block size disproved it** — the correlation
stays ~0.64 at every block size while the references hold 0.98. Control before
exempting, not just before fixing.

⚠️ **The one place in this audit where the references genuinely disagree.**
libxmp plays S3M tremor with the plain IT counter; openmpt applies ST3's
x+1/y+1. There is no inter-reference consensus to gate on, so the choice is
documented as a judgement call — openmpt carries a per-quirk regression module
for the behaviour, and libxmp's S3M loader comment is the generic description of
the effect rather than a claim about ST3 — and NOT presented as measured.

#### X9 continued (2026-07-27) — the S3M/IT command set, and a stale comment

Every fixture in `fx/` is a MOD, so nothing reached the S3M/IT letter commands.
`fmt/` adds one per file, written as **both** S3M and IT — sharing a command set
means a divergence in one and not the other localises the fault to that reader.

**Fine PORTAMENTO was badly broken.** S3M/IT overload the portamento parameter
by RANGE: `0xF0`–`0xFF` is a FINE slide (low nibble, once on tick 0), `0xE0`–
`0xEF` an EXTRA-fine one (quarter units, also once), and only below `0xE0` is it
the ordinary per-tick slide. We passed the whole byte through as a normal slide,
so `EF4` — four period units once — became a slide of **244 units every tick**:

| fixture | before | after |
| --- | --- | --- |
| `fine_porta_up_FFx.it` | **0.131** | **1.000** |
| `fine_porta_down_EFx.it` | 0.510 | **1.000** |
| `extrafine_porta_down_EEx.it` | 0.458 | **1.000** |
| `extrafine_porta_down_EEx.s3m` | 0.455 | 0.987 |

The replayer already had `E1x`/`E2x` (MOD's own once-per-tick-0 fine porta), so
this was routing, not a new mechanism. libxmp confirms the semantics exactly:
fine is `fslide = ±fxp`, extra-fine `fslide = ±0.25 * fxp`. ⚠️ Extra-fine is
therefore APPROXIMATED — we have no quarter-unit command, so it maps to fine
with `x ~/ 4`: right for the common `EE4`, and rounds to nothing below it.
`E1x`/`E2x` were also missing from the REVERSE map, so a fine porta was silently
dropped on export even once the reader could produce one.

⬜ **Two format-specific gaps remain, measured and listed in the sweep's
`_kKnownOpenDefects` so they print every run:**

| | S3M | IT |
| --- | --- | --- |
| plain `Exx`/`Fxx` | **1.000** | 0.683 / 0.544 |
| fine `EFx`/`FFx` | 0.857 / 0.828 | **1.000** |

The inversion is the clue. IT's plain porta most likely wants **linear frequency
slides** (IT carries a linear-slides flag that libopenmpt honours; we slide the
period) — which would also explain why IT's FINE porta is perfect, since
once-per-row steps are small enough for the two curves to agree. S3M's fine
porta looks like a constant scaling factor: the extra-fine variant is a quarter
of the step and roughly a quarter of the error (0.987 vs 0.857).

**Two method notes, both corrections to my own reasoning:**

1. ⚠️ **The "fine slides are approximated as a normal slide" comment sent me
   after the wrong effect.** I expected the VOLUME slides to be broken and built
   the fixtures to prove it. Every `Dxy` form measures 1.000 — but see (2)
   before believing that. The portamento family, which the comment does not
   mention, was the one that was wrong.
2. ⚠️ **Those volume-slide 1.000s are not evidence.** Spectral similarity is a
   cosine of magnitude spectra and therefore amplitude-invariant, so it cannot
   see a volume effect at all — the same trap that hid tremolo's 4× depth in X2.
   `DFx` may well be as wrong as `EFx` was; the metric simply cannot say.
   ⬜ **The volume-slide fixtures need an ENVELOPE measurement before anyone
   concludes anything from them.**
3. ⚠️ I repeated X1's own fixture mistake — holding a slide for all 31 rows runs
   it off the period table, so clamping dominates and the references disagree
   about their clamp policies rather than about our slide. Bounding the hold to
   8 rows moved `porta_down_Exx.s3m` from 0.982 to 1.000 with no code change at
   all. The lesson was already written down; I still had to relearn it.

#### The sweep gains an ENVELOPE metric (2026-07-27) — and it found three things

The audit's only gate was spectral similarity, which is a cosine of magnitude
spectra and therefore **amplitude-invariant**. It cannot see a volume effect at
all. That blind spot had already hidden tremolo's depth being 4× too shallow
(X2) and was why every `Dxy` fixture read 1.000 without that meaning anything
(X9). So `Axy`, `Dxy`, `Cxx`, `7xy` and the volume column were effectively
ungated.

The sweep now reports envelope correlation (Pearson over the RMS envelope —
scale-invariant but SHAPE-sensitive, which is what a fade is) on the same
inter-reference baseline, and gates on it under two conditions: the references
must agree about the envelope (≥0.5) **and** that envelope must actually move
(a 90th/10th percentile ratio ≥1.6). The second condition matters — a sustained
note has a flat envelope and Pearson between two flat signals is dominated by
whatever ripple each render happens to have, which produced false reds on pure
PITCH fixtures until it was added.

It found three things immediately:

1. ✅ **S3M/IT fine VOLUME slides were misread**, exactly as the stale comment
   said and exactly as spectral could not see. `DFy` is a fine slide DOWN by y
   and `DxF` a fine slide UP by x, applied ONCE on tick 0; we mapped the whole
   byte to MOD's per-tick `Axy`. `fine_volslide_down_DFx` **0.63 → 0.98**
   envelope. `EAx`/`EBx` were missing from the reverse map too, so a fine volume
   slide was dropped on export as well.
2. ✅ **S3M/IT slide volume on EVERY tick, including tick 0**; MOD and XM skip
   the first. libxmp models it as `QUIRK_VSALL` and sets it for the
   ScreamTracker family. Fixed via `TrackerChannel.volumeSlideAllTicks`, the
   same path as the effect-memory flag. ⚠️ **Source-justified but NOT confirmed
   by measurement** — the finding below masks it.
3. ⬜ **The VOLUME COLUMN does not set the channel volume.** Our replayer maps a
   cell's volume onto `noteVolume`, a 0..1 per-note multiplier, while `Axy`
   slides `volume`, the 0..64 CHANNEL volume — which is still at its default of
   64. So a slide UP from a quiet volume-column note starts already clamped and
   does nothing, where the references ramp 8 → 64.

   The ASYMMETRY is what identified it: the DOWN fixtures start at 64, which is
   the default, and pass at 1.00; only the UP fixtures fail. A rate error would
   have hit both.

   **Not fixed**, deliberately: `TrackerCell.volume` is shared with the app's own
   authoring — the Loop Mixer's ghost notes use it as a multiplier — so making it
   set the channel volume changes song semantics, not just module import. That is
   a decision about the tracker's own model, not a bug fix. The four affected
   fixtures are in `_kKnownOpenDefects` and print every run.

#### IT/XM LINEAR frequency slides (2026-07-27) — and the gate was the wrong shape

The last plain-portamento gap. IT and XM bend pitch **linearly** (a fixed
interval per unit); MOD and S3M bend the Amiga **period**, which is the same
step in a different space and therefore a different interval depending where the
note sits. Both formats carry a header flag for it and libopenmpt honours it. We
always slid the period.

The diagnosis needed no source reading at all — the same command written into
both formats and measured under each model is a **perfect mirror image**, which
is what makes it certain rather than plausible:

| | period model | linear model |
| --- | --- | --- |
| `porta_down_Exx.it` / `porta_up_Fxx.it` | 0.683 / 0.544 | **1.000 / 1.000** |
| `porta_down_Exx.s3m` / `porta_up_Fxx.s3m` | **1.000 / 1.000** | 0.685 / 0.543 |

Both formats read 1.000 now, and IT's fine porta and extra-fine came along with
it (extra-fine's envelope went 0.19 → 0.93).

⚠️ **This says the `PORTA_PERIOD` gate is the wrong SHAPE, not just off by a
default.** The slide model is a per-FORMAT property — MOD/S3M period, IT/XM
linear — and no single global switch can be right for a library holding all
four. `TrackerChannel.linearSlides` now takes precedence for IT/XM and leaves
MOD/S3M entirely to the gate, so the maintainer's pending decision about the MOD
default is untouched. ⬜ **When that decision is made, the gate should probably
become "MOD/S3M use period slides", full stop, rather than a switch at all.**

**The sweep's reporting had two bugs of its own, in opposite directions.** The
"now passing? drop the exemption" flag looked only at the spectral gap, so it
told me to retire exemptions whose ENVELOPE was still failing — the exact
mistake the flag exists to prevent. And a known-open entry failing *only* on the
envelope printed no flag at all, silently hiding the thing the list exists to
keep visible. Both fixed: one status per row, naming which metric failed
(`spectral`, `envelope`, or `spectral+envelope`).

⬜ **Remaining, all printing every run:** S3M fine porta (0.857/0.828 — a
constant scale factor, since extra-fine has a quarter the step and a quarter the
error), and the four volume-column fixtures whose cause is already diagnosed
above (the volume column does not set the channel volume).

#### The slide model is a SETTING now, and `PORTA_PERIOD` is gone (2026-07-28)

Maintainer's call, and it resolves the decision that had been open since X1.

**The gate is deleted.** It was wrong in shape as well as default: one global
switch cannot be right for a library holding MOD, XM, S3M and IT at once. XM and
IT bend linearly by definition; MOD and S3M bend the period, which is what
libopenmpt, libxmp and micromod all do. **Every portamento fixture now reads
1.000 with no compile-time flag at all** — the shipped default is the measurably
correct one.

**Where a real preference remains it is a user setting.** MOD/S3M
hardware-accurate versus the gentler evenly-spaced reading is a taste question —
a fixed period step bends further the higher the note, so a long slide
accelerates, which is authentic and not always wanted on material never written
for an Amiga. `SettingsService.authenticSlides`, on by default, de/en localised.

The shape of the setting is what makes it safe, and
`tracker_authentic_slides_setting_test.dart` pins each part:

- it changes the **pitch domain and nothing else** — the profile is otherwise
  identical, so it cannot quietly alter memory or tick behaviour;
- it reaches **MOD and S3M only**. Letting it touch XM/IT would be breaking
  those formats rather than offering a choice, which is exactly what the old
  global gate did;
- it is resolved at **import**, into the song's `ReplayProfile`, so the replayer
  consults nothing global and a song already open keeps the rules it was opened
  with. `songFromModuleDoc` takes an explicit argument and only falls back to
  `trackerAuthenticSlidesDefault` when a caller says nothing — which keeps module
  import a pure function the CLI tools and audit harnesses call without wiring up
  settings.

⬜ The sweep's `_kPeriodModelDependent` exemption is deleted with the gate: those
four fixtures are held to the same bar as everything else now and pass. **A
setting is not a reason to stop measuring the default.**

#### Fine porta bypassed the pitch domain (2026-07-28) — the fifth slide site

The `PitchDomain` refactor collapsed four scattered slide sites into domain
calls. There was a fifth, in the extended-command switch rather than the
portamento block, and it was still hardcoded:

```dart
case kExFinePortaUp:   pitch += _exVal * kPortaSemitonesPerUnit;
case kExFinePortaDown: pitch -= _exVal * kPortaSemitonesPerUnit;
```

Always linear, whatever the format wanted — right for XM/IT, wrong for MOD/S3M.

⚠️ **My recorded hypothesis for this gap was wrong, and the shape of the
evidence said so.** PLAN had it down as "an S3M constant scale factor, since
extra-fine has a quarter the step and a quarter the error". The real split was
by DOMAIN: identical command, 1.000 in IT and 0.857 in S3M. Extra-fine merely
looked closer because a quarter-sized step makes two curves diverge a quarter as
much — which is equally consistent with a scale error and with a wrong domain,
so it never distinguished them. The thing that did was noticing which FORMATS
disagreed, not by how much.

| fixture | before | after |
| --- | --- | --- |
| `fine_porta_down_EFx.s3m` | 0.857 | **1.000** |
| `fine_porta_up_FFx.s3m` | 0.828 | **1.000** |
| `extrafine_porta_down_EEx.s3m` | 0.987 / env 0.19 | **1.000 / env 0.94** |

**MOD's own `E1x`/`E2x` were wrong too, and nothing said so** — there was no
fixture for them. `fine_porta_up_E1x.mod` / `fine_porta_down_E2x.mod` exist now
and both read 1.000. Held for 20 rows, not 8: a fine slide moves once per ROW,
so a short run sits inside the references' own spread and proves nothing.

**The rule this leaves behind:** if it moves `pitch`, it goes through `_domain`.
Three exemptions retired; the only ones left are the four volume-column
fixtures, whose cause is a semantics decision rather than a bug.

#### The THIRD metric blind spot: panning (2026-07-28)

Every comparison the audit made downmixed both channels to mono first, so no
panning effect could register at all — `Yxy` panbrello, `S8x` set-pan, `Pxy` pan
slide, `S9x` surround. That is the third gap of this exact shape, and each was
only found after the previous one was closed:

| metric | blind to | what it hid |
| --- | --- | --- |
| spectral similarity | amplitude | tremolo's depth, 4× too shallow |
| (no envelope metric) | fade shape | the whole volume-slide family |
| mono downmix | stereo position | panbrello, **8× too fast** |

**Panbrello ran eight times too fast.** The constant sat at 32/x with a comment
saying it was unverified — ProTracker has no panbrello, so the 64/x finding that
fixed vibrato was no evidence about it. Declining to guess was right; the
evidence just had to be gone and got. Counting pan sweeps off the renders:

| | ours (32/x) | openmpt | xmp | 256/x predicts |
| --- | --- | --- | --- | --- |
| speed 4 | **18** | 3 | 2 | 2.25 |
| speed 2 | **9** | 2 | 1 | 1.125 |

Now 3 and 2, matching openmpt exactly. Its fixtures had been reading **1.000
spectral and 0.93 envelope** throughout.

**The metric needed fixing before it could be trusted.** Silent blocks were
being read as pan 0, but silence is not "centred": a note-cut fixture panned
hard left produced a trajectory jumping between −0.5 and 0, i.e. travel the
render never made, which then let statically-panned fixtures through the gate to
be compared on noise. Quiet blocks now HOLD the last position. `notecut_ECx.mod`
correctly reads `pan --` after that, where it had been gating on an artifact.

⚠️ **Honest limit of the pan gate.** The references correlate at only ~0.0–0.36
with EACH OTHER on these fixtures: with two or three cycles over the run, a
phase offset dominates Pearson. So the gate confirms we sit inside their spread
and little more — it was the CYCLE COUNT that settled the rate, not the
correlation. A gate that cannot distinguish 18 cycles from 3 is not the tool
that found this, and the write-up should not imply otherwise.

⬜ **Left open: panbrello DEPTH is ~10% shallow** — travel 0.89 against the
references' 0.98–0.99. Small next to an 8× rate error and now measurable, which
is the point of having the metric at all.

#### Trackers pan LINEARLY (2026-07-28) — and `8xx` set-pan is ignored

`test/fixtures/fmt/setpan_*_Xxx.it` holds a note at a FIXED pan. There is no
depth in it, so whatever it measures is the LAW:

| position | linear | constant power | openmpt | libxmp |
| --- | --- | --- | --- | --- |
| 0xC0 (¾ right) | +0.500 | +0.414 | **+0.485** | **+0.484** |

Both references pan linearly; we panned constant-power. `PanLaw` is now a
`ReplayProfile` field — linear for the four tracker profiles, **constant power
for `native`**, so our own material keeps the law that holds a sound's apparent
loudness as it crosses the field. That is a taste call for our songs and the
wrong answer for reproducing a module.

⚠️ **The law was hiding the SIGN of the depth error, not just its size.** With
constant power, panbrello's travel measured 0.89 against 0.99 and read as ~10%
SHALLOW; with the law corrected the same depth measured 1.07 — too DEEP. The
constant was 1/15, the natural guess if the nibble reads as 0–15 of a sweep; it
is 1/16. Travel is now **0.999 against openmpt's 0.993**. Three times now a
magnitude discrepancy has failed to identify its own cause (vibrato's "depth"
was rate, S3M fine porta's "scale" was domain, panbrello's "depth" was the law):
**a control fixture with the suspected variable removed is what settles it.**

⬜ **NEW, and bigger than the law: `8xx` set-pan is IGNORED on at least one
stereo render path.** Our travel on the setpan fixtures is **0.00** where
openmpt gives 0.50. The cell survives import intact (`fxCmd=8`, `param=0xC0`,
`stereoOutput=true`) and `kFxSetPan` is handled in four places, so a render path
this fixture takes is not one of them. Entirely invisible before the pan metric
existed. Not fixed here — it wants an audit of every stereo path rather than a
patch at the first site that looks likely.

⚠️ **Design cost of putting the profile on `TrackerChannel`, now visible.** Nine
places synthesize a derived channel (`zoneChannel`, `baked`) and none inherited
the profile, so zone-based renders silently fell back to `native` rules. Fixed
with `..profile = <source>.profile` at each. The field lives on the channel for
REACH — every render path already receives one — and this is what that costs:
a derived channel has to remember. A `TrackerChannel.derivedFrom()` helper would
make it structural rather than remembered.

#### `8xx` set-pan rendered dead centre (2026-07-28)

Our travel on `setpan_*_Xxx` was **0.00** where libopenmpt gives 0.50. The cell
survived import intact (`fxCmd=8`, `param=0xC0`, `stereoOutput=true`) and
`kFxSetPan` is handled in four render functions — so the path this fixture took
was not one of them.

The cause is one omission in `_hasPerTickEffect`, the predicate that decides
whether a channel needs the effect-aware renderer. It lists nineteen commands
and not `8xx` or `Pxy`. A channel whose ONLY effect is a set-pan therefore fell
through to the simple note path, which has no pan at all. Its own doc comment
already argued the case for the same class of exception — `SAx` "DOES count"
because a later `9xx` reads the memory it seeds — so the shape was established
and pan was simply missed. Now **0.479 / 0.483 against openmpt's 0.485**.

⚠️ **This was invisible for as long as the audit downmixed to mono**, which is
every comparison before the pan metric. Worth stating plainly: `8xx` is not an
obscure command.

**The pan metric took three passes to measure what it claims to.** Each pass was
found by disbelieving a number that looked fine:

1. Silent blocks read as pan 0. Silence is not "centred", so a note-cut fixture
   panned hard left produced a trajectory swinging between −0.5 and 0 — travel
   the render never made — which let statically-panned fixtures through the gate
   to be compared on noise. Quiet blocks now HOLD the last position.
2. Holding fixes the middle and not the HEAD, which has nothing to hold. A
   delayed note's lead-in sat at 0, putting a fake step at the first note and
   skewing the mean by however long the lead-in was — and lead-in length differs
   between renders. `notedelay_EDx.mod` failed on exactly that, 0.16 off
   references that agreed with each other perfectly. Leading silence is now
   back-filled with the first real position.
3. **Correlation is the wrong statistic for pan.** Pearson degenerates on
   anything near-constant: two references measuring the same STATIC pan came out
   correlating at **−1.00 with each other**. The gate now rides on MEAN POSITION,
   which is in pan units, directly interpretable, and would have called this bug
   at a glance (0.00 against 0.485). Correlation is still reported — it catches a
   wrong RATE that a mean cannot see — but it does not gate.

The general lesson, which cost three iterations here: **a metric that passes is
not thereby working.** Each of these passed everything while measuring the wrong
thing, and each was caught by asking why a specific number looked the way it did.

#### `TrackerChannel.derivedFrom` (2026-07-28) — inheritance made structural

The render paths synthesize channels in nine places (`zoneChannel`, `baked`) to
isolate one zone or one baked instrument. When `ReplayProfile` became a field,
none of them carried it, so **zone-based renders silently fell back to `native`
rules** — a MOD bending pitch linearly and panning constant-power inside an
otherwise correct song. Nothing failed: `native` is a valid profile, merely the
wrong one. That is what makes this class of bug worth a guard rather than a
convention.

Patching it with `..profile = source.profile` at nine call sites — which is what
the pan-law commit did — works until the tenth is written. `derivedFrom` copies
everything by default and takes overrides only for what differs, so a field
added to the class later is carried without anyone remembering to.
`tracker_channel_derived_test.dart` pins it, including a **source-driven** check
that no `..profile =` reappears in the replayer — a hand-maintained list of
call sites would go stale exactly when it matters, the same reasoning as the
command-collision guard.

⚠️ Note what stays: the plain constructor still defaults to `native`, because a
channel nobody told otherwise IS one of ours. That default is what made
forgetting silent, and it is still the right default — the fix is to make
inheritance easy, not to make the default hostile.

#### The ladder — check each stage before trusting the next

✅ **X0 — Re-baseline every A/B gate against inter-reference agreement.** DONE,
see above. Gate is now `refAgree − ourWorst < 0.08`, with an absolute fallback.

**X1 — One effect per fixture.** `effects.mod` runs four effects on four
channels at once, so a failure cannot be localised — which is why it read as
"effects are a bit off" instead of naming a command. Emit one fixture per
effect (arpeggio `0xy`, porta up/down `1xx`/`2xx`, tone porta `3xx`, vibrato
`4xy`, tremolo `7xy`, volume slide `Axy`, offset `9xx`, and the `Exy`
sub-commands we claim), each a single sounding channel. Done when every claimed
command has a fixture and a measured deviation.

✅ **X2 — Vibrato/tremolo depth, rate and waveform.** DONE, see above. Rate was
2× (the residual), tremolo depth 4× shallow, tick 0 wrongly an effect tick, the
retrigger flag ignored, the ramp inverted. ⬜ Left open: tremolo depth
re-measured with an envelope metric, and panbrello's rate against an IT
reference.

✅ **X3 — Portamento family. CLOSED.** Effect memory fixed (`ReplayProfile.
latchPortaParam`), fine/extra-fine routing fixed, and fine porta stopped
bypassing the pitch domain. Every portamento fixture reads 1.000 in all four
formats. *(This line read "diagnosed and not yet fixed" for a day after the
`8a2c2d52` clobber reverted the update — see the X3/X4 section above.)* The
original scope, for the record: `1xx`/`2xx` step per tick, `3xx` target snapping,
period clamping at the table edges, and effect MEMORY (a bare `300` continuing
the previous rate) — memory bugs are invisible on a single-row fixture and
obvious on a sustained one.

🔶 **X4 — Volume slide + tremor semantics. MOSTLY CLOSED.** `Axy`'s memory
rule is fixed, S3M/IT fine volume slides are routed, and `QUIRK_VSALL` (volume
sliding on tick 0) is honoured. The ENVELOPE metric it wanted now exists and
gates them. ⬜ Genuinely open: **tremor (`Txy`) is untouched**, and the four
volume-COLUMN fixtures are blocked on a semantics decision, not a bug. Original
scope: `Axy` per-tick vs per-row, the
"both nibbles set" ambiguity ProTracker and later trackers resolve differently,
and interaction with `5xy`/`6xy` (porta/vibrato + volume slide combinations).
🟡 **PARTIAL (2026-07-27, opus tracker→editors).** The both-nibbles ambiguity is
FIXED: `Axy` netted `+x−y`; ProTracker/XM read the UP nibble first — nonzero x
slides up by x and IGNORES y (`pt2_replayer.c` volumeSlide), so `A24` is +2, not
−2. Only the both-nibbles case changes; `Ax0`/`A0y` are byte-identical, so real
modules (which rarely set both) are unaffected. Pinned with exact
volume-trajectory asserts in `tracker_replayer_test.dart` (a LEVEL effect, so
spectral similarity would miss a wrong depth — trajectory is the right instrument
here). Still open: `5xy`/`6xy` combos and S3M/IT `Dxy` fine-slide (`DFx`/`DxF`)
nibble semantics, which resolve the ambiguity differently again.

✅ **X5 — Timing/flow against NodMOD.** DONE, see above — and it is the first
CI-able piece of the audit. `iter_playback_rows()` yields
(pattern, row, start_sec, end_sec, speed, tempo) from an independent
implementation. Compare against our `songFlowTimeline`/`resolveTimingMap` over
a corpus of order-list shapes: `Bxx` jumps, `Dxx` breaks, `E6x` pattern loops,
mid-song speed/tempo changes. **No audio needed, so this one can run in CI.**
🟡 **PARTIAL (2026-07-27).** The NodMOD oracle is not installed on this machine,
but the flow commands are DISCRETE and exactly computable by hand, so the two
that had zero coverage — **E6x pattern loop** and **EEx pattern delay** (the
trickiest, per-channel-counter ones) — are now pinned deterministically in
`test/mod_flow_pattern_loop_test.dart` (E6x span plays x+1×, E60 sets the start,
EEx repeats a row x+1×, Fxx speed/tempo split at 0x20, and the per-visit timeline
grouping). `walkFlow` was verified ProTracker-correct against pt2-clone's rules.
The FULL NodMOD cross-check (start_sec/end_sec timing over a Bxx/Dxx corpus)
still wants NodMOD cloned — left open.

🚧 **X6 — Reader field audit, per format.** Partly done: the IT pattern-break
reader is fixed (above). The general audit stands. Our codec tests are self round-trips
(`parse(write(x)) == x`), which cannot catch a misunderstanding our reader and
writer SHARE. Cross-check parsed structure against NodMOD (MOD/XM/S3M) and
against `openmpt123 --info`. IT has no structural oracle — treat it as the
highest-risk reader and lean on audio there.

🚧 **X7 — Writer audit: our writer → THEIR reader.** Partly done, and this is
exactly how the IT break bug surfaced — our writer against libopenmpt's and
libxmp's readers. Generalise it. Write each format from a
known doc, load it with NodMOD and libopenmpt, assert the structure matches
what was authored. `probe_file` already reports zero warnings on our MOD; make
that a test rather than a one-off, and extend to XM/S3M.

✅ **X8 — XM channel polyphony** (renumbered into use above; the fixture-
independence item below keeps the label in the original ordering). ⬜ **Fixture
independence** is still open: `musical.mod`/`effects.mod` are written by OUR
writer, so a writer bug is baked into every A/B that uses them. Author the same
content with NodMOD and confirm both files render identically; any difference
is our writer, not our replay.

🔶 **X9 — Extend the A/B to XM/S3M/IT. MOSTLY DONE.** It paid seven times over:
the IT hex break row, XM channel polyphony, XM 16-bit loop units, S3M/IT fine
porta and fine volume slides, IT/XM linear slides, **tremor's free-running
counter**, and **XM's tremor/key-off effect numbering**. Flow fixtures ship in
all four formats and `fmt/` covers the S3M/IT letter commands MOD has no
encoding for. **Envelopes are measured now too** — volume/fadeout were already
sound, and panning was lost twice (an unreachable render path, and IT's SIGNED
pan envelope read as unsigned). ⬜ Still open: **NNA/DCT** (new-note actions),
which no fixture reaches yet.
Original scope: `convertToXm`/`convertToS3m`/`convertToIt`
already exist, so the same musical content can be emitted in all four formats.
⚠️ Expect DIFFERENT failure modes, not the same one four times: XM/S3M/IT store
an explicit sample rate per sample, so the MOD tuning question does not recur —
what these probe is envelopes, NNA, volume/pan models and effect semantics.
IT is thinnest on oracles (libopenmpt + libxmp only) and richest in features,
so it carries the most risk.

🔶 **X10 — Sample-playback layer. MOSTLY DONE.** Forward wrap, ping-pong, a
short loop inside a longer sample, one-shot-past-the-end and 16-bit loop UNITS
are all verified against the references at 0.999+. ⬜ Still open: interpolation
quality and stereo samples — though every sample fixture already reads 0.999,
which is weak evidence that interpolation is not a problem at these levels.
Original scope: Interpolation, loop wrap (see the one-sample
rescale bug already fixed), 8- vs 16-bit and stereo sample paths, `9xx` offset
clamping, ping-pong loops. Oracle: single-note fixtures per case.

Ordering: **X0 → X1** first (they make everything else measurable), then X5 and
X6/X7 (cheap, CI-able, no audio), then X2/X3/X4 on the isolated fixtures, then
X9/X10. X8 whenever a result looks impossible.

## Consolidated backlog (2026-07-25 doc sweep)

Pending work carried over when ~40 handover/scoping/status docs were consolidated.
**Group 1** items came from docs that were *deleted* (full detail preserved here).
**Group 2** items still have a live reference doc — the pointer is authoritative;
kept here so nothing is lost from the canonical plan.

### Group 1 — residuals from deleted docs (no other home)

> ⚠️ **This list is STALE in places — check before you build.** An audit on
> 2026-07-26 found **nine** of its items already shipped (the whole Audio-FX
> block bar one, and the starter-module generator), because the list was frozen
> when ~40 docs were consolidated and never re-checked against the code. Each
> line below now says ✅/⬜ with `file:symbol` evidence where it's been verified.
> **If you pick something up, grep for it first** — with this many agents, a
> stale to-do costs more than a missing one. Items with no marker are unverified,
> not necessarily open.

**Tab / labeler / library** (was `TABCNN_GGML_HANDBACK`, `LIBRARIES_AND_TAB_SCOPING`):
- CrispASR-side (external repo): ship `libcrispasr` with `@loader_path`-relative
  rpaths (it currently bakes the CI build path, so a downloaded dylib can't find
  `@rpath/libggml.0.dylib`); lay the libs in one flat dir (split across `src/` +
  `ggml/src/` today); optional `CrispasrSession.tab()` wrapper in the pub package.
- ❌ **DO NOT BUILD — settled as excluded (corrected 2026-07-26).**
  `thesession_source.dart` was listed here as "specced, absent", which reads as
  an invitation to implement it. It isn't one:
  [docs/CORPUS_LICENSING.md](docs/CORPUS_LICENSING.md) — the authoritative doc —
  lists thesession under **"Not reachable (settled)"** and states *"thesession.org
  is ODbL **+ a no-LLM clause + composer-copyright risk** → excluded entirely;
  hosting it on HF can't honour 'no LLM use'."* It also notes ODbL is Tier C
  (share-alike), and **Tier C is not shippable at all until the app enforces
  SA-propagation** — once SA content enters an Editor, every export/save/share
  has to affirm SA on the output, which isn't built.
  So this needs no code; it needed the two docs to stop disagreeing. If it is
  ever revisited it starts with the SA-propagation work and a licence review, not
  with a source adapter.
  *(For context, `lib/features/library/sources/` holds cometbeat_catalog ·
  commons · freepats · github_abc · gregobase · modarchive · openscore · vcsl.)*
- IMSLP + CPDL/ChoralWiki conditional, country-gated library sources (A4) — gated
  behind the "real legal review" the scoping doc called for.
- `DonationConfig` tile flip-on (A5) — `donation.dart` exists but stays disabled
  until a Ko-fi/PayPal URL is set.

**Audio FX** (was `FX_HANDOVER`) — ✅ **VERIFIED DONE 2026-07-26, except one item.**
Audited each line against the code rather than re-implementing; all but the last
had already shipped, so this block was a trap for the next agent to redo:
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

**Samples** (was `CC0_SAMPLE_SOURCE_HANDOFF`):
- ✅ **DONE (verified 2026-07-26)** — "starter-module generator" shipped as
  `starterBeatHits` in `lib/features/library/starter_pattern.dart` (pure, with
  `test/starter_pattern_test.dart`) plus the Tracker action wired in
  `advanced_tracker_screen.dart` (`case 'starterBeat'`).

**DAW real-time engine** (was `SOUND_AND_DAW_ROADMAP` P2.1):
- 🔶 **IN PROGRESS — slice 1 SHIPPED 2026-07-26: the windowed render.**
  `renderTimelineWindowStereo(timeline, fromSample:, toSample:)` renders just the
  asked-for span instead of allocating a full-length buffer per lane plus the
  master. A two-second preview of a twenty-minute arrangement now costs two
  seconds of memory, and clips that don't overlap the window are never touched.
  **Byte-identical to the matching slice of the full render** — that's the whole
  contract, and 18 tests pin it across overlapping lanes, mid-fade windows, clip
  FX, stereo width, mute/solo, past-the-end (zero-padded) and unlimited renders.
  Why it's exact: a clip's FX chain runs on that clip's own bounded buffer, so it
  doesn't depend on where the window falls, and the master limiter is per-sample
  and stateless (now extracted so both paths run literally the same code).
  `timelineWindowIsBounded` names the constructs that DO couple across a window —
  track inserts, track gain automation, bus routing/sends, master FX — because a
  reverb tail or an automation ramp reaches in from outside it. Those lanes fall
  back to a full render + slice: still exact, just without the saving. (Same
  philosophy as the Tracker's `songCanStreamFlowVariable`.)
  ⬜ **The rest of P2.1 is OWNED, not unclaimed — do not pick it up here.** The
  coordination board settles it: *"real-time streaming engine (**= @tracker-ui
  §E3, THEIRS**)"*, and `opus (tracker-ui)` is 🚧 ACTIVE. That covers driving
  PLAYBACK block-by-block (so faders/automation apply live instead of on the next
  bake), live-playable instruments, and input monitoring. The Tracker has also
  already shipped its own streaming mixer (Renderer v2.1), so the engine likely
  exists there to reuse.
  The windowed render above was deliberately scoped to stop at that line: it is a
  pure additive core function, useful on its own, and commits nobody to an engine
  choice. **@tracker-ui: `renderTimelineWindowStereo` is ready to be the DAW's
  block source when §E3 lands** — it already renders an arbitrary
  `[from, to)` span byte-identically, which is the awkward half of block playback.
- ✅ **DONE** P0.1 convolution reverb — `crisp_dsp/convolution_reverb.dart`
  (synthesized IR + FFT overlap-add) landed and is tested; as of 2026-07-26 it's
  also wired into the shared FX rack as `FxType.convolutionReverb`, where before
  it was reachable only from the Voice Lab.

**Score Workshop** (was `WORKSHOP_G6_HANDOVER`, `WORKSHOP_NEXT_HANDOVER`,
`WORKSHOP_PLAN`):
- Richer inspector: multi-select view ✅ (edits a whole selection), rest
  properties ✅ (rest-length control, `opus (rest-props)`), bar-attribute editing
  (⬜ still open — see scoped item 3 below).
- Categorized *insertion* palettes (dynamics / lines / repeats / text), distinct
  from the modification inspector.
- Voice-2 v1 gaps — **RE-AUDITED 2026-07-26 against the code; mostly stale:**
  dynamics/lyrics on voice 2 ✅ (`buildScore` harvests markings from BOTH voices),
  slurs ✅ (shared `_slurs`, `canSlur` reads the active voice), cross-voice
  tap-select ✅ (`_onElementTap` follows `voiceOfId`→`setActiveVoice`). Still open:
  `buildGrandStaff` showed voice 1 only (⬜ → **fixed by `opus (voice2-gaps)`**);
  the grand-staff view still carries no dynamics/slurs/lyrics for EITHER voice
  (pre-existing limitation, follow-up); mid-score meter/key changes are bar-level
  and anchor on voice-1 bars by design (revisit only if per-voice changes are
  wanted).
- Grace-note LIST beyond a single run (a crisp_notation library ask); cross-part
  in-place ghost/drag note entry on `MultiPartView` (the "C11" ask).
- Wire `Measure.actualDuration` into the pickup/anacrusis path; verify rendered
  output reflects crisp_notation's metric-aware secondary beaming.

**Advanced/Beginner Tracker UX** (was `HANDOVER_DAW_UX` §C — also on the docs/PLAN.md
codex backlog): collapse the oversized Advanced-Tracker menu into Import/Open ·
Library · Edit · View · Playback · Export groups and align its import/save
vocabulary with Score Workshop; make the Beginner Tracker a genuinely capable kid
live-loop surface (quick start, layer parts, record a voice, arrange sections).

#### Scoped next candidates (2026-07-26, `opus` — clean picks are exhausted, these carry trade-offs)

These are the substantial items left after the easy wins shipped; scoped here so
whoever picks one starts from a plan, not a re-survey. Item 2 is being done now.

1. **Advanced-Tracker menu grouping** (`advanced_tracker_screen.dart`, ~7.1k lines
   — a HOT file). ⚠️ **SCOPE CORRECTION (2026-07-26, after inspection):** this is
   NOT a single oversized menu to regroup — the actions are spread across *many*
   bottom sheets, toolbars and dialogs (Load SoundFont `~2210`, Load WAV `~3012`,
   Load Song `~3976`, Export sheet `~4619`, per-channel mixer header `~2363–2517`,
   etc.). Collapsing them into **Import/Open · Library · Edit · View · Playback ·
   Export** is a genuine multi-surface UI restructure, not a menu regroup — larger
   and riskier than first scoped, and it wants a maintainer design pass (which
   entries move where, what stays a toolbar button) before a blind refactor.
   `opus (daw-suite)` is adjacent (DAW/tracker round-trip). Value HIGH
   (maintainer-flagged), but do it deliberately, with the extensive
   `advanced_tracker_screen_test.dart` in mind — not as a quick sweep.
2. **Voice-2 gaps → `buildGrandStaff` keeps voice 2** (`score_document.dart`). Done
   by `opus (voice2-gaps)`: a two-voice document now engraves as a two-hand grand
   staff (voice 1 → treble / RH, voice 2 → bass / LH) instead of dropping voice 2;
   a single voice keeps the pitch auto-split. The other voice-2 sub-gaps were found
   stale (see the Voice-2 bullet above). Follow-up: carry dynamics/slurs/lyrics onto
   the grand-staff view (both voices — a pre-existing grand-staff limitation).
3. **Bar-attribute editing in the inspector** — ✅ **DONE (`opus (bar-attributes)`).**
   The inspector's Structure section now carries inline **Key** and **Time
   signature** dropdowns (for a single selection) that read/write
   `keyChanges`/`timeChanges` via `setKeyChangeAt`/`setTimeChangeAt` and apply on
   selection — no need to open "Change from here…" for the common case; the fuller
   dialog stays for clef/tempo/volta/navigation. Reused `_changeRow` + the existing
   `_keyChoices`/`_timeChoices`, no new l10n. ⚠️ follow-up noted: a time change
   anchored at the *very first* element exports a degenerate MusicXML document (the
   base time sig is already that meter) — pre-existing in the "Change from here"
   path, worth a look but out of scope here.

### Group 2 — pointers to live reference docs (detail lives there)

- **Tracker replayer effect coverage** → [docs/REPLAYER_EFFECT_COVERAGE.md](docs/REPLAYER_EFFECT_COVERAGE.md):
  `Rxy`/`Txy` importer wiring (one line each in the `.xm` reader); fine F-nibble
  slides (need a source-format flag); `Gxx`/`Hxy`/`Mxx`/`Nxy` global/channel volume
  (need a mix-stage scalar); `Pxy`/`Kxx`/`Lxx`/`Xxx` + XM volume-column mini-commands;
  `E0x`/`E8x`/`EFx` (rare).
- **Tracker format fidelity** → [mod_pending.md](mod_pending.md).
  **🚨 ACTIVE / HARD REQUIREMENT: the module renderer must NEVER exceed 500 MB
  RAM** for any render (long native IT/XM included). The DEFAULT render must
  produce output in bounded time-blocks streamed to a sink — never hold a
  whole-song `Float64List` mix. Verify peak RSS with `bin/bench_render.dart`.
  - **Shipped (feature/tracker-complete, 2026-07-25):** render benchmark
    (`bin/bench_render.dart`, reports peak RSS); per-note buffer reuse +
    native-NNA two-pass render; native IT/XM fadeout release; S3M
    stereo/AdLib/packed + DP30 ADPCM decode + OPL/AdLib FM-approximation
    synthesis; MOD `M!K!`; XM 16-bit; cross-format `S1x/S2x/S3x/S4x` mapping;
    bounded streaming/range export
    (`--stream/--from-order/--to-order/--chunk-orders`); export-loss report;
    native flow/order timeline view. **Memory:** importer sample-dedup (the big
    win — the importer was cloning each sample up to ~120× across keymap slots),
    streamed CLI output, and direct-accumulate for the variable + native stereo
    render paths — buddhia3.it went ~2.8 GB→~440 MB, all byte-identical.

  #### Renderer v2 — per-sample streaming mixer + quality

  **Status 2026-07-25:** v2.1 (streaming mixer) SHIPPED and v2.2/v2.3 quality
  largely SHIPPED. Every song type now streams in ~65k-frame row-chunks with
  per-voice state carried across chunks → **flat RAM at any length, byte-identical**
  (buddhia3.it ~2.8 GB→347 MB; wonderfulpain 873→335 MB; a 20-min command song
  1.87 GB→283 MB, flat to 40 min). Quality: resonant IT low-pass filter (initial
  cutoff/resonance + Zxx, per-voice biquad, gated so non-filter songs stay
  byte-identical); 4-point Catmull-Rom interpolation in the tick path (was linear);
  MultiPLAY-style note-on soft-start + hard-cut residue anti-click. Oracle A/B
  unchanged (no regression).

  **Polish round SHIPPED (2026-07-26):** MOD tag-alias preservation
  (OCTA/FLT8/CD81/M!K!); IT filter cutoff **envelope**; IT **MIDI-macro** filter
  (F0F0 cutoff/resonance); **opt-in deterministic TPDF dither** (`--dither`,
  default off = byte-identical); finished **cross-format Sxy** mapping + accurate
  export-loss report (S0/S5/S7/S9/SA/Z verified genuinely unmappable, named in the
  report); **streamed the last native path** (long mono native-NNA now <500 MB —
  a 17.9-min song 264 MB flat); **OPL2 waveform-select + connection topology** for
  AdLib synthesis; **velocity-range + non-sample multi-sample zones** (model +
  render + editor). All corpus-byte-identical where required, oracle-gated where
  output changed, each with unit tests.

  **Dropped (proven pointless):** 2× oversampling of the resonant filter — the IT
  filter is a linear biquad capped ~5.1 kHz, far below Nyquist, so it cannot
  alias; oversampling only helps nonlinear/near-Nyquist filters.

  **Genuinely remaining (small / niche):** IT `\x87` non-default MIDI macros +
  per-channel active-macro selection; cycle-exact OPL2 (per-note ADSR operator
  envelopes — the static-PCM AdLib synth can't express them); one contrived memory
  edge (stereo + flow + non-variable + long + native — not corpus-exercised);
  deeper native editors (raw effect-memory, native S3M header, in-place
  flow-command editing, multi-split-per-note velocity UI). Original v2 plan below.

  Reference architecture studied: **MultiPLAY** (`github.com/logiclrd/MultiPLAY`,
  cloned at `../MultiPLAY`). It plays MOD/XM/S3M/IT in a few MB of RAM with good
  quality by (a) holding **one PCM copy per distinct sample** with keymaps as
  pointer/index tables (`sample_instrument.h:47` `sample* note_sample[120]` +
  `tone_offset[120]`; `Load_IT.cc:1331`), and (b) a **pure sample-by-sample
  streaming mix** — one output frame accumulated from all voices, pushed to the
  sink, no whole-song/pattern buffer (`MultiPLAY.cc:759-1014`). Its quality is not
  a fancy interpolator (it uses 2-point **linear**, `math.h:14`) but: all mixing in
  **double**; **anti-click** (10-sample note-on fade-in `sample_builtintype.h:402`
  + decaying residue tail on hard cut `channel.cc:180,600`); a per-voice **2-pole
  resonant IT filter** (`channel.cc:622`); correct **looped-neighbour**
  interpolation; NNA via lightweight extra voices that **share PCM**
  (`channel.cc:279-344`, `Channel_DYNAMIC.cc`).

  - **v2.1 — per-sample/block streaming mixer (durable ≤500 MB at ANY length).**
    Replace the whole-song `Float64` L/R accumulator (the last non-streaming piece,
    ~230 MB) with a MultiPLAY-style mix: walk order→pattern→row→tick; each channel
    is a **voice state struct** (fractional `readPos` + integer index, envelope
    cursor, fade, filter state, effect memory); accumulate all voices into a small
    fixed **block** (a few ms), convert to Int16, stream to the sink; reuse the
    block. NNA/DCT/DCA = lightweight ancillary voices sharing PCM (no extra audio).
    Envelopes = shared node shape + per-voice cursor (linear interp). RAM becomes
    flat regardless of song length; targets ≤500 MB for the whole corpus AND
    arbitrarily long songs, in-app playback included. Byte-identical where the math
    already matches; any unavoidable divergence documented + oracle-verified.
  - **v2.2 — quality parity with MultiPLAY (deliberate, documented output change,
    oracle-gated):** double-precision mix end-to-end; **anti-click** note-on ramp +
    hard-cut residue tail; per-voice **2-pole resonant IT filter** (Zxx / IT filter
    envelopes); correct looped-neighbour interpolation.
  - **v2.3 — quality BEYOND MultiPLAY (our differentiators):** 4-point
    **cubic/Hermite** interpolation (we already use cubic on some paths — unify it),
    optional **2× oversampling** before the filter, and **TPDF dither** at the final
    Int16 cast (MultiPLAY does none of these). Each opt-in-verified vs the oracle.
  - **Verification:** `bin/bench_render.dart` peak RSS < 500 MB on buddhia3.it,
    _dont_look_back_.xm, and a synthetic multi-hour song; `bin/oracle_ab.dart`
    A/B vs libopenmpt for quality; the acceptance suites stay green.

  - **Other remaining (lower priority):** unmapped cross-format effects
    (`S0/S5/S7/S9/SA/Z`); MOD FLT8/OCTA alias preservation; cycle-exact OPL; deeper
    native editors (raw effect-memory, native S3M header, velocity zones, in-place
    flow editing); per-sample gain/pan; exact envelope release curves.
- **Tracker GUI + interop ideas** → [docs/TRACKER_GUI_HANDOFF_IDEAS.md](docs/TRACKER_GUI_HANDOFF_IDEAS.md)
  and [docs/TRACKER_IDEAS.md](docs/TRACKER_IDEAS.md): envelope editor UI, per-pattern
  length UI, shared `MusicIoMenu` import/export, groove↔Tracker↔Loop-Mixer bridges,
  drumkit/BoomBox screen + more drum voices, VU meters + on-screen keyboard,
  `SoundLibraryService` persistence, Song→WAV export, sample-borrow-from-module,
  sample loop-point editing, instrument ADSR envelopes, CI module fixtures.
- **Sound Library UI (Advanced Tracker §C)** → [docs/SOUND_LIBRARY_UI_CONTRACT.md](docs/SOUND_LIBRARY_UI_CONTRACT.md):
  localize `soundfont_sheet.dart`; l10n the 5 new `Drum` voices; `SoundFontRef` cheap
  persistence; route "Export module" through PCM-preserving `moduleDocFromSong`; wire
  `SoundLibraryService` over `instrumentToJson`/`fromJson`.
- **Neural TTS packaging** → [docs/TTS_MACOS.md](docs/TTS_MACOS.md): release
  dylib embed + Developer-ID sign; iOS `.xcframework`; Android `jniLibs` per ABI;
  prove the web/WASM `crispasr` path; optional CPU-only build.
- **OMR on pure-Dart ONNX** → [docs/OMR_ONNX_HANDOVER.md](docs/OMR_ONNX_HANDOVER.md):
  export TrOMR/SMT to ONNX + publish to HF; validate ONNX-vs-ggml parity; add
  `omr_onnx.dart` behind `recognizeSheetMusic`, route web → onnx.
- **Native AEC** → [docs/AEC_TIER3B.md](docs/AEC_TIER3B.md) / [native/aec/README.md](native/aec/README.md):
  milestone (e) on-device tuning on real iOS/Android hardware; app opt-in
  `setDtd(true)`+`setRes(true)` on a 1024-block engine when speaker-backing is on;
  wire the adaptive learning-rate into `aec_shim`/`aec_engine`; optional SpeexDSP
  behind a build flag only if real-room residual demands it.
- **Transcription frontier** → [docs/TRANSCRIPTION_SOTA_HANDOFF.md](docs/TRANSCRIPTION_SOTA_HANDOFF.md):
  W-METRE metrical quantiser (note durations/tuplets/ties via DP); W-PIANO-MT3
  slice 2 (MT3 seq2seq multi-instrument); W-DRUMS finer kit + pattern-quantise;
  optional W-NOTATION PM2S neural model. (Patent-free algorithm rules:
  [docs/TRANSCRIPTION_SCOPING.md](docs/TRANSCRIPTION_SCOPING.md) appendix.)
- **SVC/RVC determinism** → [docs/SVC_SITE_B_HANDOVER.md](docs/SVC_SITE_B_HANDOVER.md):
  confirm the exported RVC graph contains the Site-B `RandomNormal` node; run the
  3-way harness (Python-ref vs `rvc.dart` vs ggml) and gate on `max_abs < 1e-5`.
- **Corpus / licensing engineering** → [docs/CORPUS_LICENSING.md](docs/CORPUS_LICENSING.md):
  Tier-C ShareAlike/ODbL stays unshippable until the app enforces SA-propagation on
  Editor export/save/share (not built); broader pop/film title-copyright sweep of
  PDMX; catalog re-emit + payload purge of the 24 quarantined holiday MIDIs;
  per-file licence verification for Iowa MIS / Discord GM SFZ / AVL / Flame.
- **Tab-labeler quality** → [docs/TAB_LABELER_ROADMAP.md](docs/TAB_LABELER_ROADMAP.md):
  movement-smoothness + span regularizers in training; DP-in-the-loop / CRF training
  if >85% agreement doesn't fall out; EGSet12 ingest; string-shift augmentation;
  model-card/HF hygiene.
- **Tab Editor pro-parity** → [docs/TAB_EDITOR_PARITY.md](docs/TAB_EDITOR_PARITY.md):
  close the gap to industry-standard tab editors AND make the editor faithfully
  edit what we import/export (`.gp`/MusicXML/MIDI round-trip). Phased steps A0–E2:
  finer rhythm/tuplets/ties, time-sig/key/repeats/voltas/tempo-map, parametric
  techniques (bend curves, whammy, slide kinds, harmonics, palm-mute…), dynamics,
  second voice, per-track instrument/mixer, drum-tab, practice tools, PDF export.
  A0 (round-trip harness + the 7 existing techniques now survive import→edit→export)
  shipped; A1+ pending, each scoped for a fresh agent in the doc.
