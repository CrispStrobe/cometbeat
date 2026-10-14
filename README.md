# CometBeat

A music notation and harmony learning app for children from primary school
onwards (6+), built from minigames. Sibling of Space Math Academy
(`../space_math_academy`) and WortUniversum (`../voc`), sharing the same
architecture: `lib/{core,features,shared,l10n}`, Provider, ARB-based i18n
(EN/DE), and an SM-2 spaced-repetition engine ("SRI").

Targets: iOS, Android, Web, Windows, macOS, Linux.

## Modules (each = a set of minigames)

See [docs/PLAN.md](docs/PLAN.md) for the full curriculum map and roadmap.

| id | Topic | Games (150+) + Song Book |
|---|---|---|
| `note_values` | Notenwerte & Pausen | Symbol Quiz • Duration Duel • Rhythm Echo • Count the Beats (ties!) • Sort the Beats (drag) |
| `note_reading` | Noten lesen (Violin/Bass) | Reading Quiz ×2 (fading landmark hints) • Place the Note ×2 • Melody Echo (ear↔staff) • Melody Dictation (ear→write) • Note Match (memory pairs) • Note Order (low→high) • Line or Space? (swipe) |
| `measures` | Takte & Taktarten | Measure Filler • Meter Detective (ear) |
| `scales` | Tonleitern, Dur/Moll | Scale Detective • Dur oder Moll? (ear) • Scale Builder • Sound Echo (memory sequence) |
| `chords` | Akkorde & Intervalle | Chord Quiz • Triad Builder • Interval Detective (ear) |
| `harmony` | Harmonik (T/S/D) | Function Quiz • Cadence Workshop • Hear the Function (ear) |
| `composition` | Komponieren (Kompositionstechnik) | Ending Detective (closure) • Question & Answer (phrases) • Label the Form (AnaVis-style) • My Melody + **Composition Workshop** (touch-first multi-instrument score editor) • **Loop Mixer** (tap-a-card groovebox) • **Tracker** (touch pattern sequencer) • **Multitrack DAW** (vector-clip arranger — send audio from any module, then arrange / trim / split / reverse / speed / merge on a draggable timeline → WAV/MP3) |
| `cello` | Cello-Ecke (instrument corner) | Which String? • Finger Quiz (1st position) • Tenor Clef reading |
| `guitar` | Gitarren-Ecke (tablature corner) | Open Strings (name the open string) • Read the Tab (fretted note → name) |
| `songs` | Liederbuch (real songs) | Song Book (play-along cursor + lyrics) • Name That Tune (ear) • **Sing/Play along** + **Sight-sing** (endless generated in-key tunes, major & minor, difficulty scales with the player, read off a moving score + mic-graded with a starting-pitch cue) • **Play a MIDI file** (turn any `.mid` into a play-along) • **Import**: MusicXML (paste or file), ChordPro chord sheets (playable chips), MIDI, JAMS (MIR chord/melody datasets → chord sheet or notated song; `note_midi`+`tempo`+`beat`+`key_mode`), and **scan/photograph sheet music** (OMR — on-device optical music recognition via the CrispEmbed ggml engine, model downloaded on demand; native platforms) |
| `keyboard` | Tasten-Ecke (piano corner) | Find the Key (staff→key) • Key Quiz (key→name) • Echo Keys (ear→key) • Play the Melody (sight-playing) • Chord Grip • Grand Staff (read both clefs) |

**Home** leads with a **Continue** card: the curriculum's recommended level,
opened as a short mixed session that starts on the least-ready topic. Below it
sit the review button and the module grid. The core theory modules open one at
a time as the child plays (a locked card shows a ring filling towards its
unlock); the instrument corners, Song Book, transposition and drums are open
from the start.

**Review** covers every skill that records spaced-repetition items: quizzes
that can re-ask specific items do so, and every other skill opens a round of
the game that drills it (`lib/features/review/review_router.dart`). Audio is
synthesized in pure Dart (no assets). Web deep links: `?game=<id>`.

**Studio tools** — the score workshop, tracker, tab editor, Loop Studio, audio
editor and project browser — are off the home bar on a new install, so a young
child gets the learning app only. Turn them on under Settings ▸ Studio tools.
An install that predates the switch keeps them.

**Learners** (Settings ▸ Learners): several children can share a device, each
with their own stars, streak, review data, seen-tutorials and imported songs. A learner's
progress can be backed up to a JSON file and restored; a restore always adds a
new learner and never overwrites one.

Every game gets an illustrated, localized **tutorial** (`lib/shared/tutorial/`)
shown once on first entry (and reopenable via **?**): plain-language text, a
notated + heard example, read-aloud (TTS), and interactive **"try it"** practice
steps — read/hear then tap the answer, with gentle reveal-on-stuck — so a
zero-knowledge child can clear it.
Later: more ear training, unlock gating, Kompositionstechnik (see plan).
Live web builds — two deploy regimes on purpose:
- **GitHub Pages** (https://crispstrobe.github.io/cometbeat/, via
  `pages.yml`) redeploys on **every** push to `main` — no per-day quota, so it's
  always the freshest bleeding-edge build.
