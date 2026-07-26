# Guitar Tab Editor — parity plan

Where our Tab Workshop stands against **industry-standard professional
tablature editors** (the well-known desktop/web guitar-tab suites — deliberately
unnamed here and everywhere in the repo, per the no-competitor-names rule), and
a scoped, step-by-step path to close the gaps. Each step is written so a fresh
agent can pick it up cold: what to change, where, and the unit test that proves
it. Do them **in order within a phase** (later steps assume earlier model
fields). Every step ships independently with its own tests.

### The load-bearing goal: edit what we read & write

We already import/export **GPIF (`.gp`/`.gpx`)**, MusicXML, MIDI and ASCII tab,
and our `Score` model already *carries* bends, slides, vibrato, tuplets, second
voices, dynamics/velocity, articulations, repeat barlines, key/time/tempo
changes, grace notes and fingerings. The gap is that the **editor model
(`TabDocument`) can't represent most of it**, so `import → edit → export`
silently drops everything the editor doesn't model (`toScore`/`fromScore` are
lossy). So every step below has a second acceptance test beyond "the feature
works": **a round-trip test** — load a fixture that uses the feature, convert to
`TabDocument`, edit, convert back, and assert the feature survived. The
`TabDocument` must eventually be a faithful editable projection of what the
interchange formats hold. Where a format carries something the editor still
can't, that's a gap to log here, not to silently discard.

## What we already have

Model (`lib/features/games/composition/tab_document.dart`): a `TabDocument` =
a `Tuning` + ordered `TabColumn`s. Each column pins fret(s) per string (chords),
a `NoteDuration`, a set of techniques, and an optional chord diagram.
- **Durations:** whole · dotted-half · half · dotted-quarter · quarter · eighth.
- **Techniques (7, flat booleans):** hammer, slide, bend, vibrato, dead, ghost,
  harmonic → mapped in `toScore` to Score slurs/glissandos/bends/vibratos/marks.
- **Tunings:** standard/drop-D/DADGAD/open-G guitar, 7- & 8-string, 4- & 5-string
  bass, ukulele, mandolin, banjo (good coverage).
- **Structure:** columns tiled into **fixed 4/4** bars (`toScore`, 8-eighth grid).
- **Tracks:** multi-track "band" with per-track mute/solo.
- **Chords:** diagram library (guitar/uke/banjo/mandolin) + picker; pattern
  generator (arps, Travis/boom-chuck/island picking, chord styles).
- **Views:** tab · standard notation · grand staff (treble+bass split).
- **Playback:** BPM, count-in, mic listen, play-with-instrument.
- **Interchange:** import `.gp/.gpx` (real fret data) + MusicXML/MIDI/kern/etc
  (pitch → arranged fretting via the Viterbi `arrangeTab`); export GPIF (`.gp`),
  MusicXML, MIDI, send-to-DAW. ASCII-tab paste. Song Book. Audio transcription.
- **Edit:** fret keypad, capo, tempo, transpose, insert/remove/duplicate column,
  undo/redo, inspect mode.

## What we lack (the gaps)

Grouped by area; each maps to a step below.

**Rhythm & notation depth**
- No 16th / 32nd / 64th notes; only one dot level; **no tuplets** (triplets etc.);
  **no ties**; **no explicit rests of a chosen value** (only whole-column blanks).
- **Fixed 4/4** — no other meters, no mid-song time-signature changes.
- No key signature.
- No **multiple voices** per track (one polyphonic line per column only).

**Bars & song structure**
- No **repeat barlines**, no **repeat counts**, no **alternate endings (voltas)**.
- No **sections / rehearsal marks**, no directions (D.C./D.S./Coda/Fine/segno).
- No **tempo map** (tempo changes mid-song); a single global BPM only.
- No free-position **bars operation** (insert/delete/copy whole bars as bars).

**Expressive techniques (ours are flat on/off, theirs are parametric)**
- **Bends** carry no shape: no prebend, no bend amount (¼-steps), no
  bend/release, no hold, no multi-point curve.
