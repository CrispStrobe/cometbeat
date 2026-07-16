# Loop Mixer — handover

**Status:** not started. This is the last big item on the `docs/PLAN.md` creative
backlog (E-tier). It's the first feature that needs the audio layer to do
something it currently *cannot* — play **several synced loops at once** — so most
of the work is a small **loop engine**, not a screen. This doc is meant to be
enough to build it end-to-end without re-deriving the audio plumbing.

---

## 1. What it is

A kid **loop-mixer toy**: a handful of cards — e.g. **bass · chords · melody ·
drums** — each toggles a pre-authored musical loop on/off. Tapping cards layers
the loops into a groove that plays continuously and in time. It's a **creative
sandbox** (like *My Melody* and the new *Colour Melody* grid composer): **no
stars, no wrong answers**, free play. Everything is authored in one key /
pentatonic so **any combination sounds good** (same trick as Colour Melody).

Target feel: tap "drums" → a beat starts looping; tap "bass" → a bassline drops
in *on the beat*; tap "melody" → a riff layers on top; untap any → it drops out
cleanly. Bonus polish: a moving bar-position indicator, maybe per-card level.

---

## 2. Why it isn't trivial — the audio layer today

`lib/core/services/audio_service.dart` is **single-shot and monophonic**:

- One `AudioPlayer` (`audioplayers ^6.1.0`). Every `_play(wav)` calls
  `player.stop()` **then** `player.play(BytesSource/UrlSource)` — so a new sound
  *replaces* the current one. **No mixing, no looping, no sync.**
- All sound is **synthesized offline in pure Dart** (no audio assets): a
  `List<Segment>` (`typedef Segment = ({List<double> freqs, int ms})`) →
  `renderSegments()` → PCM16 → `wavBytes()` → a data-URI/bytes WAV played once.
  See `lib/core/audio/synth.dart`.

So the Loop Mixer needs **simultaneous, looping, time-aligned** playback. Do
**not** reach for a native mixer or multiple real-time players first — there's a
much simpler path that matches the app's pure-Dart ethos.

---

## 3. Recommended architecture — **offline-mix-then-loop-one-WAV**

Render the *whole groove* to a single looping buffer, and re-render it whenever
the enabled set changes. One player, one buffer → **sample-accurate sync for
free** (all tracks share one timebase), and no real-time mixing.

```
tracks (fixed-length patterns) ──render each to PCM──▶ sum enabled ──normalize──▶ one loop WAV ──▶ AudioPlayer(loop)
        ▲ toggle a card                                                                              ▲ re-render + swap on toggle
```

**Invariant:** every track's pattern is the **same length in samples** (e.g. all
= two 4/4 bars at the chosen tempo). Then summing is index-aligned and the
buffer loops seamlessly.

### The one real subtlety: normalization

`renderSegments()` **peak-normalizes each render to 80% full scale** (and applies
`gain`). If you render each track *separately* to `Int16List` and add them, each
is already independently loud → the sum clips and levels are inconsistent.

**Fix:** sum at the **pre-normalization Float64 stage**, normalize the mix once.
Add a small function to `synth.dart` (Flutter-free, unit-testable):

```dart
/// Renders each track's segments into a shared-length Float64 buffer with a
/// per-track [gain], sums them, and normalizes the MIX once. All tracks must
/// render to the same sample length (same total ms).
Int16List mixTracks(List<({List<Segment> segments, Timbre timbre, double gain})> tracks, {int sampleRate = kSampleRate});
```

Implement it by refactoring the existing per-segment render loop in
`renderSegments` into a private `_renderToFloat(segments, timbre) -> Float64List`
(no normalization), then in `mixTracks`: allocate one `Float64List`, add each
track's `_renderToFloat * gain`, find the peak of the **sum**, scale to 0.8·FS,
convert to `Int16List`. `renderSegments` keeps its current behaviour by calling
`_renderToFloat` then normalizing — no behaviour change for existing callers
(protect this with the existing `synth_test.dart`).

Then `wavBytes(mixTracks(enabledTracks))` is the loop.

---

## 4. Building blocks that already exist (reuse, don't reinvent)

- **`lib/core/audio/synth.dart`** — `Segment`, `renderSegments` (→ `Int16List`
  PCM), `wavBytes` (PCM→WAV), `renderWav`, `timbreFor(Instrument)`. This is where
  `mixTracks` goes. Its tests are Flutter-free (`test/synth_test.dart`) — mirror
  that for the mixer math.
- **`AudioService`** — patterns to copy: `playChordSequence(List<List<int>>)`
  shows how a beat grid maps to segments (empty inner list = a rest = silence).
  `midiToFrequency`, `timbreFor(instrument)`.
- **A visual playhead** (optional polish) — `PlayAlongEngine` /
  `beat_runner_screen.dart` drive a `Ticker` clock; copy that for a bar-position
  indicator. **CLAUDE.md gotcha:** create Tickers in `initState`, never a lazy
  `late final` (lazy creation during `dispose` throws deactivated-ancestor).
- **Colours** — `pitchClassColor(Step)` (`note_reading/note_colors.dart`), used by
  Colour Melody, for per-card colour.
- **Sandbox registration** — `grid_composer` / `my_melody` in
  `lib/features/games/game_registry.dart` show a **no-star sandbox** GameInfo
  (nothing in `core/tuning.dart` — `consistency_test` only validates brackets that
  exist, so a sandbox needs none). Put the Loop Mixer in the `composition` module.

---

## 5. Build plan (slices)