- **Vercel** (https://mus-theta.vercel.app, via `deploy.yml`) deploys **only on a
  version tag (`v*`) or a published GitHub Release** (plus manual dispatch).
  Vercel's free tier caps production deploys at 100/day, which per-commit
  deploys blow through during multi-agent development; tags give it a stable,
  intentional "release" cut. Cut a release with `git tag v1.2.3 && git push
  origin v1.2.3`.

## Architecture notes

- **SRI**: `lib/core/services/sri_service.dart` — SM-2, generalized to opaque
  item IDs with the convention `<moduleId>.<skillId>.<detail>`. Tuning
  constants in `lib/core/tuning.dart` (identical values to the sibling apps).
- **Modules**: registered in `lib/core/models/learning_module.dart`; the home
  screen renders from that list. Adding a module = registry entry + ARB keys.
- **Progression**: the unlock rule is `lib/core/models/module_unlock.dart` (an
  engagement gate: `kModuleUnlockTracked` SRI items in the previous module).
  "What next?" is `lib/features/curriculum/next_step.dart`, built on the
  readiness maths in `lib/core/curriculum/curriculum.dart`.
- **Review routing**: `lib/features/review/review_router.dart` maps every SRI
  namespace to a review route. A game that records under a new
  `<module>.<skill>.` namespace needs a line there; `review_router_test` fails
  until it has one.
- **Learner profiles**: `ProfileService` + `learner_scope.dart`. Per-learner
  stores (review data, stars, streak, tutorials, user songs, saved projects)
  build their keys with `learnerKey(...)`; the first profile keeps the
  original un-prefixed keys, so there is no migration. Device-wide settings
  (language, sound, instruments, the tray) are not scoped.
- **Error log**: `lib/core/services/error_log.dart` catches errors that escape
  a build or an unawaited future and keeps the last 50 on the device (Settings
  ▸ Debug ▸ Error log, after seven taps on the home title). Nothing is sent
  anywhere.
- **Accessibility**: the shared piano keyboard, fretboards and home cards carry
  semantics (`test/a11y_widgets_test.dart`). A keyboard used where the key's
  name is the answer passes `semanticNames: false`.
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
- **Transcription — audio → sheet music** (`core/audio/transcription/`) — a
  clean-room, patent-free pure-Dart monophonic pipeline (pYIN F0 → note-state
  Viterbi → auto-tuning → spectral-flux onsets + autocorrelation tempo + Ellis
  DP beats → key/clef/meter estimation → a `crisp_notation` Score) plus a neural
  polyphonic path (Basic Pitch / CREPE via `onnx_runtime_dart`) for chords &
  inharmonic timbres, wired behind an auto-router. Exports MusicXML / MIDI / ABC.
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
- **Guitar tablature** — a touch-first tab editor (`TabDocument`) with a
  cost-based fret **arranger** (Viterbi over playable positions), plus the
  `tabconv` CLI. Reads GPIF `.gp3`/`.gp4`/`.gp5`/`.gpx`/`.gp` (and any
  notation format) and **writes GPIF `.gp`**, preserving the arranged
  string/fret choices, techniques (bends & contours, hammer-ons, slides,
  vibrato, dead/ghost/harmonic notes) and each track's tuning.

### Headless CLI tools (`dart run bin/<x>.dart`)

One dispatcher, **`mus`**, fronts the suite — `dart run bin/mus.dart <cmd> …`:

| cmd | what it does |
|---|---|
| `listen` | mic / WAV → live pitch & chord detection; `--transcribe` a recording → MusicXML / MIDI / ABC |
| `info` | sniff + dump any module (`.mod`/`.s3m`/`.xm`/`.it`) |
| `conv` | convert modules between formats + extract samples to WAV |
| `render` | a Loop Mixer groove (share token) → WAV |
| `midi` | module ↔ MIDI / MusicXML / ABC / kern / MEI / MuseScore (both ways) |
| `fx` | apply a crisp_dsp effect to a WAV offline |

Standalone bins (not under `mus`): `rendersong` (a score / MIDI / MusicXML …
through a SoundFont → WAV/MP3, per-part General-MIDI voicing; `--sf2` takes a
file **or a catalog id** like `generaluser_gs` that auto-downloads + caches a
permissively-licensed SoundFont — `--list-soundfonts`; set `COMET_SOUNDFONT_MIRROR` to pull from a self-hosted mirror, prepared by `tool/mirror_soundfonts.sh`), `tabconv` (any
notation format — ABC / MIDI / MusicXML / MuseScore / MEI / kern / GPIF /
JAMS melody — → a **GPIF `.gp`**, running the cost-based tab arranger so
the frets are playable; `--tuning`/`--capo`/`--no-arrange`, multi-part → one GP
track per part), `sfont` (inspect / render `.sf2` / `.sf3`),
`transcribe_basicpitch` · `transcribe_crepe` · `transcribe_chords` (neural
transcription paths).

## Development

```
tool/bootstrap.sh        # clones the sibling repos if missing, then pub get
flutter analyze          # strict: strict-casts / strict-raw-types
flutter test             # add --coverage for lcov.info
flutter run -d chrome    # or macos, etc.
```

The app resolves three packages by relative path — `../crisp_notation`,
`../CrispEmbed` and `../onnx_runtime_dart` — so a bare clone cannot run
`flutter pub get`. `tool/bootstrap.sh` clones whichever is missing next to this
repo (it never touches one that exists) and `tool/bootstrap.sh --check` only
reports. They track `main`, as CI does; there is no pinned revision.

CI (`.github/workflows/ci.yml`) runs format + analyze + test on every push and
PR, checking out the sibling `crisp_notation` repo alongside so the path dependency
resolves. The `build/` symlink (a dev-only SSD path) is intentionally untracked.
The test suite covers ~85% of `lib/` — the services, the pure-Dart audio/DSP
stack, the module + notation interchange round-trips, and a render smoke test per
game screen.