- No **whammy / tremolo-bar** (dive, dip, release, points).
- **Slides** have no direction/kind (legato vs shift vs slide-in/out up/down).
- Hammer-on and pull-off are the same flag; no **tapping**.
- One "harmonic" flag; no natural / artificial / pinch / tapped / semi kinds.
- No **palm mute**, **let ring**, **staccato**, **accent**, **tenuto**.
- No **trill** (with interval), no **tremolo picking** (with rate).
- No **grace notes** (before/on-beat, acciaccatura/appoggiatura).
- No **strum direction** (brush up/down), **arpeggio** roll, **pick-stroke**
  up/down, rasgueado.
- No **fingering** (left-hand 1-4/T, right-hand p-i-m-a).

**Dynamics**
- No per-note **dynamics/velocity** (ppp…fff), no crescendo/decrescendo.

**Tracks, sound & practice**
- No **per-track instrument** choice, no per-track tuning/capo, no **mixer**
  (volume/pan) — only mute/solo.
- No **drum-tab** track.
- No **practice tools**: loop a bar range, **speed trainer** (ramp tempo),
  metronome click during edit.

**Output**
- GPIF export doesn't carry the (not-yet-existing) rich features; no **PDF /
  print / image** export of the tab.

## Plan — phases & steps

Convention per step: **model → `toScore`/export wiring → UI → tests**. Keep the
`.gp`/MusicXML round-trip green (`test/tab_workshop_test.dart`,
`test/tab_document_test.dart`).

### Phase A — Rhythm & structure (the notation backbone)

- **A0. Round-trip fidelity audit + harness.** Write `test/tab_roundtrip_test.dart`
  that, for each interchange path, loads a fixture exercising many features
  (a checked-in `.gp` / MusicXML), runs `Score → TabDocument.fromScore →
  TabDocument.toScore → Score` (the editor round-trip) and diffs the two Scores,
  listing every element kind the editor drops (bends, tuplets, voice2, dynamics,
  repeats, tempo/time/key changes, fingerings, grace notes, …). Land it with the
  drops marked `TODO(A#)` so each later step flips one assertion from "lost" to
  "preserved". This is the scoreboard for the whole effort. No model change yet —
  it just measures the gap and guards regressions.
- **A1. Finer durations + explicit rests.** Change `toScore`'s bar grid from an
  eighth (8 steps/4-4) to a **sixteenth** (16 steps) grid; add 16th, 32nd and
  the dotted-eighth/dotted-16th to `kTabDurations` with correct step counts; add
  a first-class **rest** column (a `TabColumn` flavour or a `rest:true` flag) so
  a rest of any value can be entered, distinct from an empty (unsounded) column.
  Tests: `_stepsOf` values; `toScore` tiles a 16th run into the right bar count;
  a rest column emits `RestElement(duration)`.
- **A2. Ties.** Add `TabColumn.tieToPrev` (bool). `toScore` sets
  `NoteElement.tieToNext` on the *previous* column when the next is a tie; keep
  playback summing tied durations in `toPlaybackEvents`. Tests: two tied quarters
  → one 2-beat sound; Score has `tieToNext`.
- **A3. Tuplets.** Add a tuplet grouping (`TabColumn.tuplet: (actual, normal)?`
  or a span). `toScore` emits `Tuplet`s + scales the bar-fill so a triplet of
  eighths fills one beat. Tests: three triplet-eighths sum to a quarter; Score
  carries a `Tuplet`.
- **A4. Configurable time signature (+ changes).** `TabDocument.timeSignature`
  (default 4/4) and an optional per-column `timeChange`. Replace the hard
  `> 8` bar test in `toScore` with the meter's capacity; stamp `Measure.timeChange`.
  Tests: 3/4 tiling; a mid-song 6/8 change starts a new bar with the sig.
- **A5. Key signature.** `TabDocument.keySignature` → `Score(keySignature:)` so
  standard/grand views spell correctly. Tests: sharps/flats appear in `toScore`.