**Slice 0 — `LoopEngine` (pure Dart, no Flutter).**
`lib/core/audio/loop_engine.dart`: holds the fixed set of track patterns
(`List<Segment>` each, all same total-ms), an enabled-set, and
`Uint8List renderLoop()` → `wavBytes(mixTracks(enabled))`. Plus the `mixTracks`
addition to `synth.dart`. **Unit-test both** (Flutter-free, like
`synth_test.dart` / `streaming_analyzer_test.dart`): enabling more tracks changes
the bytes; the mixed peak never clips; an empty set renders silence of the right
length.

**Slice 1 — looping playback.**
The loop needs its **own** `AudioPlayer` set to `ReleaseMode.loop`
(`audioplayers` supports it: `player.setReleaseMode(ReleaseMode.loop)`), kept
**separate from `AudioService`'s SFX player** — otherwise a feedback blip or
another screen's sound would `stop()` the groove (and vice-versa). Either add a
second player channel inside `AudioService` (e.g. `LoopChannel`) or give the
mixer its own tiny service. On toggle: re-render `renderLoop()` and swap the
source. **v1: accept a tiny restart hiccup** on swap (re-`play` the new WAV);
note it and move on. Web: use `UrlSource('data:audio/wav;base64,…')`, not
`BytesSource` (same branch as `AudioService._play`). Respect the `soundOn` master
gate. **Stop + dispose the loop player** in `dispose` and when leaving the screen
(don't let a groove play on under other screens).

**Slice 2 — the screen.**
`lib/features/games/composition/loop_mixer_screen.dart`: a row/grid of big
track cards (bass/chords/melody/drums), each showing on/off state + its colour;
tap toggles. A Play/Stop (or auto-play on first enable). Register the GameInfo
(composition, no star bracket) + EN/DE ARB. Add a `@visibleForTesting` tester
seam (`Set<String> get enabledTracks; void toggle(String id);`) so the widget
test can drive toggles headlessly (mic/audio are no-ops under test — assert the
enabled set and that `renderLoop()` differs / play doesn't throw). Mirrors the
`GridComposerTester` / `KeyFindTester` seams.

**Slice 3 — polish (optional).** Gapless swap (two players, switch at the loop
boundary or short crossfade); tempo slider; a bar-position playhead (Ticker);
per-card mute vs level; more loop variants per card.

---

## 6. Loop content (author it consonant)

Author patterns in **one key / C-pentatonic** so every combination grooves (the
Colour Melody rule). Suggested starter set, all **2 bars of 4/4** (identical
length):

- **Bass** — root notes on strong beats (C … G …), low octave.
- **Chords** — a simple I–V or a held pad in C (via multi-`freqs` Segments =
  chords).
- **Melody** — a short pentatonic riff (C D E G A).
- **Drums** — **NB the synth is tonal** (`freqs` → sine harmonics). Percussion
  needs **noise**, which the current synth doesn't generate. Cheapest paths:
  (a) reuse the SFX click (`renderSfxTick`) as a kick/hat placed on the grid; or
  (b) add a `noise`/`percussion` Segment variant to `synth.dart` (a short
  filtered-noise burst). Pick (a) for v1, (b) if drums feel too "beepy".

Keep tempo fixed for v1 (e.g. ~100 BPM → a 2-bar loop is a fixed ms, so all
tracks share the sample length trivially).

---

## 7. Gotchas / traps

- **Separate audio player for the loop** (see Slice 1) — the single shared
  `AudioService` player would kill the groove on any other sound.
- **Same sample length across tracks**, or the mix mis-aligns and the loop
  clicks. Derive every pattern's total-ms from the same tempo × bars.
- **Normalize the *mix*, not each track** (§3) — else clipping / uneven levels.
- **Ticker in `initState`**, never lazy `late final` (CLAUDE.md).
- **Web audio** is `UrlSource(data-URI)`, not `BytesSource`.
- **Dispose** the loop player and stop the groove when the screen closes.
- **Test harness under load** — the monolithic `flutter test` currently
  **SIGTERM-flakes** on this machine when other agents/builds push the load
  average high (it kills a *random* stable test's subprocess, not a real
  failure). Run tests in **small batches / per-file**; they pass. `flutter
  analyze` and single-file runs are reliable.
- **Coordination** — `game_registry.dart`, `core/tuning.dart` and the ARBs are
  hot shared files; `git pull --rebase origin main` before committing, keep
  commits small, update the `docs/PLAN.md` board, and push each ship as a rebased
  fast-forward (`git push origin <branch>:main`). `dart format` FIRST, then
  whole-project `flutter analyze` LAST.

---

## 8. Verification checklist

- `test/loop_engine_test.dart` (Flutter-free): mix length, no-clip, enabled-set →
  different bytes, empty = silence.
- `synth_test.dart` still green after the `mixTracks`/`_renderToFloat` refactor.
- `test/loop_mixer_test.dart` (widget): toggle cards via the tester seam →
  `enabledTracks` tracks; play doesn't throw; Stop clears.
- `consistency_test` green (new GameInfo id/ARB resolve in both locales).
- `flutter analyze` whole project → *No issues found*.
- Full suite green (in batches, per the harness note).

---

## 9. Open decisions for the maintainer

- **How many tracks / which** (bass·chords·melody·drums is the default).
- **Drums:** reuse the SFX click (v1) or add a noise generator to `synth.dart`.
- **Tempo:** fixed (simplest) vs a slider.
- **Swap on toggle:** restart-with-hiccup (v1) vs gapless dual-player (polish).
- **One extra idea if it grows:** record/export the groove, or a "save my loop"
  slot — but that's well past v1.
