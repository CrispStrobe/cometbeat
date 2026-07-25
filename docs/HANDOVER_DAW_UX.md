# Handover — DAW & UX optimizations (paste this into a fresh agent)

You are picking up the **CometBeat** Flutter music-education app to continue
**DAW ("Audio Editor") and UX optimization work**. This document is your full
brief: orientation, the mandatory multi-agent workflow, the current architecture,
what's already done (do **not** redo it), and the prioritized open work.

---

## STATUS UPDATE (opus, 2026-07-25) — §A/§B/§D all worked (§C Tracker excluded)

The prioritized open work in §5 below is **done** (each shipped to `origin/main`
with tests). Quick index (see `docs/PLAN.md` board + `docs/HISTORY.md` for detail):

- **§A Score Workshop:** A1 narrow layout verified (`72cf3552`); A2 bar numbers —
  overlay clip fix (`18544363`) **+** engine now numbers the first system so
  grand-staff/multi-part show them (crisp `fe39bc6` + app `235edfbe`); A3 info
  button explains controls (`9f33b842`); A4 editable composer/lyricist + into PDF
  (`7c070ff0`); A5 lyric field no longer loses keystrokes to note entry
  (`790c8a85`); A6 analysis colour-by-harmony now paints the multi-part canvas
  (`a63cbc73`); A7 "Copy/Paste tune" rename + Loop-selection explained
  (`9f33b842`); A8 export web-download fallback (`c6d7b829`).
- **§B Sound Library:** B1 accurate web instrument-install reason + working
  fallback (`f42e2dcc`); B2/D3 the one unified browser is complete (codex
  `061e7924`/`832e749e`) and now guarded by a test (`8a25c3e4`) — the only
  remaining parallel entries are in the Advanced Tracker (§C, excluded).
- **§D Audio Editor:** D1a help/guide overlay + linked-clip affordance
  (`8de608a5`); D1b responsive toolbar + narrow-body scroll (`ec9d74c3`); D1c
  keyboard shortcuts + help (`d19c01cb`); D4 touch multi-select verified
  (`ef045814`); D3 cross-mode audit (Sound Library shared across all modes).
- **Remaining truly-open:** the Beginner/Advanced **Tracker** UX (§C) only —
  another agent's scope.

---

## 0. Mission

Make the app's **authoring surfaces** (the five product modes + the Sound
Library) genuinely usable, coherent, and capable — on **web and mobile** as well
as desktop. The audio *engine* is now very strong (see §4); the gap is **UX,
web/mobile parity, and cross-mode coherence**, plus a few DAW polish items.

The five authoring modes (Home → piano icon "Authoring" menu):
**Score Workshop · Advanced Tracker · Tab Workshop · Loop Studio · Audio (DAW)**.
Legacy Perform / Drumkit / Transcribe remain internal surfaces whose workflows
are folding into Loop Studio and Audio.

---

## 1. Environment & build

- Primary clone: `/Users/christianstrobele/code/mus` (branch `main`). Rendering
  comes from a **sibling path dependency** `../crisp_notation/...` (the MIT
  notation library) — this is why worktrees MUST be siblings of `mus/`.
- **This machine's Ruby/CocoaPods env is broken.** Wrap every flutter/pod/xcode
  call:
  ```bash
  PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT flutter <cmd>
  ```
- **Web build needs no pods** and is the fastest way to verify the whole app
  compiles + that your web/mobile fixes work:
  ```bash
  PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT flutter build web --debug
  ```
- Local dev notes live in `mus/CLAUDE.md` (**gitignored**, only in the main clone;
  not in worktrees). Read it first — it has App Store flow, disk policy, the
  VPS/corpus notes, and gotchas.
- Package name is `comet_beat`. l10n is ARB-based (`lib/l10n/app_en.arb` +
  `app_de.arb`) → run `flutter gen-l10n` after editing ARBs.

---

## 2. MANDATORY workflow (multiple agents push to origin/main concurrently)

Read this twice — the repo is a **hot multi-agent environment** and sloppiness
loses work.