- **A6. Repeats + counts.** Per-bar `startRepeat`/`endRepeat`/`repeatCount`
  (or column-anchored). `toScore` stamps `Measure.startRepeat/endRepeat`; GPIF
  export writes them. Playback unrolls repeats in `toPlaybackEvents`. Tests:
  Score barlines; playback plays a repeated bar twice.
- **A7. Alternate endings (voltas).** Per-bar `volta` (which ending numbers).
  `toScore` → `Measure.volta`; playback picks the ending by pass. Tests.
- **A8. Sections / rehearsal marks + directions.** A `TabSection(name, atColumn)`
  list + navigation marks (D.C./D.S./Coda/Fine). `toScore` → `Measure.navigation`
  / annotations. Playback resolves jumps. Tests.
- **A9. Tempo map.** Per-column optional `tempoChange` (BPM). `toScore` stamps
  `Measure.tempoChange`; `toPlaybackEvents` changes ms/step at the anchor. Tests.

### Phase B — Expressive techniques (make them parametric)

Replace the flat `Set<TabTechnique>` with a `TabArticulation` value object per
column/note (keep the enum for back-compat mapping). Each sub-step adds one
parametric technique end-to-end.

- **B1. Parametric bends.** A `Bend` with points `[(position 0..1, offset in
  ¼-steps)]` + presets (bend, bend/release, prebend, prebend/release). `toScore`
  emits the point list on the existing `Bend`; GPIF writes bend points; playback
  sounds the target. UI: a small bend editor. Tests: point list survives
  `toScore` + GPIF round-trip.
- **B2. Whammy / tremolo bar.** Column-level `whammy` points (dive/dip/release).
  Score + GPIF. Tests.
- **B3. Slide kinds.** `slide: {legato, shift, inFromBelow/Above, outUp/Down}`.
  Map to glissando + slur (legato) vs plain glissando (shift). Tests.
- **B4. Hammer-on vs pull-off + tapping.** Split `hammer` into `hammerOn` /
  `pullOff` (by pitch direction if unset) + a `tap` flag. Tests.
- **B5. Harmonic kinds.** natural / artificial / pinch / tapped / semi →
  `TabNoteStyle` variants. Tests.
- **B6. Articulations.** palmMute, letRing, staccato, accent, tenuto → Score
  articulations + note marks. Tests.
- **B7. Trill + tremolo picking.** trill(interval), tremolo(rate 8th/16th/32nd).
  Tests.
- **B8. Grace notes.** A grace note attached before/on a column →
  `NoteElement.graceNotes`. Tests.
- **B9. Strum/pick.** brush up/down, arpeggio roll, pick-stroke up/down. Tests.
- **B10. Fingering.** left-hand 1-4/T and right-hand p-i-m-a per note →
  `NoteElement.fingerings`. Tests.

### Phase C — Dynamics & voices

- **C1. Per-note dynamics.** `TabColumn.dynamic` (ppp…fff) → `NoteElement.velocity`
  + `Score.dynamics`; playback scales amplitude. Crescendo/decrescendo hairpins
  over a range. Tests.
- **C2. Second voice.** A per-track `voice2` column list → `Measure.voice2`.
  Tests: two voices render + export.

### Phase D — Tracks, sound & practice

- **D1. Per-track instrument + tuning + capo.** `TabTrack` gains `instrument`
  (Sound-Library ref), its own `tuning` and `capo`. Playback voices each track;
  the toolbar track dropdown edits them. Tests.
- **D2. Mixer.** Per-track `volume`/`pan` (keep mute/solo); a mixer sheet.
  Playback scales/pans. Tests.
- **D3. Drum-tab track.** A percussion track (drum names per line) → the drum
  voice; export as a GP drum track. Tests.
- **D4. Practice tools.** Loop a bar range; **speed trainer** (start %, +% per
  loop, target); metronome click. Pure helpers + UI. Tests on the pure helpers.

