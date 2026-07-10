# KlangUniversum (working title)

A music notation and harmony learning app for children from primary school
onwards (6+), built from minigames. Sibling of Space Math Academy
(`../space_math_academy`) and WortUniversum (`../voc`), sharing the same
architecture: `lib/{core,features,shared,l10n}`, Provider, ARB-based i18n
(EN/DE), and an SM-2 spaced-repetition engine ("SRI").

Targets: iOS, Android, Web, Windows, macOS, Linux.

## Modules (each = a set of minigames)

| id | Topic | Status |
|---|---|---|
| `note_values` | Notenwerte & Pausen (durations) | 2 games: Symbol Quiz, Duration Duel; SRI review flow |
| `note_reading` | Noten lesen (Violin-/Bassschlüssel) | 2 games: Treble/Bass reading quiz on partitura StaffView |
| `measures` | Takte & Taktarten | locked |
| `scales` | Tonleitern, Dur/Moll | locked |
| `chords` | Akkorde & Intervalle | locked |
| `harmony` | Harmonik (Tonika/Subdominante/Dominante) | locked |

Later candidates: Kadenzen, Stimmführung, Kompositionstechnik.

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
