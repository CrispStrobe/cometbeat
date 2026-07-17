# CometBeat (working title)

A music notation and harmony learning app for children from primary school
onwards (6+), built from minigames. Sibling of Space Math Academy
(`../space_math_academy`) and WortUniversum (`../voc`), sharing the same
architecture: `lib/{core,features,shared,l10n}`, Provider, ARB-based i18n
(EN/DE), and an SM-2 spaced-repetition engine ("SRI").

Targets: iOS, Android, Web, Windows, macOS, Linux.

## Modules (each = a set of minigames)

See [docs/PLAN.md](docs/PLAN.md) for the full curriculum map and roadmap.

| id | Topic | Games (41) + Song Book |
|---|---|---|
| `note_values` | Notenwerte & Pausen | Symbol Quiz • Duration Duel • Rhythm Echo • Count the Beats (ties!) • Sort the Beats (drag) |
| `note_reading` | Noten lesen (Violin/Bass) | Reading Quiz ×2 (fading landmark hints) • Place the Note ×2 • Melody Echo (ear↔staff) • Melody Dictation (ear→write) • Note Match (memory pairs) • Note Order (low→high) • Line or Space? (swipe) |
| `measures` | Takte & Taktarten | Measure Filler • Meter Detective (ear) |
| `scales` | Tonleitern, Dur/Moll | Scale Detective • Dur oder Moll? (ear) • Scale Builder • Sound Echo (memory sequence) |
| `chords` | Akkorde & Intervalle | Chord Quiz • Triad Builder • Interval Detective (ear) |
| `harmony` | Harmonik (T/S/D) | Function Quiz • Cadence Workshop • Hear the Function (ear) |
| `composition` | Komponieren (Kompositionstechnik) | Ending Detective (closure) • Question & Answer (phrases) • Label the Form (AnaVis-style) • My Melody + **Composition Workshop** (touch-first multi-instrument score editor) • **Loop Mixer** (tap-a-card groovebox) • **Tracker** (touch pattern sequencer) |
| `cello` | Cello-Ecke (instrument corner) | Which String? • Finger Quiz (1st position) • Tenor Clef reading |
| `guitar` | Gitarren-Ecke (tablature corner) | Open Strings (name the open string) • Read the Tab (fretted note → name) |
| `songs` | Liederbuch (real songs) | Song Book (5 songs, play-along cursor + lyrics) • Name That Tune (ear) • **Import**: MusicXML (paste or file), ChordPro chord sheets (playable chips), simple monophonic MIDI |
| `keyboard` | Tasten-Ecke (piano corner) | Find the Key (staff→key) • Key Quiz (key→name) • Echo Keys (ear→key) • Play the Melody (sight-playing) • Chord Grip • Grand Staff (read both clefs) |

SRI review runners: note-value symbols + note reading (per clef); the home
review button routes to the biggest due bucket. Audio is synthesized in
pure Dart (no assets). Web deep links: `?game=<id>`.
Later: more ear training, unlock gating, Kompositionstechnik (see plan).
Live web build: https://mus-theta.vercel.app

## Architecture notes

- **SRI**: `lib/core/services/sri_service.dart` — SM-2, generalized to opaque
  item IDs with the convention `<moduleId>.<skillId>.<detail>`. Tuning
  constants in `lib/core/tuning.dart` (identical values to the sibling apps).
- **Modules**: registered in `lib/core/models/learning_module.dart`; the home
  screen renders from that list. Adding a module = registry entry + ARB keys.
- **i18n**: `lib/l10n/app_{en,de}.arb`, generated via `flutter gen-l10n`
  (`generate: true`).
- **Notation rendering**: comes from `crisp_notation`, the standalone MIT library
  in `../crisp_notation` (path dependency). The Flutter widgets live in the
  `crisp_notation` package; the model + all the codecs (MIDI, MusicXML, ABC, MEI,
  kern, MuseScore, LilyPond) are in its **Flutter-free `crisp_notation_core`**
  package, which is what the headless CLIs and the audio layer import.

## Audio, modules & notation interchange

Everything under `lib/core/audio/` is **pure Dart** (Flutter-free, web-safe):
synthesis, DSP, pitch/chord detection, the tracker-module codecs, and the
notation bridge. Because it's Flutter-free, the same code runs **headless** from
`bin/` under plain `dart run` — ideal for scripted `render → detect → assert`
acceptance tests.

- **Live pitch/chord detection** — `pitch_analysis.dart` (McLeod/NSDF) +
  `chroma_analysis.dart` (FFT + chromagram) drive the Tuner, Play/Sing along, and
  Chord-listener games from the mic.
- **crisp_dsp** (`core/audio/crisp_dsp/`) — reverb / delay / chorus / flanger,
  distortion, ring-mod, cubic resampling, WSOLA time-stretch, ADSR envelopes,
  sfxr; sample-editing ops (trim/normalize/fade) and multi-sample instruments.
  Powers the Tracker, Loop Mixer, and voice-effect toys.
- **Tracker module codecs** — read **and write** ProTracker **MOD**, Scream
  Tracker 3 **S3M**, FastTracker 2 **XM**, and Impulse Tracker **IT**, through a
  neutral `ModuleDoc` hub with a full **N×N converter matrix**
  (`module_convert.dart`).
- **Notation interchange** (`module_notation.dart` + `core/notation/`) — bridges
  the module hub to `crisp_notation`'s **Score / MultiPartScore** model, so a
  module becomes a real (multi-part) score and back. Converts, both directions,
  between modules and **MIDI** (single + format-1 multi-track), **MusicXML**,
  **ABC**, **Humdrum kern**, **MEI**, **MuseScore** (`.mscx` / zipped `.mscz`),
  and **LilyPond** (write-only). **MusicXML, MIDI and ABC carry _every_
  instrument part**; the other text formats carry one (single-`Score` writers). A
  rest survives round-trips via a neutral note-off mapped to each format's
  key-off. Every reversible edge has a round-trip test.
- **Composition Workshop** — a touch-first, **multi-instrument** score editor.
  The editable model is `MultiPartDocument` (N staves, one per instrument; each a
  `ScoreDocument` with 2 voices, clef/key/meter/tempo, ties, slurs, dynamics,
  lyrics, transposition); `buildMultiPart()` snapshots it to an immutable
  `MultiPartScore` for rendering + export. Imports/exports the formats above.

### Headless CLI tools (`dart run bin/<x>.dart`)

One dispatcher, **`mus`**, fronts the suite — `dart run bin/mus.dart <cmd> …`:

| cmd | what it does |
|---|---|
| `listen` | mic / WAV → live pitch & chord detection |
| `info` | sniff + dump any module (`.mod`/`.s3m`/`.xm`/`.it`) |
| `conv` | convert modules between formats + extract samples to WAV |
| `render` | a Loop Mixer groove (share token) → WAV |
| `midi` | module ↔ MIDI / MusicXML / ABC / kern / MEI / MuseScore (both ways) |
| `fx` | apply a crisp_dsp effect to a WAV offline |

## Development

```
flutter pub get
flutter analyze          # strict: strict-casts / strict-raw-types
flutter test             # add --coverage for lcov.info
flutter run -d chrome    # or macos, etc.
```

CI (`.github/workflows/ci.yml`) runs format + analyze + test on every push and
PR, checking out the sibling `crisp_notation` repo alongside so the path dependency
resolves. The `build/` symlink (a dev-only SSD path) is intentionally untracked.
The test suite covers ~85% of `lib/` — the services, the pure-Dart audio/DSP
stack, the module + notation interchange round-trips, and a render smoke test per
game screen.