### Phase E — Output

- **E1. Rich GPIF export.** Extend the GPIF writer to carry A/B/C/D features that
  the format supports (bends, palm-mute, harmonics, dynamics, repeats, tempo,
  multi-voice). Tests: round-trip each through import→export.
- **E2. PDF / image export.** Render the tab/notation to a paginated PDF (reuse
  the app-side PDF path from the Score Workshop) + PNG. Tests: non-empty output.

## Status

- [x] **A0** round-trip harness + the 7 existing techniques now survive
  import→edit→export (`fromScore` reads them back). `test/tab_roundtrip_test.dart`.
- [x] **A1** finer durations — the rhythm grid is now a **32nd** (was an eighth);
  16th / 32nd / dotted-eighth / dotted-16th added; `_stepsOf` is fraction-based so
  any imported value tiles + plays exactly (no more quarter fallback). Explicit
  rests already work (an empty column of a chosen duration → `RestElement`).
  Tests in `test/tab_document_test.dart` (group A1).
- [x] **A2** ties — `TabColumn.tieToNext`; `toScore` sets `NoteElement.tieToNext`;
  playback merges a tied chain into one sound of the summed length; `fromScore`
  reads ties back (round-trip); `setTie`/`withTie` + a Tie chip in the settings
  sheet. Tests in `test/tab_document_test.dart` (group A2).
- [x] **A4** time signature — `TabDocument.timeSignature` (default 4/4) drives a
  `barCapacity` getter that replaces the hard-coded 32-step bar; `toScore` stamps
  `Score.timeSignature`; `fromScore` reads it back; a Meter dropdown in the
  settings sheet (common meters + whatever an import brought). Tests: group A4.
  (Done before A3 — it's independent and cleaner; mid-song meter changes are the
  A4b follow-up.)
- [x] **A3** tuplets — `TabColumn.tuplet: (actual, normal)?`; bar tiling now
  accumulates FRACTIONAL scaled steps (`_scaledStepsOf` = written × normal/actual)
  so a triplet group lands on the bar line; `toScore` emits a `TupletSpan` per
  run of same-ratio columns; playback scales each note's ms; `fromScore` reads
  spans back (round-trip); `setTuplet`/`makeTuplet` + a Triplet chip. Tests: A3.
  ⚠ known limit: consecutive same-ratio columns merge into ONE span (fine for a
  triplet or triplets separated by plain notes; two adjacent triplets would need
  an explicit group id — a later refinement).
- [x] **A5** key signature — `TabDocument.keySignature` (default C/0) →
  `Score.keySignature`; `fromScore` reads it back; a Key dropdown (−7..+7) in the
  settings sheet. Tests: group A5.
