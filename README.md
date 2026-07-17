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
| `composition` | Komponieren (Kompositionstechnik) | Ending Detective (closure) • Question & Answer (phrases) • My Melody (free composing sandbox, saves to the Song Book as MusicXML) |
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
  being built in `../crisp_notation` (path dependency). Its contract is
  `../crisp_notation/HANDOVER.md` as amended by
  `../crisp_notation/HANDOVER_CRISP_NOTATION.md`.

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
The test suite (140 tests) covers ~85% of `lib/`, including the services, the
import round-trips, and a render smoke test per game screen.