1. **Work in a feature branch + a sibling worktree**, e.g.
   `cd /Users/christianstrobele/code/mus && git worktree add ../mus-<topic> -b feature/<topic>`.
   A worktree under `.claude/` would break the `../crisp_notation` path dep.
2. **Board coordination is mandatory.** At every checkpoint (task start, before
   touching a hot shared file, after each ship) update the `🚧 Actively working
   on` board at the TOP of `docs/PLAN.md` with what you're doing + which shared
   files you're touching, and push it: `git pull --rebase origin main` then
   `git push origin main`. This is how agents avoid clobbering each other.
3. **No PRs.** Commit small, merge straight to `main`. To ship: from the **main
   clone** on `main`, `git pull --rebase origin main`, `git merge --no-ff
   <your-branch>`, `git push origin main`. Then `git rebase main` in your worktree.
4. **The main clone is often dirty** (another agent's uncommitted WIP). Before a
   merge there, `git stash -u`, do the merge+push, then `git stash pop`. Never
   commit another agent's files.
5. **⚠ The hot-ARB "clobber gremlin" is real.** `app_en.arb`/`app_de.arb` and the
   generated `app_localizations*.dart` get concurrently rewritten; your
   uncommitted ARB keys can silently vanish, and a stale-branch revert can drop
   another agent's keys (there are commits in history literally titled "restore …
   clobbered by a stale-branch revert"). Mitigation: add ARB keys, `gen-l10n`,
   **commit promptly**, and if a merge conflicts on generated l10n, resolve by
   taking the merged ARBs and re-running `gen-l10n`. If analyze shows
   `undefined_getter` on l10n after a sync, an ARB lost keys — restore from
   `origin/main` and re-apply only yours.
6. **Pre-commit:** `dart format` FIRST, then `flutter analyze` LAST (whole project
   incl. `test/`). Aim for **"No issues found."** Format can introduce
   trailing-comma lints, so analyze after formatting.
7. **Tests gate ships.** `flutter test <files> | tail && git push` EATS the exit
   code — use `set -o pipefail` whenever a push gates on piped test output.
8. **Coordinate with live agents.** As of this handover the active worktrees are:
   `codex/crispaudio-parity` (DAW FX/stereo — very active on `daw_screen.dart` /
   `daw_service.dart` / `daw_timeline.dart` / the shared FX editor),
   `codex/tracker-render-regression`, `feature/tracker-ux`,
   `feature/asset-catalog` (Sound Library/catalog), `feature/textbook-prose-anavis`.
   **Do not deep-edit files another agent is mid-refactor on** without a board
   heads-up; prefer new shared files you own + thin wiring.

---

## 3. Architecture map (where things live)

Authoring screens — `lib/features/games/composition/`:
- `daw_screen.dart` (~4000 lines) — the **Audio Editor** ("Audio"/"Multitrack").
- `loop_studio_screen.dart` — **Loop Studio**: Simple + Advanced views over one
  Loop Mixer document (`loop_mixer_screen.dart`).
- `advanced_tracker_screen.dart` — the **Advanced Tracker** (pattern editor).
- `tab_workshop_screen.dart` — the **Tab Workshop** (now multi-instrument: one
  tab track per part via `initialParts`).
- `multipart_to_tracker.dart` — `trackerSongFromMultiPart` (score→tracker bridge).

Score editor — `lib/features/workshop/screens/composition_workshop_screen.dart`
(the **Score Workshop**; model in `workshop/model/{score_document,multi_part_document}.dart`).

DAW engine (pure-Dart, headless-testable):
- `lib/core/audio/daw_timeline.dart` — `ClipSource`/`Clip`/`DawTrack`/`DawTimeline`,
  `renderTimeline` (now **stereo**, per-track pan, bus/master FX chains,
  `TrackEffect`/`DawClipEffect` with automation). Adapters in `daw_sources.dart`
  (Drum/Groove/Score/Tracker/Sample/**StereoSample**).
- `lib/core/services/daw_service.dart` (~1800 lines) — the app-wide `DawService`
  Provider: clips/tracks, undo/redo, split/reverse/respeed/freeze/merge,
  crossfade, cut/copy/paste, per-clip/track/bus/master FX + automation, stereo
  pan/width, project save/load. Key methods from the recent arc: `clipScore`,
  `clipSourceAt`, `replaceScoreClipSource` (in-place round-trip),
  `setClipInstrument`/`setTrackInstrument`, `setTrackEffect`.

Library / cross-mode routing (shared, `lib/shared/music/`):
- `music_picker.dart` — `showMusicPicker → MultiPartScore?` (Song Book + file
  import + **online catalog scores**) and the pure `decodeMusicFile` (MIDI,
  MusicXML/.mxl, ABC, MEI, **kern, MuseScore .mscx/.mscz, GP/GPX, **.gabc**).
- `score_router.dart` — `openScoreInWorkshop` / `openScoreInTab` /
  `openScoreInTracker` / `showScoreDestinations`, all with an optional
  `onReturn` for the **in-place round-trip** (editor's "Send to Audio Editor"
  updates the SAME clip). Editors accept `onReturnToDaw`.

Sound Library (instruments/samples) — `lib/features/sound_lab/` (Sound Lab /
Voice Lab now live here + as Audio Editor modals) and
`lib/features/library/` (`CometbeatCatalogSource` — the curated HF catalog with
`soundfont/instrument/sample/module/score` kinds; `library_import.dart`).

Home menu wiring: `lib/features/home/screens/home_screen.dart`.

Docs: `docs/PLAN.md` (pending/planned + the live board), `docs/HISTORY.md`
(shipped), `../testing_dart.md` (testing methodology).

---

## 4. What is ALREADY DONE — do not redo

**The "Editors unification & Audio Editor" arc (opus):** Sample Extractor + Sound
Lab + Voice Lab moved into Sound/Voice Lab and the Audio Editor as SoundFX modals;
Multitrack→"Audio Editor"; instrument-lane tracks (per-clip/track voice, inherited
by new clips); music import into the DAW (`Add clip → Add music`: Song Book / file
/ online catalog, all formats incl. `.gabc`); Transcribe-as-a-function inside the
Score editor; Topics-by-grade folded into the Textbook; Progress+Recitals united;
**instrument sound selectable from the assets library everywhere**; full **symbolic
round-trip** (DAW music clip → Score/Tab/Tracker editor → send back updates that
same clip in place). Fully unit- + live-widget-tested (`test/music_flow_test.dart`,
`test/music_picker_test.dart`, `test/daw_service_test.dart`).

**The "crispaudio-parity" arc (codex) — the DAW is now a pro-grade engine:** full
**stereo** throughout (import/persist/freeze/reverse/respeed/merge, stereo
waveform UI); a **shared FX chain** across clip/track/bus/master with a common FX
tile + **automation** (breakpoints, curve shapes, inline lane summary): Reverb
(decay-seconds), Pan (constant-power), Noise Gate (attack/release), Compressor
(knee), Delay (spread), Chorus/Flanger (decorrelated), Pitch Shift, Time Stretch,
Tremolo, Vocoder, Voice Shape, Gain; **per-clip** pan/width/fade-curves;
**crossfade**; **selected-clip cut/copy/paste** across lanes; **track pan +
stereo export**; **export** format/bit-depth/rate/bitrate choices; FLAC/MP3 import
+ SFZ MP3/FLAC sample playback; DAW catalog **insert-first** path.

Treat the above as **shipped**. Your job is UX/parity/coherence on top of it.

---

## 5. OPEN WORK — prioritized

The single biggest open backlog is the **Score-Workshop-web / authoring-UX** item
at the TOP of `docs/PLAN.md` (owned/started by `codex/score-editor-web`).
**Coordinate — claim sub-items on the board before starting so you don't collide.**
Concretely, still open:

### A. Score Workshop web/mobile usability (highest priority)
- **Responsive layout:** the top action/settings rows must scroll/reflow at narrow
  widths; every control reachable on web/mobile.
- **Note names must include octave** (e.g. `F2`) and stay legible at compact sizes;
  the bar-number setting currently has no visible effect — fix it.
- **Editing UX:** marquee selection is unreliable; `Insert` needs an explicit
  label/help state; V1/V2 need descriptive voice labels + help; the info button
  must explain controls, not only shortcuts.
- **Score identity & metadata:** editable **title** on the main surface (saving
  must not be the first place a title is requested), plus optional
  subtitle/composer/lyricist carried into PDF / MusicXML / other formats.
- **Lyrics:** remove input lag / dropped keypresses; deterministic syllable entry;
  unit + widget tested.
- **Analysis:** repair or disable the broken "color by harmony" until it produces
  verified colors + explanations.
- **Sharing/library:** rename "Share Tune / Load shared Tune" to clear
  Copy/Paste or Save/Load-Library actions and make persistence match the labels;
  make "Loop Selection" range behavior visible/explained.
- **Export:** native share handoff where supported (iOS/macOS share sheets/AirDrop)
  with a web download fallback; extend multi-part exporters where the format can
  represent parts and explain unavoidable losses.

### B. Sound Library web parity
- Fix sample-import failures on web; make instrument install/playback work on web
  where feasible; replace "Browsable here — install coming soon" with a working
  fallback or an accurate reason.
- Unify: Mod Archive, Load SoundFont, catalog browsing, instrument/sample install,
  and score/module loading should all live in the **one** Sound Library browser,
  not parallel one-off menu entries. (Coordinate with `feature/asset-catalog`.)

### C. Advanced Tracker UX
- Reduce its oversized menu into logical **Import/Open · Library · Edit · View ·
  Playback · Export** groups; make import/load + save/export consistent with the
  Score Workshop.
- **Beginner Tracker experience:** make the kid surface intuitive, expressive, and
  capable enough to recreate a reduced-but-real live-loop workflow (start quickly,
  layer parts, record a voice, arrange). (Coordinate with `feature/tracker-ux`.)

### D. DAW ("Audio Editor") polish (your home turf — lower collision if you avoid
codex's in-flight FX files; check the board)
- **First-open DAW-ness & discoverability:** the transport/toolbar and the large
  FX/automation surface need an information-hierarchy pass for web/mobile
  (scroll/reflow narrow toolbars; make the clip inspector's growing action set
  legible; keyboard shortcuts + a help overlay).
- **In-place round-trip UX:** currently "Open in editor" on a music clip and
  "Send back" updates the same clip (via `replaceScoreClipSource`). Add a visible
  affordance/label so users understand a clip is "linked to an editor", and
  consider round-tripping the Tracker destination too.
- **Cross-mode coherence:** the five modes should share consistent
  Import/Open · Library · Export vocabulary and the same Sound Library. Audit for
  parallel/inconsistent entry points.
- **Selection & timeline ergonomics:** verify marquee/multi-select, snap, and
  playhead interactions are discoverable and work under touch.

### E. Verification (required for every fix)
Add **unit tests** for pure conversion/metadata/import methods and **widget/live
tests** for each repaired interaction, at **narrow AND desktop widths**. Follow the
existing patterns: `test/support/game_test_support.dart` `pumpGame(...)`, the
per-screen `*Tester` interfaces, and `test/music_flow_test.dart` for live flows.
Use the layout-audit style (pump at phone + tablet sizes, EN + DE, assert no
overflow) — see `test/layout_audit_test.dart`.

---

## 6. Working style

- **Prefer new shared files you own + thin wiring** over deep edits to
  `daw_screen.dart` / `daw_service.dart` while `codex/crispaudio-parity` is live.
- Ship in **small, independently-verifiable slices**; update the board + push
  after each.
- When in doubt about a decision that's the maintainer's to make (product scope,
  irreversible/outward-facing actions), ask rather than guess.
- Keep it **web + touch first**: if a control isn't reachable/usable at a narrow
  width on the web build, it isn't done.

Good luck. Start by reading `mus/CLAUDE.md`, the top of `docs/PLAN.md`, and doing
one `flutter build web --debug` to confirm a green baseline.