- [x] **A6** repeats — `TabColumn.startRepeat`/`endRepeat` (bar-level, anchored to
  a bar's first column); `toScore` stamps `Measure.startRepeat/endRepeat`;
  `fromScore` reads them back (round-trip); `setBarRepeat` + Repeat ‖: / :‖ chips.
  Tests: group A6. (A6b — audible repeat *unrolling* in playback — is the
  follow-up; notation + interchange land here.)
- [x] **A7** alternate endings (voltas) — `TabColumn.volta` (bar-level, first
  column); `toScore` → `Measure.volta`; `fromScore` round-trip; `setBarVolta` +
  an "Ending" cycle chip. Tests: group A7.
- [x] **A8** directions + section labels — `TabColumn.navigation`
  (`NavigationMark`: D.C./D.S./Coda/Fine/Segno…, bar-level) → `Measure.navigation`;
  `TabColumn.section` (rehearsal label) → a `Score.annotation` on that note; both
  round-trip. `setBarNavigation`/`setSection`. Tests: group A8. (UI controls for
  these land with the Tab-Editor UX pass, not the settings sheet.)
- [x] **A9** tempo map — `TabColumn.tempoChange` (BPM, bar-level, anchored to the
  bar's first column); `toScore` stamps `Measure.tempoChange = Tempo(bpm)`;
  `fromScore` reads it back (round-trip); `toPlaybackEvents` re-times ms/step from
  that bar on; `setBarTempo`. `TabColumn` was refactored to a single `copyWith`
  (sentinel-guarded nullable fields) — the named `with…` helpers are now thin
  wrappers, ending the per-field copy-constructor sprawl. Tests: group A9.
- [x] **B1** parametric bends — `TabColumn.bend: List<BendPoint>?` (control points
  `(pos 0..1, height in whole steps)`) + `TabBends` presets (bend / bend-release /
  prebend / prebend-release); `toScore` emits `Bend.curve` when a curve is set
  (else the flat `TabTechnique.bend` still gives a plain `Bend`); `fromScore` reads
  the point list back (round-trip); `setBend`/`withBend`. Tests: group B1–B3.
- [x] **B2** whammy / tremolo bar — `TabColumn.whammy: List<BendPoint>?` →
  `TremoloBar.curve` in `toScore`; `fromScore` reads it back (steps-only imports
  synthesised to a 2-point dive); `setWhammy`/`withWhammy`. Tests: B1–B3.
- [x] **B3** slide-in/out — `TabColumn.slide: SlideInOut?` (scoop/fall in or out,
  distinct from the legato `TabTechnique.slide`) → `TabSlide(id, direction)`;
  `fromScore` reads the direction back; `setSlide`/`withSlide`. Tests: B1–B3.
- [x] **B4** hammer/pull + tap — `TabColumn.tap` → `Tap` in `toScore` (round-trip
  via `score.taps`). Hammer-on vs pull-off stay the `TabTechnique.hammer` slur —
  the h/p distinction is by pitch direction, which the notation slur conveys.
  `setTap`/`withTap`. Tests: group B4–B6.
- [x] **B5** harmonic kinds — `TabColumn.harmonic: TabNoteStyle?` (natural /
  artificial / pinch / tapped / semi / feedback) → `TabNoteMark(id, style)`;
  `fromScore` keeps the specific kind (dead/ghost still fold to flat techniques,
  the flat `TabTechnique.harmonic` still round-trips as `harmonic`).
  `setHarmonic`/`withHarmonic`. Tests: B4–B6.
- [x] **B6** articulations — `TabColumn.palmMute`/`letRing` → self-span
  `PalmMute(id,id)`/`LetRing(id,id)` (import reads multi-note spans and flags every
  column in range); `TabColumn.articulations: Set<Articulation>` (staccato / tenuto
  / accent / marcato / fermata …) set on `NoteElement.articulations`, read back on
  import. `setPalmMute`/`setLetRing`/`toggleArticulation`. Tests: B4–B6.
- [x] **B7** trill + tremolo picking — `TabColumn.ornament: Ornament?` (trill /
  mordent / turn …) → `NoteElement.ornament`; `TabColumn.tremolo: int?` (beam
  count 1/2/3 = 8th/16th/32nd) → `NoteElement.tremolo`. Both read back on import.
  `withOrnament`/`withTremolo`. Tests: group B7–B10. (A trill's auxiliary interval
  is not modelled — logged gap.)
- [x] **B8** grace notes — `TabColumn.graceMidis: List<int>?` + `graceStyle`
  (acciaccatura / appoggiatura) → `NoteElement.graceNotes`/`graceStyle`; round-trip
  via the element. `withGrace`. Tests: B7–B10.
- [x] **B9** strum / pick — `TabColumn.arpeggio: Arpeggio?` (rolled-chord up/down)
  → `NoteElement.arpeggio`; `TabColumn.pickStroke: bool?` (up/down) → `PickStroke`.
  Both read back. `withArpeggio`/`withPickStroke`. Tests: B7–B10.
- [x] **B10** fingering — `TabColumn.leftFingers: List<int>?` (0/T,1–4 per pitch)
  → `NoteElement.fingerings`; `TabColumn.rightFinger: RightHandFinger?` (p/i/m/a) →
  `TabFingering`. Both read back. `withLeftFingers`/`withRightFinger`. `copy()` now
  deep-copies the bend/whammy/grace/finger lists. Tests: B7–B10. **Phase B done.**
- [x] **C1** dynamics — `TabColumn.dynamic: DynamicLevel?` → a `DynamicMarking` +
  a mapped `NoteElement.velocity` (`velocityOf` ramp); import reads the marking
  back, and a raw velocity with no marking (MIDI/GP) quantises to the nearest level
  (`nearestDynamic`). `TabColumn.hairpin: HairpinType?` starts a crescendo/
  diminuendo running to the next dynamic → `Hairpin`; the start marker round-trips.
  `setDynamic`/`setHairpin`. ⚠ playback amplitude isn't scaled yet (the
  `(midis,ms)` event tuple carries no velocity) — notation/export/round-trip only.
  Tests: group C1.
- [x] **C2** second voice — `TabDocument.voice2: List<TabColumn>` tiled into the
  same bars as voice 1 and emitted as `Measure.voice2` (notes / rests / ties +
  string voicings; per-note techniques on voice 2 are a follow-up); `fromScore`
  reconstructs it via the arranger. Round-trip tested. **Phase C done.**
- [x] **D1** per-track instrument + capo — `TabTrack.instrument` (GM program) and
  `TabTrack.capo` (per-track tuning already lives on the track's `doc`). Model +
  tests. ⚠ playback voicing each track by its program + the toolbar edit UI are the
  app-side follow-up.
- [x] **D2** mixer — `TabTrack.volume` (0..1) + `TabTrack.pan` (−1..1) alongside
  mute/solo. Model + tests. ⚠ the mixer sheet + pan/scale in playback are the
  app-side follow-up (the `(midis,ms)` merge tuple carries no gain/pan yet).
- [x] **D3** drum-tab — `TabTrack.isDrums`; `kDrumLines` (9 standard lines →
  GM percussion notes) + `drumMidiForLine`; `TabDocument.toDrumScore()` engraves
  each fretted line as its drum voice on the neutral percussion clef with
  `isPercussion` metadata (→ GM channel 10 on export). Tests: line map + drum
  score.
- [x] **D4** practice tools — pure helpers: `LoopRange(startBar,endBar)`,
  `speedTrainerTempos` (ramp start%→target%, always landing on target),
  `metronomeClicksMs`. Tests on the helpers. ⚠ wiring them to the loop player +
  UI is the app-side follow-up. **Phase D model done.**
- [x] **E1** rich GPIF export — the GPIF writer already carried bends (incl.
  multi-point curves) / slides / hammer / vibrato / harmonics (all kinds) /
  dynamics / staccato+accent / grace; extended it (crisp_notation@`ee05c33`) to
  also write **palm-mute, let-ring, tap, and left/right-hand fingering** note
  properties. Writer test in crisp_notation + an app-side end-to-end test
  (`TabColumn` → `toScore` → `scoreToGpif` carries them, still a valid `.gp`).
  The **whammy bar**, **pick-stroke** and **brush/arpeggio** are GP *beat*
  properties (they apply to the strum, not one note); the writer now emits them
  on the `<Beat>` too (crisp_notation@`167ba18`: `WhammyBar` +
  Origin/Destination, `PickStroke` Direction, `Brush` Direction), so the whole
  A/B/C technique set now survives to `.gp`. Tests: group E1 (+ beat-property
  assertions).
- [x] **E2** PDF export — the Tab Workshop export menu gained **PDF (print)**,
  reusing the Score Workshop's paginated `exportScoreToPdf` on `_doc.toScore()`
  (localized de/en). App-side wiring; the renderer itself is covered by the
  workshop suite. **Phase E done — parity plan complete.**

Each completed step is recorded in [HISTORY.md](HISTORY.md); this file tracks the
remaining scope. See also the root [PLAN.md](../PLAN.md) backlog pointer.
