# KlangUniversum (working title)

A music notation and harmony learning app for children from primary school
onwards (6+), built from minigames. Sibling of Space Math Academy
(`../space_math_academy`) and WortUniversum (`../voc`), sharing the same
architecture: `lib/{core,features,shared,l10n}`, Provider, ARB-based i18n
(EN/DE), and an SM-2 spaced-repetition engine ("SRI").

Targets: iOS, Android, Web, Windows, macOS, Linux.

## Modules (each = a set of minigames)

See [docs/PLAN.md](docs/PLAN.md) for the full curriculum map and roadmap.

| id | Topic | Games |
|---|---|---|
| `note_values` | Notenwerte & Pausen | Symbol Quiz • Duration Duel |
| `note_reading` | Noten lesen (Violin/Bass) | Reading Quiz ×2 • Place the Note ×2 (SRI review runners) |
| `measures` | Takte & Taktarten | Measure Filler |
| `scales` | Tonleitern, Dur/Moll | Scale Detective |
| `chords` | Akkorde & Intervalle | Chord Quiz |
| `harmony` | Harmonik (T/S/D) | Function Quiz |

Later: audio/ear training, Kadenzen, Kompositionstechnik (see plan).
Live web build: https://mus-theta.vercel.app

## Architecture notes

- **SRI**: `lib/core/services/sri_service.dart` — SM-2, generalized to opaque
  item IDs with the convention `<moduleId>.<skillId>.<detail>`. Tuning
  constants in `lib/core/tuning.dart` (identical values to the sibling apps).
- **Modules**: registered in `lib/core/models/learning_module.dart`; the home
  screen renders from that list. Adding a module = registry entry + ARB keys.
- **i18n**: `lib/l10n/app_{en,de}.arb`, generated via `flutter gen-l10n`
  (`generate: true`).
- **Notation rendering**: comes from `partitura`, the standalone MIT library
  being built in `../partitura` (path dependency). Its contract is
  `../partitura/HANDOVER.md` as amended by
  `../partitura/HANDOVER_PARTITURA.md`.

## Development

```
flutter pub get
flutter test
flutter run -d chrome   # or macos, etc.
```
