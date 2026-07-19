# CometBeat — Curriculum & Game Plan

Music notation and harmony for children from primary school onwards (6+),
decomposed into exciting minigames. EN/DE, modularly extendable, running on
iOS/Android/Web/Windows/macOS/Linux. Notation rendering via the MIT
[crisp_notation](https://github.com/CrispStrobe/crisp_notation) library (our own).

This file tracks **what is pending and planned**. What's already built and live
is recorded in [HISTORY.md](HISTORY.md).

## 🚧 Actively working on (agent coordination — keep in sync with origin/main)

Live board so parallel agents don't collide. **Update this at every checkpoint
and push to origin/main** before/after touching shared files. Format:
`agent · task · files touched · status`.

> Only 🚧 **ACTIVE** entries are live claims — don't edit another agent's ACTIVE
> claim. The long chronological log of shipped board entries has been moved to
> [HISTORY.md → "Agent coordination board — shipped log"](HISTORY.md#agent-coordination-board--shipped-log-chronological).
> **Pending, actionable work is scoped in the two blocks immediately below.**

- **opus (connect-degrees)** · ✅ **SHIPPED — new minigame: Connect the Scale Degrees** (`3042bd37`, `connect_degrees`). Fresh `ConnectMode.degrees`: match degree number 1-7 to its name (Tonic…Leading tone) + hear it in C major; pillars 1/4/5/7 for beginners, colour tones 2/3/6 at 2★. Reuses the ConnectLine scaffold (shared star bracket); placed in the `harmonic_function` concept; +EN/DE + widget test; consistency/coverage/home smoke green. Now idle.
### 📋 Handoff — items for other agents (raised by @tracker-replayer)

The tracker/SF2/sound-library ENGINE lane is closed + full-suite-verified. These
are the SCREEN/CONTENT items that depend on it — each in another agent's lane, so
listed here rather than done by me:

- **@loop-mixer / audio** · ⚠️ **BUG (breaks CI): `loop_mixer_screen.dart:1911`
  — a track card's `Column` overflows by 0.2px** (icon+label in the
  `AnimatedContainer`). Trips BOTH broad smoke tests (`live_flow_test` +
  `layout_audit_test`, which render every game) → `main` is red on 2 tests.
  Introduced by a concurrent push (NOT the drum-enum change — that card doesn't
  use `Drum.values`). Trivial fix (`mainAxisSize.min` / a hair of height /
  `Flexible`); your actively-worked file, so flagging not patching. **Also:** a
  `require_trailing_commas` lint at `test/loop_mixer_test.dart:287` keeps
  project-wide `flutter analyze` from being clean (one comma).
- **@tracker-ui** · wire the 5 shipped engine primitives (full checklist +
  one-line snippets in `docs/SOUND_LIBRARY_UI_CONTRACT.md`): (1) `showSoundFontSheet`
  into the instrument panel; (2) instrument JSON codec → a persistent
  `SoundLibraryService`; (3) `SoundFontRef`/`resolveInstrumentJson` for referenced
  GM voices; (4) l10n labels + per-voice colours/icons for the **5 new drum voices**
  (openHat/clap/tom/rim/cowbell — I left neutral defaults) + decide whether the kid
  Drumkit grid shows all 8 or a curated subset; (5) route "Export module" through
  `moduleDocFromSong` (PCM-preserving) instead of the Score path; (6) a native
  **Save/Load/Share song** via `tracker_song_codec.dart` — lossless
  `trackerSongToToken`/`fromToken` (compact `CBS1.` share token) +
  `tryTrackerSongFromToken` (paste, never throws) + `trackerSongInfoFromToken`
  (library-list preview).
- **@textbook-prose** · (optional) refine the `voice_leading` prose wording to your
  voice — I authored a functional EN+DE entry (`9b16472`) to unbreak the coverage
  test; content-correct but yours to polish.

- **opus (mp3-short)** · ✅ **SHIPPED — app MP3 export now uses stereo + short blocks** (`lib/shared/music_io/audio_export.dart`). The shared export sheet was mono-only + long-only; now `pcmFloatToMp3`/`pcmFloatToWav`/`showAudioExportSheet` take an optional `right` channel (→ joint(M/S) MP3 / interleaved stereo WAV) and MP3 export defaults to **short blocks ON** (offline → spend a little encode time to cut pre-echo on drums/beatbox/tracker/DAW mixes; byte-identical when no transients). Every existing mono call site (Sound Lab, Voice Lab, DrumKit, tracker, DAW…) gets better MP3 automatically with NO signature change; stereo is ready for panned sources (`synth.dart` has a panning stereo mixer). +5 tests (stereo WAV 2ch, stereo MP3→2ch decode, short-on-transient valid+differs, steady-tone byte-identical); analyze clean. Only `audio_export.dart` + its test touched (no hot shared file). Now idle.
- **opus (mp3-short)** · ✅ **SHIPPED — MP3 short blocks extended to STEREO + joint(M/S)** (follow-up to the mono fix below). The transient path is now channel-general: one `Mp3BlockScheduler` per channel (each keeps its own long→start→short→stop→long chain), raw subband held per (granule, channel) so M/S combines before the MDCT, per-channel freq-inversion→MDCT→WS-quantize; the SIDE channel stays un-psy-shaped. `shortBlocks` now on `mp3EncodeStereo`/`mp3EncodeJointStereo` too, still **default OFF = byte-identical** (verified: steady stereo tone with `shortBlocks:true` picks all-long → bytes == plain). Stereo transient reconstructs **L 59.4 / R 56.5 dB, beating long-only (57.0/53.5)**; joint L 58.7 / R 57.2. Only the opt-in `useShort` branch changed — the published non-short path is untouched. +4 tests (stereo/joint reconstruct+beat-long, steady=plain); 63 mp3 tests green; analyze clean. Next: WS psy-shaping (short scalefactors, NMR gap). Now idle.
- **opus (mp3-short)** · ✅ **SHIPPED — pure-Dart MP3 encoder: short-block (transient) emission now WORKS** (was the long-standing ~3 dB bug). Two compounding defects in the window-switching quantizer (`lib/core/audio/mp3/mp3_short.dart`), both fixed: (1) `_bestTable`'s ESC candidate list stopped at table 24 (linbits 4, max coeff ~30) so large short-block coefficients emitted **truncated Huffman codes** AND under-counted bits (the gain search then wrongly accepted a too-fine gain) — replaced with proper ISO `table_candidates` picking the ESC table whose linbits cover the value; (2) `mp3QuantizeGranuleWs` had no **anti-clip min-gain bound** so the peak coefficient clipped to 8191 — added glint's `g > 210 − (16/3)·log2(8190/peak34)` bound. Forced valid long→start→short→stop→long now reconstructs at **77.5 dB** (was 3.2), auto-transient **69.8 dB > 68.0 long-only** (short blocks finally help), and the **ffmpeg oracle agrees exactly (69.8 dB)**. `shortBlocks` stays **opt-in, default OFF = byte-identical** to the published long-only encoder. +`test/mp3_short_encode_test.dart` (3 tests); 60 mp3 tests green; analyze clean. Only `lib/core/audio/mp3/*` + a test touched (no hot shared file). Next: sync the two-line fix into the `glint_audio_pure` package + bump. Now idle.
- **opus** · ✅ **SHIPPED — Loop Mixer §A: sheet-music panel now shows EVERY track** (`ad1ab10`). Root cause wasn't a render crash (layout/widget both clean in fuzz): the panel engraved only the single *leading* pitched track (`_engravedTrackId`), so a full band showed just melody/chords — bass/sparkle outranked, drums never engraved — and toggling Score with nothing on silently showed nothing ("button did nothing"). Now one labelled staff **per enabled track** (pitched = real notes; drums/beat = a one-staff rhythm reduction via new `groove_notation.drumGrooveScore`), each fitted to a compact fixed height so the whole band is visible at once; an empty-state **hint** when nothing is on. +tests (staff-per-track incl. drums, empty-state hint, `drumGrooveScore`) + l10n de/en. No `loop_engine.dart`/DAW touch. Now idle.
- **opus (loop-juice)** · ✅ **SHIPPED — Loop Mixer 3.0 §D-1: beat-reactive cards** (`15c1b95`). Each enabled card flashes a soft glow + tiny scale swell on every beat (fuller on the downbeat) via a `_BeatPulse` wrapper around `_TrackCard`, driven by the existing `_step` beat notifier. Paint-only (Transform+shadow), no layout/tap impact, no engine change; 16 loop-mixer tests green, tasteful magnitudes verified by a render capture. Now idle — next 3.0 candidates: §C-4 dice, §D-3 step playhead, or §B kits/styles.
- **opus (loop-juice)** · ✅ **SHIPPED — Loop Mixer 3.0 §C-4: dice / "surprise me"** (`5bf4cec`). A filled dice button (top control row) rolls a fresh always-good groove: drums anchor + a random mix guaranteeing ≥1 melodic voice (never empty), random variant per layer, light swing nudge; every combo consonant. Existing engine API + `_syncPlayback` (starts from stopped); test rolls 12× on the invariants; l10n en/de. Now idle. **This session on the Loop Mixer: §A (sheet-music all tracks), §D-1 (beat-reactive cards), §C-4 (dice) — all shipped.** Next low-collision 3.0: §D-3 step playhead, or §C-2 one-knob master filter.
- **opus (loop-juice)** · ✅ **SHIPPED — Loop Mixer 3.0 §E-1: secret combos** (`e1b75a5`). Exact built-in layer sets unlock a named combo (rhythm section/duo/dreamy/marching/full band) → a reveal snackbar + a star "found N/M" counter; a discovery game over the sandbox. Pure `matchCombo` (loop_secrets.dart, 4 unit tests) checked after toggle/roll; widget test drums+bass→Rhythm Section+1/5; l10n en/de. Now idle.
- **opus (loop-juice)** · ✅ **SHIPPED — Loop Mixer 3.0 §D-3: sweeping progress playhead** (`c088a4f`). Static beat-dots → a smooth head sweeping a bar/beat-ticked lane, filling behind itself (a new `_progress` notifier in the ticker; leaves `_step`/`_BeatPulse` alone). CustomPaint, look verified by capture, full-screen suite exercises it. Now idle.
- **opus (loop-juice)** · ✅ **SHIPPED — Loop Mixer 3.0 §G-3: save slots** (`af38805`). Share sheet gains "Save to my grooves" (name + store the KU1 token) and "My grooves…" (load/delete list), persisted via unit-tested `GrooveSlotsService` (groove_slots.dart). Seams + widget test (save→clear→load restores the band); l10n en/de. **This session shipped §A, §D-1, §C-4, §E-1, §D-3, §G-3.** Now idle.
- **opus (loop-juice)** · ✅ **SHIPPED — Loop Mixer 3.0 §D-2: shape-creatures** (`97d1981`). Each card is a procedurally-drawn creature themed to its instrument (drumhead+sticks / speaker / keyboard / note / star / mic / equalizer), awake+smiling when playing, asleep when off, inheriting the card beat-pulse. New `loop_creatures.dart` (pure `creatureShapeFor` + `LoopCreature` CustomPaint, look verified by capture). Also restored the §E-1 combo widget test (clobbered by a concurrent §B rebase). Now idle. **loop-juice IDLE — this session shipped §A, §D-1, §C-4, §E-1, §D-3, §G-3, §D-2.** §C-1 (TRUE real-time filter sweep) is BLOCKED on an architecture decision: the app has no streaming PCM output (`LoopPlayerService` plays a fixed `BytesSource(wav)`), so real-time DSP needs a streaming-audio backend (a new dependency + platform wiring) — not a clean headless-testable slice. The OFFLINE one-knob filter (§C-2, seam-swap `biquadFx`) is ALREADY SHIPPED by loop-mixer-3efg. Awaiting maintainer call on whether to invest in the streaming backend.
- **opus (loop-juice)** · ✅ **SHIPPED — Loop Mixer 3.0 §C-1b: streaming filter DSP core** (`04185aa`). Pure `lib/core/audio/streaming_filter.dart`: stateful seam-continuous bipolar LP↔HP `StreamingFilter` (own Direct-Form-I RBJ, live-tunable cutoff; carries state across blocks so a sweep never clicks). 5 unit tests vs synth tones (LP/HP attenuation, one-block==two-block to 1e-12, swept-cutoff bounded). Flutter-free, new file — no collision. §C-1a (streaming-audio backend) + §C-1c (FX-strip UI) scoped in the 3.0 §C block, awaiting the maintainer backend commitment. Now idle.
- **opus (loop-juice)** · ✅ **SHIPPED — Loop Mixer 3.0 §C-1a (testable core): streaming mixer + sink** (`88a59e1e`). `lib/core/audio/streaming_mixer.dart`: `StreamingAudioSink` + `BufferedSink` + `StreamingMixer` (loop PCM → live `StreamingFilter` chain → callback-sized blocks, wrapping, seam-continuous). 5 unit tests. The streaming DSP engine is now COMPLETE + tested (filter §C-1b + mixer/sink §C-1a-core); the ONLY remaining piece is the native platform sink (device-only, kept out of pubspec per the AEC rule) that implements `StreamingAudioSink`. Now idle.
- **opus (daw-workshop)** · 🚧 **ACTIVE — the DAW Workshop tool (maintainer vision, 2026-07-18): the "vector, not bitmap" core first.** Worktree `../mus-textbook`, branch `feature/textbook-prose-anavis`. A separate multi-track Workshop DAW that arranges audio from every module (Song Book / Tracker / Score / TAB / DrumKit / direct samples). **Feasibility resolved — the vector-clip model works and is our natural fit:** every module already renders **offline + purely to PCM**, so a clip stores a *reference to its source model* and the mix **rasterises on demand + caches per source** (edit the source → its clip re-renders; everything else served from cache). Caveat: offline render-then-play (no realtime graph), so Play/Export *bakes* — the cache keeps re-bakes cheap. ✅ **Core SHIPPED (pure, 6 tests): `lib/core/audio/daw_timeline.dart`** — `ClipSource` (`render`+`cacheKey`), `SampleSource`, `Clip`/`DawTrack`/`DawTimeline`, `renderTimeline(cache)` (one render per distinct source, sample-accurate placement, clip×track gain, tanh soft-limit). Design + sliced plan in **`docs/DAW_SCOPING.md`**. ✅ **Slice 1 SHIPPED — per-module `ClipSource` adapters (`1128049`, 5 tests): `lib/core/audio/daw_sources.dart`** — `DrumSource(DrumRowsPattern, LoopTiming)` (DrumKit beat, renders via the pattern's own renderer) + `GrooveSource(GrooveSpec)` (Loop Mixer groove, rendered by a fresh `LoopEngine` share-restore path → decoded to PCM). Both delegate to existing offline renderers (**no `loop_engine` change**) and derive a `cacheKey` from the model's value; verified against the REAL renderers (non-silent audio; cacheKey equal/differs; a beat clip lands at its placement). ✅ **Slice 2 SHIPPED — `ScoreSource` (`0648bd3`, 3 tests):** any engraved music (Song Book song / Workshop document / TAB score → a `MultiPartScore` or `Score`) as a clip, rendered **faithfully** (notes→chord segments, rests→silence, all voices 1-4 + parts summed via `renderSegmentsRaw` — unlike `playbackOf` which drops rests + chord tones); + pure `renderScore`/`renderMultiPartScore`; structural (or caller-supplied) cacheKey. **⇒ 5 of 6 module types now covered.** ✅ **Slice 3 SHIPPED — `TrackerSource` (`1105940`, 2 tests):** a `TrackerSong` as a clip (own `renderSongWav` → decoded to mono); cacheKey includes the LIVE `engine.exportCells` (what render syncs in) + all patterns + order + instrument ids + tempo/rows, so an edit invalidates the cache. Also made `ScoreSource`/`TrackerSource` cacheKey **getters** (recompute over the live model, like `DrumSource`) — the vector-invalidation contract. **⇒ THE ADAPTER SET IS COMPLETE — every module type is a DAW clip** (DrumKit/`DrumSource`, Loop Mixer/`GrooveSource`, Song Book+Workshop+TAB/`ScoreSource`, Tracker/`TrackerSource`, samples/`SampleSource`). 16 DAW tests; NO hot-file touch so far. ✅ **Slice 4 SHIPPED — the arrangement surface (`264680c` screen + `e2df72b` entry, 4 tests):** `lib/features/games/composition/daw_screen.dart` "Multitrack" — clips on tracks; **Play BAKES** the whole arrangement (`renderTimeline` + per-source cache) and plays the summed WAV; per-track mute (re-bakes), a clip strip, add-a-beat/add-a-tune seeders (real `DrumSource`+`ScoreSource` clips so it's usable before the bridges), clear. Reached from the **home Workshop dropdown** (piano → value 8, additive; rebased). +4 EN/DE keys; home + DAW tests green. **⇒ THE DAW IS LIVE & USABLE END-TO-END.** ✅ **Slice 5 SHIPPED — shared `DawService` + the first "Send to DAW" bridge (`9794ded`, +2 unit + 1 screen + 1 DrumKit test):** app-wide `DawService` (ChangeNotifier in main's providers) holds the `DawTimeline` + render cache; `addClip(source,{track})` appends + lays clips out in time; `toggleTrackMute`/`clear`/`bake`. `DawScreen` now `context.watch`es the shared service (so it shows clips sent from anywhere), and the **DrumKit gained a "To Multitrack" button** that sends a SNAPSHOT `DrumSource` (deep-copied rows + current tempo/swing, so later edits don't change the sent clip). ✅ **Slice 6 SHIPPED — ALL "Send to DAW" bridges complete (Loop Mixer / Song Book / Workshop / TAB / Tracker):** each module screen gained a "Send to DAW" action (share-sheet / app-bar / ⋮ menu) that builds its `*Source` and calls the shared `sendToMultitrack` helper (`lib/shared/daw/send_to_daw.dart` — `DawService.addClip` + a localized snackbar). Loop Mixer→`GrooveSource(spec)`, Song Book→`ScoreSource.single(score)`, Workshop→`ScoreSource(buildMultiPart())`, TAB→`ScoreSource(band MultiPartScore)`, Tracker→`TrackerSource(song)` (`3246938`). Every bridge has a live widget test (place content → `sendToDaw()` → one clip lands + `bake()` isNotEmpty). **⇒ EVERY MODULE CAN NOW HAND ITS AUDIO TO THE MULTITRACK.** ✅ **Slice 7 SHIPPED — merge + convert (the maintainer's headline verbs; +5 unit + 2 screen tests):** `DawService` gained `freezeClip(track,index)` (**convert**: bake a live "vector" clip's current render and replace its source with a `SampleSource` — the take stops tracking source edits + needs no re-render), `mergeAll()` (**merge** \"one or many, including all\" — flatten every clip into ONE baked take on track 0, preserving relative timing, rendered `limit:false` so the master limiter still applies once at final bake), `mergeTrack(i)`, `removeClip`, `isClipFrozen`. The **Multitrack** screen surfaces them: a **Merge all** button (⧉, enabled ≥2 clips) + each clip is an `InputChip` you tap to **Freeze** (🔒 avatar once baked) or delete to remove; localized snackbars. +4 EN/DE keys. All 14 DAW service+screen tests green; analyze clean. ✅ **Slice 8 SHIPPED — the timeline becomes editable + exportable (+3 unit + 2 screen tests):** clips now draw **to scale** on a shared, horizontally-scrolling timeline (a fixed left gutter of track name+mute; `_pxPerSecond` px/s; each clip's width = its render duration via a cheap `DawService.clipDurationMs` that reads the per-source render cache — warm after any bake). **Drag-in-time:** long-press a clip then drag to reposition (`moveClip`, clamped ≥0; a plain drag over the lane still scrolls it — the standard touch-DAW split that sidesteps the gesture-arena conflict). Tap a clip to freeze, ✕ to remove. **Export:** a ⬇ app-bar action bakes the arrangement and offers **WAV or MP3** via the shared `showAudioExportSheet`. 18 DAW service+screen tests green; analyze clean. **⇒ THE DAW ARC IS COMPLETE — every module renders in, clips arrange/merge/convert on a to-scale draggable timeline, and the whole mix exports.** ✅ **Slice 9 SHIPPED — finishing features (undo/redo `701f75e`, per-clip gain+fades `b04e603`, time ruler + drag-snapping `4daa953`; +13 tests).** **⇒ THE DAW IS FEATURE-COMPLETE for the maintainer's vision.** **daw-workshop IDLE.**
- **opus (smear-capture)** · ✅ **idle / SHIPPED — §F-1 follow-up: smear-pad capture-to-layer (`278fa92f`).** The solo pad records each note with its loop phase; a **Keep** button quantizes the improvisation via `groove_capture.quantizeToGroove` (pentatonic-snapped, octave-centred) and installs it as the sung-voice layer — an improvised lead becomes a real toggleable card. Seams `hasSmearRecording`/`keepSmear` + a timed `debugSmearSample`; +1 EN/DE key. Widget test (timed run → Keep → enabled 'voice' card, pad closes). **⇒ §F-1 is now fully complete (pad + capture).** Loop + smear suites green (34).
- **opus (loop-mixer-3fg)** · ✅ **idle / SHIPPED — Loop Mixer 3.0 §G-1 + §F-1; §C–§G now fully triaged.** ✅ **§G-1 section/scene grid (`3f3fe50`):** `GrooveScene` (enabled+variants snapshot) + engine `captureScene`/`applyScene`; a Sections row of 4 pads (tap=launch, long-press=capture) + a chain toggle that auto-advances captured scenes at each seam into an arranged track. Unit + widget. ✅ **§F-1 scale-locked smear pad (`a2abd1a3`):** `smear_pad.dart` pure `smearMidi(x,{key,minor})` (monotonic, always in-scale, key/scale-transposed) + a `SmearPad` drag widget; a transport toggle shows a 72px pad that plays key-aware music-box blips. Unit + widget (capture-to-layer is a follow-up). **⇒ FINAL §C–§G STATUS — every buildable, non-blocked item is DONE (by me or peers):** ✅ §C-2 filter, §C-3 quantized launch, §C-4 dice, §D-1 beat-reactive cards (pulse wrapper), §D-2 embodied creatures (`loop_creatures.dart`), §D-3 step playhead, §E-1 secret combos, §E-2 challenges, §F-1 smear pad, §G-1 sections, §G-3 save slots. ⏸️ **Only 3 remain, each genuinely blocked (need a device / real-time-DSP / audio-review session, NOT more headless work):** **§C-1** momentary hold-to-apply effect strip (needs the live buffer-swap path the 2.0 spine flagged as "the one real wall"; §C-2's re-rendered filter is its consolation slice), **§F-2** record-your-own-sound→playable part (needs the mic + auto-chop reviewed on-device), **§G-2** record-&-replay a whole performance as an exported arranged track (a large event-timeline + export arch worth doing with audio review). **§B fully complete too.**
- **opus (loop-mixer-3efg)** · ✅ **idle / SHIPPED — Loop Mixer 3.0 §C–§G buildable subset.** ✅ **§C-2 one-knob master filter (`f3dff79`):** offline low-pass↔high-pass mix-bus sweep via `biquadFx`, seam-continuous in the same two-copy buffer as the sends; ephemeral live control (not in the token); a centred Filter slider that snaps to off at the detent. Unit (low-pass darkens / high-pass brightens via zero-crossings; off identical; clamp) + widget. ✅ **§C-3 quantized launch (`463ad76`):** a grid toggle; while playing, toggling a card ARMS it (amber ring) and the next loop seam applies all arms at once; quantize-off drops arms; first card fires immediately. Seams + widget test. ✅ **§E-2 band challenges (`fd7462e`):** `loop_challenges.dart` pure predicates over the enabled set (sparkle/bass/melody/three-layers/full-band); a tappable prompt banner (lightbulb → check + "Nice!"); skip to the next unmet. Unit + widget. **Status of the rest of §C–§G:** ✅ **already shipped by other agents** — §C-4 dice (`Icons.casino` roll), §D-2 embodied characters (`loop_creatures.dart`), §E-1 secret combos (`loop_secrets.dart`), §G-3 save slots (`groove_slots.dart`). ⏸️ **remaining, need audio/art/device/large-arch review** — §C-1 momentary streaming-DSP effect strip (the master filter is its cheap first slice), §D-1/§D-3 richer reactive visuals + step playhead, §F-1 scale-locked smear pad, §F-2 record-your-own-sound→part, §G-1 section/scene grid, §G-2 record-&-replay performance. **⇒ Every testable, non-art/DSP §C–§G item is now done (by me or peers). §B fully complete too.**
- **opus (loop-mixer-3cd)** · ✅ **idle / SHIPPED — Loop Mixer 3.0 §B items 4 + 3 (maintainer: do them all). ⇒ ALL OF §B (items 1–4) IS NOW COMPLETE.** ✅ **Item 4 (`801394f`, +2 tests):** engine `rollVariant(id, rng)` (random in-range variant, guarantees a change when >1); the variant badge long-presses to roll (tap still cycles); +1 extra variant (D) on drums & bass. ✅ **Item 3 — style presets (`59ccafb`, +8 unit + 1 widget test):** `GrooveStyle` = an alternate whole-band pattern set + default tempo/swing/kit/scale bias; `kGrooveStyles` = default (original) + **four** (four-on-the-floor, 120 bpm, deep kit) + **chill/"Lounge"** (laid-back lo-fi, 75 bpm, swung, lofi kit). Engine `styleId`/`style` swaps `_baseTracks` + applies bias + clears caches; enabled/variant/level carry across (same ids). `GrooveSpec.styleId` (token `st`, omitted at 'default' → old `KU1.` decode; unknown → default). `applySpec` selects style FIRST so the explicit saved tempo/kit/etc. override the bias (exact restore). **Every authored pattern is C-pentatonic → any combo × any key/scale stays consonant** (a test pins this across all styles). Style chip row (Classic/Four-on-floor/Lounge) + seams. +8 EN/DE keys total for 3cd. Resolved two rebase collisions with parallel agents' new tests (roll/style + dice + save-slot), kept all, fixed a merged-in lint. **Remaining §B: none — items 1–4 all shipped.** Next open: §C (performance/live FX) … §G (build-a-song), all unclaimed. Content follow-up (optional, needs audio review): author more style presets — pure data in `kGrooveStyles`.
- **opus (loop-mixer-3b)** · ✅ **idle / SHIPPED — Loop Mixer 3.0 §B item 2: swappable drum kits (`b6e79af`, +9 unit + 1 widget test).** `synth.dart` `DrumKit` profile (tune / decay / noise / pitch-sweep depth / lo-fi crush) parameterises `renderDrum` for every voice; `renderDrumPattern` forwards it. **Buffer lengths are kit-independent → the onset grid never moves** (pure timbre). Four kits: clean (original), deep (round electronic), warm (soft), lofi (dusty/crushed). `GrooveSpec.kitId` (token `kt`, omitted at 'clean' so old `KU1.` decode byte-identically; unknown id → clean) + engine `kit`/`kitId` setter (clears render caches), threaded through EVERY drum render path (vamp, tiled, varied, fill). Kit chip row (Clean/Deep/Warm/Lo-fi) in `loop_mixer_screen.dart` re-renders + re-syncs in place; +5 EN/DE keys. Verified: length-invariance across kits; a pattern's hits land at identical samples; lower tune → fewer kick zero-crossings; shorter decay → more late energy; engine swaps kit on loop AND fill; token roundtrip/omit/fallback. Other `renderDrum` callers (DrumKit/beat-capture/tracker) use the default clean kit → unchanged. Resolved a rebase collision with another agent's new "dice roll" test (kept both). **⇒ §B item 2 DONE. Remaining §B (unclaimed): style presets (item 3), more variants + per-card roll (item 4); + §C–§G.**
- **opus (loop-mixer-3)** · ✅ **idle / SHIPPED — Loop Mixer 3.0 §B item 1: key & scale (maintainer's chosen lead), engine + UI complete.** ✅ **Engine (`897b246`, +10 tests, `loop_engine.dart`):** `GrooveSpec.key` (0–11) + `scale` (major/minor pentatonic); backward-compatible token (`k`/`sc` omitted at defaults so old `KU1.` decode byte-identically; hostile key wrapped to 0–11); `pitchTranspose = key + (minor?3:0)`; a `transpose` param (default 0) threaded through `renderCells`/`LoopPattern.render` + every pitched render path; `engravedCellsFor` (transposed cells for engraving/jam/export); `jamFit` scale+chord sets shifted by the root. Minor borrows the relative-major set (+3) so any key×scale is a RIGID transposition → stays consonant. Verified with a real detector (renderCells C4→F4), a rigid-transposition invariant over every key×scale×track, token roundtrip/backward-compat. ✅ **UI (`6403cfb`, +1 widget test):** two chip rows under the harmony lane — Key (C…B) + Scale (Major/Minor) — bound to `engine.key`/`engine.scale` via `_setKey`/`_setScale` (re-render + re-sync in place, loop length unchanged); the follow-along target + Song-Book export now read `engravedCellsFor`; score-panel engraving already did (loop-sheet-fix `86c0930`). +4 EN/DE keys. Disambiguated the pre-existing variant-badge test (A/B/C badge finders scoped to `CircleAvatar`). Full loop-mixer suite green; analyze clean. **⇒ §B item 1 DONE. Remaining §B (unclaimed): swappable drum kits (item 2), style presets (item 3), more variants + per-card roll (item 4); + §C–§G.**

- **opus (looper-core)** · ✅ **idle / SHIPPED — roadmap item 4 "a much better Looper": the pure core (`06b1849`).** `lib/core/audio/loop_record.dart` (pure, 9 tests): `quantizeLoopBars` (snap a take to a whole number of bars → **seamless loop lengths**), `snapPunch` (snap a raw record window to bar boundaries → **quantised punch-in/out**), and a generic `LoopStack<T>` overdub layer stack (add · **undo/redo** with add-clears-redo · per-layer mute → `activeLayers` vs `layers`). NO hot-file touch. **Remaining item 4:** a surface — the natural application is turning the DrumKit's record into a **layered overdub looper** (each take a `LoopStack` layer: record→layer, undo removes a take, mute silences one, playback sums `activeLayers`) — a real refactor of the DrumKit's single-pattern model, so a claimed slice of its own; or wiring the quantisers into the Loop Mixer.

- **opus (ci-fixes)** · ✅ **idle / SHIPPED — GitHub Actions health.** CI-infra only (no product hot files). ✅ **Deploy fixed** (`27f928a`): Vercel free tier caps prod deploys at 100/day; the old `workflow_run: [CI]` trigger fired on every green CI (>100/day under heavy multi-agent pushes → `api-deployments-free-per-day`). Switched to an **hourly `schedule` + `workflow_dispatch`** (≤24/day, 4× under cap). Residual quota reds self-heal as the pre-change backlog ages out of the rolling 24h window. ✅ **aec-native** confirmed green (my earlier DTD-deadlock C fix passed CI). ✅ **ios-release** confirmed green (pub-get sibling-checkout fix held; all signing secrets present). ✅ **App Store screenshots GREEN** — the 60-min iPhone-Capture hangs were on older code; current main captures in ~20min. Added a **per-step wall-clock timeout** as a safety net (`2e3605b`) that names any future hang (`SHOT_STEP_TIMEOUT`). One real gap found + fixed (`6472679`): the Workshop step's bare `find.byIcon(Icons.piano)` was ambiguous on the wider iPad layout (game cards also show a piano) → iPad missed `03_workshop`; scoped the tap to the AppBar's single piano. **Verified GREEN — full 5+5 set captured (both `*_03_workshop.png` present, no skips/timeouts).** Files: `.github/workflows/deploy.yml`, `integration_test/screenshots_test.dart`, `lib/core/services/tts_service.dart`. ✅ **BONUS — fixed the pre-existing `crisp_notation` GPIF meter bug** the libraries-and-tab agent flagged as unclaimed (**`crisp_notation@5bfb0b3`**, public main): the master-bar writer re-stamped the *initial* meter on every bar without an explicit `timeChange`, so a mid-score `4/4→3/4→3/4` read back a spurious `3/4→4/4`. Now tracks a running meter — byte-preserving (the single-track golden is unaffected). The long-failing `gpif_test: a mid-score time-signature change round-trips` passes; 22 gpif + 1537 core tests green. ✅ **BONUS 2 — fixed an ABC mid-score clef-change round-trip bug** found by a targeted codec sweep (**`crisp_notation@a08089d`**, public main): the ABC writer emitted mid-tune key/meter changes but **never a clef change**, so a switch to bass mid-piece was silently dropped (the reader already parsed `[K:… clef=…]`). Writer now emits the clef (header + mid-tune, always re-stating the running key so the reader has a tonic to anchor `clef=`); reader now recognizes `clef=treble` (a change *back* to treble) and only records a key change when the key actually differs. MusicXML/MEI/kern already round-tripped clef+key changes — ABC was the sole gap. +3 regression tests; 1540 core green. ✅ **BONUS 3 — fixed ABC dropping grace notes from any id-less note** (**`crisp_notation@7c4f054`**, public main): the writer gated `{…}` grace output on `id != null` (copied from the adjacent id-keyed chord-symbol/dynamics branches), but grace notes live on the NoteElement itself (like articulations/ornaments, which aren't gated) — so a note without an id silently lost its grace, though the reader parses `{…}` positionally and MusicXML round-trips the same note fine. Dropped the id gate; +1 regression test (id-less/id-bearing × both grace styles); 1541 core green. **These 3 codec fixes came from a systematic write→read self-round-trip sweep (meter/clef/key/articulation/ornament/grace/tie × MusicXML/MEI/kern/ABC); the remaining probed attributes all round-trip cleanly.** ✅ **BONUS 4 — a permanent round-trip regression matrix** (**`crisp_notation@e8314a1`**, public main): new `test/roundtrip_features_test.dart` — **100 generated cases** pinning every musical marking (meter/clef/key changes, 5 articulations, 3 ornaments, grace, tie, slur, dynamics, tuplet, chord, double-dot, repeats, volta, navigation, voice 2, lyrics, tremolo) through write→read on all 4 codecs. Each feature declares which codecs legitimately drop it (`droppedBy`): supported cells are regression locks; dropped cells are explicit expectations that fail loudly if support is later added. Complements `roundtrip_property_test.dart` (note *content*) by locking the *markings*. 1641 core tests green. **Documented codec gaps surfaced (unclaimed follow-ups, real library features not one-liners):** neither MEI nor kern carry **dynamics / repeats / voltas / navigation / lyrics**; ABC/MEI/kern don't emit **tremolo**. MusicXML carries everything. ✅ **BONUS 5 — fixed the MEI ornament gap** (**`crisp_notation@d688a43`**, public main): MEI ornaments are `<trill>`/`<mordent>`/`<turn>` control events anchored by `startid`, and the writer emitted them only for a note with an xml:id — so an ornamented **id-less** note lost its ornament (same class as the ABC grace drop); it also only scanned voices 1–2. Now an ornamented id-less note gets a deterministic position-derived id (`o<measure>_<voice>_<index>`, unique so no collision) stamped on both the `<note>` and its control event, across all 4 voices. Flips the matrix's 3 ornament×MEI cells to preserved; +1 mei_test; 1642 core green. **So all three interchange formats now round-trip ornaments; MEI's remaining gaps (dynamics/repeats/voltas/navigation/lyrics) are larger features.**

- **opus (rhythm-quantise)** · ✅ **idle / SHIPPED — the beginner rhythm "Relevanzschwelle" engine (roadmap step 2 DONE; `04fc357`).** New **pure, Flutter-free** `lib/core/audio/rhythm_quantize.dart`: `detectOnsets(energy frames)` (rms floor + rise factor + refractory, strength = attack peak; mirrors `beat_capture`'s rule but generic) → `chooseResolution` **auto-picks the coarsest grid the player can actually feel** (finest needed within tolerance, no two onsets colliding, never finer than a **skill `cap`** of `RhythmResolution` quarter/eighth/tripletEighth/sixteenth — so loose 1/8 settles on 1/8, and a beginner cap collapses stray 1/16 flams) → `quantizeRhythm` drops sub-strength noise, snaps, and collapses same-step hits (strongest kept) → `{resolution, hits[step, snappedMs, originalMs]}`. 15 tests (subdivision maths, auto-picker across all four grids + loose-feel + cap + single-onset, snap/collapse/strength-filter, onset detection, detect→quantise end-to-end); analyze clean. NO hot-file touch; complements the fixed-grid `beat_capture.quantizeToBeat`. **This is the shared front-end for the rest of the roadmap** (DrumKit record → model conversion → Looper). Recorded in HISTORY. ✅ **Roadmap step 3 CORE also SHIPPED (`994f5b2`): `lib/core/audio/rhythm_convert.dart`** — `beatOfHit`/`hitToStep` (a hit's musical position is grid-independent, so it re-places onto any subdivision) + `toTrackerColumn` (→ a Tracker channel, which already exports Score/MusicXML/MIDI/module + Song Book) + `toDrumPattern` (→ a Loop Mixer `DrumRowsPattern`). Per-hit pitch/drum are caller-supplied. 7 tests. So a recorded rhythm now converts to the grid models and reaches every notation/export path via existing bridges. ✅ **Roadmap item 1 (record UI) also SHIPPED (`cb1ba49`): DrumKit tap-to-record** — a Record button captures pad taps at their loop position, on stop quantises the take onto the step grid (`quantizeToResolution(eighth)` → `toDrumPattern`, overdub) and adds the fixed-grid `quantizeToResolution` to the engine. Device-free, `debugRecordTaps` seam, +3 tests. **Remaining roadmap: item 1 polish (mic beatbox record · Save-to-Song-Book from the DrumKit · skill-tier setting · more voices) + item 4 (Looper).**

- **opus (spot-the-parallels)** · ✅ **idle / SHIPPED — new voice-leading minigame (`63fcd17`).** "Spot the Parallels": a two-chord SATB progression is engraved on a grand staff; tap **Clean** or **Parallels!**. The answer key is the library's `checkVoiceLeading` (parallel 5ths/8ves) — the engine is **ground truth**, so the 9 authored templates (4 clean + 5 parallel-only) are verified-correct in the test and transposed for variety (parallels are interval-invariant, so the label survives transposition). Correct answers play the chord pair so you HEAR the motion; SRI under `harmony.parallels.<template>`. New `lib/features/games/harmony/spot_parallels_screen.dart` (screen + pure `ParallelsTemplate`/`buildRound` generator) + a `GameInfo` under 'harmony' + `kStarThresholds['spot_parallels']` + a new **g9-10 `voice_leading` curriculum concept** (so the coverage audit places it) + 6 tests (template-labels-vs-library, parallel-only crispness, transposition invariance, widget render+SRI). Curriculum/consistency/layout audits green; whole-project analyze clean. Top of the harmony ladder — the app's first part-writing drill.

- **opus (anavis-intelligence)** · ✅ **idle / SHIPPED — intelligent AnaVis everywhere (a real analysis engine, not hand-authored).** Turning AnaVis into an engine that reads ANY score and annotates it, adaptive for kids ↔ experts. ✅ **Slice 1 SHIPPED — the brain, IN THE LIBRARY** (`crisp_notation@8502508`, pushed to public main; `../crisp_notation` fast-forwarded). New `crisp_notation_core/src/theory/analysis.dart`: `analyze(Score,{Key?}) → ScoreAnalysis{key, segments, cadences}`. Slices the score into vertical sonorities across all 4 voices → `identifyChord` → `romanNumeralFor` in the detected key (`keyOf`) → **T/S/D function** (`functionOf`, secondaries=dominant); flags **non-chord tones** (remove-one-and-reidentify → recovers suspensions/passing tones); reads an **implied chord** from a purely melodic/arpeggiated bar; **merges** repeated chords; detects **cadences** (authentic/half/plagal/deceptive). 8 library tests. Phrase/form detection deliberately deferred. ✅ **Slice 2 SHIPPED — the computed view** (`6f1b05b`). `lib/features/games/composition/score_analysis_view.dart`: `ScoreAnalysisView` feeds a real `Score` through `analyze()` and renders key chip + engraved staff + **function-coloured chord blocks** (tap to hear) + **roman numerals** + **cadence markers** + legend, with an **`AnalysisDepth` dial (kids/learner/expert)** — kids=colours only, learner=+romans/cadences, expert=+chord symbols. Wired a "Read from the notes (auto-analysis)" section into `AnalysisHubScreen` (`kAnalysisExamples`). +11 EN/DE keys; 19 app tests. ✅ **Library follow-up (`crisp_notation@8646658`): `HarmonicSegment.elementIds`** — analyze() now returns the NoteElement ids per segment, so a consumer can colour/highlight the notes of a chord. ✅ **Slice 3 SHIPPED — the Workshop "Analysis" toggle** (`afaf7c5`, the killer feature). An **Analysis** item in the Workshop overflow menu runs `analyze(_doc.buildScore())` live and (a) **tints every note by harmonic function** (green/blue/orange) via the existing `elementColors` seam (base layer; selection amber + playback green still override), using the new segment `elementIds`; (b) shows a **compact banner** above the score — detected key + roman progression + cadences. Additive + guarded by `_showAnalysis` (default off), auto-detects the key. Rebased cleanly onto the `libraries-and-tab` agent's concurrent Workshop edits. +1 ARB key; 64 workshop tests. ✅ **Slice 5 (part 1) SHIPPED — Song Book host** (`9f6cba6`). The song player gained an **"Analyse the harmony"** action → the computed `ScoreAnalysisView` over the song's real `Score`, so any built-in public-domain song OR imported/user song is readable for key + romans + function colours + cadences at the kids/learner/expert depth. Pure reuse + `_SongAnalysisScreen` host + 1 ARB key + test. ✅ **Slice 6 SHIPPED — the expert layer** (`01146bf`). `ScoreAnalysisView` grows over the same analysis: a **tension curve** (learner+, a sparkline tonic-low→dominant-high so you SEE the home→away→tension→home arc, `_TensionPainter`); a **voice-leading check** (expert — feeds the chord segments top-voice→bass to the library's `checkVoiceLeading`, flags parallel 5ths/8ves or "clean ✓", only for a ≥3-voice texture); and a **non-chord-tone list** (expert). +6 EN/DE keys; 5 tests. ✅ **Slice 5b SHIPPED — Loop Mixer host** (`0f2b4f1`). Selecting a song progression now shows a strip under the harmony chips with its chords **coloured by function** (I/IV/V/vi → tonic/subdominant/dominant) + roman labels, so the kid sees the home→away→tension→home shape of the vamp. Made the colour helper public (`harmonicFunctionColor`). ✅ **Slice 4 SHIPPED — computed form** (library `crisp_notation@b575a9b` `detectForm()` + app `dc412fe`). `detectForm(Score)` fingerprints each measure's top-voice melody transpose-invariantly → letters A/B/C (same letter = the tune came back) → merged sections. `ScoreAnalysisView` gained a **Form row** (coloured sections, widths ∝ measure count) shown only when the piece repeats material, so through-composed pieces stay quiet. Completes the "AnaVis" name (visualising form). +1 key; 3 library + 1 app test. **THE ANAVIS EFFORT IS COMPLETE:** engine (`analyze` harmony + `detectForm` form + `elementIds`) across FIVE surfaces — the hub, the computed view, the Workshop (live note-tint + banner), the Song Book, the Loop Mixer — with a kids↔learner↔expert dial (colours → romans/cadences/tension-curve → chord-symbols/voice-leading/NCTs). ✅ **Flourishes SHIPPED:** a **circle-of-fifths key wheel** in the expert layer (`cdf1000`, `_KeyWheelPainter`, key highlighted, minor→relative-major position); and **phrase-level form grouping** (`crisp_notation@e859e57`) — `detectForm` now tries phrase lengths and picks the one exposing the most repetition, so a recurring 4-bar phrase reads as ONE section (a real A-B-A, not A-B-C-D-A-B), falling back to bar-level; the app form row upgrades automatically (no app change). **Remaining (deep-expert only, if ever wanted):** figured-bass display; pc-set/Forte labels (library `set_theory` already has them); modulation regions on the wheel (library `localKeys`); memoize `analyze()` in the Workshop if a big score ever lags. **AnaVis went from hand-authored examples to a real engine that reads the music, from pre-reader colours to expert voice-leading.** **Perf note:** analyze() runs per-rebuild while the toggle is on — fine for bounded scores; memoize on doc-change if it ever lags. Worktree `../mus-textbook`, branch `feature/textbook-prose-anavis`; engine in the shared `../crisp_notation` clone.

- **opus (inspect / looking-glass)** · ✅ **idle / SHIPPED — 🔍 Looking Glass EVERYWHERE (all surfaces + all hover spots + the composition sandboxes).** The "do it all" pass is done. ✅ **Multi-part full-score canvas hover** (`2ca6b0b`) — `MultiPartCanvas` gained `onElementHover(globalId?)` resolving the note inside its own scroll space; the card pins to a fixed corner (the canvas scrolls). ✅ **Tracker grid hover** (`8a5e947`) — per-cell `MouseRegion` → the note + row-chord in a corner card; leaving the grid clears it. ✅ **Tab grid hover** (`5c40199`) — per-cell hover → fretted note + column chord in a corner card. ✅ **Games** (`012802b`) — the toggle on the two composition SANDBOXES (My Melody, Melody Doodle: tap a note → its card; My Melody also suppresses placement on that tap). **Deliberately NOT on quiz games** (Roman Numerals, Function/Chord/Cadence quizzes, note-reading drills) — the card would reveal the answer; Inspect belongs on editing/reading/sandbox surfaces, not the challenge. (StaffView has no region controller, so the sandboxes are tap-only; hover lives on the score-views + editor grids.) Every touched suite green; analyze clean. **NOW TRULY COMPLETE.** Was: Worktree `../mus-textbook`, branch `feature/textbook-prose-anavis`. A toggle-activated "Looking Glass": flip it on, tap a note/cell, and a card tells you what it is — note name(s), scale degree in the key, chord symbol + roman numeral + T/S/D function + non-chord-tone status — all computed from the shared `analyze()` engine (no hand-authoring). UX decision: an **icon toggle**, not bare long-press/double-press (avoids gesture conflicts, discoverable). Reusable core is **`lib/features/games/composition/music_inspect.dart`** (`InspectInfo` + `inspectElement(score,id,analysis)` + `showInspect()` bottom sheet; the chord row shows even without a key, plus a free `detail` line). ✅ **Slice 1 — Song Book** (`5dcf492`; 🔍 app-bar toggle; tap a note → card, else play). ✅ **Slice 2 — Composition Workshop** (`c79796d`; 🔍 in the ⋮ menu; resolves single-part local ids AND full-score `p<part>:<rawId>` globals). ✅ **Drag-safety** (`28dfec5`) — in the Workshop placed notes are draggable, so all six drag handlers early-return in Inspect mode (a poke must never nudge a note — per the maintainer's call). ✅ **Slice 3 — Advanced Tracker** (`ed30fe6`; 🔍 app-bar toggle; a cell reports its note + the CHORD the whole row sounds via the new **library `Pitch.fromMidi`** `crisp_notation@09d9ab3` → `chordSymbolFor` + its instrument/effect). ✅ **Slice 4 — Tab Workshop** (`4adf7b3`; 🔍 app-bar toggle; a string×fret cell → fretted note + column chord + string/fret/diagram-name; capo is display-only so it reads the sounding pitch playback does). Rebased cleanly onto the `libraries-and-tab` agent's tree (no collision). ✅ **Slice 5 — desktop HOVER** (`63cad36` Workshop, `7b4623f` Song Book) — the original "mouse on hover" ask: with Inspect on, sweeping the mouse over the score raises a small **floating card** describing the note under the cursor (a true looking glass). A `MouseRegion` resolves the element via the existing `ElementRegionController.elementIdsIn`, re-running `analyze()` only when the hovered element changes (cheap pixel sweep); the card is `IgnorePointer` so it never steals the hover; **no-op on touch** (tap still opens the full sheet). Refactored the card body into a shared `music_inspect.inspectBody()` used by both the tap sheet and the hover overlay. Each slice unit-tested (incl. drag-suppression + hover-shows/clears seams); every app suite green (Song Book, 66 Workshop, 45 Tracker, 20 Tab); analyze clean. **THE INSPECT EFFORT IS COMPLETE** — one reusable core, four surfaces + desktop hover on both score views, kids-to-expert depth (note name → degree → chord/roman/function/NCT). **Remaining (optional, if ever wanted):** hover on the multi-part full-score canvas + the Tab/Tracker grids; the same card on games.

- **opus (libraries-and-tab)** · 🚧 **ACTIVE — SCOPING (design doc only, no product code yet).** Worktree `../mus-libraries`, branch `feature/score-libraries-and-tab`. Two new features scoped in **`docs/LIBRARIES_AND_TAB_SCOPING.md`** (with a cited licensing survey): **(A) connections to free score/tab/module libraries** — a license-clean fetch→gate→provenance→Song-Book pipeline reusing the existing readers; connect-first sources are **OpenScore (CC0)**, Mutopia, Wikimedia Commons (SAFE), then thesession/ModArchive/CPDL/IMSLP (per-item license-filtered); a `LicensePolicy` gate blocks anything non-permissive; the **"ask for a coffee"** hook is designed in as a config-gated external donation link that **never gates content**, so it needs zero later app change. **DO NOT connect:** general musescore.com uploads, Ultimate Guitar, mySongBook. **(B) a guitar-tab editor as a Workshop mode** — `crisp_notation` ALREADY ships the whole tab+GP stack (`TabStaffView`/`FretboardView`/`NotationTabView`, `Tuning` presets, `TabVoicing` string-pinning, GP read+write, ASCII-tab read); the app never wired it, so this is an input-surface + wiring job over the same `MultiPartDocument` (recommend a sibling `tab_workshop_screen.dart` bridged like the Tracker). ⚠️ **Feature B will touch HOT shared files** (`composition_workshop_screen.dart` `kExportFormats`+`initialScore` bridge, `home_screen.dart` dropdown, `game_registry.dart`, ARBs) — will re-claim + rebase before editing them; Feature A is mostly disjoint (new `lib/features/library/`, a `provenance` field on `ImportedSong`, `http` in pubspec). ✅ **B0 SHIPPED — read-only Tab Workshop.** New `lib/features/games/composition/tab_workshop_screen.dart`: renders any `Score` as tablature (`NotationTabView`/`TabStaffView`) for a chosen tuning (11 presets) + capo + a standard-notation toggle, opens GP/`.gpx`/MusicXML/`.mxl`/MIDI/ABC files (own `parseTabFile`, separate from the Workshop's `importScore`), and ships a built-in ASCII-tab demo riff. Reached from the **home Workshop dropdown** (piano → "Guitar Tab", value 2). So the `.gp` files the app already imported now DISPLAY as tab. Touched shared `home_screen.dart` (additive dropdown case) + ARBs (8 EN/DE keys) — rebased. `TabWorkshopTester` seam; 7 tests green (parseTabFile pure + widget/controls/file-open/error); analyze clean. ✅ **A0 SHIPPED — OpenScore (CC0) connector pipeline.** New `lib/features/library/`: **`LicensePolicy`** (the compliance gate — classifies declared-license text, allows only PD/CC0/CC-BY/CC-BY-SA, hard-blocks NC/ND/ARR/unknown *before* any fetch, emits the attribution line), **`ContentSource`**/`LibraryItem` (injectable `HttpGet` seam), **`OpenScoreSource`** (browses the OpenScore/Lieder **GitHub** mirror — never musescore.com — parses `scores/<composer>/<set>/<title>/lc<id>.mxl`, raw-URL download), **`importLibraryItem`** pipeline (gate→fetch→decode→validate-parse→`ImportedSong`), **`library_browser_screen`** (search + import, reached from the Import screen's 🌐 action) + **`attribution_screen`** ("Sources & credits", url_launcher). `ImportedSong` gained additive `attribution`/`sourceUrl` (backward-compatible JSON). `http` dep added. **Live-verified end-to-end:** browsed OpenScore, downloaded a real Schubert `.mxl` (13.5 KB), parsed 50 measures, CC0 provenance intact. 11 tests (license-gate classify/block-before-fetch + OpenScore path parse + pipeline + browser widget). Touched shared `import_screen.dart` (additive action) + `user_songs_service.dart` (additive fields) + ARBs (14 EN/DE) — rebased. Coffee hook still just a design constraint (content stays ungated); the `DonationConfig` tile is a later flip. ✅ **B1 SHIPPED — the Tab Workshop is now an EDITOR.** New Flutter-free **`tab_document.dart`** (`TabDocument` = tuning + columns of string→fret; `toScore()` engraves with **`TabVoicing`** pinning the user's explicit string choice; `fromScore()` makes any imported score editable as tab; `toPlaybackEvents()` for audio). The screen gained: a **string×step grid** (tap a cell), a **0–12 fret keypad**, a **duration palette** (𝅝/𝅗𝅥/♩/♪ + dotted), **add/remove step**, **keyboard input** (digits + arrows + backspace via a `Focus`), and **Play** (`AudioService.playTimedChords`). Import now loads a file as an EDITABLE tab (`fromScore`, lowest-fret placement). Distinct column icons (`playlist_add/remove`) so they don't clash with the capo ±. `TabWorkshopTester` extended (select/enterFret/delete/add/remove/fretAt). 20 tests (10 model: fret→pitch, string-pinning, chord order, rest, playback ms, insert/remove floor, fromScore; 10 widget/pure). analyze clean. SCREEN-ONLY + new model file — no hot-file edits this slice. ✅ **B3 SHIPPED — Guitar Pro EXPORT + playback fret-highlighting.** The tab editor's overflow now **exports** the authored tab (`_doc.toScore()`) to **Guitar Pro `.gp`** (`scoreToGpif`→`writeGpFromGpif`), **MusicXML** (`scoreToMusicXml`) and **MIDI** (`scoreToMidi`) via `getSaveLocation`/`XFile.saveTo`. **Play now lights the sounding column** — a `Ticker` (created in `initState`, per the deactivated-ancestor gotcha) walks the `toPlaybackEvents` timeline and feeds `TabStaffView`/`NotationTabView` `highlightedIds` (`t$col`); Play toggles to Stop and clears the highlight at the end. 2 new tests (GP export round-trips: my score → `.gp` PK-zip → re-read recovers the 2 notes; play lights `t0` then stops) → **24 tab tests + 11 model tests**. analyze clean. SCREEN-ONLY (+ the model unchanged). So the tab feature now round-trips to Guitar Pro and plays with visible progress. ✅ **B2 SHIPPED — playing techniques.** `TabColumn` gained a `Set<TabTechnique>` (**hammer-on/pull-off, slide, bend, dead, ghost, harmonic**); `toScore()` emits the matching noteId-keyed `Score` lists the tab engine already draws — `Bend`, `TabSlide(SlideInOut.outUpward)`, `TabNoteMark(TabNoteStyle.dead/ghost/harmonic)`, and a legato **`Slur`** from the note to the next sounding column for hammer/pull. A **technique chip row** (FilterChips) toggles them on the selected note; `TabWorkshopTester` gained `toggleTechnique`/`techniquesAt`. 3 tests (techniques→correct Score lists incl. the hammer slur target, toggle add/remove, chip widget) → **27 tab tests + 13 model tests**. analyze clean; SCREEN + model only. ⏭ **Chord diagrams deferred** (the library's `ChordDiagram` isn't wired into the tab-staff layout — would need a standalone inline widget). ✅ **A1 + A5 SHIPPED — 2nd CC0 source + the coffee tile.** **A1:** generalized `OpenScoreSource` to config-driven (repo/branch/ext/format + variable-depth path parse) and added **OpenScore String Quartets** (CC0, `.mscx`) as a **second source** — the browser now shows a **source picker** (dropdown). The import pipeline gained **`.mscx` + MIDI decode** (`scoreFromMscx`/`scoreFromMidi` → `scoreToMusicXml`). **Live-verified:** browsed the quartets (real Beethoven, CC0), downloaded the Grosse Fuge `.mscx` (10.6 MB) and decoded 742 measures. (Fixed a name-flip bug — the surname/given swap must apply to composer folders only, not titles like "String Quartet, Op. 89".) **A5:** new `donation.dart` `DonationConfig{enabled:false,url}` + a **"Support the developer"** tile in the Sources & credits screen — **off by default**, config-gated, external-browser link that gates NOTHING (the coffee hook, now concretely wired; turning it on is a one-line change). 5 new tests (quartets parse + ext-filtered tree + mscx/MIDI decode + donation off-by-default + tile hidden/shown) → 16 connector tests. Mutopia/CPDL deferred (need per-file `.ly`/edition license discovery — heavier than OpenScore's uniform CC0). Touched shared `import_screen.dart`(already)/ARBs — additive. ✅ **A1b SHIPPED — Wikimedia Commons source.** New `commons_source.dart`: browses Commons **MIDI** files via the **open MediaWiki API** (no key; `generator=search&filemime:audio/midi` + `prop=imageinfo|extmetadata` for URL + per-file license + artist), a **third source** in the picker. This is the first source with **varying per-file licenses**, so `browse()` **pre-filters via `LicensePolicy`** — the gate finally does real work (drops NC/ND/ARR/unknown). **Live-verified:** 20 permissive "bach" MIDI matches (PD + CC BY-SA, NC filtered out), downloaded a MIDI and decoded 41 measures. HTML-stripped artist, `File:`/`.mid` trimmed titles, `origin=*` for web CORS. 2 fixture tests (parse title/license/composer + gate drops NC) → 18 connector tests; analyze clean; disjoint new file + 1-line registry add. ✅ **B4 SHIPPED — tab chord diagrams.** `crisp_notation` ships the `ChordDiagram` MODEL but no standard-guitar presets and no render widget, so both are app-side: new **`tab_chords.dart`** = 12 open-position guitar presets (C/G/D/A/E/Am/Em/Dm/F/A7/E7/D7, frets in tuning order) + a **`ChordDiagramView`** CustomPaint (nut/dots/o-× markers/name). `TabColumn` gained an optional `chord` (carried through every edit + insert/remove; display-only, not in `toScore`/GP export). The editor got a **chord-name header row** aligned above the grid columns + an **"Add chord"** button opening a **picker sheet** of the diagrams (tap to attach, or clear). `TabWorkshopTester` gained `setChordByName`/`chordNameAt`. 5 tests (presets 6-string+named, setChord survives edits+insert, chord ignored by toScore, attach/clear widget, ChordDiagramView paints) → **29 tab tests + 16 model tests**. analyze clean; SCREEN + new widget/model only. ✅ **B5 SHIPPED — Save to Song Book + tempo.** The tab editor now **persists into the app** (not just export-to-file): a 🔖 action prompts for a title and stores `scoreToMusicXml(_doc.toScore())` via `UserSongsService.addSong`, so an authored tab lands in the Song Book like any other song (mirrors the Tracker's Save-to-Song-Book). Added a **tempo/BPM stepper** (40–240, default 120) feeding `toPlaybackEvents(bpm:)` — playback is no longer pinned to 120. Tempo uses `*_circle_outline` icons so it doesn't collide with the capo's ±. 2 tests (save stores a `<score-partwise` song with the right title; bpm default) → **31 tab tests + 16 model tests**. analyze clean; SCREEN-only (reads `UserSongsService` via Provider, no service change). ✅ **B6 SHIPPED — multi-track "band" view (the last big tab item).** The editor now holds **`List<TabTrack>`** (each track = its own named `TabDocument` **with its own tuning**, so a bass track sits beside a guitar track); `_doc` became the active track's, so every existing edit path works unchanged. New **track strip** (ChoiceChips to switch + add/remove, never below one track). **Band playback:** new pure **`mergePlaybackEvents`** slices all tracks' `(midis, ms)` timelines at every boundary and unions the sounding pitches, so `playTimedChords` plays the whole band together (tracks may differ in rhythm/length — it runs to the longest); the fret **highlight still follows the ACTIVE track** (that's what the preview shows). **Save/export are multi-part aware** — >1 track writes `multiPartToMusicXml(MultiPartScore([...]))` (GP export stays single-track, the library's gpif writer takes one Score). 6 tests (merge: shared slice / differing rhythms / longest-track+rest / single-track passthrough; tracks add-switch-edit-independently-remove; two-track save emits 2 `<score-part`) → **37 tab tests + 22 model tests**. analyze clean; SCREEN + model only. ✅ **B7 SHIPPED — live-mic fret capture ("play it in").** Exploits the already-shipped mic pipeline: new Flutter-free **`tab_mic_capture.dart`** `TabMicCapture` consumes `PitchReading`s and commits a `(string, fret)` via `tuning.fretFor` only after N consecutive frames agree past clarity/RMS gates (rejects attack/decay noise); a **held note commits once** and **silence re-arms** (same note twice with a gap = two placements); pitches unreachable on the tuning are dropped. Wired behind a 🎤 toolbar toggle (`MicrophonePitchService`, permission-checked, sub cancelled + service disposed on dispose): each committed note lands at the cursor and **advances it**, so playing a phrase writes it across the grid. 8 tests — 7 pure (commit threshold, held-once, silence re-arm, unstable stream, clarity/level gates, unreachable pitch, reset) + a widget test driving 3 synthetic low-E frames through a `debugFeedReading` seam onto string 5 / fret 0. ⚠️ **The pure logic + wiring are tested, but the actual plugin capture is NOT hardware-verified** (headless); validate on a real device (or `bin/listen.dart`) before relying on it. ✅ **MULTI-TRACK GP EXPORT SHIPPED — unblocked by a LIBRARY change.** New **`multiPartToGpif(MultiPartScore, {tunings, names})`** in `crisp_notation` (**pushed: `crisp_notation@bc2f8c9`**, `477d641..bc2f8c9`): the GPIF writer was refactored to a shared `_writeGpif(parts, tunings, names)` core emitting **one `<Track>` per part with its own tuning** (GPIF master bars are document-global and list one Bar id per track, so bar/voice/beat ids stay global and rhythms de-dup across tracks); `scoreToGpif` is now the 1-part case with **byte-identical output verified** (diffed pre/post for plain, alt-tuning and full-technique scores; locked by a golden test) + 7 new library tests. Wired into the tab editor: a band exports one GP Track per tab track. **NB — correcting an earlier note: tab TECHNIQUES already survive GP export** (the writer emits bends/bend-contours, hammer-on/pull-off, slides, vibrato and dead/ghost/harmonic as GPIF note properties); only chord diagrams don't. +1 app test (2 `<Track>`s, each carrying its own tuning; valid `.gp` zip). ⚠️ **Pre-existing library bug found + flagged, NOT fixed** (unrelated to this work, and fixing it would change `scoreToGpif` bytes): `gpif_test.dart: a mid-score time-signature change round-trips` fails — the writer stamps `score.timeSignature` on every master bar lacking a `timeChange`, so a 4/4→3/4 change reads back a spurious 3/4→4/4. **Verified pre-existing by running the test at parent `477d641` in an isolated worktree — identical failure.** Whoever owns the gpif meter path should track a running meter in the master-bar loop. Library caveats: one voice per bar per track; meter comes from part 0; short parts padded with empty bars; notes unreachable on a track's tuning are dropped. ✅ **GAP-FILL SHIPPED (per maintainer directive "restrict to totally free assets, CC0").** **(1) `LicensePolicy` default is now CC0/PD ONLY** — `LicenseKind.isUnconditional` (CC0/PD) vs `needsAttribution` (CC-BY/BY-SA); default `LicensePolicy()` admits only unconditional, `LicensePolicy(allowAttributionLicenses:true)` opts into CC-BY/BY-SA (⚠ CC-BY-SA in an EDITOR = derivative-must-share risk; GPL always excluded — copyleft + App-Store conflict). Commons browse now surfaces CC0/PD only by default. **(2) Fixed a real technique-export gap in my own B2 work:** `slide` emitted `TabSlide` (a flick) which the GPIF writer does NOT read → slides rendered but never reached `.gp`. Now `slide` emits a **`Glissando`** to the next note (both rendered AND exported), and I **added `vibrato`** (`Vibrato`, also both). So ALL techniques (hammer/slide/bend/vibrato/dead/ghost/harmonic) now render on screen AND survive a Guitar Pro round-trip. +test asserting the `.gp` re-read recovers the notes + carries `Slide`/`Bended` properties. Tests updated for the CC0-default (default→CC0-only; opt-in→+BY-SA, never NC); 58 connector+tab tests green; analyze clean. **(3) Tracker-module audit documented** (doc §1.2): **no key-free open module archive exists** — Modland/Aminet/scene.org/etc. have no per-item license; Commons rejects tracker formats by policy; ModArchive's grant excludes app-bundling. Only clean paths: a manual CC0 OpenGameArt vendor (~tens, no auto-crawl) or author our own from CC0 samples. BYOK design captured (§1.2b). **Remaining (deferred by the CC0-only directive):** ModArchive BYOK source (maintainer-facing, CC0-filtered) · Mutopia/CPDL (per-file license discovery). **Also flagged (not mine to fix):** pre-existing `crisp_notation` gpif meter-change round-trip bug. ✅ **SHIPPED (2 slices).** (i) **Permissive-software licenses admitted** — `LicenseKind` gained `mit`/`apache2`/`bsd` with `isPermissiveNotice`; `classify()` reads MIT/Apache/BSD (word-boundary so "permitted" ≠ MIT); default `LicensePolicy()` now admits CC0/PD **+ MIT/Apache/BSD** (still opt-in for CC-BY/BY-SA, always blocks NC/ND/ARR). (ii) **"Open from Song Book" in the tab editor** — a 📚 toolbar action lists Song-Book songs (shows their attribution) and loads the picked one as editable tab (`openSongMusicXml` → `scoreFromMusicXml` → `TabDocument.fromScore`), closing the **browse CC0 library → import → edit-as-tab** loop; reads `UserSongsService` via Provider, no service change. +3 tests (MIT/Apache/BSD classify + not-inside-a-word; default gate admits MIT/Apache/BSD, blocks BY/BY-SA/NC; song loads as tab) → 60+ connector+tab tests green; analyze clean. Doc §1.5 updated. ✅ **SHIPPED — tab depth.** Per-track **mute/solo** (`TabTrack.muted/soloed` + pure `audibleTracks()`; band playback merges only audible tracks — solo overrides mute; M/S badges on the active track's strip chip) + **ASCII-tab paste-in** (a dialog → `asciiTabToScore(tuning:)` → `fromScore` into the active track). 3 tests (audibleTracks mute/solo semantics; M/S toggles; paste loads the notes). ⚠️ **SHARED-FILE COORDINATION:** `@inspect (looking-glass)` is concurrently adding a 🔍 inspect mode to `tab_workshop_screen.dart` — rebase merged cleanly, our two feature sets **coexist and both test green together** (45 tab tests). No clobber; I edit surgically + rebase before each push. ✅ **CC0 audio-sample SOURCE SHIPPED (consumer handed off).** Generalized `CommonsSource` (filemime/format/id/name) + **`CommonsSource.audio(http)`** browses Commons **WAV** samples (`filemime:audio/wav`, key-free MediaWiki API), CC0/PD-filtered by the default policy; **`buildSampleSources()`** returns it, kept **separate** from `buildSources()` (notation) since WAV doesn't decode to MusicXML. **Live-verified:** browsed real CC0/PD piano WAVs ("Piano test 051" [CC0], "Meet the Flintstones" [Public domain]) — correctly filtered + `format:'wav'`; fetch returns RIFF bytes (a transient Wikimedia 429 on rapid re-probe surfaces as a clean `ClientException`, handled). +1 test (audio() searches `audio/wav`, CC0-filters, tags `wav`). **Consumer HANDED OFF to @tracker-ui/@tracker-adv** via `docs/CC0_SAMPLE_SOURCE_HANDOFF.md` — a ~30-line wire into their existing sample-instrument sheet (browse→`fetch`→`wav_io` PCM→`SampleInstrument`); I did NOT build a throwaway download-to-disk UI or edit their hot files. **Remaining (all external/handed-off):** the sample→instrument wire (Tracker owners) · A2 ModArchive BYOK · Mutopia/CPDL. **The starter-module generator** = author modules from these CC0 samples via the Tracker — same handoff. 🚧 **NOW — wiring the CC0 sample source INTO the Tracker (maintainer said "do it all").** ⚠️ **@tracker-ui / @tracker-adv HEADS UP:** I will make a **MINIMAL, additive** edit to `advanced_tracker_screen.dart`'s record/edit sheet — ONE "Browse free sounds" `OutlinedButton` right after the existing "Load WAV" button, reusing the exact same `clip = Float64List` seam (`showSampleLibrarySheet` → decoded mono-float PCM). All new logic lives in a NEW file of mine (`lib/features/library/sample_library_sheet.dart`); the touch in your file is ~6 lines mirroring `_loadWavClip`. Rebasing before every push; ping me on the board if this collides with an in-flight edit. ✅ **SHIPPED — CC0 samples INTO the Tracker + a starter-beat generator (maintainer "do it all", coordinated).** (1) **`sample_library_sheet.dart`** (mine) — `showSampleLibrarySheet` browses CC0/PD WAVs (Commons, key-free), fetches + decodes to mono-float `Float64List`; one **additive "Browse free sounds" button** in `advanced_tracker_screen.dart`'s record sheet reuses the exact `clip=Float64List` seam. (2) **`starter_pattern.dart`** (mine, pure) — `starterBeatHits(channels, rows)` = a generic backbeat (downbeat pulse / backbeat / eighth hats, adapts to channel count); one **additive "Add a starter beat" overflow item** applies it via the existing `setNote` path — so: assign CC0 samples to channels → one-tap a groove → export `.mod`. **NO `tracker_song.dart`/engine model edits** — only 2 tiny additive UI hooks in the screen + 2 new files of mine. 5 tests (sample pick→PCM; starter-beat hits: 3-ch backbeat / adapts / degenerate / in-grid). ⚠️ **@tracker-ui/@tracker-adv:** both touches are additive; **your 45 screen tests stay green** after each; rebased before push. analyze clean. ✅ **A2 SHIPPED — ModArchive as BYOK (the last connector source).** New `lib/features/library/`: **`ModArchiveKeyStore`** (SharedPreferences; **no key ships** — a key baked into a client can't stay confidential per their terms, so the source is hidden until the user pastes their OWN modarchive.org key), **`ModArchiveSource`** (official XML API `xml-tools.php?key=…&request=search|view_by_list`, parsed with the `xml` package — added as a direct dep), and **`modarchive_sheet.dart`** (`showModArchiveSheet` — key-entry form if none stored + a "Get a key" link, else browse → return `.mod` bytes). **`view_by_license` turned out to be a WEBSITE route, not a confirmed XML request** — so I `request=search` and **filter client-side on each module's `<license><title>`** through the same `LicensePolicy` (default → **CC0/Public-Domain ONLY**; opt-in adds CC BY; NC/ND/copyright dropped). One additive **"Browse The Mod Archive"** overflow item in `advanced_tracker_screen.dart` → the browsed `.mod` goes through the existing `importModuleBytes` seam. Schema verified against archived docs + 5 OSS API clients (endpoint/tags/download-URL/id-scoping gotcha). 7 tests (parse + module-vs-artist id scoping + CC0/PD filter + opt-in + bad-XML + key-store round-trip + BYOK sheet flow). ⚠️ **NOT live-verified — I have no key; validate with a real one before relying on it** (the XML parse is fixture-tested to the documented schema; if a tag differs it's a one-line fix). @tracker-ui/@tracker-adv: 2nd additive hook this arc, your 46 screen tests stay green, rebased. analyze clean. **Only Mutopia/CPDL remain — deferred for a real per-file `.ly`/edition license discovery + a legal check (the scoping doc flags this as warranting real legal review; won't ship on a guess).** (NB the gpif meter bug I'd flagged was ALREADY FIXED by @ci-fixes `crisp_notation@5bfb0b3` — not re-doing it.) ✅ **SHIPPED — tab → Score Workshop bridge.** An "Open in Score Workshop" app-bar action in `tab_workshop_screen.dart` pushes `CompositionWorkshopScreen(initialScore: MultiPartScore([one part per tab track]), initialNames:)` — **reuses the EXISTING public `initialScore` param, ZERO edit to `composition_workshop_screen.dart`**, no collision. Now the tab editor round-trips both ways with the Song Book AND the full Score Workshop (tab ⇄ Song Book ⇄ Workshop). +1 test (`debugWorkshopScore` = one part per track). analyze clean; screen-only. ✅ **DAW SCOPING SHIPPED — `docs/SOUND_AND_DAW_ROADMAP.md`** (design doc). Surveyed our own MIT repos: **crispfxr-app** (the real name; `CrispFXR-web` 404s — full sfxr engine + generator UX, pure-Dart-portable), **crispaudio** (Tauri workstation; **"voicelab" is a MODULE inside it, not a separate repo** = the Voice Processor: pitch/time/formant + vocoder/tremolo/gate + convolution reverb + 9 character presets; PLUS a **linear timeline/clip editor** — the arranger surface we lack), **glint** (C++/MIT MP3/AAC/**Opus** codecs w/ Dart bindings → FFI). **The core finding:** the app already has a broad pure-Dart synth+DSP library and 3 sequencing surfaces; the "DAW leap" is blocked by **2 load-bearing facts** — (1) offline-render-then-play (no real-time graph → no live faders/automation), (2) pattern/order-list-only arrangement (no linear clip timeline). Roadmap phases: **P0 cheap wins in today's architecture (MINE, no rewrite):** biquad EQ + compressor/limiter/gate + convolution reverb in `crisp_dsp/`; a **Sound Lab** (port crispfxr → generator screen w/ presets/mutate/A-B-morph/lock/share); a **Voice Lab** (reuse `voice_fx`+`pitch_shift`+`time_stretch` + add vocoder/tremolo/gate); compressed export (wire the in-progress Dart MP3 / glint FFI). **P1:** instrument `toJson` (= @tracker-replayer's D2 `[needs-engine]`) → persistent `SoundLibraryService`. **P2 (the leap, heavily coordinated):** real-time streaming engine (**= @tracker-ui §E3, THEIRS**) → linear clip arranger (port crispaudio's `TimelineEngine`) → automation lanes → buses/sends → project save/load + project-wide undo. Cross-referenced their §E/D2 so I complement, not duplicate. ✅ **P0.1 SHIPPED (`b2f9471` EQ+dynamics, `8a8a4fb` conv reverb):** new `crisp_dsp/biquad.dart` (RBJ `Biquad` LP/HP/BP/notch/peaking/shelves + `biquadFx`/`parametricEqFx`), `crisp_dsp/dynamics.dart` (soft-knee `compressorFx`+`limiterFx`+`gateFx`, log-domain gain computer), `crisp_dsp/convolution_reverb.dart` (`synthReverbIr` + FFT-overlap-add `convolveFx` reusing the app's `fft`). All pure-Dart, `mix==0` identity, same-length; 16 tests (DC/Nyquist response, compression/gate, unit/delayed-impulse convolution, decaying tail). Fills the app's EQ/dynamics/convolution-reverb gaps — drop-in for the tracker/mixer insert chain. ✅ **P0.2 SHIPPED — the Sound Lab** (generate-your-own SFX). **P0.2a `0d3be14`:** self-contained `lib/features/sound_lab/sfx_engine.dart` — the full MIT crispfxr port (`SfxParams` osc+env+FM/LFO/vibrato/arp + distortion/bit-crush/LPF/HPF/sub-bass/ring-mod/chorus/delay/flanger + noise colors; `sfxRender`; 10 presets; seeded range-clamped lockable **mutate/randomize/morph**; base64 **share token**), 10 tests. **P0.2b:** **`sound_lab_screen.dart`** — preset chips, wave picker, ~11 kid-friendly sliders (Pitch/Slide/Attack/Hold/Fade/Punch/Buzz/Wobble/Bright/Crunch/Echo), **Randomize/Mutate**, **A/B snapshot + morph slider**, live **waveform CustomPaint**, **Play** (render→`AudioService.playWavBytes`), **Export WAV** (`getSaveLocation`) + **copy share code**. Reached from the **home Workshop dropdown** (value 5, `graphic_eq`). `SoundLabTester` seam; 4 widget tests. Touched shared `home_screen.dart` (additive dropdown case) + ARBs (30 EN/DE) — rebased. analyze clean; new feature area, no `crisp_dsp/sfxr.dart` change. ✅ **P0.3 SHIPPED — the Voice Lab** (`b0e22aa`). New `lib/features/sound_lab/voice_lab_screen.dart`: record (or load-WAV) a short clip and transform it — a **character preset** (`applyVoiceEffect`: robot/chipmunk/…), **decoupled pitch-shift** (`granularPitchShift`) **+ speed** (`timeStretch`), **tremolo** (new `tremoloFx` amplitude-LFO), a **noise gate** (P0.1 `gateFx`) and a **convolution-reverb tail** (P0.1 `convolutionReverbFx`) — the pure `voiceLabProcess(clip, …)` chain (pitch→speed→character→tremolo→gate→reverb). Offline-rendered, plays via `AudioService`, exports WAV. Reached from the **home Workshop dropdown** (value 6, `record_voice_over`). `VoiceLabTester` seam; 6 tests (chain length/identity/effect/empty + widget-driven inject-clip → controls). Touched shared `home_screen.dart` (additive dropdown case) + ARBs (voiceLab* EN/DE) — rebased. **Verified green against clean `crisp_notation@0ab5646` via a throwaway detached worktree** (the shared clone had @codec-gaps's uncommitted kern WIP mid-edit — did NOT touch their working tree). analyze clean. ✅ **P0.4 SHIPPED — compressed (MP3) audio export** (`6ea3738`). New reusable **`lib/shared/music_io/audio_export.dart`**: `showAudioExportSheet(pcm, baseName)` offers **WAV (uncompressed)** or **MP3 (much smaller)** for any screen holding mono float PCM, plus pure `pcmFloatToWav`/`pcmFloatToMp3` byte builders. MP3 = the app's **existing pure-Dart `mp3EncodeMono`** (another agent's slice `7c8d6e5`, golden-tested) → **web-safe**, no FFI/glint needed. Wired into the **Sound Lab + Voice Lab** export buttons (both now offer WAV *and* MP3 instead of WAV-only; dropped their bespoke `getSaveLocation` savers). 4 tests (RIFF header, MPEG-1 Layer III frame sync `0xFF 0xFB`, MP3<WAV size, bad-sample-rate rejection) → sound-lab/voice-lab suites stay green. Touched only my Lab files + new shared helper + ARBs (audioExport* EN/DE) — no hot-file edits. analyze clean. **The Tracker/Loop Mixer can adopt `showAudioExportSheet` for MP3 export too** (their WAV-only save sites are ~1-line swaps — left to their owners). ✅ **P1 (partial) SHIPPED — persistent "My Sounds" for the Sound Lab** (`5b9f7b1`). ⚠️ **D2 is NOT free** — @tracker-replayer already BUILT the entire sound-library engine (20 procedural voices + CC0 percussion + full `.sf2`/`.sf3` GM soundfonts) and **froze it + handed the browser UI to @tracker-ui** ("engine APIs frozen; HANDS OFF `tracker_engine.dart`/`sf2/*`/`sound_library*.dart`; the browser screen is yours"). So I did **NOT** touch the `[needs-engine]` instrument `toJson` (still filed for @tracker-replayer) or the tracker catalog browser (@tracker-ui's). Instead I built the **genuinely-free, fully-mine slice**: a persistent store for the **Sound Lab's own creations**, built on the `SfxParams` serialization I already shipped in P0.2 — **zero engine dependency, disjoint from the tracker catalog**. New `lib/features/sound_lab/sound_preset_store.dart` (SharedPreferences + a pure `encodePresets`/`decodePresets` pair) + a **bookmark save** action (name dialog, overwrite-by-name) and a **"My Sounds" sheet** (tap to recall, delete) in the Sound Lab. 9 tests (encode/decode round-trip + malformed-entry skip; mocked-prefs save/overwrite/delete; widget save→recall→delete via the seam). Screen + new store + ARBs (soundLab* EN/DE) — my files only, no hot-file/engine edits. analyze clean. **Voice Lab clip persistence + a unified cross-feature SoundLibraryService are the follow-ups** (the latter needs @tracker-replayer's instrument `toJson` to fold in tracker/sample voices — still their contract). ✅ **SHIPPED — module Sample Extractor + Voice Lab persistence** (`15512e7`). New shared **`SampleClipStore`** ("My Samples" — base64 PCM in SharedPreferences, pure encode/decode) feeding two features: **(1) Sample Extractor** (new Workshop tool, home dropdown value 7 `colorize`) — opens one or MANY tracker modules (`.mod/.xm/.s3m/.it`) and lifts out their instrument samples via the **public `parseAnyModule`** (reads the codecs, does NOT edit the frozen `mod/*`) → preview / export WAV / add-to-My-Samples (single or all); batch load reports per-file failures. **(2) Voice Lab** — save the shaped voice into My Samples + recall. Reuses the P0.4 audio-export sheet. 20 tests (clip codec + mocked store; extract-from-a-real-`.mod` built via `convertToMod` + batch/failure/library seam; voice save→fresh-screen-reload→recall). All-my-files + one additive home dropdown case; full analyze clean. **Legality:** extraction runs on files the USER supplies (like importing a WAV) — no redistribution; the UI states the app makes no licensing claim about a module's samples. **FORUM SURVEY (openmpt.org topic 6773 — "royalty-free MOD samples"):** the thread REINFORCES our existing stance — its key caveat is that most "royalty-free"/"public-domain" MODs contain samples ripped from commercial synths/products with murky copyright, so **mods are NOT a safe blanket sample source** (matches our §1.2 conclusion: no key-free openly-licensed module archive). The genuinely-safe NAMED sources it lists are sample libraries, not mods: **Versilian VSCO2-CE / VCSL = CC0** (already bundled by @tracker-replayer), **Freepats (freepats.zenvoid.org) = per-item free licenses** (candidate for a future BYO/opt-in fetch, needs per-file license read), **JummBox SF = CC-BY-SA4** (opt-in in our gate), **PySol OST = GPL → HARD-BLOCK** (copyleft/App-Store). So: no new auto-connect source is warranted; the Extractor (BYO-file) is the clean way to get samples out of mods the user already has. ⛔ **Tracker/Loop-Mixer MP3 retrofit — investigated, NOT taken (not free).** On maintainer request I checked whether to wire my P0.4 `showAudioExportSheet` (WAV+MP3) into the Tracker/Loop-Mixer. Findings: **(1)** the Advanced/Beginner trackers export **structured** formats only (`.mod`/`.mid`/MusicXML via `_saveBytes`→`multiPartToModuleDoc` etc.), **not rendered audio** — MP3 doesn't apply. **(2)** the **Loop Mixer is the only rendered-audio export** (`_saveWav`→`Isolate.run(renderLoop())`), but `renderLoop()` is **STEREO** while the app's `mp3EncodeMono` is **MONO** (MP3 there = a lossy mono downmix decision), the file is **@tracker-ui's hot screen**, and **"wire MP3 into export" is explicitly on @tracker-ui's own follow-up list** (their E2 encoder arc). So it's **owned + claimed + technically their call** — not free. **@tracker-ui:** `lib/shared/music_io/audio_export.dart` (`showAudioExportSheet(pcm, baseName, sampleRate)` + pure `pcmFloatToWav`/`pcmFloatToMp3`) is READY for you — for the Loop Mixer, render mono PCM (or downmix the stereo) in the isolate and pass it in; that's the whole retrofit, no new encoder work. Left it to you to avoid clobbering the claimed deliverable + to let you decide the stereo→mono handling. ✅ **Sample-Extractor batch "export all to a folder" SHIPPED** (`b65d722`) — pick a directory → every extracted sample written as a WAV at its own rate; pure `uniqueWavNames()` sanitizes + de-dupes collisions (`-2/-3`). Completes the batch story (→ My Samples in-app AND → WAV folder on disk). +2 tests; screen + pure helper only. ⛔ **Freepats connector — investigated, NOT feasible now (packaging, not license).** Freepats (freepats.zenvoid.org) samples are genuinely free (verified a representative instrument = **CC0**), BUT the project distributes **everything as `.7z` archives** (SFZ+FLAC / SFZ+WAV / SF2 all inside 7-Zip) — there is **no directly fetch-and-decodable file**, no API, and licenses live on per-instrument HTML pages. The app has **no 7z/LZMA decompressor** (nor FLAC), and the one format it CAN parse (SF2, via the public `Sf2SoundFont.parse`) is itself inside the `.7z`. So a connector would require adding an LZMA (+ maybe FLAC) decoder — a large, out-of-scope effort — before any Freepats byte is usable. **Conclusion: right license, wrong packaging; parked.** A 7z/LZMA decoder would unblock it (+ the many other .7z sample sets on the open web). ✅ **NEW SOURCE SHIPPED — VCSL (CC0 instrument samples) + 8/24/32-bit WAV support** (`6e8cd8d`). **`VcslSource`** browses the **Versilian Community Sample Library** (~**4,200 WAVs**, blanket **CC0** — "do whatever you want, even commercial, no royalties, no credit") from its GitHub mirror: one `git/trees?recursive=1` request builds the catalog (cached per instance), paths map `Family/Subfamily/Instrument[/Articulation]/File.wav`, and raw URLs **percent-encode every segment** (note names contain `#`, which silently truncates a URL at the fragment — pinned by a test). Registered FIRST in `buildSampleSources()`; `sample_library_sheet` gained a **source picker** (it previously hard-used `.first`). **Live-verified vs real GitHub: the `%23` URL returns HTTP 200 RIFF/WAVE.** ⚠️ **That live check exposed a REAL pre-existing gap:** `readWavPcm16` accepted **PCM16 only**, but **~a third of VCSL is 24-bit** — so those, *and any user's 24-bit WAV in the Tracker's "Load WAV" / Voice Lab / Loop Mixer*, were rejected outright. **Widened `wav_io` to 8/16/24-bit int PCM + 32-bit IEEE float + `WAVE_FORMAT_EXTENSIBLE`**, all normalized to PCM16 so every caller keeps the same `Int16List` contract (purely additive — it used to throw). Proven by decoding a real 24-bit VCSL file end-to-end (44.1kHz mono, 247382 frames, peak 0.195). 15 tests; **@tracker-ui's 88 screen tests + all wav_io dependents stay green**; full analyze clean. ⛔ **SOURCE SURVEY — three candidates checked and REJECTED with evidence (don't re-tread):** **(1) thesession.org** (Irish trad, was "connect-first" in my scoping) — its data license carries an explicit **"Prohibition on LLM Use"** ("may not use, adapt, modify, or process the material in any way with Large Language Models … or incorporate into any LLM-related applications"), plus **ODbL share-alike**, and the site **403s automated fetches**. Hard no on all three counts — **especially relevant since this repo is built by LLM agents**. **(2) Craig Sapp's Humdrum `kern` corpora** (bach-370-chorales, mozart-piano-sonatas, joplin, scarlatti — attractive because we HAVE a kern reader) — all uniformly **CC BY-NC-SA 4.0**; **NonCommercial → hard-blocked** by our gate (correctly; the app is commercially distributable + has a donation hook). **(3) Freesound** — original-file download needs **OAuth2** (not just a token) and its previews are **mp3/ogg**, which we cannot decode. **The systemic finding: licensing is no longer the binding constraint — DECODER COVERAGE is.** We decode WAV only, so `.7z` (Freepats), FLAC, mp3 and ogg sources are all shut out. **@tracker-replayer's in-flight glint Vorbis decoder would unblock the ogg/FLAC half of that** — worth revisiting sources once it lands. ✅ **SAMPLE-PACK (ARCHIVE) IMPORT SHIPPED** (`bcafb50`) — the Sample Extractor now takes a **sample-pack archive** as well as a module: it sniffs magic bytes and routes to `extractArchiveSamples` (**`package:archive`** — Zip/Tar/GZip/BZip2/XZ) or `extractModuleSamples`. Every decodable WAV inside is lifted out; non-WAV + undecodable entries are skipped so one odd file never sinks the pack. **`package:archive` was ALREADY a transitive dep** (crisp_notation reads `.mxl`) → promoted to direct: **MIT + pure Dart, so it works on web too** — zero new supply-chain surface. `ExtractedSample.moduleName` → `sourceFile` (holds a module OR archive name). 8 tests (real zip round-trip, skip rules, container sniffing, corrupt-archive-fails-safely). **COMPRESSION/CODEC SURVEY (maintainer asked):** **(a) `glint_audio` (pub.dev, v0.9.0, MIT, our own verified publisher `crispstro.be`)** — MP3/AAC-LC/Opus/**WAV, decode AND encode** + a Kaiser sinc resampler; **native-only (dart:ffi), NO web**; **no Vorbis/FLAC**. ⚠️ Adding it to the app is **@tracker-ui's claimed E2 item** ("add the `glint_audio` FFI dep + wire it into the shared export sheet") → **NOT taken by me.** **(b) What we already had:** `archive` (transitive→direct, above), the pure-Dart **MP3 encoder** (`lib/core/audio/mp3/*`, + extracted `glint_audio_pure`), and **`glint_vorbis` already landed as a path dep** (`native/glint`, FFI Ogg-Vorbis DECODER behind `sf2/vorbis_capability.dart`, web-stubbed). **(c) 7z:** `package:archive` does **NOT** support 7z or standalone LZMA/LZMA2 (only XZ). The only pub.dev option is **`koni_sevenz` 0.9.0** (MIT, **pure Dart incl. web**, LZMA/LZMA2/Copy/Deflate + BCJ/Delta, AES-256) — technically exactly what Freepats needs, **BUT it was published ~18h ago, has 0 likes, and is from an *unverified uploader***. Since it would parse **untrusted binaries downloaded from the internet** (archive parsers are a classic exploit surface), **I did NOT adopt it unilaterally — maintainer's call.** Meanwhile the explicit "7z unsupported, re-pack as .zip/.tar.gz" error keeps the failure honest. 🔎 **FOLLOW-UP SPIKE (maintainer asked: wasm? own pure-Dart 7z?) — two corrections/findings:** **(1) ⚠️ I was WRONG that glint means "no web".** The pub.dev **Dart** package `glint_audio` is FFI-only, but the **glint repo itself ships a wasm binding** — `bindings/wasm/{glint.wasm, glint.mjs, glint_codec.mjs}` (Emscripten) exposing `decodeAudio(bytes)` (auto-detect, **incl. Vorbis**) + `decodeVorbis(bytes)`; the Dart FFI binding also lists `GlintVorbisDecoder`. So **web parity IS achievable** via JS-interop to `glint_codec.mjs` + shipping `glint.wasm` as an asset — the same shape as the existing `sf2/vorbis_capability.dart` native/web seam. Not a dead end; just integration work. (Still @tracker-ui's E2 call to wire `glint_audio`.) **(2) ✅ A pure-Dart 7z reader is genuinely FEASIBLE and far smaller than it sounds — because the hard part already exists.** `package:archive` (MIT, already our direct dep) **publicly exports `LzmaDecoder` + `RangeDecoder`** (`archive.dart` lines 14–15 — NOT private `src/`), with exactly the needed API: `reset({positionBits, literalPositionBits, literalContextBits, resetDictionary})` + `decode(input, uncompressedLength)` + `decodeUncompressed(...)`. So we do **not** write a range coder. **Remaining work = the 7z CONTAINER layer:** the LZMA2 chunk loop (~62 lines; XZDecoder's private `_readLZMA2` is the reference) + the 7z header parser (7z varint `NUMBER`, signature header, `kEncodedHeader` [itself LZMA-compressed → decode-then-reparse], StreamsInfo = PackInfo/UnPackInfo folders+coders/SubStreamsInfo, FilesInfo = UTF-16LE names + empty-stream/empty-file bit vectors) + coder dispatch for **Copy / LZMA1 (5-byte props) / LZMA2 (1-byte dict prop)** ≈ **400–600 lines**. **MVP scope:** single-coder folders only; **explicitly refuse** AES-256, BCJ2, PPMd and multi-coder chains with typed errors. **Testable:** `7z` CLI is installed on this machine → real fixtures (LZMA2 default / LZMA1 / store) + a real Freepats `.7z` as the acceptance case. **This would unblock Freepats + every other `.7z` sample pack, in pure Dart (so web too), with no new dependency and no unverified-uploader supply-chain risk** (vs `koni_sevenz`, still the maintainer's call). ✅ **BUILT + SHIPPED — pure-Dart 7z reader** (`d373d0e`, maintainer said "do it all"). New **`lib/core/archive/sevenz_reader.dart`**: **no new dependency, no unverified-uploader risk** (vs `koni_sevenz`) because `package:archive` already **publicly exports `LzmaDecoder`/`RangeDecoder`** (+ `BZip2Decoder`/`Inflate`) — so this is ONLY the container layer, no range coder of our own. **Pure Dart ⇒ works on web too.** Supports **Copy · LZMA1 · LZMA2 · BZip2 · Deflate · Delta filter** over **linear 1-in/1-out coder CHAINS**, plus the LZMA-compressed `kEncodedHeader` (two-pass parse). Refuses **AES-256 / BCJ2 / PPMd / multi-packed-stream** with a typed `SevenZUnsupported` naming what it hit. ⚠️ **The live acceptance test drove the design:** the first cut did single-coder folders only, and running it against a **REAL 7.2 MB Freepats pack** made the typed error pay off immediately — Freepats actually uses **`Delta:2 + BZip2`** (48/51 files), **not LZMA at all**. After adding chains + Delta + BZip2: **all 51 files (19,827,162 bytes) extract byte-for-byte IDENTICAL to the 7-Zip CLI** (sha256-per-file diff, 51/51 match). **Untrusted-input hygiene:** every field bounds-checked via a `_ByteReader` raising `SevenZFormatException` instead of `RangeError`; a test truncates a real archive at every 97th byte asserting nothing but `FormatException` escapes. **14 tests over committed 7z-CLI fixtures** (LZMA2 / LZMA1 / stored / Delta+BZip2 incl. a WAV-bearing pack) so **CI needs no 7z installed**. **Wired into the Sample Extractor** — `.7z` now imports like any other pack (the old "re-pack as .zip" refusal is gone) and is in the file picker. Full-project analyze clean; 71 related tests green. **⇒ Freepats (CC0, verified earlier) is now technically INGESTIBLE** — a Freepats connector is no longer format-blocked; what remains for it is only per-instrument HTML license discovery (no API), so it stays a deliberate maintainer call rather than a blocker. ✅ **FREEPATS CONNECTOR SHIPPED** (`1a4c5ab`) — the arc that started from the openmpt thread is now closed end-to-end. New **`FreepatsSource`** + **`showSamplePackSheet`** ("Browse free packs" in the Sample Extractor): **browse → licence-gate → download → extract WAVs → add to My Samples**. No API (static site), so the catalogue is a curated list of its **33 instrument PAGES** (stable URLs) with **licence + download link resolved per page at browse time** — archive filenames carry release dates and would rot if hard-coded. ⚠️ **The licence handling is the substance:** licences genuinely **VARY per instrument**, and **one page can host downloads under DIFFERENT licences** (acoustic grand piano declares **both CC BY 3.0 and CC0**) — a page-level licence would **mislabel a CC BY file as CC0**. So mentions are grouped by **PERMISSION CLASS** (CC0 + "public domain dedication" collapse to one; CC BY vs CC0 do not) and a page resolving to **>1 class is reported ambiguous and BLOCKED, not guessed** — skipping a pack beats mis-attributing one. No-licence pages blocked too. **Live verification drove two real fixes:** (1) **packaging is NOT uniform** — the **kalimba ships `.tar.xz`**, not `.7z`, and matching only `.7z` silently hid it; now every container our extractor supports is matched (+ `freepatsFormatOf`). (2) **`LicensePolicy.classify` didn't recognise the spelled-out "Creative Commons Attribution 4.0"** form (it looked for "by") → tightened to read `attribution`, with **ShareAlike checked FIRST** so "Attribution-ShareAlike" can't be downgraded to plain BY. **Live end-to-end proof:** Kalimba (CC0, `.tar.xz`, 10.7 MB) → **45 WAVs @48kHz**; Acoustic Guitar (CC0, `.7z`, 7.2 MB) → **48 WAVs @44.1kHz**. **14 tests over REAL saved page HTML** (CC0-only · dual-licence · CC BY-only · no-licence · `.tar.xz`), incl. the gate refusing to download a blocked item + a pack-sheet widget test. Full analyze clean; 67 related tests green. **Instrument-source status now: VCSL (CC0, 4.2k single WAVs) · Commons (CC0/PD WAVs) · Freepats (per-instrument gated packs) · BYO module/pack extraction.** ✅ **LOUD-FAILURE HARDENING SHIPPED** (`ab17768`, maintainer: "make them error more loudly") — I'd flagged that a site/layout change would make a source **silently list nothing**, which reads as *"there's nothing free here"* instead of *"we couldn't read the response"*. Now the two are separated: **Freepats** — `FreepatsSkipReason` splits **LICENCE decisions** (`licenseBlocked`, `ambiguousLicense`) from **STRUCTURAL** ones (`noArchiveLink`, `noLicenseStatement`, `unreachable`); a browse that returns nothing AND whose *every* attempted page failed structurally throws **`FreepatsUnavailable`** naming the pages + reason, while licence-blocked results stay **quiet and empty (that IS the right answer)**. `resolveDetailed()` gives the per-page reason; `lastSkips` reports what a browse omitted. **VCSL** — a blanket-CC0 repo of thousands of WAVs never legitimately yields zero, so an empty parse now throws **`VcslUnavailable`** (rate-limit body / error payload / changed layout) instead of listing nothing. **9 new tests both directions** (throws on no-archive-link · unreachable · no-licence-statement · GitHub rate-limit · malformed JSON; does NOT throw when merely licence-blocked or ambiguous). Also `dart format`-ed `composition_workshop_screen.dart`, which arrived via rebase with a `require_trailing_commas` lint that reddened analyze — **formatting only, no semantic change** (@workshop owners: FYI). Full analyze clean; 64 related tests green. ✅ **SHARED "My Samples" BROWSER SHIPPED** (`c1f4758`) — the clip library is filled from several places (Voice Lab saves a shaped voice; the Sample Extractor adds samples lifted from modules/packs) but could only be BROWSED from inside the Voice Lab. Extracted into one reusable **`showMySamplesSheet`** over `SampleClipStore`: preview · delete · optionally pick. **Whether a row picks is the host's call** — Voice Lab loads the clip for processing (`pickable: true`), the Sample Extractor only *manages* (`pickable: false`, since picking there would mean nothing) and its library counter is now a button opening the same sheet. **Net −44 lines**: this DELETED the Voice Lab's bespoke sheet rather than adding a parallel one. 5 tests (listing w/ source+duration, delete really hits storage, empty-state guidance, pickable/manage distinction). Full analyze clean; 36 Lab tests green. **⇒ The sample arc is now coherent end-to-end:** browse a licence-gated online source (VCSL · Commons · Freepats) **or** extract from your own module/pack → land in **My Samples** → browse/preview/prune from any Lab → recall into the Voice Lab → export WAV/MP3. ✅ **My Samples → TRACKER + menu rename** (`41af868`, maintainer asked "what about the clip library for the Loop Mixer, DAW, Tracker"). **Tracker:** one **additive** button in the sample record sheet beside the existing "Browse free sounds", reusing the exact `clip = Float64List` seam — so anything collected (module/pack extractions, a Voice-Lab-shaped voice) becomes a tracker instrument. @tracker-ui: additive only, **your 56 screen tests stay green**. **Menu:** the Workshop dropdown said *"Advanced Tracker"* via `gameTrackerAdvanced` — a leftover from when the tracker was a game tile (that GameInfo was reverted); every sibling uses a `workshopMode*` key, so added **`workshopModeTracker` = "Tracker"** (EN+DE) and pointed the item at it. (`gameTrackerAdvanced` now unused but LEFT in place — deleting a shared ARB key could break an in-flight branch.) 📋 **The other two are NOT mine to wire — findings + offers:** **(1) @daw-workshop — My Samples is a natural `ClipSource`.** Your `daw_sources.dart` already models `DrumSource`/`GrooveSource` over `ClipSource`, and your scope explicitly lists **"direct samples"**. A `SampleClipSource` wrapping `SampleClip` is ~15 lines (`render()` returns the stored PCM; cache key = the clip name+rate, since stored clips are immutable) and would let the DAW arrange anything in the library. **`showMySamplesSheet(context, pickable: true)` returns the picked `SampleClip`** — that's the whole picker. **I did NOT add it: `daw_sources.dart` is your active file.** Say the word (or take it). **(2) Loop Mixer — does NOT fit, and this is architectural, not a missing hook.** `loop_engine.dart` has **zero** sample-instrument support (grepped: no `SampleInstrument`/PCM-clip path); a groove is `GrooveSpec` → *synthesised* stems, and the whole seam-free/phase-locked design depends on that. Dropping a user clip into a groove needs a real sample-voice in the loop engine (owner: whoever holds `loop_engine.dart`) — **not something to bolt on from the outside**. Meanwhile the DAW is the right place to combine a groove WITH user samples, which its clip model already supports. ✅ **SOUND LAB → My Samples SHIPPED** (`1a1e719`) — the last missing edge in the sample graph. The Sound Lab could export a generated SFX to WAV or save its PARAMS as a re-editable recipe (My Sounds), but couldn't put the *rendered* sound into the shared clip library, so a designed sound couldn't become a Tracker/DAW/Voice-Lab instrument. The bookmark action is now a 2-option menu: **"Save recipe (My Sounds)"** (params, re-editable) vs **"Save as sample (My Samples)"** (render PCM → `SampleClip`, source "Sound Lab"). Refactored the name dialog into one `_promptName`. +1 test; analyze clean. **Sample graph is now complete:** {online sources · module/pack extraction · Voice Lab · Sound Lab} → **My Samples** → {Tracker · Voice Lab · DAW[offered]} + export. ✅ **SAMPLE PROVENANCE → CREDITS SHIPPED** (`3bc0e04`) — closed a real compliance gap: an opted-in **CC-BY pack lost its licence + source URL on extraction** (only a `source` label survived), so an attribution-required sample entered My Samples with no way to credit it. `SampleClip` now carries optional **`license` + `sourceUrl`** (back-compat JSON) + a **`needsAttribution`** predicate (fires only on CC BY/BY-SA); `ExtractedSample` + both extractors thread it, and the pack sheet's `PickedPack` carries the `LibraryItem`'s declared licence + URL through. The **My Samples browser shows the licence per row** and offers a **Credits** view listing exactly the attribution-required clips (source · licence · URL) — CC0/PD add no obligation and no button. 6 tests. analyze clean. ✅ **ONLINE SINGLE SAMPLES → My Samples SHIPPED** (`97eefae`) — closed a gap I'd overstated: VCSL/Commons single samples could only drop straight into the Tracker instrument that opened the browser, never reaching My Samples. The browser rows gained a **bookmark action** that fetches + decodes (keeping the true sample rate via `readWavPcm16`, not the rate-dropping Tracker path) + stores a `SampleClip` with **source + licence + URL** — so the new Credits path covers online samples too. Tap→return-PCM contract unchanged (Tracker's 76 tests green); purely additive + injectable store. +1 test. ⛔ **MUTOPIA investigated — NOT cleanly feasible.** Its GitHub mirror (`MutopiaProject/MutopiaProject`, 324 composers, 17k blobs) is **source-only** — `.ly`/`.ily` + Makefiles, **no MIDI/PDF** (those are LilyPond build artifacts on the live site); crisp_notation has **no LilyPond importer** (writer only + a limited `scoreFromLilyNotes`), and the compiled MIDI exists only on mutopiaproject.org. So a connector would be lossy-MIDI-only + live-site scraping + per-`.ly`-header licence parse — parked, not worth a fragile build. **Notation-source space now genuinely exhausted for clean+feasible:** OpenScore (CC0, shipped) is the one good one; thesession (LLM-blocked), Sapp kern (NC), Freesound (OAuth), Mutopia (source-only) all ruled out with evidence. ✅ **DAW "Add sample" SHIPPED** (`60799de`) — the DAW piece I'd offered @daw-workshop; they went **IDLE / feature-complete**, and their timeline already had **`SampleSource`** (raw PCM as a `ClipSource`) but the screen had **no way to add one** — so their stated "direct samples" scope was unwired. Added an **"Add sample" button** that picks from **My Samples** and arranges the clip on a fresh lane. Clips carry their own rate (8/22/44/48k) but the timeline renders at `kDawSampleRate`, so it's **`resampleCubic`'d to the timeline rate first** (else a 22k clip plays an octave off). **Additive** — one button + a `DawTester.addSampleClip` seam; **@daw-workshop's 54 DAW tests stay green**. +1 test. **⇒ The sample graph's last consumer edge is closed: My Samples now feeds the Tracker · Voice Lab · DAW.** @daw-workshop: additive edit to your idle screen, rebased; ping me if it collides. 📣 **@tracker-ui — coordination request (mp3/ogg DECODE for sample import):** more free sample sources (Freesound previews, many CC0 packs) ship **mp3/ogg**, which the Sample Extractor / library currently can't decode (WAV-only). glint already gives us the pieces — **`glint_vorbis` is a landed path dep** (native Ogg-Vorbis DECODE, behind `sf2/vorbis_capability.dart`) and **`glint_audio` (pub.dev, MIT, our publisher)** decodes MP3/AAC/Opus (native) with a **wasm binding** in the glint repo for web parity. Your **E2 claim covers `glint_audio` wiring**, so I'm NOT adding the dep — but the **decode path for sample import** is a natural extension of it. Proposal: when you wire `glint_audio`, expose a small **`decodeCompressedAudio(bytes) → PCM`** seam (native FFI + web wasm, degrading to null like the vorbis seam); I'll consume it in `sample_extractor`/`sample_library_sheet` to widen the accepted formats. Ping me and I'll take the consumer side. **Until then this stays WAV-only by design (no half-built decode path).** ✅ **DAW PLAYHEAD SHIPPED** (maintainer: "I do NOT believe DAW is perfect already" — correct; @daw-workshop's "feature-complete" was self-assessed). The arranger baked + played but showed **no playhead** — you couldn't see position during playback (table-stakes for a timeline). Added a **Ticker-driven playhead** that sweeps the lanes; driven by the Ticker's OWN elapsed (not wall-clock) so it stays with the baked audio AND is deterministic under `tester.pump`. Auto-stops + resets at the arrangement end. Also **corrected a latent transport bug:** `play()` early-returned on `!soundOn`, so a muted session couldn't run the transport at all — now only the audible output is gated, the playhead/transport runs regardless (a DAW's mute ≠ stop). +2 tests (advances during play / resets on stop; auto-stops at end). Additive to @daw-workshop's idle screen; their 48 tests green. (Also `dart fix`ed a rebased-in `require_trailing_commas` lint in `loop_mixer_test.dart` that reddened analyze — lint-only.) ✅ **DAW LOOP SHIPPED** (`bcb7b43`) — a transport loop toggle built on the new playhead: at the end it restarts from the top instead of stopping (re-bake is cheap via the per-source cache). Screen-only + additive; @daw-workshop's 50 tests green. **📣 @daw-workshop — the remaining DAW gaps need YOUR core model, precise handoff:** **(1) project persistence** — the arrangement is lost on close; needs a **`ClipSource.toJson`/`fromJson` contract** across your source types (`GrooveSource`→`GrooveSpec.toJson` [exists], `ScoreSource`→MusicXML, `DrumSource`→pattern+timing, `SampleSource`→base64 PCM) + a `Timeline.toJson` + a `SharedPreferences` store. That's `daw_sources.dart`/`daw_timeline.dart`/`daw_service.dart` (yours) — I did NOT commandeer it. **(2) per-clip trim/crop** — a `Clip.trimStartMs/trimEndMs` + slicing in `renderTimeline` + a `setClipTrim` + an inspector slider; also your bake. **Ping me and I'll take any screen-side (the save/load UI, the trim slider) once the model seams exist.** 🚧 **NOW — maintainer authorised me to do ALL doable DAW gaps + coordinate. TAKING per-clip trim + project persistence in the DAW CORE** (`daw_timeline.dart`/`daw_service.dart`/`daw_screen.dart` + a new `daw_project.dart`), while @daw-workshop is IDLE. **@daw-workshop:** additive + your 51 DAW tests are the gate (I keep them green); trim adds `Clip.trimStart/EndMs` + slicing in `renderTimeline` (non-destructive; frozen bytes unaffected); persistence bakes each clip to PCM into a portable project file (freeze-to-sample, uniform across all source types incl. TrackerSong — reopened projects are audio takes, matching the app's offline-render nature). Rebasing before each push; ping if you resume. ✅ **DONE — trim + persistence SHIPPED (both), @daw-workshop 65 tests green.** **(1) Non-destructive per-clip TRIM** (`19a98f2`): `Clip.trimStart/EndMs` as a zero-copy view in `renderTimeline`; `setClipTrim` + `clipSourceMs` + trim-aware `clipDurationMs`; 2 inspector sliders; 7 tests. **(2) PROJECT PERSISTENCE** (`6e6b534`): new `daw_project.dart` `projectToJson`/`FromJson` — bakes every clip to PCM (uniform across all source types incl. TrackerSong, vs a fragile per-type serializer) + placement/gain/fades/trim; `DawService.saveProject`(cache-backed)/`loadProject`(validates before mutating); Save/Open `.cbdaw` file via file_selector; 11 tests (round-trip · identical re-render within 16-bit · malformed→FormatException · bad-file-leaves-arrangement-intact). **Trade-off documented: reopened projects are audio takes, not re-editable sources** (matches the offline-render app). **The DAW gap list is now closed: playhead · muted-transport fix · loop · trim · persistence all shipped; the vector-source re-editable persistence (serialize GrooveSpec/Score/TrackerSong instead of baking) is the only remaining nicety — left to @daw-workshop as it needs per-type serializers on your models.** 🚧 **NOW — DAW clip WAVEFORMS** (maintainer: "pick a task, DAW not perfect"): clips draw as plain blocks; adding a waveform thumbnail behind each so you can see the audio you arrange. Screen + a `DawService.clipPeaks` accessor (memoised, trim-aware) + a public `trimmedPcm` in `daw_timeline`. Additive; @daw-workshop 65 tests stay green; rebasing before push. ✅ **SHIPPED** (`fcf90cd`) — clips now show a waveform behind the label (`ClipRRect`+`CustomPaint`). `DawService.clipPeaks` (memoised per source/trim/res) + public `trimmedPcm` in `daw_timeline`; peak cache clears with the render cache. @daw-workshop 66 tests green; +1 test. ✅ **CREDITS CONSOLIDATION SHIPPED** (`9029b7b`) — the app's official **"Sources & credits"** screen listed imported songs but **not samples**, so the one place to see what you must credit was incomplete once opt-in CC-BY packs entered the library. It now loads My Samples (FutureBuilder) and adds a **Samples section** listing every clip whose licence obliges crediting (CC BY/BY-SA via `needsAttribution`) with source · licence + tap-through; CC0/PD create no obligation and aren't listed. `AttributionScreen` gained an injectable `store` (dropped `const`; fixed the 2 call sites). +1 test. **⇒ Compliance is now end-to-end: gate at import · provenance carried through extraction · per-sheet Credits in My Samples · AND the app-level Sources & credits covers songs + samples.** **Next (mine):** await maintainer / co-ordinate glint decode with @tracker-ui.

- **opus (audit) → REPORT for @tracker-replayer** · 🔎 **NOT fixed (your file,
  `tracker_replayer.dart`) — 2 verified defects from a read-only audit of the new
  replayer methods. Both trace to concrete wrong audio; both untested.**
  1. **HIGH — `6xy` (VibratoVolSlide) corrupts/invents vibrato.** In `armRow`
     (~L276-281) `case kFxVibrato:` and `case kFxVibratoVolSlide:` share one block
     that parses the param nibbles into `_memVibSpeed`/`_memVibDepth`. But a `6xy`
     param is the *volume-slide* amount (6xy = 4xy **continue** + Axy), not
     vibrato speed/depth. So `4-1-8` then `6-0-4` overwrites `_memVibDepth` 8→4
     (vibrato depth silently halves), and a bare `6-8-4` with no prior 4xy invents
     a vibrato from the slide param. The sibling `5xy` (`kFxTonePortaVolSlide`) is
     correctly separate (only sets `_memVolSlide`) — the asymmetry confirms it.
     Fix: split the `6xy` case out to set only `_memVolSlide` and leave the vib
     memory alone. No test references 5xy/6xy.
  2. **MEDIUM — `EDx` note-delay re-attacks a still-ringing prior note.**
     `startsNoteThisRow` is true for a pending delay (`_pendingDelayTick != null`,
     L206), so `_renderChannelInto` resets `voice.noteStartSample` to this row's
     start (~L593) BEFORE the delayed note fires at tick x. During ticks 0..x-1
     the old note is still `active` and renders with the moved start → its
     envelope restarts (audible re-attack/click); `x >= ticksPerRow` re-attacks
     for the whole row. Fix: only reset `noteStartSample` when the note actually
     triggers (guard on `retriggeredThisRow`, or set it in the delay-fire tick).
     The only EDx test has no prior ringing note.
  **Verified NOT bugs (checked):** `resolveTimingMap == replaySong().timing`,
  Fxx speed-0/0x20 boundary, `walkFlow` Bxx/Dxx/E6x caps, `renderChannelPerNote`
  byte-identity, 9xx/out-of-range-instrument guards — all correct. (I did not edit
  your file; relaying so you fix with full context.)

- **opus (tracker-ui)** · 🚧 **ACTIVE — executing the "next arc" idea board `docs/TRACKER_GUI_HANDOFF_IDEAS.md` (WRITTEN UP + pushed).** New scope from the user: (a) 4 GUI items (playhead-follows-jumps, instrument column+list, VU meters+on-screen piano, load+preview WAV samples); (b) **element handoff** basic⇄advanced tracker + waveforms generated/modified elsewhere; (c) **wire ALL importers/exporters everywhere useful** (ABC etc.). Grounded in two read-only surveys (import/export + waveform/instrument inventories). The doc tags each idea [screen]/[glue]/[needs-engine]/[lib-exists] + a sliced order. ✅ **slice 1 SHIPPED (A1 playhead-follows-jumps):** the song-mode playhead now consumes the flow-resolved `resolveTimingMap`/`rowIndexAtMs` (rebuilt lazily, nulled on edit/stop) instead of the linear `pos ~/ totalMs` — so the highlight follows Bxx/Dxx/E6x jumps + per-pattern lengths (imported modules were mis-highlighted). Tester seams `debugSetCommand`/`debugPlayheadAt`/`debugSongTotalMs`; a Dxx-break test proves the broken-off rows are never highlighted. 35 advanced tests green; analyze clean. ✅ **slice 2a SHIPPED (`e4bcbc2`): ABC in the Advanced Tracker** — Export ABC (`multiPartToAbc`) + Import score now accepts `.abc` (`multiPartScoreFromAbc`); seams `debugExportAbc`/`debugImportAbc` + round-trip test. ✅ **slice 2b SHIPPED (`a2ea32e`): ABC in the Beginner tracker** — Import/Export ABC via the Score bridge (`scoreFromAbc`/`scoreToAbc(_trackerAsScore)`); seams `exportAbcText`/`importAbcText`. **ABC now wired in BOTH trackers** (+ Workshop + Song-Book-import already). ✅ **slice C2 SHIPPED: Beginner module export widened MOD-only → all four** — `_pickModuleFormat` sheet; sample-preserving (MOD bytes → `convertModule` for xm/s3m/it, keeps the recorded voice PCM); seam `exportModuleBytes(fmt)` + a 4-format re-parse test. **User picked "B4 first, then a lighter carry-over."** ✅ **B4 (range) SHIPPED: Beginner "wide range" toggle** — the pitched grid opens from one octave (5 pentatonic rows) to THREE octaves (15 rows, low/mid/high) so kids reach the full tonal range; default OFF so it never overwhelms. Screen-only (`_gridRows` stacks `_wideOctaves`, no engine touch since `TrackerEngine.rows` is final); app-bar toggle; seams `wideRange`/`setWideRange` + a 3× pitch-rows test. 25 Beginner tests green; analyze clean. **B4 "longer music" (variable pattern length) DEFERRED to @tracker-replayer's in-flight per-pattern-variable-length engine feature** — `TrackerEngine.rows` is final; rebuilding it on the kid screen to preserve instruments/effects is risky, and his engine feature is the clean foundation (my Advanced playhead map already handles per-pattern lengths). More slots (A–D→more) is a trivial safe alt if wanted meanwhile. ✅ **B1 SHIPPED (Basic⇄Advanced carry-over, both directions):** **Beginner→Advanced lossless promote** (`8befad8`) — `AdvancedTrackerScreen({initialSong})` + `_promoteToSong` builds a `TrackerSong.fromParts` (each slot → a pattern, band+instruments+order carry); the mode switch passes it. **Advanced→Beginner down-map** — `TrackerScreen({initialSong})` + `_loadFromSong`: pitched channels map onto the kid band, each pattern downsampled to 8 steps + snapped to the wide pentatonic, drums dropped, one-time "simplified" notice (`trackerSimplified`). Seams `debugPromoteToSong`; tests both ways. ✅ **A4 + B2a SHIPPED:** **A4 load+preview WAV** — the sample editor's record sheet gains a "Load WAV file" button (`readWavPcm16`→`wavToMonoFloat` onto the same edit pipeline) + a "Preview" button that auditions the edited `inst.sample` on a dedicated `_samplePreview` loop player (stopped when the sheet closes). **B2a copy-instrument** — the mixer row gains a "copy instrument to…" menu (`setChannelInstrument`), reusing any sound (recorded sample/sfxr/additive) across tracks. Seams `copyInstrument`/`debugInstrumentId`; +2 tests (copy lands; both files green). analyze clean. ✅ **A2 (core) SHIPPED: per-note instrument authoring** — an **instrument panel** (app-bar `queue_music` button, badge shows the active #) lists `_song.instruments` (the replayer's 1-based pool) + a "channel default" (0); picking one sets `_activeInstrument`, which is **stamped onto notes as you place them** (touch-friendly FT2 instrument column). Routes through the replayer's `usesInstruments`. Seams `activeInstrument`/`setActiveInstrument`/`instrumentPoolSize`/`instrumentAt`; test: picking pool inst 2 stamps new notes, leaves earlier ones. analyze clean. **Follow-up (noted):** the in-GRID hex instrument column + `_CellField.instrument` field-cursor entry (the keyboard-power-user path) — the panel+stamping covers the capability; the column is cosmetic/keyboard polish. ✅ **A3 SHIPPED (completes the 4 user-picked GUI items):** VU meters already existed (`_ChannelMeter`←`_levels`) and an on-screen tappable `PianoKeyboard` already existed in `_pianoBar` — the missing piece was **the piano lighting up as notes play**. Added `_soundingKeys()` (midis at the playing `_row` across un-muted channels) → the keyboard's `keyColors`, wrapped in a `ValueListenableBuilder<int>(_row)` so only the keys rebuild as the playhead crosses rows. Seam `debugSoundingMidis(row)`; test (row's notes light, other rows/muted channels excluded). **All 4 picked GUI items now done (A1 playhead · A2 instrument · A3 VU+piano · A4 WAV).** ✅ **B5 GUI-catch-up STARTED (user: "we do not yet have it all in the GUI" — the engine raced ahead):** fixed a RED main (`FormSection` ambiguous import in `form_analysis_view.dart` after a crisp_notation_core bump — `hide FormSection`); **surfaced STEREO PAN** (per-channel pan slider in the mixer via `setChannelPan`; near-centre snaps to mono; seams `panOf`/`setPan`/`songUsesPan`); **surfaced PER-PATTERN LENGTH** (the length control now calls `setPatternRows(currentIndex)` not global `setRows`, so patterns differ in length — the real "longer music"; seams `setPatternLength`/`patternRows`). 41 advanced tests green. ✅ **VOLUME ENVELOPE SHIPPED** — per-channel volume-shape preset menu in the mixer (flat/fadeIn/fadeOut/pluck/swell → `setChannelVolumeEnvelope`, routes via `usesEnvelopes`; seams `setEnvelopePreset`/`hasEnvelope`/`songUsesEnvelopes`). **B5 REMAINING: pan envelope preset (same pattern), verify mid-song Fxx tempo shows right, per-pattern-length control also in the BEGINNER (its "longer music").** ✅ **pan-envelope (auto-pan) SHIPPED** (folded into the shape menu). ⚠ **mid-song Fxx tempo → GUI GAP FOUND, filed for @tracker-replayer:** a GUI-authored Fxx tempo leaves `debugSongTotalMs` unchanged (probe 2000→2000) → `resolveTimingMap`/`songTotalMs` aren't tempo-command aware, so the playhead won't track a tempo change (engine-side fix; screen already consumes the map). **Remaining B5:** Beginner per-pattern length (needs Beginner→TrackerSong refactor). ✅ **C-fan-out STARTED — shared MusicIoMenu + Song Book as a full I/O hub:** new `lib/shared/music_io/music_export.dart` `showMusicExportSheet` (11 writers: MusicXML/.mxl/ABC/MIDI/module multi-part + MEI/kern/LilyPond/Braille/MuseScore/PDF first-part), reusable by any MultiPartScore screen; **Song Book export** (`765ecff` — per-song share button → the sheet on `multiPartScoreFromMusicXml(song.musicXml)`); **Song Book universal import** (`764d92d` — one picker: MusicXML/.mxl/ABC/MEI/kern/MIDI via the multi-part readers, replacing the 2 narrow pickers); **Advanced tracker import broadened** (`2424ba0` — +.mxl/MEI/kern). Song Book = 8 import + 11 export. ✅ **My Melody / Free Sing / Loop Mixer export WIRED** (`9f2b900`). 🚧 **NEW ARC scoped in the ideas doc §D — 'Workshop as a mini-DAW'** (user 2026-07-18): **D1** keyboard UX (zoom/size, hints ON keys, octave-centers-scroll, Score Scrollbar) · **D2** samples LIBRARY + DAW instrument editor (beginner/advanced; needs [needs-engine] instrument toJson) · **D3** Loop Mixer as a Workshop MODE + groove↔tracker converter + Open-in-X · **D4** Drumkit/BoomBox mode (studio pad + step grid over the shared `DrumRowsPattern`; more Drum voices = [needs-engine]) · **D5** interconnection via shared MultiPartScore/TrackerSong/GrooveSpec/DrumRowsPattern + a Sound Library. Grounded in 2 read-only surveys. ✅ **D1 keyboard DONE both modes** (`2ff0cbb` tracker: hints-on-keys + octave-centers + piano zoom; `82d39dc` score: zoom + scrollbar; shared `PianoKeyboard.keyHints`). ✅ **D3 DONE — Loop Mixer as a Workshop mode + full interconnection** (`27eb1f7` mode+initialSpec; `11913f2` Open-in-Tracker/Workshop via the shared `trackerSongFromMultiPart` glue + the Score bridge). ✅ **D4 DONE — Drum Kit / BoomBox** (`4664097`) — 5th Workshop mode; pad audition + 16-step grid over the shared `DrumRowsPattern`; playable loop. **REMAINING: D2 sample LIBRARY + DAW editor — BLOCKED on a [needs-engine] contract for @tracker-replayer:** instrument `toJson`/`fromJson` (`SampleInstrument` base64 PCM / `SfxrInstrument` params / `MultiSampleInstrument` zones in `tracker_engine.dart`/`multi_sample_instrument.dart`) so a persistent `SoundLibraryService` can save/load sounds across sessions. Screen-side (the DAW editor UI, the library picker, `MultiSampleInstrument` surfacing) is mine once serialization lands. 🚧 **AUDIO ARC claimed (idea doc §E) — doing all three, risk-ordered, coordinated here:** ✅ **(E2) pure-Dart MP3 port STARTED — slice 1 SHIPPED (`9ddd77d`):** all-platforms compressed export = a PURE-DART MP3 encoder (glint FFI is native-only, no web). `lib/core/audio/mp3/` — `Mp3BitWriter` (MSB-first, ported byte-for-byte from glint's clean-room MIT `BitstreamWriter`) + MPEG-1 Layer III frame header/tables/framing, unit-tested against known values (128k/44.1k = FF FB 90 04, etc.; 8 tests). ✅ **slices 2-4 SHIPPED (subband, MDCT, quantizer) + VALIDATED vs glint:** a glint C++ reference harness (`bench/glint_ref.cpp` + `bin/mp3_bench.dart`, same LCG input) shows the Dart DSP is **machine-equivalent** to glint — subband max abs err 5.3e-15, MDCT 6.7e-16 (relative ~5e-16, the double floor; NOT literally bit-identical only because glint builds `-ffast-math`/FMA). Speed: glint ~95,640 granules/s vs Dart JIT ~4,000 (~24x slower, still ~52x realtime; release=AOT). `test/mp3_golden_test.dart` pins glint's values in CI. **Remaining: Huffman + reservoir + frame assembly → wire `mp3Encode` into `music_export.dart`.** **Remaining slices (staged DSP): subband filter → MDCT → quantize → Huffman+reservoir → frame assembly → wire `mp3Encode` into `music_export.dart`.** ✅ **(E1) isolate render SHIPPED (first cut):** the Loop Mixer WAV export now renders on a worker isolate (`Isolate.run`) — sends only the small serializable `GrooveSpec` (not the engine + stem cache), rebuilds `LoopEngine()..applySpec` + `renderLoop()` in the worker, so exporting a long groove never freezes the frame. The LIVE in-phase loop re-render stays SYNCHRONOUS on purpose (async would break phase-sync, and a sample-heavy song's send-copy has its own cost — documented in §E). Same pattern applies to module/tracker exports (follow-up). **(E2) glint MP3/AAC/Opus export** — add the `glint_audio` FFI dep + wire it into the shared export sheet (native dep → verify CI/build). **(E3) real-time multi-track engine** (`flutter_soloud`/miniaudio) — live faders w/o re-render; a LARGE core swap of `audioplayers`+offline-WAV, staged/scoped, done last. Worktree `../mus-trk-ui`. **Interconnect follow-ups (unclaimed):** Drumkit→Loop-Mixer/Tracker (`DrumRowsPattern` is shared), more `Drum` voices [needs-engine]. **REMAINING after: D4 Drumkit/BoomBox (new screen: studio pad + step grid over the shared `DrumRowsPattern`; more Drum voices = [needs-engine]) · D2 sample LIBRARY + DAW instrument editor (biggest; needs a [needs-engine] instrument toJson contract for the persistent store).** ~~**REMAINING: wire `showMusicExportSheet` into My Melody / Free Sing / Loop Mixer (each has a score); refactor Advanced tracker export to the shared sheet (optional).** **THEN: C-fan-out (broaden Advanced import/export, Song Book export, Loop Mixer / My Melody / Free Sing I/O via a shared `MusicIoMenu` — HOT shared screens) · in-grid instrument hex column.** **[needs-engine] items (B2b PCM-preserving Advanced .mod export, B2c serializable sound+share token, B2d MultiSample surfacing, maybe a `setCellInstrument`) are FILED FOR @tracker-replayer, not done here.** SCREEN-SIDE only (`advanced_tracker_screen.dart`/`tracker_screen.dart`/`home_screen.dart`+ARBs+docs); the enablers `resolveTimingMap`/`rowIndexAtMs`/`TrackerSong.instruments` are already shipped by @tracker-replayer. Still **HANDS OFF `tracker_song.dart`/`tracker_engine.dart`/`mod/*`** (his). Worktree `../mus-trk-ui`, branch `feature/tracker-ui`. ✅ **idle / SHIPPED so far — Advanced Tracker UX + export + Workshop bridge + GUI polish batch.** SEPARATE worktree `../mus-trk-ui` (branch `feature/tracker-ui`) — do NOT point another agent here (the shared `../mus-tracker-adv` collided with the replayer agent). ✅ **SHIPPED (`4de60a9`):** cursor-follow scroll, undo/redo, Save-to-Song-Book spans the whole song (fixed "place some notes first"), removed redundant app-bar Play-song, Clear-confirm, key-hints toggle, "···" tooltip. ✅ **SHIPPED (`bf5656b`): export menu + two-way Score-Workshop bridge** (all over the whole song via the order list): **Export MIDI** (`multiPartToMidi`, format-1 SMF) + **Export MusicXML** files; **Open in Score Workshop** (`CompositionWorkshopScreen` gains an additive `initialScore`/`initialNames` param → `MultiPartDocument.fromMultiPartScore`); **Import score (MusicXML/MIDI)** → new tracker song, 1 chromatic track/part (`multiPartScoreFromMusicXml`/`multiTrackMidiToMultiPart` → `scoreToChannels`, `snapToScale:false`). Refactored into one `_songMultiPart()` shared by Save/Export/Open; `debugExportMidi/MusicXml` seams; 4 EN/DE keys. analyze clean; 19 advanced + 63 workshop tests green. ⚠️ `importMultiPart` is `@visibleForTesting` — used the public `multiPartScoreFromMusicXml`/`multiTrackMidiToMultiPart` instead. ✅ **SHIPPED (`197ff23`+`1bebc35`): FT2-feel batch** (all screen-side, disjoint from the replayer's `tracker_song.dart`): **live record** (⏺ — notes land at the playhead while playing, preserving that cell's vol/fx); in-grid **field cursor** (Tab/Shift+Tab or the ♪/vol/fx button cycle note/vol/fx; hex 0–F in the volume field sets the note's volume; effect field opens the command editor; active column underlines); **interpolate** volumes across a selection (Block menu · Ctrl+I); two-level **row highlights** (beat + measure); Ctrl+Z/Y; **note preview** on entry (hear notes as you type, edit mode). +6 EN/DE keys; analyze clean; 21 advanced tests. ✅ **SHIPPED — "FT2 workflow" batch (SCREEN-ONLY, disjoint from @tracker-replayer):** (1) `f626b47` **FT2 function-key transport** — F5 song · F6 pattern · **F7 play-from-cursor** · F8 stop, in the ⓘ legend. (2) `7f9b692` **editable order list** — select a slot (outlined) + move ◀▶ + insert-copy + delete + retarget ▲▼ (mutates the public `_song.order` directly, no model file). (3) `6f38bf1` **metronome** (`AudioService.playTick` on beat crossings) + **FT2 2-digit hex volume column** (00–40 → 0–64, hex cell display, accumulator resets on move). Each its own commit; 24 advanced tests green; analyze clean. ✅ **SHIPPED (`345e7bf`): authoring UI for the FULL effect-command set** — now that @tracker-replayer plays them. `_CommandEditor` lists every command (arp/porta/tone-porta/vibrato/combos/tremolo/vol-slide/set-vol/jump/break/speed-tempo/extended) + 00–FF param + live hex readout; the in-grid **effect field is directly typeable** (FT2: cmd nibble then 2 param digits, resets on move; Backspace clears) — completing the note/vol/fx field cursor; ⓘ legend gained an effect cheat-sheet. Used canonical MOD nibbles (imported nothing from `tracker_replayer.dart`). Tester seams typeEffect/effectAt; 25 advanced tests; analyze clean. **The tracker now has FULL effect commands END-TO-END** (replayer plays · UI authors). ✅ **SHIPPED (`f5b86bd`): module EXPORT in the GUI** — the tracker overflow now has **Export module (.mod/.xm/.s3m/.it)** via `_songMultiPart`→`multiPartToModuleDoc`→`convertDocTo`→save (public lib fns; no model/engine). Round-trip tested through all four formats. NB via the Score path it carries notes+structure+a generated sample timbre; the authored effect COLUMN isn't in the Score so effects drop (documented). **Conversion coverage now complete in the GUI:** tracker ⇄ module (import + export), tracker → MIDI/MusicXML/SongBook, tracker ⇄ Score Workshop. ✅ **SHIPPED (`a207799`): Tracker as a Workshop MODE, not a game tile** — per feedback, reverted the `tracker_advanced` GameInfo/concept_map; the **home Workshop button (piano) is now a DROPDOWN**: "Score Workshop" (default) / "Advanced Tracker". Reachable: home dropdown + Beginner-tile switch + Workshop overflow entry. Touched shared `home_screen.dart`+`game_registry.dart`(reverted)+ARBs — additive, rebased. coverage/consistency/home tests green. ✅ **SHIPPED — GUI polish batch (SCREEN-ONLY `advanced_tracker_screen.dart`+ARBs; user-picked all 4), all four done, each its own commit:** **(1)** insert/delete row at the cursor + loop-a-selection while playing + follow-scroll toggle. **(2)** `32faa77` classic-tracker LOOK (dark/mono/colour-coded-notes skin) + grid ZOOM (A−/A+). **(3)** `6ff491a` master OSCILLOSCOPE strip (`_scopeStrip` paints `engine.renderLoopPcm()`, cached via `_scopeDirty`, red playhead on the `_row` notifier; toggle in the transport row) + built-in **demo song** loader (`_loadDemo` — a two-pattern call/response groove via the public `TrackerSong` API; overflow menu). **(4)** `fc72a5b` waveform SAMPLE editor in the record sheet — `_SampleWaveform` (peak-per-column render + two drag/tap trim handles, kept region bright / cropped tails dim) + pure non-mutating `sliceFraction(pcm,start,end)` applied first in `_sampleFrom`. 34 advanced tests green (incl. 4 `sliceFraction` unit tests + scope/demo widget tests); analyze clean throughout. ✅ **idle — batch COMPLETE.** **HANDS OFF for @tracker-replayer:** the MODEL/ENGINE parity gaps are YOURS — per-cell instrument column, per-pattern variable length, full effect-command set (your phases 2/3), volume/pan envelopes, panning; I will NOT edit `tracker_song.dart`/`tracker_engine.dart`. Worktree `../mus-trk-ui`, branch `feature/tracker-ui`. **DO NOT reuse `../mus-tracker-adv`** (collided with replayer agent). 🚧 **NOW ACTIVE — pure-Dart MP3 encoder (all-platforms audio export) quality pass.** The port ships (`lib/core/audio/mp3/*`, 38 tests, ffmpeg-decodable). A/B vs glint on glint's OWN harness (`bench/ab_vs_glint.py` + `bin/mp3_encode_cli.dart`) shows: DSP front-end machine-equivalent (subband 5e-15, MDCT 7e-16), ~3–4× slower JIT (still 28× realtime), but SNR 8 vs 32–37 dB and audible noise (NMR>0 in 66% of Bark bands) because the first cut has **zero scalefactors + no reservoir**. Ported glint's real masking model (`compute_band_masks`) + the NMR scalefactor/noise-shaping outer loop (`mp3_psycho.dart`+`mp3_shape.dart`), verified stage-by-stage against frozen glint fixtures. ✅ **SHIPPED** (`62d4e02`). **Found + fixed the real bug: MPEG frequency inversion** — glint's encoder uses `MDCT::process_strided` (negates odd subbands at odd time slots); we matched plain `process()` and omitted it, so odd subbands decoded spectrally flipped (self-consistent 35 dB MDCT recon but 8 dB decoded audio; band-0 tones masked it). 3-line fix → glint's `measure_audio.py` (speech 128k): **SNR 8→35.2 dB, beating glint's 32.1**; sweep 1.8→78 dB. ffmpeg-gated regression `test/mp3_decode_roundtrip_test.dart`. ✅ **EXTRACTED to a pub package `glint_audio_pure`** (pure-Dart, all-platforms sibling of FFI `glint_audio`) at `CrispStrobe/glint` `bindings/dart_pure/`, branch `feature/dart-pure-mp3` — publish-ready (0 dry-run warnings), owner merges+publishes. ✅ **Huffman region optimizer SHIPPED** (`4002271`, glint's `huffman_select_and_count` + pair-cost LUT + `Mp3HuffRegions.bits`): NMR −5.8→−6.7 dB on speech, count1-tail round-trip drift fixed, ~1.6× realtime JIT. Remaining NMR gap to glint = the bit reservoir (next lever). ✅ **MP3/WAV audio export WIRED** (`d16d936`) into Loop Mixer ("Save audio"→WAV/MP3 picker), Advanced Tracker (export-menu "Export audio"), Drumkit (download button) — reusing the shared `showAudioExportSheet`; MP3 now exports on ALL platforms incl. web. Package `glint_audio_pure` synced with the optimizer (branch `feature/dart-pure-mp3`, owner merges+publishes). Files touched: `lib/core/audio/mp3/*`, `bench/*`, `test/mp3_*`, + `loop_mixer_screen.dart`/`advanced_tracker_screen.dart`/`drumkit_screen.dart` (audio-export wiring only, no l10n/registry changes).
- **opus (tracker-replayer)** · 🚧 **ACTIVE — effect-command phases 2 & 3 (the tick-based MOD replayer).** Own worktree `../mus-replayer`, branch `feature/tracker-replayer` (off `origin/main`; picks up phase-1 effect columns `3e7e62e`). This is the "Remaining effect-command phases" the tracker-adv entry below scopes — claimed here so we don't both start it. ✅ **Phase 2 (PITCH commands) SHIPPED locally (not yet pushed):** new Flutter-free `lib/core/audio/tracker_replayer.dart` — a tick-level state machine (`ReplayVoice`: per-channel pitch/volume/LFO/effect-memory across ticks) + a phase-accumulating additive oscillator, implementing **0xy arp · 1xx/2xx porta · 3xx tone-porta · 4xy vibrato · 5xy/6xy combos · 7xy tremolo · Axy/Cxx (migrated per-tick)**. Emits `ReplayResult{pcm, timing}` (row-timing map built now, wired in phase 3). **Trap A solved:** voices sum at fixed-normalized amplitude × gain → tanh (NOT unit-peak per stem), so Cxx/tremolo are audible; gated to the replayer. `tracker_song.dart` gains `usesCommands` → `renderSongWav`/`renderCurrentPatternWav` route through `replaySong`/`replayPattern` when commands present, else the untouched offline path. Non-additive channels fall back to offline whole-channel render (unit-peak×gain). **13 trajectory+audio tests** (`test/tracker_replayer_test.dart`) — pure per-tick pitch/volume trajectories pin every command; audio acceptance via `bin/listen.dart` reads a C4→C5 tone-porta glide that lands exactly at C5/0¢ and a plain scale at 0¢. analyze clean; 40 tracker tests green. ✅ **Phase 3 (FLOW: Bxx jump + Dxx break) SHIPPED locally too:** `walkFlow(song)` expands order→pattern→row under the flow rules (Bxx position-jump wins the order, Dxx pattern-break sets the landing row via the classic *decimal* param; both on one row → jump order + break row) into the exact played row sequence, guarded by a `maxRows` cap so a backward Bxx loop terminates. `replaySong` routes flow songs through `_replayFlow`, which **flattens** the played rows into one long column per channel and renders through the same per-channel path — so pitch commands AND non-additive voices stay aligned with the reordered timeline. `tracker_song.dart` `songTotalMs` is now flow-aware (resolved played length, no-flow path short-circuits allocation-free) so the transport loops/stops correctly. +7 flow tests (exact played-sequence asserts + guard cap + length); real `bin/listen.dart` acceptance: a D00 break truncates a scale to C4 D4 E4 F4 then jumps to pattern 1's C3 (rows 4–7 correctly skipped). **20 replayer tests + 84 tracker tests green, analyze clean.** ✅ **Exy extended + E6x pattern-loop SHIPPED too:** in the tick state machine — **E1x/E2x fine porta** (one-time pitch bump), **EAx/EBx fine volume**, **ECx note cut** (volume 0 at tick x), **EDx note delay** (deferred trigger at tick x — `tick()` now returns a `retrigger` flag; the audio renderer restarts the envelope + skips pre-delay silence per tick), **E9x retrigger** (re-trigger every x ticks); and in `walkFlow`, **E6x pattern loop** (E60 marks the start, E6x repeats the span x extra times, counter state, guarded by the same `maxRows` cap). `songUsesFlow` now also catches E6x. +7 extended tests (trajectory + retrigger-flag + walkFlow sequence); real `bin/listen.dart` acceptance: an EDx note delayed to tick 5/6 stays silent until its onset (~0.19 s) then reads a clean C4/0¢. **27 replayer + 91 tracker tests green, analyze clean.** ✅ **Import MOD effects (handover §7) SHIPPED:** imported `.mod` files now PLAY their effect column instead of dropping it. `DocCell` gained `effect`/`effectParam`; `docFromMod` carries `ModCell.effect/effectParam` (MOD's nibble maps **1:1** onto our `fxCmd`/`fxParam` since our command set is modeled on MOD); `_patternFromDoc` emits a `TrackerCell` with `fxCmd`/`fxParam` for a note **or** an effect-only cell (so slides continue on a ring) → the imported song `usesCommands` → routes through the replayer. MOD carries all 0x0–0xF effects; XM too (its main effect column shares MOD numbering — the letter effects G+ that exceed a nibble are dropped). S3M/IT keep 0 (letter-command numbering — the cross-format table stays a follow-up). +2 tests (precise doc→cell mapping incl. effect-only cells + render; golden.mod carries every parsed effect and invents none); module_convert/notation suites green (no regression from the DocCell field add). ✅ **Fxx SET-SPEED SHIPPED:** `songInitialSpeed(song)` reads the first `Fxx` (param `<0x20`, ticks/row) in play order; `replaySong`/`replayPattern` use it as the render's `ticksPerRow` (effect granularity) — so an imported/authored module replays at its authored speed. Timing-SAFE: speed subdivides the row (tickMs = rowMs/ticksPerRow) so it does NOT change row duration → no `songTotalMs`/non-additive rework. +2 tests (helper reads speed / ignores tempo+none / honours fallback; the speed provably changes the vibrato render at identical length). 100 tracker tests green, analyze clean. Fxx-**tempo** (param `≥0x20`) stays a follow-up: the module's initial tempo is already applied at import; mid-song tempo changes need the per-row-duration rework. **Remaining (follow-ups):** Fxx set-tempo + mid-song speed/tempo changes (per-row duration rework), ✅ 9xx sample-offset SHIPPED (SampleInstrument.renderChannel starts at param×256; +test), the S3M/XM/IT cross-format effect table; and **wire the Advanced playhead to follow jumps** — ✅ **enabler now shipped for the tracker-ui agent:** pure `resolveTimingMap(song)` returns the flow-resolved `(startMs, orderIndex, patternIndex, row)` sequence WITHOUT rendering audio (same map as `replaySong().timing`, proven equal in a test), and `rowIndexAtMs(map, ms)` binary-searches it. **@tracker-ui:** replace the fixed-length playhead math in `advanced_tracker_screen.dart` (~L310–319: `_playingOrder = pos ~/ t.totalMs`) with `final map = resolveTimingMap(_song)` (once, at play start) + `final e = map[rowIndexAtMs(map, elapsed % _song.songTotalMs)]` → `_playingOrder = e.orderIndex; _row = e.row`. That's the whole change; the engine side is done. Also author the new commands (0/1/2/3/4/7/B/D/E/F) in the screen's `_CommandEditor` + ⓘ legend + ARBs. ✅ **Fxx SET-TEMPO SHIPPED (initial value).** `songInitialTempo(song)` reads the first `Fxx` (param `≥0x20`, BPM) in play order; `effectiveTiming(song)` applies it, and `replaySong`/`_replayFlow`/`resolveTimingMap` + `tracker_song.dart` `songTotalMs` all use it, so the render length, the playhead map and the transport all agree (uniform tempo — no per-note rework). +2 tests (helper reads tempo/ignores speed+none; render length + songTotalMs match the Fxx tempo and differ from base). 104 tracker tests green, analyze clean. ✅ **PER-CELL INSTRUMENT COLUMN SHIPPED (additive).** `TrackerCell.instrument` (1-based into the new `TrackerSong.instruments` pool; default pool = the 4 additive voices) + `TrackerSong.usesInstruments` routes such songs through the replayer. The replayer's additive voice switches timbre when a cell names an additive pool instrument (persists per channel, tracker-style) — so one channel can play piano then flute; `_renderChannelInto` gained a `pool` param + a `_timbreParamsOf` helper. +2 tests (default pool = 4; a cell instrument makes note 2 render a different timbre while note 1 stays byte-identical). 106 tracker tests green, analyze clean. **@tracker-ui:** `TrackerSong.instruments` is the pool to expose in the UI (an instrument column / picker). ✅ **PER-NOTE NON-ADDITIVE RENDER SHIPPED → per-cell instrument on SAMPLE voices + imported modules play the right sample per note.** New public `renderChannelPerNote(channelInstrument, cells, timing, pool)` renders a non-additive channel note-by-note, each note played by its effective instrument (channel default, or `pool[cell.instrument-1]` — sample/sfxr too, persists per channel). Each note is rendered over its EXACT run via a dummy cap-trigger, so it's **BYTE-IDENTICAL** to the whole-channel render when the instrument doesn't change (pinned by a regression test). `_renderChannelInto` uses it only when the channel has per-cell instruments (else the unchanged fast whole-channel path). **Module import now wires it:** `songFromModuleDoc` builds the pool from ALL the module's samples (1-based, matching `DocCell.instrument`) + `_patternFromDoc` carries `TrackerCell.instrument`, so an imported `.mod/.xm` plays each note's own sample instead of one voice per channel. +3 tests (byte-identical guard; a cell plays a different pool sample; import builds the pool + carries per-cell instrument, none invented). 138 tracker/module tests green, analyze clean. **@tracker-ui:** `TrackerSong.instruments` is now the real per-note pool for imports too. ✅ **Also fixed:** `setCellVolume`/`setCellEffect` (engine) + `transposeBlock` (song) reconstructed cells and DROPPED `fxCmd`/`fxParam`/`instrument` — now that those columns carry real data that was silent corruption on a volume/effect edit or a block transpose; all three preserve every field (+2 tests). 🚧 **NOW ORCHESTRATING the three remaining engine-parity features via parallel Opus agents, contract-first.** Contracts + acceptance-test invariants: **`docs/TRACKER_ENGINE_CONTRACTS.md`** (I own it + one independent acceptance test per feature = the gate). **A — mid-song tempo/speed changes** (per-row duration; worktree `../mus-tempo`, branch `feature/tracker-midsong-timing`). **B — per-pattern variable length** (worktree `../mus-patlen`, branch `feature/tracker-pattern-length`). **C — stereo output + panning + (stretch) vol/pan envelopes** (worktree `../mus-stereo`, branch `feature/tracker-stereo-pan`). Each agent works ONLY in its sibling worktree, must NOT push to main, and implements to pass its `test/*_acceptance_test.dart` (which it must NOT edit). I integrate sequentially with my tests as gates and rebase before each push. ✅ **B (per-pattern length) INTEGRATED to main (`2cad762`)** — passed my acceptance gate + 84 tracker tests, analyze clean. A + C still running; will rebase them onto main-with-B (they overlap in walkFlow/replaySong — I merge the semantics). @other-agents: these three touch `tracker_replayer.dart`/`tracker_song.dart`/`tracker_engine.dart`/`synth.dart` — please don't edit those engine files until integration lands. ✅ **Fixed both @audit bugs first (so the agents branch off correct code):** (1) HIGH `6xy` was reparsing its param as vibrato speed/depth — split out so `6xy` only sets `_memVolSlide` and CONTINUES the vibrato with existing memory; (2) MEDIUM `EDx` reset `noteStartSample` at row-arm for a pending delay, re-attacking a still-ringing prior note — now only a real trigger resets it at arm, the delayed note sets its own start+run when it fires. +3 regression tests; analyze clean. Thanks @audit. Refactor the replayer's non-additive channel branch (`_renderChannelInto` in `tracker_replayer.dart`, MINE) from one whole-channel `renderChannel` into a per-NOTE render: walk the runs, render each note with its EFFECTIVE instrument (channel default, or the per-cell pool instrument — sample/sfxr too), place into the channel stem, then unit-peak × gain as today. **Guarded by a byte-identical regression test** for the single-instrument, instrument-0 case (must match the current whole-channel render), so the tested sample path can't silently regress. Then wire module import (`_patternFromDoc` → `TrackerCell.instrument`, pool from the module's samples). Only touches `tracker_replayer.dart` + later `tracker_song_module.dart`/`mod/*` (all mine). **Follow-on (was: needs per-note NON-additive render):** per-cell instrument on SAMPLE voices, so imported modules pick the right sample per note; then wire module import (`_patternFromDoc` → `TrackerCell.instrument`, pool from the module's samples). **Other follow-ups:** mid-song speed/tempo CHANGES (per-row duration rework), ✅ 9xx sample-offset SHIPPED (SampleInstrument.renderChannel starts at param×256; +test), the S3M/IT cross-format effect table (verify vs a libopenmpt oracle). Files touched (all engine/import, **no screen/ARB edits**): `tracker_replayer.dart` (new), `tracker_song.dart`, `mod/{module_doc,module_convert}.dart`, `tracker_song_module.dart`. ✅✅✅ **ALL THREE INTEGRATED to main:** B per-pattern length (`2cad762`), C stereo+panning (`75650bb`), A mid-song tempo/speed (`7b95567`). Each passed my independent acceptance gate; I hand-merged the walkFlow/replaySong semantics (walkFlow now does per-pattern rows AND per-row Fxx tempo/speed) and built `_replayVariableStereo` so the full triple composes — a **cross-feature test** (variable length + mid-song tempo + hard-left pan → 2-channel, panned, summed-per-row length, transport agrees) is green, alongside all 3 acceptance suites + the full tracker suite; analyze clean. New APIs for -ui: `TrackerSong.setPatternRows`, `TrackerChannel.pan`/`setChannelPan`, `usesPan`; `mixStemsStereo`/`wavBytesStereo`; per-row `PlayedRow.tempoBpm`/`ticksPerRow`. ✅ **VOLUME ENVELOPE SHIPPED (the STRETCH).** New `VolumeEnvelope(points: List<({int ms, double level})>)` (linear interp, hold-last) + `TrackerChannel.volumeEnvelope` (nullable = no change) + `TrackerEngine.setChannelVolumeEnvelope`, applied as a per-note level multiplier in the replayer's additive voice (both the uniform `_renderChannelInto` and the variable `_renderChannelIntoVariable`, so it propagates to stereo too). No envelope = byte-identical (regression-tested). Touches `tracker_engine.dart` + `tracker_replayer.dart` (mine). +3 tests (levelAt interp/hold; a fade-out envelope is quieter at the note end; a flat envelope is byte-identical). 113 tracker tests green, analyze clean. ✅ Volume envelope now covers NON-ADDITIVE (sample/sfxr) voices too — renderChannelPerNote + the variable path post-multiply each note by the envelope before unit-peak (shape preserved); null/flat = byte-identical (guard test). ✅ **PAN ENVELOPE SHIPPED too** — `PanEnvelope` + `TrackerChannel.panEnvelope` + `setChannelPanEnvelope`; the stereo render auto-pans each note per-sample from its onset (base pan + envelope, clamped; takes precedence over 8xx). `usesPan` catches it. +2 tests (panAt interp; a −1→+1 sweep shifts the stereo energy left→right over the note). **The tracker engine parity roadmap is now FULLY CLOSED** (both envelope types across additive + sample voices; only a variable-timing pan-envelope combo is an ultra-niche follow-up). ✅ **S3M mapping + libopenmpt oracle SHIPPED (`4fe52ac`); oracle FOUND the real gap** — ✅ **SAMPLE TICK VOICE now BUILT** — `_renderSampleChannelInto` (resampling read-pointer with per-tick pitch/volume; gated by `_hasPerTickEffect` so effect-free sample channels stay byte-identical). Oracle-verified: the porta S3M now RISES in ours (A3→C4→G4→C5) matching openmpt123. So imported MOD/XM/S3M porta/vibrato/tremolo/Cxx/Axy now SOUND on sampled channels. +test; 127 tracker tests green. See docs/ORACLE.md. ✅ **IT mapping DONE + oracle-verified** (near-identical to openmpt123). **Cross-format effect import COMPLETE (MOD/XM/S3M/IT all carry + SOUND their effects).** ✅ **SAMPLE LOOP POINTS SHIPPED (`f8c37b6`) — oracle-verified.** `SampleInstrument` carries `loopStart`/`loopLength` (scaled to the engine rate in `sampleInstrumentFromDoc`); looping notes render through a wrapping read-pointer (`_resampleLooping` on the whole-channel path + an inline wrap in the per-tick sample voice), so imported MOD/XM/S3M/IT samples with a loop now SUSTAIN across a held note instead of dying after one sample length; non-looping samples (loopLength 0) keep the byte-identical one-shot path. **Oracle-verified vs openmpt123:** a looping-sample S3M sustains flat across the whole held note in BOTH ours and the reference (per-0.2s RMS ≈ constant), while the same sample with the loop flag OFF decays to silence after one sample length in both. +2 engine tests; analyze clean. ✅ **VARIABLE-TIMING SAMPLE PER-TICK SHIPPED (`a0e2c2d`)** — the last replayer gap. A sample channel with per-tick effects AND a mid-song tempo/speed change (or per-pattern length) now renders through `_renderSampleChannelIntoVariable` (variable-span sibling of the uniform sample tick voice) instead of one-shot-per-note; effect-free stays on the cheap path. Also verified `songTotalMs`/`resolveTimingMap` ARE already mid-song-tempo-aware (onsets go non-uniform after the change) — the old "timing map not tempo-aware" note was stale/screen-side, not an engine bug. +1 test. **NO KNOWN REPLAYER FOLLOW-UPS REMAIN.** ✅ **ORACLE A/B HARNESS SHIPPED (`b52597c`)** — `bin/oracle_ab.dart`: renders a module through OUR import+replay AND `openmpt123`, runs our pitch detector over both, prints per-side note trajectory + pitch-class overlap + voiced fraction + glide direction + a PASS/CHECK verdict. `--selftest` synthesizes a scale S3M and A/Bs it (PASS). This is how we test audio-output correctness against another implementation; dev-only (needs openmpt123). ✅ **SOUND LIBRARY — ENGINE SLICE 1 SHIPPED (`457aa41`): Karplus-Strong plucked strings.** New `crisp_dsp/karplus.dart` (pure KS pluck) + `KarplusInstrument` (TrackerInstrument) + `pluck`/`harp`/`pluckBass` registered in `kTrackerInstruments` — the built-in sound library is now **4 additive + 7 sfxr + 3 plucked**, all sample-free/zero-license, all pool-instrument-ready. Pitch exact (autocorrelation = sr/freq ±3 samples); +4 tests. **Sound Library plan (from a licensing survey — see below):** the tracker already plays additive/sfxr/recorded/sample instruments; `kTrackerInstruments` (in `tracker_engine.dart`, MINE) is the catalog seam any picker/browser enumerates. **Licensing (researched):** bundle-safe = **CC0/MIT** (VCSL & VSCO2-CE CC0 orchestral one-shots; Boochi44/tidalcycles CC0 drum hits; FluidR3_GM/Mono **MIT** soundfonts) and **CC-BY with a credits screen** (Salamander piano; Freesound CC0/CC-BY filtered). **HARD-BLOCK (redistribution-forbidden or NC):** Sonatina (CC Sampling+ = NC), Philharmonia ("not as samples"), 99Sounds ("no sound apps"), generic "royalty-free" 808 packs. Trademark hygiene: label drum-machine samples generically ("Analog Kick"), never "Roland/TR-808". ✅ **SLICE 2 SHIPPED (`855758f`): categorized library** — `SoundCategory{tonal,plucked,chiptune,drum,recorded}` + `soundCategoryOf()` + `soundLibraryByCategory()` (the Song Book-style browsing seam). ✅ **SLICES 3–5 ALL SHIPPED (user-approved all three):** (3) **procedural FM + subtractive** (`7af0250`, `crisp_dsp/fm.dart`+`subtractive.dart` + `FmInstrument`/`SubtractiveInstrument` — ePiano/fmBell/fmBass + pad/lead/synthBass; the library is now **20 sample-free voices**: 4 additive + 7 sfxr + 3 plucked + 3 FM + 3 subtractive); (4) **bundled CC0 percussion** (`7652570`, `assets/sounds/percussion/{snare,rim,shaker,clave}.wav` from **VCSL, SPDX CC0-1.0 machine-verified**, 16-bit mono ~76KB + LICENSE.txt; `sound_library.dart` `BundledSampleInfo`/`sampleInstrumentFromWavBytes`; chose VCSL over Boochi44 [no license file] + Dirt-Samples [mixed]); (5) **SoundFont `.sf2` parser** (`49a46e5`, `sf2/sf2.dart` `Sf2SoundFont.parse`→samples w/ root-key+loops→`SampleInstrument`; verified on a real 520-sample TimGM6mb.sf2; uncompressed .sf2 only — .sf3/OGG + GM preset-zone graph are documented follow-ups; MIT FluidR3_GM.sf2 is the compatible bundle target, not committed [140MB → on-demand decision]). Each +tests, analyze clean. **@tracker-ui: the browser UI** over `kTrackerInstruments`/`soundLibraryByCategory()`/`kBundledPercussion` (audition + drop into a slot) **is yours.** ✅ **ROUND 2 ALL SHIPPED (user "do it all"):** (b) **SF2 GM preset→zone mapping** (`b7bd45e`) — `Sf2SoundFont.parse` now walks phdr/pbag/pgen→inst/ibag/igen→shdr into `Sf2Preset`s (bank/program/name + key-split `Sf2Zone`s); `Sf2Instrument` (TrackerInstrument) picks the covering zone per note + resamples from its root key with the sample loop = a real multi-sample GM voice; `sf2InstrumentFromPreset()`. **Verified on real TimGM6mb.sf2: 136 GM presets** (Flute TB=10 zones, drum kits at bank 128). (a) **On-demand SoundFont download** (`f43a5f7`) — `sf2/sf2_remote.dart`: `downloadSoundFont(source, fetch:, cache:)` (injectable `ByteFetcher`+`SoundFontCache` seams) with an `isPermissiveLicense()` gate that refuses NC/ND/ARR/GPL BEFORE fetching; `kFluidR3Gm` (MIT, ~140MB, configurable mirror) — avoids bundling. +6 tests via a shared `test/sf2_fixture.dart` writer. (c) **UI contract HANDED OFF → `docs/SOUND_LIBRARY_UI_CONTRACT.md`** for **@tracker-ui**: the Song Book-style browser (browse by `SoundCategory` · audition via `renderChannel`→your `_samplePreview` player · "Use" → `TrackerSong.instruments`/`setChannelInstrument`) over `kTrackerInstruments`/`soundLibraryByCategory()`/`kBundledPercussion`/`Sf2SoundFont`. **@tracker-ui: the browser screen is yours — engine APIs are frozen; HANDS OFF `tracker_engine.dart`/`tracker_song.dart`/`sf2/*`/`sound_library*.dart`.** ✅ **SF2 END-TO-END VERIFIED + tuning fix (`e68314d`):** real-soundfont pitch check (TimGM6mb) via the app's detector — sustained voices play in tune (Reed Organ **2.6¢** across all 20 zones, Flute 6.2¢, Sax 4.6¢; Piano reads higher only from real inharmonicity + attack, not a bug → key-split root selection is correct). Found + fixed a latent gap: the reader dropped each sample's shdr `chPitchCorrection` (byte 41) — now read + baked into the resample (fonts like FluidR3 use it; TimGM6mb happens to be all-zero). **Sound Library engine work is COMPLETE + VERIFIED:** 20 procedural voices + CC0 bundled percussion + full `.sf2` GM soundfonts (parse + preset-zones + pitch-correct tuning + on-demand download). ✅ **MORE SF2/SF3 SHIPPED + real-data verified:** (i) **per-zone generators** (`7129c16`) — initialAttenuation (gen48 → linear `.gain`), coarse/fine tune (gen51/52 → baked into the zone resample on top of the sample's `chPitchCorrection`); `Sf2Instrument` scales each note by the zone gain. **On real TimGM6mb: of 2063 zones, 1764 carry attenuation + 1717 carry fine tune** — so this materially fixes level balance + tuning for ~85% of real GM zones (not cosmetic). 136 presets still parse (no regression). (ii) **`.sf3` detection** (`9994227`) — `.parse` throws a clear catchable error on the `OggS` magic; `sf2IsCompressed(bytes)` pre-check for the UI (`sf2IsCompressed(TimGM6mb)=false` verified). +5 tests. **The concurrent verification AGENT** (real-data oracle A/B breadth + procedural-voice pitch + bundled-sample checks, fenced OFF `sf2/*`) is still running — findings will be actioned when it reports. **`.sf3` DECODE — path chosen:** our own **glint** codec suite (MIT, `~/code/glint`) has MP3/AAC/**Opus** + Dart(FFI)+wasm bindings but **no Vorbis** (`.sf3` = Ogg Vorbis; glint's `detect()` even maps OggS→Opus). So `.sf3` needs a clean-room **Vorbis decoder added to glint** — spec'd in **`docs/GLINT_VORBIS_HANDOVER.md`** (contracts: C ABI `glint_vorbis_decode` + `detect()` Vorbis/Opus split + Dart/wasm bindings; test harness: decode-vs-ffmpeg+libvorbis ≥120 dB, real FluidR3Mono.sf3 end-to-end + fuzz; DoD). The CometBeat-side integration (a platform seam in `sf2.dart` calling glint native/wasm) is the follow-up once glint ships Vorbis. 🚧 **An Opus 4.8 agent is executing the handover in `~/code/glint`** (branch `feature/vorbis-decoder`, incremental clean-room build + ctest gates; won't touch glint `main` until DoD met). ✅ **CometBeat SIDE READY (`200f497`):** `Sf2SoundFont.parse(bytes, {VorbisDecode? vorbis})` — a `.sf3` now extracts each sample's `smpl[start,end)` Ogg-Vorbis stream and decodes via the injected `VorbisDecode` seam (verified on the REAL FluidR3Mono.sf3: 1186 streams all begin `OggS`, 197 presets; loop points are decoded-frame positions, no `-start`). **Only the actual decoder wiring remains** — a platform seam that plugs glint's `glint_vorbis_decode` (native FFI / web wasm) into `vorbis:` once glint ships it. +2 tests (synthetic .sf3 + fake decoder). ✅ **END-TO-END HARNESS + PROOF (`b8fbea4`):** `bin/sf3_oracle.dart` plugs a REAL Vorbis decoder (**ffmpeg**, stand-in) into the seam → on the real FluidR3Mono.sf3, **Synth Strings 2 plays at 2.9¢** (in tune, matching the .sf2 bar). So the CometBeat `.sf3` side is PROVEN correct with a real decoder — this same harness is the **acceptance gate for glint** (swap ffmpeg→`glint_vorbis_decode`, pitch must match + per-stream SNR high). Documented in docs/ORACLE.md. ✅ **GLINT VORBIS DECODER SHIPPED + INDEPENDENTLY VERIFIED:** the Opus 4.8 agent delivered an end-to-end clean-room Ogg-Vorbis I decoder (glint `feature/vorbis-decoder`, 5 slices); I built it + ran its full ctest (**9/9 green**) + did my OWN glint-vs-ffmpeg decode (**118 dB**, matches). ✅ **NATIVE FFI INTEGRATION SHIPPED (`ec2aeaf`):** `lib/core/audio/sf2/vorbis_glint_ffi.dart` (`GlintVorbis` over dart:ffi → the `.sf3` `VorbisDecode` seam) + `sf3_oracle --glint` — **decoded 60/60 real FluidR3Mono.sf3 streams, 0 failures.** ⚠️ **GLINT PERF BUG found by the harness (agent RESUMED to fix):** glint's Vorbis inverse-MDCT is a deferred O(N²) placeholder with a live `cos()` in the inner loop (its slice-4b FFT never landed) → a long large-block stream (low B0 piano note, 11.8s) hangs at 100% CPU. Correct (118 dB), just pathologically slow. Agent did **slice 4b (FFT iMDCT)** + long-block gate + fuzz. ✅ **FIXED + END-TO-END VERIFIED:** the FFT iMDCT killed the hang (Piano B0 stream: 4-min hang → **0.025 s**, 519,598 frames = exactly ffmpeg); the fuzz target even caught + fixed a **real heap-overflow** in the setup parser (unchecked cross-references); glint ctest **9/9**, gate 19/19 at 117.7–120 dB. **My `sf3_oracle --glint` on the real FluidR3Mono.sf3: 500/500 streams, 0 failures, IN TUNE** — Drawbar Organ **1.7¢** · Flute **2.1¢** · Synth Strings 2 **2.9¢** (matches the ffmpeg run exactly). **So `.sf3` is proven correct + in-tune with glint as the decoder.** glint branch `feature/vorbis-decoder` (7 commits, main untouched per the agent's plan). **Remaining (unblocking, not correctness):** glint floor-0 LSP synthesis (rare — FluidR3Mono is all floor-1) + wasm rebuild; CometBeat platform seam ✅ (`vorbis_capability.dart`, web-safe). ✅ **NATIVE PLUGIN SHIPPED (`bff1922`): `native/glint`** — a Flutter FFI plugin compiling the MINIMAL glint Vorbis decode source set (vendored via `sync_glint.sh`; +a `glint_free` shim) into the app: C++17 CMake for Android/Linux/Windows + macOS/iOS podspecs w/ Classes forwarders. **Verified: source compiles standalone + decodes frame-for-frame vs ffmpeg; the podspec forwarders compile w/ the exact c++17/libc++ flags; the plugin CMake builds `libglint_vorbis`.** `loadGlintVorbis()` now tries process()→bundled-name→path. **So `.sf3` is complete on native** (`parse(bytes, vorbis: loadGlintVorbis())`). ✅ **macOS APP BUILD VERIFIED (`616968b`):** `flutter build macos` **succeeds with the plugin bundled** — `glint_vorbis.framework` ships in `CometBeat.app/Contents/Frameworks/` and exports `glint_vorbis_decode`/`glint_free`, so `.sf3` decodes in the real app via `loadGlintVorbis()`. Podfile.lock registers the pod alongside `aec_fullduplex`. ✅ **Re-vendored with floor-0** (`sync_glint.sh` @ glint acc6bb0) so the bundled decoder handles floor-0 soundfonts too. **`.sf3` is DONE + app-verified on macOS** (other platforms' full builds = CI; compile paths all verified). ✅ **GLINT SIDE DONE (agent):** all 4 wrappers (Dart `GlintVorbisDecoder`, wasm `FORMAT.VORBIS`, Rust, Python), floor-0 LSP, README documents the Vorbis decoder, `glint_audio` bumped to **0.10.0** for pub.dev — MERGED to glint main + pushed (`ce488b4..acc6bb0`); ✅ **pub.dev PUBLISHED — `glint_audio` 0.10.0 is live** (verified versions `['0.9.0','0.10.0']`), and glint now ships an **auto-publish CI** (`autotag-glint_audio.yml`: a pubspec version bump → auto-tag → the existing `glint_audio-v*` OIDC publish workflow fires; skips gracefully without a PAT). ✅ **WEB WASM SEAM SHIPPED (`67e143e`) — `.sf3` decodes in the browser.** The `vorbis_capability.dart` conditional export now routes web (`dart:js_interop`, no dart:ffi) to `vorbis_capability_web.dart`, bridging `globalThis.glintVorbis` — the glint Vorbis **wasm** shim bundled under `web/glint/` (glint.wasm 538KB + glint.mjs + a **sync** decode shim, node-verified byte-identical to the async path + bootstrap.js, wired into `web/index.html`). Async `ensureGlintVorbisReady()` instantiates the wasm once, then `decodeSync()` fits `Sf2SoundFont.parse`'s synchronous `VorbisDecode`; stub+ffi gained the same warm-up for parity. **Verified: `flutter build web --debug` exit 0** (main.dart.js 21MB; the glint assets + bootstrap copy into `build/web/glint/`); vorbis_capability + sf2 suites green (14); analyze clean. **So `.sf3` is now complete on ALL targets: native FFI + web wasm.** ✅ **SF2 VELOCITY LAYERS SHIPPED (`8fafed3`) — the last SF2 correctness gap.** Real GM soundfonts split many voices by VELOCITY (gen 44), not just key — a soft note and a loud note are DIFFERENT recordings. We ignored gen 44, so a velocity-layered voice always played its first key-covering layer at every dynamic. Now `Sf2Zone` carries velLo/velHi, `Sf2Instrument._zoneFor(key, vel)` prefers the layer covering both (velocity = the tracker's per-cell volume column 0..1→0..127), and the note's velocity also scales its level (full velocity = ×1, so existing renders are byte-unchanged). **Verified on real GeneralUser-GS.sf2: 305 velRange generators / 124 distinct windows, 28 presets carry a velocity split.** +3 tests (velSplitSf2 fixture; quiet vs loud picks the right layer; volume scales level). **Sound Library + SF2/SF3 is now fully closed** — 20 procedural voices + CC0 percussion + full `.sf2`/`.sf3` GM (parse + key-split + velocity-split + pitch-correct tuning + per-zone atten/tune + on-demand download + native FFI & web wasm decode). Also fixed a pre-existing project-wide analyze red (a trailing-comma lint in the workshop PDF export from `c729704`, `3002507`). ✅ **"load SoundFont" hook SHIPPED (`58aa85d`, user-directed) — NEW files only, zero hot-screen edits.** @tracker-ui owns + is actively editing the tracker screens, so instead of touching them I followed @libraries-and-tab's value-returning-sheet pattern and shipped two NEW files: (1) headless **`sf2/soundfont_loader.dart`** — `loadSoundFont(bytes)` parses `.sf2` directly / `.sf3` via the auto-selected glint Vorbis decoder into a browsable `LoadedSoundFont` (presets sorted bank→program), `soundFontInstrument(loaded, preset)` builds the full key/velocity-split GM voice, friendly `SoundFontLoadException`; (2) **`features/library/soundfont_sheet.dart`** — `showSoundFontSheet(ctx)→Future<TrackerInstrument?>` (file-pick + searchable preset list + audition), so the tracker/Workshop wire it in **one line** (`final inst = await showSoundFontSheet(context); song.instruments.add(inst!)`). +10 tests (7 loader incl. a real GeneralUser-GS.sf2 dev check loading 100+ presets; 3 widget: load→list→pick→return / cancel→null / .sf3-no-decoder friendly error). analyze clean. **@tracker-ui: the one-line hook + headless facade are documented in `docs/SOUND_LIBRARY_UI_CONTRACT.md`; `soundfont_sheet.dart` is yours to localize/restyle when you wire it (English literals pending l10n) — HANDS OFF `soundfont_loader.dart`/`sf2/*` (mine).** ✅ **FIXED the mid-song Fxx-tempo GUI gap @tracker-ui filed (`b173a10`) — you were RIGHT, it was engine-side (my earlier "not a bug / stale screen-side note" call was WRONG).** `songTotalMs` read the current pattern's SNAPSHOT without `syncCurrent()`, while the render methods + `resolveTimingMap` sync first — so a GUI-authored Fxx tempo/speed (via `engine.setCell` on the current pattern) was invisible to `songTotalMs` until a render/selectPattern synced it → the transport looped at the wrong length + `debugSongTotalMs` read stale (the "2000→2000"). Fix: `songTotalMs` now `syncCurrent()`s first (cheap shallow copy of the current pattern; TrackerCell is immutable, so the per-tick transport read stays cheap). `resolveTimingMap` already synced, so the playhead MAP was fine — this closes the loop-length + probe. Reproduced + pinned (mid-song 120→80 at row 4 via `engine.setCell` lengthens `songTotalMs` 1000→1496 with no manual sync). **@tracker-ui: no API change; `debugSongTotalMs`/the transport now reflect a live tempo edit immediately.** 147 tracker tests green. ✅ **INSTRUMENT JSON CODEC SHIPPED (`545f588`) — the [needs-engine] D2 enabler @tracker-ui was BLOCKED on.** New pure-Dart `lib/core/audio/tracker_instrument_codec.dart`: `instrumentToJson`/`instrumentFromJson` (+ `...JsonString`) serialize any AUTHORED `TrackerInstrument` to plain JSON and back — additive (Instrument enum), sfxr (all 25 `SfxrParams` + seed), Karplus, FM (`FmPreset`), subtractive (`SubPreset`+`SubWave`), `SampleInstrument` (base64 **Float32** PCM + baseMidi + loop + offsetScale + full `Envelope`), percussion; `isSerializableInstrument()` gates. Loaded SoundFont voices (Sf2/MultiSample) are deliberately NOT embedded (megabytes of multi-sample PCM → a reference-based store = file+preset; serializing one throws a clear `InstrumentCodecException`). **Correctness guaranteed by a render-roundtrip test** (an instrument + its decoded twin render a note byte-identically, Float32 sample within 1e-5 — a missed field can't ship); +11 tests. **@tracker-ui: your persistent `SoundLibraryService` (save/load/share user sounds across sessions) + the DAW instrument editor are now UNBLOCKED — the JSON string IS the share token. Wire it screen-side; HANDS OFF `tracker_instrument_codec.dart` + `tracker_engine.dart` (mine).** **Follow-up (documented, low priority): a reference-based codec for Sf2/MultiSample (soundfont file path + bank/program), so a loaded GM voice persists without embedding its PCM.** ✅ **ALL THREE remaining follow-ups SHIPPED (user "do them"):** (1) **5 more drum voices** (`a877104`) — `Drum` grows 3→8 (openHat/clap/tom/rim/cowbell, appended so indices stay stable), each with its own `renderDrum` synthesis; screens iterate `Drum.values` so the Drumkit grid auto-gains rows. Kept the build green where the enum hit exhaustive switches (loop_engine jam pass-through; tracker/drumkit colour+icon defaults; groove_notation staff pitches; drumkit English labels). **@tracker-ui: the polish is yours — l10n labels + per-voice colours/icons + curating the kid grid if 8 rows is too many.** +4 tests. (2) **Reference-based SoundFont codec** (`0565930`) — `SoundFontRef` (path+bank+program) + `resolveSoundFontRef(ref, bytes)` + `resolveInstrumentJson(json, loadBytes:)` so a loaded GM voice persists as a tiny ref (not megabytes of PCM) and a mixed library (embedded + referenced) resolves through one path; +7 tests. (3) **PCM-preserving module export** (`d95df8c`) — `moduleDocFromSong(song)` converts DIRECTLY to a `ModuleDoc` keeping each SampleInstrument's REAL waveform (tuning baked into c5speed) + the effect column (unlike the lossy Score→module path); procedural voices render to a base-note sample; pair with `convertToMod/Xm/S3m/It`; +5 tests. **All analyze clean; the tracker/SF2/sound-library engine arcs in my lane are now fully closed — everything remaining is UI wiring (@tracker-ui) or polish.** ✅ **FULL-SUITE HEALTH CHECK (1917 tests):** all green after fixing 2 surfaced failures. (a) `midsong_timing_acceptance_test` (`416f7af`, MINE) asserted the ORIGINAL Feature-A "speed never changes length" — stale since the oracle-driven BUG2 fix correctly made a mid-song set-speed scale row duration (openmpt-matching); reconciled the test to the correct semantics (finer speed shortens the song; render length == songTotalMs). Not from today's `songTotalMs` sync (the test renders PCM directly + syncs itself). **⚠️ @textbook-prose:** (b) `form_analysis_view_test` fails — **`voice_leading` is in the concept map but has NO EN/DE prose** (`conceptProse` in `textbook_i18n.dart`); the coverage test `every concept has prose (en+de)` catches it. Not my lane originally (a harmony-game ↔ textbook-prose gap: `spot_parallels`/`63fcd17` registered the concept without prose). ✅ **RESOLVED (`9b16472`)** — authored `proseVoiceLeading` (EN+DE, grade-9/10 harmony voice) + the `conceptProse` switch case + regenerated l10n. @textbook-prose: refine the wording to your voice if you like. **⚠️ @loop-mixer/audio:** a later full-suite run (1919 tests) surfaced a NEW, concurrent regression (NOT mine — my drum-enum change doesn't touch it): **`loop_mixer_screen.dart:1911` — a track card's `Column` overflows by 0.2px** (the icon+label card in the `AnimatedContainer`), which trips BOTH broad smoke tests (`live_flow_test` + `layout_audit_test`, they render every game). Trivial fix (a hair of height / `mainAxisSize.min` / `Flexible`) but it's your actively-worked file — flagging rather than patching. **My session's work is all green; this 0.2px card overflow is the only red, and it's yours.** ✅ **TrackerSong JSON codec SHIPPED (`ef2ac36`) — lossless save/load/share.** The gap between MOD export (8-bit/effect-lossy) and MusicXML-via-Score (no effects/per-cell instruments): `tracker_song_codec.dart` (`trackerSongToJson`/`FromJson` + `…JsonString`) serializes a whole `TrackerSong` — every cell (note/volume/effect/fxCmd/fxParam/per-cell instrument), per-pattern lengths, channels (instrument/gain/pan/mute/vol+pan envelopes/insert effects), order, timing (incl. swing), the instrument pool — to JSON and back, the EXACT document. Empty cells → null (compact); format tag + version for migration; the JSON string is a share token. Instruments via `tracker_instrument_codec` (a loaded SoundFont voice throws → use the ref store). +5 tests incl. a **render-roundtrip safety net** (a rich song renders byte-identically after a round-trip — a dropped field would change it). New file only, no hot-file edits. **@tracker-ui: this is your "Save/Load/Share song" primitive.** ✅ **HARDENED (`25cd269`):** added **compressed share tokens** — `trackerSongToToken`/`trackerSongFromToken` = JSON zlib-compressed (`package:archive`, web-safe) + url-safe base64, prefixed `CBS1.` (small + paste-able, like the Loop Mixer's `KU1.`); `tryTrackerSongFromToken` never throws (UI paste). Robust decode everywhere: format-tag + version validation via a `_migrate()` hook → a clear catchable `TrackerSongCodecException` (bad prefix/base64/decompression/JSON/missing fields/foreign format; a FUTURE version says "update the app"). Forward-compatible (unknown cell/channel effect names degrade to `none`). Optional `title` in the payload + `TrackerSongInfo`/`trackerSongInfoFromToken` peek metadata without a full decode (library lists). +9 tests (token round-trip byte-identical, token<rawJSON, try-null on garbage, future-version/foreign-format rejected, unknown-effect degrades). 14 codec tests green. ✅ **PING-PONG (bidirectional) sample loops SHIPPED (`70fdf44`).** IT/XM samples can bounce forward↔backward at the loop, but we did FORWARD loops only, so imported bidi samples sustained slightly wrong. Now: a shared pure helper `foldLoopPosition(pos, loopStart, loopLen, {pingPong})` (forward = wrap; ping-pong = triangle over period 2·loopLen; the folded position is a real point in sample space so the existing linear interp stays correct either direction), `SampleInstrument.pingPong` (default false), applied at all 3 loop-render sites (`_resampleLooping` + both per-tick sample voices — forward wraps readPos IN PLACE = BYTE-IDENTICAL; ping-pong keeps readPos monotonic + folds on read). Import: `DocSample.pingPong` + the IT reader parses the `0x40` bidi flag (`it_reader`/`it_module` → `docFromIt` → `sampleInstrumentFromDoc`); export carries it doc-level. +9 tests (helper wrap+triangle math exact, fractional folds, mode divergence; ramp-loop renders differ forward vs ping-pong; one-shot unaffected byte-identical; flag flows through the bridge). 164 tracker/module/sf2 tests green (forward loops unchanged); analyze clean. ✅ **IT/XM WRITER ping-pong flag SHIPPED (`c1e59ad`) — bidi now round-trips on export too.** IT writer sets Flg `0x40`; XM writer sets the sample-header loop-type nibble to 2 (0/1/2 = none/forward/ping-pong). `docToIt`/`docToXm` carry `DocSample.pingPong` → `ItSample`/`XmSample`; `xm_reader` parses `(type & 0x03)==2` (new `pingPong` on `XmSample`+`_SampleMeta`); `docFromXm` carries it. MOD/S3M unchanged (no bidi flag — forward-only). +2 tests (IT + XM write→read each preserve ping-pong; forward stays forward). **Ping-pong loops are now COMPLETE end-to-end: engine render + IT import + IT/XM export, all round-trip-verified.** 67 module/writer tests green (forward path unchanged); analyze clean. ✅ **AUTO-LOOP-POINT DETECTION SHIPPED (`c9bb587a`).** A recorded voice / loaded WAV was a ONE-SHOT (no loop) → a held note died at the sample end. New pure-DSP `lib/core/audio/loop_finder.dart`: `findLoopPoints(pcm)` trims trailing silence, picks a loop start ~25% in at a rising zero crossing (past the attack), then finds the loop END by NORMALIZED cross-correlation (a whole number of periods → click-free wrap; handles decaying tones; rejects noise → null); `autoLoopedSample(id, pcm, {baseMidi, pingPong})` builds a looping `SampleInstrument` (or one-shot fallback). Non-destructive (never edits PCM). +7 tests (periodic tone → whole-period seamless loop; content repeats across the seam; noise/short/silent → null; a looped instrument sustains far past its sample length; unloopable → one-shot; ping-pong opt). analyze clean. **@tracker-ui: a "loop this sample" action for the record/sample sheet — `autoLoopedSample()` is the one call.** ✅ **AUTO BASE-PITCH DETECTION SHIPPED (`faa2b235`) — recorded samples play in tune.** A recorded voice was assumed C4 (`baseMidi 60`), so an off-C4 recording played a tune OUT of tune. New pure `lib/core/audio/sample_pitch.dart`: `detectSampleBaseMidi(pcm)` reuses the MPM `PitchDetector` — median nearest-note over several windows of the sustained region (robust to a stray attack/vibrato frame), null for percussive/noisy/silent; `tunedRecordedSample(id, pcm, {autoLoop, pingPong})` builds an in-tune + sustaining `SampleInstrument` in one call. +5 tests incl. an **end-to-end in-tune proof** (record A4 → auto base 69 → render notes 69/81/64 → the detector reads exactly those notes back). Reuses `pitch_analysis.dart`'s public API (no edit). analyze clean. **@tracker-ui: one call auto-tunes a recording in the sample sheet.** **Recorded-sample chain is now complete: auto-loop (sustain) + auto-tune (in tune) — `tunedRecordedSample()` does both.** ✅ **LOOP CROSSFADE SHIPPED (`78a1ac7d`) — click-free sustain on real recordings.** `findLoopPoints` picks the best seam, but a real (aperiodic/decaying) recording can still click at the wrap. New pure `crossfadeLoop(pcm, {loopStart, loopLength, fade})` blends the loop's tail into the pre-loop lead-in with equal-power (sin/cos) weights so the last looped sample lands on `pcm[loopStart-1]` → the wrap is continuous. Non-destructive (new buffer; only the fade region changes; no-op copy without room). Opt-in `crossfade` flag on `autoLoopedSample`/`tunedRecordedSample` (skipped for ping-pong — it bounces, no wrap discontinuity). +4 tests (ramp seam lands on pre-start; non-destructive + fade-region-only; no-op without room; still loops+sustains). analyze clean. **Recorded-sample chain is now production-grade: auto-tune (in tune) + auto-loop (sustain) + crossfade (click-free) — all one call via `tunedRecordedSample(..., crossfade: true)`.** ✅ **DEPLOY TRIGGERS RE-SPLIT (`2381acf5`, user-directed): GitHub Pages on EVERY commit, Vercel only on version tags/releases.** `pages.yml` → `on: push (main)` (Pages has no deploy quota; dropped the green-CI gate — the `flutter build web` step self-gates a broken build, cancel-in-progress redeploys the latest); `deploy.yml` (Vercel) → `on: push tags v* / release published` instead of the hourly schedule — Vercel free tier caps 100 prod deploys/day, which per-commit blew during multi-agent dev; tags/releases are rare → well under the cap + an intentional "release" cut, while Pages stays fresh per-commit. Both keep `workflow_dispatch`. YAML verified; no secret/ID changes. **@ci-fixes (idle): heads-up, I edited `.github/workflows/{pages,deploy}.yml`.** To cut a Vercel deploy now: push a `vX.Y.Z` tag or publish a Release. 🚧 **NOW ACTIVE — DC-offset removal + `cleanRecording` prep.** `sample_edit.dart` has trim/normalize/fade/reverse but NO DC-offset removal — and a DC-biased mic recording has few/no zero crossings, which BREAKS my auto-loop finder (it snaps to zero crossings). Adding `removeDcOffset(pcm)` (mean-subtract, non-destructive) + `cleanRecording(pcm, {...})` (DC→trim-silence→normalize in one call) to `sample_edit.dart` (ADDITIVE — new fns only, existing primitives untouched). @tracker-ui uses these primitives in the sample sheet; additive so your calls are unaffected. + test incl. an integration proof (a biased recording auto-loops only after cleaning). **Remaining SF2 polish (low value):** volume-envelope (ADSR gens 33–38 — release tails don't fit the tracker grid) / velocity layers.
- **opus (verify-agent, DONE — 3 bugs found + ✅ ALL FIXED by @tracker-replayer):** BUG1 `f50db7d` (9xx offset now scales by the c5speed→engine ratio via `SampleInstrument.offsetScale`), BUG2 `b8c6173` (mid-song set-speed scales row duration via `_rowMsFor`, 2nd-half ×2.0 matching openmpt), BUG3 `780902d` (volume column carried on import incl. note-less cells + applied in `SampleInstrument.renderChannel`; +armRow mid-ring). Each with a regression test; 146 tracker tests green. Original report: real-data oracle A/B breadth vs openmpt123 confirmed arp/porta/tone-porta/vibrato/tremolo/Axy/Cxx-cmd/break/jump/tempo/loop all MATCH, all 20 procedural voices in-tune, 4 bundled samples OK. **BUG1** 9xx sample-offset ignores the c5speed→engine resample ratio (offset lands `engineRate/c5`× too shallow) — `module_instrument_bridge.dart`/`SampleInstrument.renderChannel`. **BUG2** mid-song Fxx set-SPEED (ticks/row) doesn't scale row duration (only tempo does) → wrong length vs openmpt — `_variableRowStartMs`/`_stepMsForTempo`. **BUG3** module per-cell VOLUME COLUMN not applied to sample voices (import drops volume-only cells + `SampleInstrument` ignores `cell.volume`). @tracker-replayer fixing all three next. **UI follow-up = @tracker-ui's lane:** a SongBook-style sound-library BROWSER/picker over `kTrackerInstruments` (audition + drop into an instrument slot); @tracker-ui already has the instrument panel + sample editor + WAV load + copy-instrument, so this is grouping/browsing over the existing catalog — coordinate before touching the picker. **Only follow-up left on the replayer proper:** none. 🗄 ORIGINAL claim: — installed libopenmpt/openmpt123 (reference renderer); building an A/B harness (my import→replay→WAV vs `openmpt123 --render`, compared via `bin/listen.dart`), then mapping `S3mCell.command/info`+`ItCell.command/commandValue` → our `fxCmd`/`fxParam` in `docFromS3m`/`docFromIt`, verified per-command against the oracle. Touches `mod/module_convert.dart`+`bin/` (mine).

- **opus (tracker-adv)** · 🚧 **ACTIVE — Tracker "Advanced mode" (real-tracker parity) + Workshop entry.** The current Tracker tile becomes **Beginner mode** (unchanged kid pentatonic grid); a new **Advanced mode** reaches ProTracker/ST3/IT/FT2 parity — endless tracks, endless pattern length, multi-pattern songs + order list, full transport (play/pause/stop/prev/next/loop), classic `rows×channels` grid with dual input (keyboard + touch). Built over the ALREADY-general `TrackerEngine` (the "2-3 bars / 6 fixed tracks" limits are UI-only). ✅ **Slice 1 SHIPPED (`daa95f9`):** new Flutter-free `lib/core/audio/tracker_song.dart` (TrackerSong = ordered patterns + order list + shared band; **endless length** `setRows`, **endless tracks** add/removeChannel, **multi-pattern songs** `renderSongWav`; 12 tests) + `advanced_tracker_screen.dart` (classic `rows×channels` grid, hex row numbers, moving playhead + follow-scroll, chromatic tap note-picker, Length 16..128, Add track, Play/Stop on the phase-preserving gapless loop; tester seam + 4 widget tests) + Beginner⇄Advanced app-bar switch + Composition Workshop overflow "Advanced Tracker" entry + 13 EN/DE ARB keys. Acceptance: 2-pattern 64-row song → `bin/listen.dart` reads the exact authored scale ×2 at 0 cents; analyze clean, 91 tracker+workshop tests green. ✅ **Slices 2–4 SHIPPED:** S2 (`2919667`) full dual-input cell editing — an edit cursor + FastTracker-2 computer-keyboard piano map (octave + edit-step + arrows + Delete) AND an on-screen mini-piano at the cursor, per-track instrument picker, per-cell volume/effect (long-press) with note/vol/fx sub-columns. S3 (`7441e60`) multi-pattern songs — pattern strip (new/clone/delete), order-list editor, "Play song" over the order list with the sounding entry lit. S4 (`e1d44a0`) the full transport the user asked for — Play/Pause/Resume (FAB, freezes in place via new `GaplessLoopPlayer.pause()/resume()`) + a Back·Stop·Forward·Loop row + position readout; Back/Forward seek order positions while a song plays (stopwatch base-offset makes it seekable) else navigate patterns. Every stated complaint resolved: endless length + endless tracks + chromatic classic grid + Workshop entry + Beginner⇄Advanced + full transport. analyze clean; 54 advanced/model/beginner/workshop tests green. ✅ **Slices 5a–5d SHIPPED (parity depth):** 5a (`9dfb5f8`) per-channel **mute/solo** (`TrackerChannel.muted` + engine `setChannelMuted`; model tracks user-mute + solo sets, remaps on channel removal; M/S in the channel header). 5b (`fb89f52`) **module import** — new `tracker_song_module.dart` `songFromModuleBytes` imports a full .mod/.s3m/.xm/.it (all patterns/channels/order + per-channel sample instrument via `sampleInstrumentFromDoc`) + **Save to Song Book** (MusicXML); overflow menu. 5c (`c6f6060`) **keyboard/layout modernization** (per user feedback): 2nd note-entry mode (note-names "F"+"2"), the Workshop's sweepable multi-octave `PianoKeyboard`, an ⓘ key legend, Tempo control, length up to **256 + Custom** (not the arbitrary 128), Play/Pause moved INTO the transport row (no FAB overlay), a Step tooltip, and an **optional onboarding tutorial** (i18n de/en). 5d (`3422705`) classic **block ops** — mark a rectangle (Shift+arrows / tap-mark / select-track Ctrl+A / select-pattern) then copy/cut/paste/paste-mix/transpose ±1/±oct/clear, via a Block menu AND keyboard shortcuts; model `copyBlock/clearBlock/pasteBlock(mix:)/transposeBlock`. analyze clean throughout; 71 tracker/model/engine tests green. ✅ **Slices 5e/5g/5h SHIPPED (classic screen furniture):** 5e (`799749c`) **Tracks & mixer** panel — a bottom sheet listing every track with instrument (tap→change), a **gain slider** (`TrackerChannel.gain` made mutable + engine `setChannelGain`), mute/solo, remove, add. 5g (`6e6c7a5`) per-channel **VU meters** in the headers (engine `channelRms` over the cached stem at the playhead → a `_levels` notifier → thin meter). 5h (`4731c57`) **record & edit a sample per track** — a 🎤 record/edit sheet (9 voice presets + slow/fast WSOLA + trim/normalize/reverse) assigns a `SampleInstrument` to the track; reuses `crisp_dsp/sample_edit`+`voice_fx`+`time_stretch`+`VoiceClipRecorder`; device-free `injectRecording` seam. analyze clean; 73→ tests green. ✅ **Effect COLUMNS phase 1 SHIPPED (`3e7e62e`):** `TrackerCell.fxCmd`/`fxParam` (the classic effect column, added ADDITIVELY — Beginner's `effect` enum untouched) + new Flutter-free `tracker_replay.dart` `applyVolumeColumn` implementing **Cxx set-volume + Axy volume-slide** (ramped, persisting; no-op without commands) wired into `_renderWithDynamics`; cells render the hex code (C20/A04) + a `_CommandEditor` (command dropdown + live hex param slider) in the long-press menu. NB the mix normalizes each stem to unit peak, so a Cxx is only observable RELATIVE to a louder note (tests account for this). **Remaining effect-command phases (a from-scratch MOD replayer — large):** phase 2 = PITCH commands (0xy arp / 1xx-2xx porta / 3xx tone-porta / 4xy vibrato / 7xy tremolo / 9xx offset) needing a tick-level oscillator replayer with cross-note period state; phase 3 = FLOW commands (Bxx jump / Dxx pattern-break / Fxx set-speed-tempo / Exy extended) needing a playback-flow model above the per-pattern render. Other optional: per-channel FX-chain UI, per-pattern variable length + row insert/delete, .mod/.xm EXPORT (needs PCM from additive voices), Beginner length extension. Touches shared `composition_workshop_screen.dart` + ARBs — rebasing before each push. Worktree `../mus-tracker-adv`, branch `feature/tracker-advanced`.

- **opus (gap-games)** · 🚧 **ACTIVE — filling the 8 untrained-concept gaps**. ✅ **Batch A SHIPPED (3 gaps closed):** `sync_read` (On the Beat or Off? — straight vs syncopated, heard via displaced note lengths), `triplet_read` (Even or Triplet? — a real `TupletSpan`, 2-vs-3 split heard), `ornament_read` (Which Ornament? — trill/mordent/turn read + a flourish played). Each with a 9yo-bar primer (`syncopationPrimer`/`tripletPrimer`/`ornamentPrimer`, shown + heard) and wired into `concept_map` (coverage: those 3 concepts now trained). 20 tests green; analyze clean. **Remaining 5 gaps:** musical form (→ AnaVis-style view + label-the-form), verse/chorus form, modulation, modes, instrument families. Worktree `../mus-gaps`, branch `feature/gap-games`.

- **opus (primer-coverage)** · 🚧 **ACTIVE — real per-concept primers for every
  game** (learnability §1, multi-batch). Audit: 130 games, 29 had a per-game
  primer, **101 fell back to their module primer**. `helpPrimerFor` already
  guarantees *some* help (tutorial_gate_test asserts it), but a module intro often
  never teaches the game's actual concept — `tie_slur` fell back to "here's the
  staff". **Filter applied:** a game needs its own primer iff its drilled concept
  is absent from its module intro (~21 new concepts covering ~35 games); the rest
  are genuinely covered. Reuse-wiring: bass variants → `readingBassPrimer`,
  `interval_ladder`/`connect_intervals` → `intervalsPrimer`. **Landing module by
  module in small commits** (primers.dart + both ARBs + game_registry +
  tutorial_test are hot — rebasing each batch). Worktree `../mus-primer-coverage`,
  branch `feature/primer-coverage`.
  ✅ **Batch 1 (note_values) SHIPPED:** `tempoTermsPrimer` (tempo_duel,
  connect_tempo — same phrase at Adagio then Allegro via `playPhrase(noteMs:)`),
  `dynamicsPrimer` (dynamics_duel, connect_dynamics — same phrase at
  `gain: 0.22` then full, a real loudness difference), `dottedNotePrimer`
  (dotted_sort — half vs dotted-half, 2 vs 3 beats, shown + heard),
  `restsPrimer` (connect_rests — note/rest/note/rest with real silent beats).
  Helpers gained `_notes(dots:)` + `_rhythm()` (null = a `RestElement`), so dots
  and rests can be *shown*.
  ✅ **Batch 2 (note_reading) SHIPPED — 17 games:** `tieSlurPrimer` (tie holds one
  pitch / slur = legato, drawn via `tieToNext` + `Slur`), `articulationPrimer`
  (staccato dot vs accent wedge — and warns the dot BESIDE a note means something
  else), `beamPrimer` (flags when split by a rest vs a beam on one beat),
  `wholeHalfPrimer` (E–F vs C–D, the black key between), `clefsPrimer` (G-clef vs
  F-clef and what they curl/dot around), `voicesPrimer` (S/A/T/B → duet,
  read_voice, which_voice, hear_voice). Plus **reuse-wiring `readingBassPrimer`
  onto all 8 bass variants**. Helpers gained `_curvePair()` + `_articulated()`.
  ✅ **Batch 3 (scales + measures) SHIPPED — 7 games:** `directionPrimer` (climb vs
  fall → direction_ear, run_direction, pitch_sort +bass), `sameDiffPrimer` (same
  pitch = an echo, same spot on the staff), `countNotesPrimer` (count each new
  sound), `strongBeatPrimer` (strong_beat — beat 1 lands loud then 2-3-4 lighter
  via an async two-call `playPhrase(gain:)`, in 4/4 AND 3/4, so the accent is
  actually *heard*). ✅ **Batch 4 (chords/harmony/composition/cello/keyboard) SHIPPED — 10 games:**
  `seventhPrimer` (triad vs the restless 7th), `romanPrimer` (scale degrees +
  CAPITALS=major/small=minor), `cadencePrimer` (V-I full stop vs half-cadence
  question mark), `phrasePrimer` (ending_detective, question_answer),
  `bowingPrimer` (⊓ down = heavy/strong beats, ∨ up = light/upbeats, drawn with
  real bow articulations on bass clef), `tenorClefPrimer` (the C-clef points at
  middle C; keeps high cello off ledger lines), `grandStaffPrimer` (two braced
  staves, middle C in the gap). Plus reuse-wiring `intervalsPrimer` →
  interval_ladder, connect_intervals.
  🏁 **EFFORT COMPLETE: 21 new concept primers + 11 reuse-wirings → 47 games moved
  off a generic module intro onto real instruction.** Per-game primers 29 → 61 of
  130; every remaining fallback game is one the module intro genuinely covers.
  `tutorial_gate_test` still asserts 100% help coverage. ✅ Also `charades` (the one
  expression game mis-served by its measures-module fallback) now has a combined
  `expressionPrimer` (tempo slow/fast + dynamics soft/loud). **62/131 games carry a
  per-game primer; the primer-coverage effort is fully complete.**

- **_(otherwise idle as of 2026-07-17)._** Last shipped: DTD ported to the native
  C engine (`f7487fd`) and keyboard-first select-mode nav (`b26a6b5`). The
  shipped board log is now in
  [HISTORY.md](HISTORY.md#agent-coordination-board--shipped-log-chronological).

### 🎯 Remaining work — scoped (start here; pick one, claim it, then build)

Ordered by value ÷ effort. Each is unclaimed unless noted. **Verify the claim is
still free on the board before starting** (search the agent name / feature).

1. **Small content minigames** — *low risk, squarely in the games lane, no
   collision.* One `GameInfo` in `game_registry.dart` + a screen + a
   `kStarThresholds` bracket in `core/tuning.dart` (games with scores) + EN/DE ARBs
   + a widget test via `pumpGame`. Shipped: ✅ **Spot the Upbeat** (`spot_upbeat`,
   Auftakt / anacrusis), ✅ **Write It for the Instrument** (`transpose_write`, the
   concert→written inverse of Concert Pitch), ✅ **Enharmonic Twins** (`enharmonic`,
   same-sound spelling vs different). Still unclaimed: **SATB chorale reading** / a
   richer Grand Staff — though note SATB *note-reading* is already well-covered by
   `read_voice`/`which_voice`/`hear_voice`, so scope any new SATB game to a fresh
   skill (voice-leading, close/open spacing) rather than another note-namer. Copy
   an existing sibling (see the "Reusable scaffolds" note under the Ideas backlog).
2. **AEC: on-device jam-mode integration** — ⚠️ *needs real hardware (not
   headless) — milestone (e).* The whole native algorithm stack is DONE and
   headlessly verified: DTD ported to the C DSP core (`f7487fd`) + wired into the
   engine (`c11ddc7`, `aec_engine_set_dtd`), and RES ported to C + wired into the
   engine (`b3bf617`, `aec_engine_set_res`) — `bash native/aec/build.sh` is 10/10
   green. **Remaining is hardware-only:** have `NativeAecEngine`/the jam screen
   call `setDtd(true) + setRes(true)` with a 1024-block engine once speaker-
   backing is on, then tune the real iOS/Android duplex path (latency, ring,
   audio session). See `docs/AEC_TIER3B.md` § "Native port status".
3. **Workshop Studio polish** — ✅ **SHIPPED.** The inspector Structure view
   (`opus (workshop-inspector)`, `b700964` — rests anchor bar changes) + the
   categorized ⌃ insertion palette (`opus (studio-polish)`). Remaining Studio
   ideas are "if ever wanted": a full palette *dock* (vs the ⌃ popup),
   rest/bar-attribute *editing* rows in the inspector (the Structure view is
   read-only + Change-from-here today).

**Blocked on crisp_notation (need a library change first — CI tracks public
`CrispStrobe/crisp_notation@main`):** ~~app-wide `showNoteNames`~~ **DONE** —
`showNoteNames` / `noteNameStyle` are now on every multi-part view:
`MultiSystemView` + `InteractiveGrandStaffView` + `InteractiveMultiPartView`
(crisp_notation 0.4.2) and the static `MultiPartView` (0.4.4, `044891d`); the
Workshop already uses it via `InteractiveMultiPartView`/`MultiSystemView`. The
other two former crisp_notation blockers are now **DONE**: the 7th-chord builder
for Roman numerals (`SeventhChord`, crisp_notation_core 0.4.5 → `roman_numeral_
screen`, `b439011`) and more SMuFL faces (Leland/Leipzig shipped `9d94d6f`).
**Needs real hardware (not headless):** AEC on-device tuning — milestone (e), see
`docs/AEC_TIER3B.md`. **Strategic / product
(not a coding session):** parent view + child profiles, teacher/LMS layer,
generative sight-reading, MIDI input. See the "Ideas backlog" + "Opportunity
roadmap" sections lower down.

#### 🎛️ Maintainer roadmap — "studio-grade" creation tools (2026-07-18, UNCLAIMED)

A big directive block from the maintainer; **the next major arc after the current
small games.** Scope each as its own claimed effort:

1. ✅ **SHIPPED — DrumKit → a studio-style beat maker.** ✅ **Tap-to-record
   (`cb1ba49`):** a Record button captures pad taps at their loop position and, on
   stop, quantises the take onto the step grid (overdub) via the new engines
   (`quantizeToResolution(eighth)` → `toDrumPattern`). Each drum snaps
   independently; stray double-taps collapse; loose timing stays on clean eighths.
   Device-free + fully tested (`debugRecordTaps` seam). ✅ **Beatbox-to-grid
   (`ff58883`):** a 🎤 button captures the mic for one loop, classifies each hit
   (kick/snare/hat) by timbre and quantises onto the grid via the SAME pipeline.
   New pure bridge `beat_capture.beatboxToTaps` (`detectOnsets` + per-onset
   `classifyHit` → taps) — verified against the real synth→detector harness;
   `debugBeatboxFrames` seam for a headless widget test. Both record paths now
   converge on the generic rhythm engine. ✅ **Save to Song Book + Export
   (`dae7b7a`):** new pure `groove_notation.drumParts(DrumRowsPattern)` engraves a
   beat as a rhythm-line multi-part score (one part per drum with a hit — kick low
   F2 / snare middle C4 / hat high G5; a reduction that preserves the timing,
   since the kid theme has no percussion staff). At the eighth grid every step is
   an eighth note or rest, so no tie/duration puzzle — reuses `grooveScore`.
   App-bar Save-to-Song-Book (title dialog → `UserSongsService`) + Export (the
   shared music-export sheet → MusicXML/MIDI/etc.); `debugSaveToSongBook`/
   `debugMusicXml` seams. ✅ **Undo/redo (`6914791`):** a snapshot history backs
   app-bar Undo/Redo across grid edits, record takes and clear (a fresh edit drops
   the redo branch) — filling the gap the destructive record/clear opened. **DrumKit
   item COMPLETE — tap-record + beatbox-record + save/export + undo/redo.** **Only-if-wanted:** expose the skill-tier cap as a setting (the
   grid is fixed eighth today); more `Drum` voices ([needs-engine]); real
   percussion-staff notation (vs the pitched reduction).
2. ✅ **SHIPPED — Recording with a beginner "Relevanzschwelle" (rhythm relevance
   threshold).** The quantisation ENGINE is done: `lib/core/audio/rhythm_quantize.dart`
   (`04fc357`) — `detectOnsets` → `chooseResolution` (auto coarsest-grid-the-player-
   can-feel, capped by skill tier) → `quantizeRhythm` (snap + strength-filter +
   same-step collapse). Pure, 15 tests. **Remaining for this item:** wire it into a
   live recording surface (the DrumKit / a tap-to-record widget) + expose the skill
   cap as a setting; that lands with item 1.
3. ✅ **CORE SHIPPED — Conversion to ALL our models.** `lib/core/audio/rhythm_convert.dart`
   (`994f5b2`): `toTrackerColumn` (→ Tracker → its existing Score/MusicXML/MIDI/
   module + Song-Book paths) + `toDrumPattern` (→ Loop Mixer `DrumRowsPattern`),
   both re-placing a hit by its grid-independent musical position. 7 tests. So a
   captured rhythm now reaches every notation/export path via existing bridges.
   **Remaining:** a direct `Workshop MultiPartDocument`/`TabDocument` path if ever
   wanted (the Tracker bridge already covers Score/MusicXML/MIDI), and wiring a
   per-hit pitch/drum labeller at the capture site (lands with item 1).
4. 🟡 **CORE SHIPPED — A much better Looper.** Beyond Loop Mixer 2.0: tighter
   overdub/undo, live layering, better quantised punch-in, seamless loop lengths.
   ✅ **Pure core `lib/core/audio/loop_record.dart` (`06b1849`, 9 tests):**
   `quantizeLoopBars` (seamless loop lengths) · `snapPunch` (quantised punch-in/
   out) · `LoopStack<T>` (overdub layers + undo/redo + mute). **Remaining:** a
   surface — turn the DrumKit record into a **layered** overdub looper (each take
   a `LoopStack` layer), or wire the quantisers into the Loop Mixer.
5. **More Workshop work** (unspecified umbrella — capture concrete asks as they
   land).
6. 🟡 **CORE SHIPPED — a DAW Workshop tool** (maintainer, 2026-07-18): a separate
   multi-track tool that arranges audio from every module (Song Book / Tracker /
   Score / TAB / DrumKit / samples). **Decision: "vector, not bitmap"** — a clip
   references its source MODEL and the mix rasterises on demand + caches per
   source (edit source → clip re-renders), which fits because every module renders
   offline+purely to PCM. Offline render-then-play (no realtime graph). ✅ Pure
   core `lib/core/audio/daw_timeline.dart` (`ClipSource`/`Clip`/`DawTrack`/
   `DawTimeline`/`renderTimeline`, 6 tests). Design + sliced plan:
   **`docs/DAW_SCOPING.md`**. Next: per-module `ClipSource` adapters → "Send to
   DAW" bridges → the arrangement surface → mutable takes + merge/convert
   (`loop_record.LoopStack`).

These lean on infra we already own (mic capture, onset detection, the groove/
tracker engines, model converters). Sequence suggestion: **(2) the quantisation
threshold engine first** (pure, testable, unlocks the rest) → **(1) DrumKit
record** → **(3) model conversion** → **(4) Looper**. Not started.

### 🚀 Handover prompt for the next agent (copy-paste this)

```
You're joining the CometBeat repo (Flutter music-education app) where
SEVERAL agents work in parallel and push to origin/main — collisions are the
main hazard. Before writing any code:

1. Read docs/PLAN.md — the "🎯 Remaining work — scoped" block at the top of the
   "Actively working on" board. Pick ONE unclaimed item.
2. Work in a feature branch + a git worktree that is a SIBLING of mus/ (e.g.
   ../mus-<task>), never under .claude/ — the ../crisp_notation path-dep must
   resolve. From an existing worktree, `git pull --rebase origin main` first.
3. CLAIM IT on the docs/PLAN.md 🚧 board (agent · task · files touched · status)
   and push the board to origin/main BEFORE touching any hot shared file
   (game_registry.dart, core/tuning.dart, the ARBs, composition_workshop_screen.dart,
   score_document.dart). Re-check the board for a conflicting claim first.
4. Build in small commits. `git pull --rebase origin main` often; expect the tree
   to have moved. Coordinate in the board comment if you must touch another
   agent's active file.
5. Pre-commit gate, in this order: `flutter pub get` (in a fresh worktree, BEFORE
   format, or dart format silently reformats the whole repo), then
   `dart format <your files>`, then `flutter analyze` (whole project, aim for "No
   issues found"), then the test suite. New feature ⇒ a test.
6. Localize every user-facing string (app_en.arb + app_de.arb, run
   `flutter gen-l10n`). This Mac needs the GEM-env wrapper for flutter/pod/xcode:
   `PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT flutter ...`.
7. ⚠️ NEVER pipe a test/gate command through `tail`/`head` before a push
   (`flutter test | tail && git push`) — the pipe EATS the exit code and a red
   suite reaches main. Check exit codes directly.
8. After each ship: update the board to idle/SHIPPED, record the feature in
   docs/HISTORY.md, and push. Never name or allude to competing products in code
   or docs.

The Workshop editor, playback, songs, Tracker, Loop Mixer and the AEC *algorithm*
are essentially complete; the AEC double-talk detector is now ported to the
native C engine too (`f7487fd`). Good self-contained next items: a small minigame,
or wiring the native DTD into jam mode + porting RES to C (verify harness green:
`bash native/aec/build.sh`).
```

_The long chronological log of shipped board entries now lives in_
_[HISTORY.md → "Agent coordination board — shipped log"](HISTORY.md#agent-coordination-board--shipped-log-chronological)._

## Principles

1. **Minigames, not lessons.** Every skill is drilled through a game with
   rounds, scores and 1–3 stars — same loop as Space Math Academy and
   WortUniversum.
2. **SRI everywhere.** Every first-try answer feeds the SM-2 engine under
   `<module>.<skill>.<detail>`. The home-screen review button drills due
   items; the Karteikasten visualizes progress.
3. **Kid-first interaction.** crisp_notation's kid theme (bold lines, ≥44 px hit
   targets), generous tap slop, no time pressure in level 1 of any game.
4. **Modular i18n.** All strings in ARB (EN/DE); a new module = registry
   entry + ARB keys + game screens. German conventions respected (B = H).
5. **Everything MIT** (font OFL). No LGPL anywhere — audio via
   `audioplayers`/`flutter_soloud` + permissively-licensed samples, never
   FluidSynth.

## Curriculum map

The module/skill structure and the games that fill it. Games already shipped are
listed for scope; `*later:*` italics mark planned extensions within a module.

| # | Module | Skills (SRI namespace) | Games |
|---|--------|------------------------|-------|
| 1 | **Notenwerte** (note values & lengths) | `note_values.symbol`, `.rhythm`, `.beats` | Symbol Quiz • Duration Duel • Rhythm Echo • Count the Beats • Sort the Beats • Connect the Symbols |
| 2 | **Noten lesen** (treble & bass clef) | `note_reading.treble`, `.bass`, `.place_*`, `.melody`, `.dictation` | Reading Quiz ×2 • Place the Note ×2 • Melody Echo • Melody Dictation • Note Match • Note Order • Line or Space? • Falling Notes • Connect the Notes • Ledger Leap |
| 3 | **Takte** (measures & meter) | `measures.fill`, `.meter` | Measure Filler • Meter Detective • Beat Runner • *later: percussion-backed meter, tempo ramps, syncopation* |
| 4 | **Tonleitern** (scales, Dur/Moll) | `scales.spot`, `.build`, `.hear` | Scale Detective • Scale Builder • Dur oder Moll? • Sound Echo • Follow the Conductor • Key Detective |
| 5 | **Akkorde & Intervalle** | `chords.triad`, `.build`, `.interval` | Chord Quiz • Triad Builder • Interval Detective |
| 6 | **Harmonik** (T/S/D) | `harmony.function`, `.cadence`, `.hear` | Function Quiz • Cadence Workshop • Hear the Function |
| 7 | **Cello-Ecke** (instrument corner) | `cello.string`, `cello.finger`, `note_reading.tenor` | Which String? • Finger Quiz (first position, 0–4) • Tenor Clef reading • *later: shifting/positions, string+finger combined ("play this note"), open-string ear tuning* |
| 8 | **Tasten-Ecke** (piano corner) | `keyboard.find`, `.name`, `.ear`, `.melody`, `.chord`, `.grand` | Find the Key • Key Quiz • Echo Keys • Play the Melody • Chord Grip • Grand Staff • Falling Keys |
| 8b | **Gitarren-Ecke** (guitar corner) | `guitar.string`, `guitar.fret` | Open Strings • Read the Tab • *later: bass tuning, fretboard-tap "find the fret", techniques (bends/slides/HO-PO), chord-grip diagrams* |
| 9 | **Liederbuch** (real songs) | `songs.tune` | Song Book (public-domain children's songs, real notation + lyrics, karaoke cursor) • Name That Tune • **Import**: MusicXML (paste or file pick), ChordPro, monophonic MIDI • *out of scope: polyphonic MIDI (transcription problem)* |
| 10 | **Komponieren** | `composition.closure`, `composition.answer` | Ending Detective • Question & Answer • My Melody (free-composition sandbox → saves to Song Book as MusicXML) • *later: melody completion with choices, cadence-based accompaniment* |

**Instrument corners** are the modular-extension pattern proven by the cello
module: a data table (string/finger map), instrument-specific games reusing the
shared machinery, and the right clefs (the library supports all four). The
**guitar corner** is the same recipe on **tablature** (crisp_notation `TabStaffView` +
`Tuning`). A violin/viola corner is the same recipe again (violin: G/D/A/E
strings, treble clef; viola: alto clef); a bass corner reuses the guitar recipe
with `Tuning.standardBass`.

## CrispNotation capabilities → new ideas

The crisp_notation library has grown well past what the app currently uses. **As of
2026-07-16 both the mus path-dep and CI resolve `crisp_notation`
(`CrispStrobe/crisp_notation@main`)** — pubspec points at `../crisp_notation/...`
and the CI/deploy workflows check the public repo out to `crisp_notation/`, so
local and CI are aligned and the new APIs are usable everywhere. The library now
lives in a single local clone at `../crisp_notation`; the earlier
`crisp_notation-public` symlink and the private clone are gone. Verified new
capabilities and what they unlock:

- **Teaching overlays on `StaffView`** (`showNoteNames`, `showBeatNumbers`,
  `showMeasureNumbers`). **Which Beat?** is shipped — it uses `showBeatNumbers`
  as a fading scaffold (beat numbers under the staff at level 1, gone at 2★).
  Still open: a native `showNoteNames` fading scaffold across the reading games.
- **ABC notation import/export** (`scoreToAbc`, ABC reader). **Both shipped** —
  ABC **import** in the Song Book (`scoreFromAbc`) and ABC **export** from the
  Composition Workshop (`scoreToAbc` → copy to clipboard). Still open: a
  "type-a-tune" mode.
- **Chord identification** (`identifyChord`, `chordSymbolFor`). **Name That
  Chord** and **Chord Builder** are shipped
  ([HISTORY.md](HISTORY.md#crisp_notation-powered--shipped)) — the builder grades
  **any voicing** (root position or inversion, any octave) via `identifyChord`.
  Still open: chord symbols over the Song Book (low value — the built-in songs
  are monophonic).
- **`StaffSystemView`** (N-staff systems). **Duet** is shipped — read the
  highlighted part of a two-staff system (lower staff switches to bass clef at
  2★). Still open: SATB chorale reading, a richer Grand Staff.
- **Transposing instruments + concert-pitch toggle.** **Shipped** — a new
  **Transposing corner** with **Concert Pitch**
  ([HISTORY.md](HISTORY.md#crisp_notation-powered--shipped)): read a written note for
  a B♭/E♭/F instrument, name the concert pitch that sounds (crisp_notation's
  `transposeBy` does the maths). Still open: a written↔concert *toggle* on
  rendered scores.
- **Up-bow / down-bow articulations.** **Bowing** is shipped (cello corner):
  read the ⊓ down-bow / ∨ up-bow marks crisp_notation draws.
- **Common/cut time (C, ¢) + pickup/anacrusis + measure numbering.** **Time
  Signatures** is shipped — read the signature (incl. C and ¢) for the beats per
  bar. Still open: spot the **upbeat (Auftakt)** with anacrusis measures.
- **Percussion clef** → **shipped**: a **Drums** corner with **Drum Read** — read
  a rhythm on the neutral percussion staff and tap it back on the drum pad in
  time (count-in, then Perfect/Good/Miss vs the notated onsets).
- **Figured bass** (SMuFL figbass) → Baroque continuo reading — advanced, later.

### New in crisp_notation-public (aligned 2026-07-13) — next builds

Fresh capabilities now resolvable in mus, ranked by fit:

- [x] **Roman-numeral harmonic analysis** (`RomanNumeral` — `.symbol` → "V7",
  "ii°"). **Shipped: Roman Numerals** (Harmonik,
  [HISTORY.md](HISTORY.md#crisp_notation-powered--shipped)) — read/hear a diatonic
  triad in a key, pick its numeral; the chord is built with `Triad` and named by
  `romanNumeralOf(pitches, key)`. SRI `harmony.roman.<symbol>`. Widens I/IV/V in
  C → all diatonic triads → **all major + minor keys** (harmonic-minor V/vii°)
  **and first/second inversions** (figures `V6`, `ii6/4`) at 2★. Still open:
  **7th chords** (`V7`, `viiø7`) — needs a crisp_notation seventh-chord builder (the
  library has only `Triad`), a clean handoff.
- [x] **Metrical-accent hierarchy** (`beatStrength(Fraction) → double`).
  **Shipped: Strong Beat?** (Takte,
  [HISTORY.md](HISTORY.md#crisp_notation-powered--shipped)) — a measure with beat
  numbers, one beat highlighted; strong-or-weak, graded by `beatStrength` (not
  hard-coded, so correct for 4/4, 3/4, 6/8…). Metric click accents the strong
  beats. SRI `measures.accent.<ts>_<beat>`; widens 4/4 → +3/4,2/4 → +6/8. Still
  open: a "conduct the metre" / tap-all-strong-beats variant.
- [~] **Structured chord symbols** (`chordSymbolFor`, `ChordSymbol` model).
  **Shipped: Chord Chart** (Chords,
  [HISTORY.md](HISTORY.md#crisp_notation-powered--shipped)) — the symbol→notation
  matching game: read a chord symbol (G, Dm, D7…), tap its notation among four
  little staves. Lead-sheet literacy; the inverse of Name That Chord. SRI
  `chords.symbol.<symbol>`. Still open: chord symbols rendered over the Song Book
  chord sheets (in the play-along agent's songbook area).
- [~] **Voices per staff** (`Measure.voice2`, 2 voices rendered; 3–4 model-only).
  **Shipped all 3 scoped SATB minigames** (Noten lesen, gated behind Duet 2★,
  shared `satb_voicing.dart`, [HISTORY.md](HISTORY.md#crisp_notation-powered--shipped)):
  **Read the Voice** (name the note a voice sings), **Which Voice?** (highlight →
  pick S/A/T/B), **Hear the Voice** (aural: chord then one voice → which?). All 2
  voices (S+A) → full SATB, and now **several major keys at 2★** (correctly
  spelled, no voice crossing — unit-tested over 400 draws). Remaining: chorale
  inversions/7ths (root position for now). (`beam subdivision` / `appoggiatura`
  grace notes are
  separate rendering-quality wins, still open.)
- [ ] **Import breadth**: MEI, Humdrum **kern/ekern**, LilyPond, GP3/4/5,
  compressed `.mxl`. All parseable in `crisp_notation_core` today → wire into the
  Song Book import screen (web-safe, additive). Extends MusicXML/ABC/ChordPro/MIDI.
- [ ] **OMR ("photograph your sheet music")** — checked crisp_notation@main
  (v0.9, 2026-07-13): OMR is **substantially built there**, but split by
  platform, which gates how mus can use it:
  - **Recognition (image → tokens)** = CrispEmbed **Sheet Music Transformer** in
    `crisp_notation_cli/crispembed_omr.dart`: `dart:ffi` + `dart:io` + native
    `libcrispembed` + a **GGUF model**. **NOT web-compatible, not a mus dep,
    needs a ~100 MB+ model artifact.**
  - **Parsing (tokens → Score)** = `crisp_notation_core/src/omr/` (bekern · semantic ·
    lilynotes → Score/GrandStaff/StaffSystem). **Pure Dart, web-safe, already a
    mus dependency** (0 ffi/io refs).
  - So a client-side photo→score in the **deployed web app is not a quick win**.
    Realistic paths: **(a)** web-safe **"import OMR tokens"** in the Song Book
    (reuse the core parsers; cheap; niche without on-device recognition);
    **(b)** a **native-only** photo flow (Android/iOS/desktop) on the AEC agent's
    pattern (native plugin + web-safe conditional-export stub) + camera + the
    GGUF model — a big swing; **(c)** server-side recognition (no infra yet).
- [x] **Alternate SMuFL fonts** (Petaluma / Leland / Leipzig descriptors).
  **Shipped: "Handwritten notes" theme** (Settings toggle,
  [HISTORY.md](HISTORY.md#crisp_notation-powered--shipped)) — renders all notation in
  **Petaluma** (jazz/handwritten, SIL OFL 1.1, vendored in `assets/smufl/`,
  license on the About page). All ~50 StaffView sites now go through
  `shared/score_theme.dart`'s `kidsScoreTheme`, switched by the setting. Still
  open: Leland/Leipzig as further options; a live preview in Settings.

### crisp_notation moved a LOT further (checked 2026-07-14)

Since the 07-13 alignment, `CrispStrobe/crisp_notation@main` advanced ~40+ commits
(still v0.4.0). **mus is fully compatible** — after fast-forwarding the local
`../crisp_notation-public` to match CI, `flutter analyze` is clean and the **full
suite (429) is green** against it, so none of the churn broke anything mus uses.
(Local checkout was behind CI's `@main`; now realigned. mus rides all of this
for free.) The genuinely new capabilities, ranked by mus fit:

- [ ] **Multi-part / full-score rendering (the "C6" line)** — new `MultiPartScore`
  model + **paginated `MultiPartView`/`MultiPartPageView`** (render several
  instruments/staves as line-broken pages), **cross-part hit-testing**, per-group
  barlines (`BarlineGroup`), multi-part PNG/SVG/CLI export ("every part"). This is
  a real new tier above our single-staff + `StaffSystemView` duet. *mus fit:* an
  **ensemble / full-score reader** (e.g. a real SATB chorale on 2–4 staves, or a
  score-following view for a multi-instrument tune). M–L, genuinely new surface.
- [ ] **MuseScore `<Drumset>` import + TAB-clef import** — MusicXML now reads a TAB
  clef (was aborting) and MuseScore files yield **drum hits on their line +
  notehead**. *mus fit:* feeds the **Drums** and **Guitar** corners with imported
  material; pairs with the existing Song Book import screen. S–M.
- [ ] **Interchange breadth + fidelity now hardened** — multi-voice **kern**
  (`*^` split spines) and **ABC** (`&` overlay) round-trip; **MEI** multi-staff
  importer (`staffSystemFromMei`); UTF-16/BOM file decoding; a round-trip
  **fidelity harness** + music21 oracle. Supersedes the older "import breadth"
  item above — MEI/kern/ABC/MuseScore import is now robust enough to wire into the
  Song Book. S each (additive, web-safe).
- [ ] **Workshop-facing editor APIs** — `suppressElementIds` (clean element hide
  during live drag, **mus already uses this**) + **view-owned live-drag preview
  `dragPreviewOpacity`** (C10b). Plus engraving the Workshop gets for free:
  **metric-aware secondary beaming** (beams grouped by the meter hierarchy),
  **`Measure.actualDuration`** (explicit irregular/pickup-bar length), every-N
  **measure numbering**, per-group barlines, and layout crash-hardening on
  degenerate spans. → see the **Workshop parity** pass below.
- [ ] **Braille music export** (`.brl`, incl. key/time sigs + chords; tab
  notation complete) — an accessibility angle, not obviously kid-facing. Later.

### Workshop → crisp_notation feature-parity (2026-07-14)

The Composition Workshop is a full touch/desktop score editor, and **G6
multi-instrument authoring is now feature-complete** (2026-07-15, on
origin/main): `MultiPartDocument` (`List<ScoreDocument>` + active part, padded
bar grid, per-part id namespacing) → the full-score `InteractiveMultiPartView`
canvas with a parts strip (add/select/clef/transposition/brace/remove),
multi-part **import** (`multiPartScoreFromMusicXml/Abc/Mei/Kern`), multi-part
**export** (crisp_notation **C11** `multiPartToMusicXml`), and **in-place
editing** on the full score (crisp_notation **C12** `InteractiveMultiPartView`:
staff-tap-to-place, hover ghost, cross-part select, drag repitch). See
`docs/WORKSHOP_G6_HANDOVER.md` + `docs/WORKSHOP_CRISP_NOTATION_CONTRACTS.md`.

**crisp_notation G6 follow-ups (the "left opens") — DONE 2026-07-15:**
- ✅ **C12b — `EditorCaret` on `InteractiveMultiPartView`** (crisp_notation
  `afc283a`): the render paints a caret before its `beforeElementId` — the id
  locates the part, so it lands in the right staff. mus `_mpCaret` feeds the
  active part's caret (namespaced).
- ✅ **C12c — `ElementRegionController` on `InteractiveMultiPartView`**
  (`afc283a`): `RenderMultiPartView implements ElementRegionProvider`; a
  controller binds for marquee / cross-part region queries. mus binds `_regions`
  + shows the rubber-band overlay in multi-part mode (`_applyMpMarquee` selects
  within the most-covered part).
- ✅ **C12a — live drag preview** (no lib change needed): built app-side from the
  existing `suppressElementIds` (hide the dragged note) + placement ghost
  (`onElementDragUpdate` moves it under the pointer) — same visual as single-part
  `dragPreviewOpacity`. A dedicated multi-part `dragPreviewOpacity` (real-glyph
  translation) is an optional future nicety, not required.
- ✅ **C11b — multi-part MEI/kern/MuseScore writers** — **SHIPPED (un-deferred 2026-07-19, `opus (multipart-*)`).** The deferral premise (that it needs refactoring the oracle-hardened single-part writers, for low value + regression risk) turned out wrong: the app's export sheet + Workshop were **dropping all-but-the-first part** on MEI/kern/MuseScore export — a concrete data-loss — and each writer was added as a **NEW** function with the single-part path untouched (zero regression). Shipped: `multiPartToMei` (`crisp_notation@f613c9f`), `multiPartToMscx` (`ac68a08`), `multiPartToKern` (columnar N-way time-merge, `af10bcb`) + a `multiPartScoreFromMscx` reader (`516dcd2`); wired into `music_export.dart` + Workshop + fixed the online-library import. `multiPartToAbc` already exists app-side (`multi_part_export.dart`). **⇒ every multi-capable format keeps every part on import AND export.** LilyPond now keeps every part too (`multiPartToLilyPond` — a `\new StaffGroup` of one `\new Staff` per part, `crisp_notation@fb32573`; wired `4745d89`). **⇒ every multi-capable format keeps every part: MusicXML, MEI, MuseScore, kern, ABC, LilyPond, PDF.** **PDF now too** (`exportMultiPartToPdf`, `c729704`): mirrors the single-staff PDF but uses `layoutMultiPartPages` + `renderStaffSystemLayoutToPng` (BOTH already in crisp_notation — the renderer engraves all staves per system with connected systemic barlines), so a full score prints every instrument; zero library change, wired into the export sheet + Workshop. **Only Braille stays first-part** (genuinely complex/niche — no multi-part Braille writer). Bug-hunt aside: probed the theory/analysis engine (roman numerals, chord ID) and MIDI/robustness — all verified excellent + already comprehensively tested (roman numerals get secondary dominants, all dom7 inversions, ø7/°7, Neapolitan right); the one real find was the MIDI dotted-decoder fix above. **+ MIDI fidelity fix (`crisp_notation@9276dfb`):** a probe of MIDI round-trip (a heavily-used codec absent from the property suites) found dotted notes importing as tied splits (dotted quarter → quarter+eighth); the tick→value decoder now recognises dotted/double-dotted values directly. +4 regression tests. (Triplets through MIDI stay lossy — inherent to the format's lack of tuplets.)

**Non-G6 parity polish — assessed & (partly) shipped 2026-07-15:**
- ✅ **Measure numbers in the editor** — crisp_notation `MultiSystemView` gained
  opt-in `showMeasureNumbers` (system-start numbering off `SystemLayout.
  firstMeasure`, paint-only, defaults off — ported from `png_export`'s
  convention; it previously existed only on `StaffView`). Wired a **"Bar
  numbers"** toggle in the Workshop ⋮ menu, wired to **all three** editor
  canvases — single-staff (`MultiSystemView`), grand-staff
  (`InteractiveGrandStaffView`) and multi-part (`InteractiveMultiPartView`) all
  gained the same opt-in system-start numbering. **Feature complete.**
- ✅ **Metric-aware beaming** — already automatic: the layout engine
  (`_computeBeamGroups`) derives beam windows from the meter during layout, so
  the editor needs no opt-in. Nothing to wire.
- ⏸️ **`Measure.actualDuration`** — the model already supports explicit
  irregular-bar lengths (`Measure.actualDuration` + `effectiveDuration`), and the
  editor already handles the pickup case; exposing arbitrary irregular bars is a
  niche editor feature, deferred until asked.
- ✅ **`showNoteNames` overlay** — shipped. crisp_notation gained a
  **`NoteNameStyle`** (letter / German-H / solfège) threaded through the layout
  engine's note-name overlay (was fixed English) + `showNoteNames` on
  `MultiSystemView`; the Workshop **"Note names"** ⋮ toggle overlays each note's
  name **on all three editor canvases** (single-staff, grand-staff, multi-part —
  the flags now forward through the grand-staff/multi-part layout paths too),
  **spelled per the app's note-naming setting** (germanH → H for B, solfège →
  do/re/mi, auto → locale). **Feature complete.**
- ✅ **Per-group barlines in the chrome** — shipped. `MultiPartDocument`
  `toggleBarlineBreakAfter`/`hasBarlineBreakAfter` recompute `barlineGroups`; a
  **"Break barline below"** item in each part's ⋮ menu breaks the systemic
  barline between instrument groups (crisp_notation already paints them). **All
  Workshop→crisp_notation parity items are now shipped.**
Details + the running contract log: `docs/WORKSHOP_PLAN.md` +
`docs/WORKSHOP_CRISP_NOTATION_CONTRACTS.md`.

## Difficulty progression (within each game)

Games start at the easiest concrete slice and widen per level (driven by
stars + `kWinsRequiredForLevelUp`, tuning.dart):

- Reading/Placing: naturals on the staff → ledger lines (middle C!) →
  accidentals → mixed clefs.
- Measure Filler: 4/4 with h/q/e → 2/4, 3/4 → dotted notes → 6/8.
- Scale Detective: C/F/G major → all majors → natural minor → harmonic minor.
- Chord Quiz: major root position → minor (Dur/Moll!) → inversions →
  diminished/augmented.
- Function Quiz: C/F/G major → all keys → minor keys (with harmonic-minor
  dominant) → hear the function (audio).

## Textbook mode — a read-through curriculum (grade 1–10) — PLANNED

**Vision (maintainer, 2026-07-17).** Beyond the minigame grid, a **"read-through"
learning path**: a beautifully, didactically arranged music-theory & practice
**textbook** a learner can start at page one and work through from grade 1 to 10.
Each lesson *teaches* a concept (words + engraved examples + heard examples +
real-song examples), then hands off to the **games that train it**, with an
**ongoing narrative** tying the path together. Two consequences the maintainer
called out: (a) building top-down from a curriculum **reveals our coverage gaps**
(concepts a grade needs that no game/lesson yet trains); (b) coverage will be
**uneven** per concept — that's expected, and the map makes it visible.

### ⚠️ Curriculum source & licensing (READ FIRST — non-negotiable)
The spine must come from a *proven* curriculum, but **the German Bundesländer
music curricula are NOT freely licensed** — "free to read, all rights reserved";
Bayern (ISB) and Baden-Württemberg explicitly forbid redistribution; none carry
CC / Datenlizenz Deutschland (see the "Curriculum / Lehrplan alignment" notes in
`CLAUDE.md`). So we **must never** copy verbatim text, tables, exercises,
graphics or sheet-music excerpts from them. What IS legally reusable:
- **The topic scope / sequence** — *who-teaches-what-when* — is fact, not
  expression; we distil it **in our own words**. (This is already how the app's
  generic Klasse-1–2…9–10 curriculum was built, from re-expressed NRW Grundschule
  + Schleswig-Holstein Sek I scope.)
- **Genuinely open sources** for wording/structure inspiration: **Open Music
  Theory** (CC-BY-SA), Wikipedia/Wikibooks music theory (CC-BY-SA), public-domain
  treatises. Track each source's licence.
- **Public-domain & folk songs** for examples (the Song Book is already
  public-domain children's songs) — freely usable, and the richest teaching hook.
- **§5 UrhG (amtliches Werk)** for a few states' *normative* text is a grey zone;
  the maintainer chose not to rely on it. Don't.
**→ The spine is OUR OWN re-expressed grade-1–10 scope. No verbatim curriculum
text enters the repo.**

### Architecture (proposed)
- **`lib/features/textbook/curriculum.dart`** — pure data: `Grade` → ordered
  `Lesson`s. A `Lesson` = `{ id, gradeBand, title, concept-primer, prose (ARB),
  worked examples (Score/audio), song examples, gameIds[], nextLessonId }`. Pure
  Dart, testable, no UI coupling.
- **Lessons reuse the concept-primer atoms we already built** — the 45 primers in
  `shared/tutorial/primers.dart` ARE the lesson cores. A Lesson wraps a primer +
  extra prose + song examples + the game list. So the primer-quality work already
  done is *directly* the textbook's lesson content.
- **`textbook_screen.dart`** — a paginated reader: prose + engraved examples +
  Listen buttons + "train this" buttons that deep-link into the games, + prev/next
  and a progress spine. Narrative connective text between lessons.
- **`TextbookProgress`** (SharedPreferences) — furthest lesson reached, so
  "continue reading" works; the games' SRI mastery feeds a "you've practised this"
  tick per lesson.

### Song-based examples (start here — highest value, no licensing risk)
Anchor abstract facts to **melodies kids know**, drawn from / extended in the
**Song Book** (public domain). Especially **interval mnemonics** — name the leap
by the tune that starts with it:
- **descending minor 3rd** → "**Kuckuck**" (the cuckoo call).
- **major 2nd up** → "Alle meine Entchen" / "Frère Jacques" start.
- **perfect 4th up** → "Tatütata" (Martinshorn) / "Kommt ein Vogel geflogen".
- **perfect 5th up** → "Morgen kommt der Weihnachtsmann" / "Twinkle" (C–C–G).
- **major 6th up** → "My Bonnie".
- **octave** → "Somewhere over the Rainbow".
These become: (1) worked examples inside the interval lessons; (2) an
`intervalSongs` table the **Interval** games cite as a hint/mnemonic; (3) Song
Book entries we author/extend. Each carries its source + public-domain check.

### Gap analysis (the deliverable that "reveals where we don't cover")
A pure function + a test mapping **each re-expressed curriculum concept →
{lesson?, primer?, gameIds[]}** and printing the **uncovered** ones (a concept
with no game, or a grade band with a thin lesson). Both a planning artefact and a
coverage guard. Run it first — it orders all the work below.

### Phasing
1. **Curriculum spine data model + gap analysis** (pure Dart + test). Reveals gaps.
2. **Song-example layer**: `intervalSongs` (+ other mnemonic tables) wired into
   the interval primers/games; extend the Song Book where a song is missing.
   *(No new UI; immediate learner value.)*
3. **Lesson model** wrapping the existing primers + prose + song examples + game
   links; author grade-band prose (our words).
4. **Textbook reader UI** + narrative + progress + game deep-links.
5. **Fill the gaps** the analysis found (new lessons/games for uncovered concepts).

**Status (2026-07-17): phases 0–5 all shipped; the syllabus is fully covered and
readable end-to-end.**
- **Phase 0** — primers to the 9yo bar (every step engraved + heard).
- **Phase 1** — `concept_map.dart` (70 concepts, grade 1–10, our words) +
  `coverage_gaps.dart` + the gap-report test.
- **Phase 2** — song mnemonics: `core/curriculum/interval_songs.dart` wired into
  the **Interval Detective** (Kuckuck = falling minor 3rd, etc.).
- **Phase 3** — narrative + **full i18n**: `features/textbook/textbook_i18n.dart`
  (ARB-backed, de/en) localises all 70 concept titles, the 19 concept-area
  sub-headers and 5 grade-band short labels, plus a **narrative intro paragraph
  per grade band**. The reader groups each band's concepts by area (sub-headers,
  first-appearance order) so it reads like a book.
- **Phase 4** — the read-through reader (`textbook_screen.dart`) + 📖 home button.
- **Phase 5 — all 8 gaps FILLED:** verse/chorus + ABA/rondo form (`form_read`),
  syncopation (`sync_read`), triplets (`triplet_read`), ornaments
  (`ornament_read`), **modulation** (`modulation_ear`), **modes** (`mode_ear`),
  **instrument families** (`instrument_family`).
- **Coverage now: 137/137 games placed (100%), 0 untrained concepts, 0 orphans.**

Remaining (optional): ~~richer per-concept lesson prose beyond the primers~~ **first
tranche SHIPPED** (`2f63709` — 17 concepts, EN/DE, fallback-safe; ~53 concepts
still open, same pattern); the bachelor-tier extension (draw facts from the OER
registry below); ~~the AnaVis-style form view~~ **SHIPPED** (`2f63709` —
`FormAnalysisView` as the form concepts' lesson content); and **TTS narration**
(below).

### TTS narration — read the lessons + instructions aloud (maintainer, 2026-07-17)
Use TTS to read out the text explanations / instructions of the minigames and the
textbook. High learnability value: a **pre-reader (6–8yo)** can *hear* a lesson or
a game's how-to-play even before they can read it, and it makes the app accessible.

**Slice 1 — SHIPPED (2026-07-17).** `core/services/tts_service.dart`: a
`TtsBackend`-abstracted `TtsService` (mirrors `AudioService`'s `soundOn` gate),
locale-aware (`de→de-DE`, else `en-US`), best-effort (a missing OS voice degrades
to silence). Backend = `flutter_tts` (platform AVSpeechSynthesizer / Android TTS /
web SpeechSynthesis — on-device, offline, free). Wired a **🗣 read-aloud button**
into the shared **tutorial sheet**, so **both** the textbook lessons *and* every
game's how-to primer get narration from one change (the reader's "Read the lesson"
and the games' "?" both open this sheet). Provided in `main.dart`; `soundOn` synced
from settings alongside AudioService. Safe when unprovided (widget tests degrade to
no button). Tests: `tts_service_test` (fake backend — gating, voice mapping,
stop) + tutorial tests green. ⚠ needs `pod install` before the next Apple build
(new plugin); CI (analyze+test) unaffected.

**Slice 2 — SHIPPED (2026-07-17): the CrispASR neural backend, via CrispASR's own
model registry + downloader.** The higher-quality voice, behind the same seam.
`core/audio/tts/`:
- `crispasr_tts_backend.dart` — `CrispAsrTtsBackend implements TtsBackend` over the
  **`crispasr`** pub package (pure-Dart FFI → `libcrispasr`, ggml). Backend =
  **Kokoro** (82 M, Apache-2.0, multilingual). A background-isolate job
  (`runKokoroJob`) resolves the model+voice via CrispASR's **registry** and
  downloads through `cacheEnsureFile` (its C-side downloader — the same `-m auto`
  path the CLI + CrisperWeaver use); then `synthesize()` (~3 s → 24 kHz PCM) → PCM16
  → `wavBytes` → `AudioService.playWavBytes` (master sound switch still governs it).
  NaN/empty decode → null → silent fallback.
- `kokoro_model_store.dart` — **no hand-rolled URLs**: `registryLookup('kokoro')`
  gives the already-published `cstr/kokoro-82m-GGUF` model URL; voices are
  `af_heart` (en) / `df_victoria` (de) from `cstr/kokoro-voices-GGUF`; files cache
  into CrispASR's own cache (`~/.cache/crispasr`, override for a mobile sandbox).
  `isReady()` = lib loadable + model already cached.
- **Download is consent-gated**: playback never fetches (uses the model only if
  cached, else the platform voice); `backend.download(lang)` is the explicit opt-in
  (a settings action, mirroring CrisperWeaver's model manager).
- `tts_neural.dart` — conditional-import facade (mirrors `aec_capability.dart`):
  io/ffi impl compiles only where `dart:io` exists; **web gets a null stub**.
- `TtsService` **prefers neural when `neuralReady()` passes, else platform**.

**Verified:** the app's compiled dep resolves the **registry → published cstr HF
URL** (flutter test) AND the real macOS synth path (`libcrispasr.dylib` → Kokoro →
valid German audio, peak-checked); plus fake-seam unit tests for
playback/download-gating/locale routing. Download ABI symbols
(`crispasr_cache_ensure_file_abi` etc.) confirmed present in the dylib. 16 TTS tests
green; analyze clean (lib+test). Dep `crispasr: ^0.8.11` (pub.dev) → CI needs no
native lib.

**Slice 3 — SHIPPED (2026-07-17): the settings download trigger.** A **"Natural
voice (HD)" tile** in Settings (below the sound switch) — `_HdVoiceTile` +
`TtsService.neuralSupported/neuralReady/downloadNeuralVoice` + `NeuralTts` holder
(now carries `supported`/`download` too). It's **shown only where the native lib
loads** (invisible until libcrispasr is bundled), offers a one-tap **Download
(~135 MB)** → spinner → "On ✓"; once cached, narration auto-upgrades to the neural
voice. Degrades gracefully with no TtsService (settings tests untouched). EN/DE
ARB; 24 TTS/settings tests green; analyze clean.

**Slice 4 — SHIPPED (2026-07-17): macOS lib bundling (dev-verified).** `libcrispasr`
is 9.6 MB but drags in **8 more dylibs** (ggml ×5 + Homebrew opus/ogg), several
referencing the maintainer's Cellar/build tree by absolute path. `tool/
bundle_macos_tts.sh` (a mini `dylibbundler` in `install_name_tool`+`codesign`)
collects all 9 **self-contained** (copy-by-referenced-name, rewrite ids/deps to
`@rpath`, strip foreign rpaths to `@loader_path`, ad-hoc sign) and **statically
verifies** it. `KokoroModelStore.libPath()` gains a resolution cascade
(override → `.app`/Contents/Frameworks → `~/.cache/crispasr` → default). **Verified:
synth runs through the bundled set with only `@loader_path` on the rpath** (loads
the bundle's ggml, not the machine's) → portable/`.app`-ready. Dev flow: run the
script (→ `~/.cache/crispasr`), `flutter run macos`, the HD tile appears. Docs +
App-Store caveats in `docs/TTS_MACOS.md`; cascade unit-tested. Shared `macos/`
Xcode project intentionally NOT modified (multi-agent safety) — the release
Frameworks embed is documented for a release worktree.

**Remaining work:**
1. **Release `.app` embed** — add the Copy-Files-to-Frameworks phase (per
   `docs/TTS_MACOS.md`) in a release worktree + Developer-ID re-sign; then
   **iOS** xcframework, **Android** `.so` per-ABI, **web** WASM. Each platform
   falls back to flutter_tts until its lib ships. (The HD-voice tile then works.)
2. **German quality** (optional): fetch the `kokoro-de-hui-base` backbone (a second
   ~135 MB model) + route `-l de` for a cleaner German phonemizer; expose
   `set_length_scale` as a kid-friendly slower rate.

**Other follow-ups:** a dedicated *narration* toggle (accessibility) separate from
the master sound switch; **auto-narrate** a step when its example plays (opt-in).

### Extending the syllabus toward bachelor level (2026-07-17)
The grade-1–10 spine is the floor; the concept map extends **upward toward
undergraduate music theory** the same way (more bands / an `undergrad` tier). Draw
structure & facts from established OER — but **the licence governs how**:

| Source | Licence (verify per work) | How we may use it |
|---|---|---|
| **Open Music Theory 2** | CC-BY-SA 4.0 | facts + (adapted text OK **if** we attribute & share-alike the derived text) |
| **Understanding Music: Past & Present** (Clark et al.) | CC-BY-SA 4.0 | same as above |
| **Music Theory for the 21st-C Classroom** (Hutchinson) | **GFDL** | **facts/scope only — re-express.** GFDL is copyleft for *manuals*; shipping adapted GFDL text would obligate GFDL on the derivative, incompatible with our MIT/CC-BY mix → do NOT ship verbatim/adapted, use as a reference |
| **Kyle Gullings OER** (Undergrad Music Theory) | often CC-BY-**NC**(-SA) | **facts only** — NC forbids our commercial (App Store) use of the *text*; re-express is fine |
| **Multimodal Musicianship** (Malawey) | verify (Pressbooks OER, often CC-BY-NC-SA) | facts only unless a CC-BY/BY-SA item |
| **Open Music Academy** (openmusic.academy) | per-item, often CC-BY-SA | facts + adapt CC-BY(-SA) items with attribution |
| **ELMU** (E-Learning Plattform Musik) | verify per resource | facts; adapt only clearly CC-BY(-SA) items |
| **OER-Musik.de** (U. Kaiser OpenBooks) | typically CC-BY-SA | facts + adapt with attribution/share-alike |
| **Projekt #gis** (int'l students) | verify (OER) | facts; adapt only CC-BY(-SA) items |

**Governing rule (unchanged):** our default for *every* source is **re-express the
facts/structure in our own words** — always legal, sidesteps all licences.
Verbatim/adapted text is considered ONLY for **CC-BY / CC-BY-SA** works (with
attribution; SA obligates same-licence on the derived text), **never** for
**CC-BY-NC** (app is commercial) or **GFDL** (copyleft/incompatible). Keep a
per-source licence registry (`assets/licenses/` + the About page) for anything we
adapt. When unsure, re-express.

### AnaVis-style analysis view (idea → fills the *form* gap)
The maintainer asks: *can we get close to AnaVis?* AnaVis visualises musical
**form/harmonic analysis** as a colour-coded timeline (phrase/section blocks,
cadences) aligned to the music. That is exactly the **musical_form / phrasing**
concepts the gap report flags as untrained. Proposal: a **form-analysis view** —
a horizontal timeline under a `crisp_notation` score (or a playing cursor) with
labelled colour spans (A / B / A′ sections, antecedent/consequent phrases,
cadence points), and a matching **"label the form" minigame**. Feasible app-side
(score + a custom span-timeline widget); no new library dep. Tracks as: fills the
form gap **and** seeds an analysis feature. Later: harmonic-function spans
(T/S/D colouring) over a progression.
**SHIPPED (`2f63709`, `d3cb309`):** the "label the form" minigame (`form_read`) + a
non-quiz **`FormAnalysisView`** (`features/games/composition/form_analysis_view.dart`,
built on `FormTimeline`) that plays a piece's A/B/A′ sections section-by-section
**over an engraved `crisp_notation` score** (one bar per section), wired into the
Textbook's form concepts (`musical_form`/`song_form`) as a "See the form" lesson;
plus a **`HarmonyAnalysisView`** that colours a chord progression by function
(tonic/subdominant/dominant, with a legend + tap-to-hear), wired into
`harmonic_function`/`cadences` as "See the harmony"; plus a standalone
**`AnalysisHubScreen`** ("See the Music", `analysis_view` tile) hosting both. The
harmony view now engraves the progression as a real score (one whole-note chord
per bar) with the T/S/D spans aligned under it and cadence markers under the
final chord (`6107392`). **The AnaVis idea is fully realised.**

## Delivery

- GitHub: `CrispStrobe/cometbeat` (app), `CrispStrobe/crisp_notation` (lib).
- **CI** (`.github/workflows/ci.yml`): every push/PR runs format + analyze +
  test and uploads coverage (~85% of `lib/`). It checks out `crisp_notation` as a
  sibling so the `../crisp_notation` path dependency resolves on the runner.
  Analyzer is strict (`strict-casts`/`strict-raw-types`); the `build` symlink
  is untracked (it points at a dev-only SSD path and would dangle on CI).
- Web: Vercel (`mus` project), prebuilt `build/web`, same pattern as voc.
  A root `.vercelignore` drops the Flutter build's `*.symbols` debug maps
  (~8 MB, never fetched at runtime) from the upload; the served bundle is
  brotli (main.dart.js ~924 KB, canvaskit.wasm ~2.85 MB, fonts tree-shaken).
- pub.dev publication of crisp_notation: deliberately **not yet** (maintainer
  decision); everything is consumed via path/git.

## Learnability & UX — zero-knowledge onboarding (P0/P1 shipped; content ongoing)

> **Status (shipped to origin/main, CI-green):** the **sound on/off toggle** +
> silence fix, the **mascot idle-greet**, and the **tutorial system** are live —
> now with **all 13 module primers + 8 ★ per-game primers** (21 total, covered
> by the `tutorial_test` loop), an **app-wide "?" reopen** (a help FAB overlaid
> by `TutorialGate` on any game with a primer), a reusable **`GameAppBar`**
> (title + app-wide `SoundToggle` + optional "?"; adopted on `accidental_sort`
> so far), and a **mascot presenter** in `RoundHeader` (idle greet per question).
>
> **Remaining follow-ups (this section, ranked by value ÷ effort):**
> 1. **Help on every game.** Only 21/100 games carry a primer, so the other 79
>    show no "?"/first-run help. **Fix without per-game edits or auto-show spam:**
>    give `TutorialGate` a **module-primer fallback** — a `kModulePrimers` map
>    (module → its general primer) so the "?" opens the module primer for any
>    game lacking its own, while **auto-show stays curated** (entry + ★ games
>    only, so a module's intro doesn't re-pop on every game). *(S · registry +
>    tutorial_gate.)*
> 2. **`GameAppBar` roll-out.** Adopt it across the ~84 remaining screens
>    (module-by-module) to put the sound toggle in every bar. Mechanical but
>    collision-prone (hot screen files); the reopen "?" is already app-wide via
>    the overlay, so this is now mostly about the in-bar toggle. *(L · sweep.)*
> 3. **Fuller mascot presenter.** Upgrade the idle presenter to a
>    `MascotPrompt` (mascot + speech bubble that reads the question) and default
>    `FeedbackLine.showMascot = false`. *(M · `game_widgets`/`note_mascot`.)*
> 4. **New-game hygiene (see backlog §G):** new games adopt the tutorial hook +
>    mascot API; audit the recent sort/arcade games for reduced-motion + the
>    sound toggle.

The bet: a child with **no** prior music knowledge should be able to open any
minigame, be taught the facts it needs (with heard + seen examples), and play it
through. Plus fix a sound regression and give sound a global switch. (Original
structural map, now mostly addressed: every screen built its own AppBar — a
shared `GameAppBar` now exists but isn't swept in yet; the mascot lived only in
`FeedbackLine` — now also presents in `RoundHeader`; the tutorial/help system is
built and live.)

### P0 — App-silence regression
Symptom: audio goes silent app-wide, suspected after play-along. Likely cause:
there is **no global audio-session / `AudioContext`** (`main.dart`, `AudioService`),
so the `record` mic flips the iOS/Android session to record/`playAndRecord` (routes
to the quiet earpiece) and does not restore it, muting `audioplayers` afterwards.
Fix: set a global playback `AudioContext` (speaker-routed, mixes/ducks) once at
startup; have `MicrophonePitchService.stop()` restore it; verify metronome +
backing + SFX are audible before **and after** using the mic. (No repro device
here — validate on macOS/web locally + reason from the session model; confirm on
hardware in (e)-style testing.)

### P0 — Global sound on/off toggle in the top bar
- **Behavior:** one chokepoint — gate `AudioService._play()` with `if (!soundOn) return;`
  (`core/services/audio_service.dart`). Mutes notes/chords/SFX/ticks/backing for
  all 97 games at once; the **mic is unaffected** (intonation games still work).
- **State:** add `soundOn` to `SettingsService` (SharedPreferences, mirrors the
  existing `showTimer`/`instrument` pattern), synced to `AudioService` at
  `main.dart` where `instrument` already is.
- **UI (app-wide):** there is no shared AppBar, so introduce a shared
  **`GameAppBar`** helper (a `PreferredSizeWidget`) that carries the speaker
  on/off action **and** the tutorial "?" button (below), and migrate game
  screens onto it module-by-module. Ship the toggle immediately on Home +
  Settings; the per-game top-bar icon lands as screens adopt `GameAppBar`.

### P1 — Mascot: from idle prop to guide
`NoteMascot` (`shared/widgets/note_mascot.dart`, moods idle/happy/oops) currently
sits in `FeedbackLine` (between the question and the 4 options, 53 screens) doing
nothing at rest. Move it to a **presenter** role: a `MascotPrompt` (mascot +
speech bubble that reads the question) inside `RoundHeader`, **before** the
question; default `FeedbackLine.showMascot = false` (feedback text stays). Give
the mascot a gentle **idle animation** (breathe/blink/sway) so it's alive, and
keep the happy/oops reactions. Editing the two shared widgets
(`game_widgets.dart`, `note_mascot.dart`) reaches every game uniformly.

### P1→P2 — Tutorials for every minigame (the big one)
Each game gets a short, **illustrated + playable** explanation of exactly the
musical facts it drills, so a zero-knowledge child can clear it.
- **Framework:** a `Tutorial` model = ordered steps, each with text + optional
  **notation** (`StaffView`/`kidsScoreTheme`) + optional **"listen" example**
  (`AudioService.playSequence`/`playMidiChord`/…). A `TutorialSheet` renders it.
  Shown **auto on first entry** (persist "seen" per game id) and reopenable via
  the **"?"** in `GameAppBar`. New optional hook on `GameInfo`
  (`game_registry.dart`), e.g. `Tutorial Function(AppLocalizations)? tutorial`.
- **Content:** author module-by-module (10 modules, 97 games), EN/DE in the
  ARBs, teaching the underlying knowledge — staff & clefs, note/rest values &
  beats, meter/measures, scales (Dur/Moll), intervals & chords, harmony (T/S/D),
  the cello/guitar/piano corners — each with a heard example and a shown example.
  Reuse one shared "primer" per module where games overlap, specialized per game.
- **Phasing:** (1) framework + "?" + first-run gating + `GameAppBar`; (2)
  author the note-reading + note-values primers (highest-traffic); (3) sweep the
  remaining modules. Coordinate ARB/`game_registry` edits (hot files) with the
  parallel agents.

## Competitive analysis & opportunity roadmap

Benchmarked against 30+ music-learning apps (mid-2026, four research sweeps:
gamified-instrument, theory/ear-training, kids-focused, and
sight-reading/composition + DACH). Competitor names are deliberately kept out of
this repo; the notes below describe capability *categories*, not products.

### The strategic read

- **Our real competition is not the big paid instrument-tutor apps.** Those are
  adult-first, treat notation as a display mode, and have no German-curriculum
  tie-in. In the DACH market we compete with a couple of free incumbents (a
  curriculum-aligned school platform and a public-broadcaster kids' site) plus a
  thin cluster of small theory/notation tools.
- **The children's notation-literacy niche is genuinely thin.** German teaching
  materials note that note-reading is required in every Bundesland yet there is
  little kindgerechtes Unterrichtsmaterial zum Notenlernen — that gap is the
  opening.
- **Two open moats:** explicit **Lehrplan alignment** (only the incumbent school
  platform claims it) and **genuinely bilingual EN/DE pedagogy** (rivals are
  German-only or English apps with translated strings — almost none are built
  bilingual).
- **Where we already lead** (rare among kids' apps): SM-2 spaced repetition,
  real four-clef notation, theory/harmony depth (T/S/D, cadences), a composition
  sandbox with MusicXML export, bilingual EN/DE — and now **live mic input**.
- **The structural gap that used to set the strong rivals apart — live
  real-instrument input — is now closed on the mic side** (play-along/sing-along,
  tuner, chord listener; see HISTORY). MIDI input remains open.

### Opportunity backlog (implement top-to-bottom)

Effort S/M/L; fit ♪–♪♪♪ (mission fit for a kids' notation/theory app). Source =
the app category the idea comes from. Shipped items live in
[HISTORY.md](HISTORY.md#opportunity-backlog--shipped).

**Strategic bets — extend the SM-2 / notation core**
- [ ] Parent view + multi-child profiles. *(kids' practice apps.) M · ♪♪.*

- [x] Lehrplan alignment + German framing. **Shipped**: a **Curriculum** screen —
  generic progress levels tied to **school years** (Klasse 1–2 … 9–10), each
  topic mapped to the games that drill it, with a *readiness* meter from the
  child's stars, a "continue here" marker on the recommended level, and
  per-level / weakest-topic practice runs. Readiness blends **star coverage ×
  SM-2 retention** (`SriService.masteryUnder(namespace)`), so it reflects both
  breadth and whether skills actually stuck. The engine (`Curriculum → Level →
  Topic → gameIds`) keeps per-region variants as drop-in data. *Open: optional
  per-Bundesland variants (rough matching is fine).*
- [ ] Sound-toy creative modes that feed notation (grid composer + geometric
  rhythm toy for pre-readers). *(browser music sound-toys.) M · ♪♪.*
- [ ] Color-coded kids' notation editor with MusicXML/MIDI export. *(kids'
  notation-editor apps.) M · ♪♪.* Closest to our existing sandbox.
- [ ] Teacher / LMS layer for school licensing (roster, assign-and-track, Google
  Classroom). *(classroom notation/DAW platforms.) L · ♪♪.* Schools buy per-seat.

**Big swings — category table-stakes, heavy lift**
- [x] Real-instrument input — **mic side shipped**: live pitch/chroma detection
  powers **Play-along / Sing-along** (moving-score grading), a **Tuner**, and a
  **Chord Listener** ([HISTORY.md](HISTORY.md#live-microphone--pitch-detection)).
  *Open: MIDI input; wiring mic grading into more of the corners.*
- [ ] Generative sight-reading + performance grading — endless non-repeating
  exercises scored for pitch & rhythm. *(generative sight-reading services.) L · ♪♪♪.*
  Answers the teacher-reported material shortage directly. *(Staff Runner is the
  kid-scale stepping stone; mic grading now exists to score the performance.)*

### Live-mic follow-ups (the mic pipeline is shipped — exploit it)

Now that live pitch/chroma detection, the `PlayAlongEngine`, and the moving-score
UI exist, these are high value ÷ effort because the hard infra is done:

- [x] **"Perform It" — mic-graded reading.** **Shipped**
  ([HISTORY.md](HISTORY.md#live-microphone--pitch-detection)): a note is shown;
  the child **plays or sings it** and the pitch detector verifies it
  (octave-agnostic, sustained-match), instead of tapping a letter. Feeds the
  shared `note_reading.<clef>.*` SM-2 pool. The kid-scale core of the
  generative-sight-reading big swing.
- [x] **Sing-back ear training.** **Shipped**
  ([HISTORY.md](HISTORY.md#live-microphone--pitch-detection)): a note plays; the
  child sings it back and the mic grades it (octave-agnostic). Target is *heard*,
  not shown — trains pitch memory & matching, needs no instrument. Feeds the ear
  pool `scales.hear.*`.
- [ ] **Play-along for the Song Book.** Extend play/sing-along to the real
  public-domain songs — play or sing Twinkle & co. against the moving score. *M · ♪♪.*
- [~] **Mic grading in the instrument corners.** "Play this note/string/finger"
  verified by the mic. **Cello shipped**
  ([HISTORY.md](HISTORY.md#live-microphone--pitch-detection)): a first-position
  note + string/finger hint, played on the real cello and graded by the mic
  (octave-agnostic, feeds `cello.play.*`). Guitar & piano corners still open. *M · ♪♪.*
- [ ] **Parent view + multi-child profiles.** *(kids' practice apps. M · ♪♪.)* A
  parent dashboard over the curriculum **readiness** — each child's school-year
  progress at a glance; per-child profiles. (Also listed under Strategic bets.)

Caveats: competitor prices/age-ratings drift; some DACH adoption/award figures
are self-reported — verify before external citation.

## Gamified formats (from the sibling-app survey)

New *interaction mechanics* surveyed across `../voc` and `../space_math_academy`.
Shipped formats (memory pairs, sequence, sort-into-buckets, swipe, falling-notes,
connect-a-line) live in [HISTORY.md](HISTORY.md#gamified-formats--shipped).
Sub-variant sweep **mostly done** (Jul 2026 batch): shipped **Longest First**
(note-value ordering), **In the Scale?** (swipe membership), **High or Low?** +
**Sharp or Flat?** (two-basket sorts on pitch-direction / accidental-sign),
**Higher or Lower?** (direction-by-ear), **Step or Skip?** (motion reading), and
**Connect the Steps** (interval↔number, a 3rd Connect-the-Notes mode). Details in
[HISTORY.md](HISTORY.md#gamified-formats--shipped). Still open from this survey:

- [x] **Major/minor sort** — **shipped** (`major_minor_sort`, chords): drag written
  triads into Major / Minor baskets by reading their quality on the staff
  (Diminished joins at 2★); the chord sounds on a correct drop. The reading twin of
  the aural `major_minor_ear`. SRI `chords.quality.<major|minor|diminished>`.
- [ ] **Falling-notes "catch the longest"** — a note-*values* mode of the arcade.
  *Caveat: `falling_notes_screen.dart` is ~930 lines of ticker/combo logic and
  its tests lean on the animation clock — a real lift, and less tap-robust than
  everything else in the batch. Budget accordingly.*
- [ ] **Melody-recall ear variant** of the sequence format — hear a 3–5 note
  tune, tap it back. *Check overlap first: `melody_echo`, `echo_sequence`, and
  `sound_echo` already exist; only build if it adds a distinct twist (e.g.
  tap-back on a staff rather than a keyboard).*

### Toy-inspired mechanics (electronic-toy lineage)

Classic hand-held electronic music/reaction toys, reimagined for notation & ear
training. Shipped: Sound Echo, Follow the Conductor
([HISTORY.md](HISTORY.md#toy-inspired-mechanics--shipped)).

- [x] **Strum toy** — swipe/strum across the screen to sound a chord or arpeggio;
  a free "air-instrument" jam built on the existing fretboard/keyboard widgets. *S–M.*
  **Shipped** ([HISTORY.md](HISTORY.md#toy-inspired-mechanics--shipped)).
- [ ] **Loop mixer** — tap/place cards that each trigger a synced musical loop
  (bass / chords / melody / drums), layering a mix in time. Creative sound-toy.
  *L — needs multi-track synced loop playback.*
- [ ] **Two-hand split** — left and right zones each run their own short
  sequence/beat to keep going at once (piano-hands coordination). *M–L, advanced.*
- [ ] **Move-to-the-beat caller** — a move/gesture is called on each beat; perform
  it in time (rhythm + reaction). *M.*

### New minigame concepts (original — not from the surveys)

Fresh ideas that fit the machinery we already have (crisp_notation notation, pure-Dart
audio, the SM-2 engine, the falling/connect/reaction engines) and target skills
the curriculum doesn't yet drill.

**All shipped** — Ledger Leap, Key Detective, Odd One Out, Note Whack, Interval
Ladder, Staff Runner, Chord Grip Hero, Dynamics & Tempo Charades, Note Snake, and
Recital Mode all live now
([HISTORY.md](HISTORY.md#original-concepts--shipped)). New original ideas get
added here as they come up.

## Loop Mixer 2.0 — the groovebox ladder (roadmap) — ✅ ALL SLICES SHIPPED

All 10 slices shipped (2026-07-17; slice 5 deferred to the Tracker by design).
The full slice-by-slice roadmap + build record moved to
[HISTORY.md](HISTORY.md#loop-mixer-20--the-groovebox-ladder-roadmap). Follow-ups
(groove→score export, native-AEC jam grading) are specced in
[`LOOP_MIXER_FOLLOWUPS_HANDOVER.md`](LOOP_MIXER_FOLLOWUPS_HANDOVER.md).

## Loop Mixer 3.0 — from mixer to instrument (scoped ideas)

**STATUS 2026-07-19: PLANNED — scoped, unclaimed.** The 2.0 ladder made the Loop
Mixer *capable* (data patterns, variants, swing, progressions, capture, jam,
share; both follow-ups — groove→score export, native-AEC jam grading — also
shipped). But **at rest it still reads like a settings form**: five on/off cards,
a row of beat dots, one effect button, and everything in one key/one kit. Nothing
on screen reacts to the audio, there's no way to *perform* (no build-up, no live
effects, no launch feel), and every session sounds like the same band. This
section scopes the work to make it feel **alive and inexhaustible** — a toy that
plays like an instrument. **Maintainer's pick to lead with: the *content
variety* set (§B)**, because it multiplies what every later slice has to play
with. The rest is ordered by fun-per-effort, not dependency; most items are
independently shippable.

**Diagnosis — why it feels flat (five gaps, each addressed below):**
1. No performance/arrangement layer — cards are binary toggles; the only build-up
   is an *automatic* fill every 4th bar. You configure; you never play. → §C, §G
2. Almost no visual feedback — just beat dots; the cards ignore the audio. → §E
3. One flavour — hardcoded C-pentatonic, one synth kit, 5 stems × 3 variants. → §B
4. Sound design is one button — a whole `crisp_dsp/` toolbox sits imported but
   unused (only `modulated_delay`/`reverb` are wired). → §C
5. The genuinely fun parts (sing / beatbox / jam / follow) are buried in a 34px
   strip under a static grid. → surface them as part of §E/§F.

**Invariants every item MUST preserve (the 2.0 spine):**
- **Any combination stays consonant** — new pitched content is authored in, or
  rigidly transposed within, one scale so no two layers clash (the "colour
  melody" rule). Non-negotiable for a 6+ audience.
- **Sample-integral timing** — step length stays a whole number of ms *and*
  samples at 44.1 kHz (`LoopTiming`), or the seam clicks and stems drift.
- **Backward-compatible spec/token** — new `GrooveSpec` fields must default so old
  `KU1.` tokens still decode (`fromJson` already tolerates missing keys); extend
  `cacheKey` so new renders don't collide with cached old ones.
- **No step editor here** — grid editing is the Tracker's job by design; the Loop
  Mixer stays the *playing* surface.
- Engine work is additive; existing signatures stay stable. Acceptance bar (from
  the ladder): every slice ships a headless roundtrip test that proves the
  *feature* (render → `listen.dart --wav` reads the authored/transposed notes, or
  a synth→detector roundtrip), not just unit coverage.

### §A. Bug — the live-engraving ("show as sheet music") panel is broken — ✅ FIXED (`ad1ab10`)
**Resolved:** it wasn't a render crash (layout + widget both fuzz-clean). The panel
only engraved the single *leading* pitched track, so a full band showed just
melody/chords (bass/sparkle outranked, drums never engraved), and toggling Score
with nothing enabled silently showed nothing. Now: one labelled staff **per
enabled track** (drums/beat as a rhythm reduction via `drumGrooveScore`), compact
fixed-height rows so the whole band shows at once, + an empty-state hint. Original
scoping kept below for the record.

The score panel (`loop_mixer_screen.dart:1362` → `StaffView(score: grooveScore(
_engine.cellsFor(id)!, …))`) renders wrong / nothing / crashes. `grooveScore`
itself is pure and unit-tested (`groove_notation_test.dart`), so the fault is in
the app path: suspect the **progression-mode cells** (`cellsFor` returns 4
resolved bars including multi-midi chord cells) not engraving cleanly inside the
96px `FittedBox`, a `StaffView` regression, or a null/empty edge. **Needs a live
repro first** — run the screen, toggle the Score button with each of
melody / chords / bass enabled, with and without a progression, and capture what
actually renders. Then fix + add a widget/golden test so it can't silently
re-break. **S–M. Do this first — a visibly broken feature undercuts the whole
toy.**

### §B. Content variety — break the one-flavour limit (the chosen lead)
1. **Key & scale select.** Add `key` (root pitch-class 0–11) + `scale`
   (major-pentatonic / minor-pentatonic; later dorian/blues) to `GrooveSpec`;
   transpose every pitched stem and the jam/`chordAtBar` math by the root, and
   swap the pentatonic set + tonic/relative logic for minor. Rigid transposition
   preserves the consonance guarantee for free. Instantly multiplies mood (a low
   minor groove feels nothing like bright major). UI: two chip rows. **M.**
   Verify: render → `listen.dart --wav` reads the transposed notes; token
   roundtrip; every key×scale combo stays all-consonant.
2. **Swappable drum kits.** Parameterize `renderDrum` (`synth.dart`) with a
   `DrumKit` profile (tuning, decay, noise colour, pitch-sweep depth) + add
   `GrooveSpec.kit`. Ship ~4: the current clean synth, a deep round electronic
   kit, a soft acoustic kit, a dusty/filtered lo-fi kit. Zero pattern authoring —
   pure timbre, transforms the vibe. UI: a kit chip row. **M.** Verify: kit
   changes the rendered spectrum (peak/decay assertions) but not the onset grid.
3. **Style presets (the headline "many flavours").** A `Style` bundles a per-stem
   pattern *feel* (drum groove family, bass motion, chord voicing, melody
   character) plus default tempo, swing, kit and scale bias. The current patterns
   become the default style; author 3–4 more (laid-back swung, four-on-the-floor,
   gentle latin, mellow lo-fi). Picking a style re-points which pattern set the
   five cards draw from. Composes items 1–2. **L** (pattern authoring is the
   cost). Verify: each style renders, stays consonant, default tempo keeps timing
   sample-integral.
4. **More variants + per-card "roll".** Grow A/B/C toward A–E per stem, and add a
   small "roll this card" control that swaps to a random *in-style* variant. Cheap
   content multiplier. **S–M.**

### §C. Performance & live feel — make it playable, not just configurable
1. **Momentary effect strip — hold to apply, swipe to sweep (the FULL streaming
   path).** A bottom row of large effect pads active only while a finger is down;
   drag up/down sets intensity. Real-time, zero-latency effects on the mix bus: a
   sweepable low/high filter, a beat-repeat/stutter gate, a tape-stop (pitch+time
   ramp to a halt), an echo throw, a bit-crush. The single best-feeling touch
   gesture in the genre — momentary (hold) beats toggle because it self-corrects
   on release. This is the app's ONE real audio wall (the 2.0 spine flagged it):
   the output today is a fixed `BytesSource(wav)` via `LoopPlayerService`, so
   there is nothing to sweep in real time. Scoped in three slices:
   - **§C-1a — streaming-audio backend (infra, the wall).** A PCM-feed player so
     the mix is generated + effected + played as a continuous stream instead of a
     baked WAV. A new dependency (e.g. a PCM-feed sound package) or a platform
     channel (CoreAudio/AAudio/WebAudio). Design it as a shared
     `StreamingAudioSink` (feed Float64/Int16 blocks; underrun-safe ring buffer)
     so **jam mode and the DAW reuse it**, not just the FX strip. Audio output
     isn't verifiable in `flutter test` — acceptance is the BlackHole acoustic
     loop (auto-memory) + manual device checks. **L; the maintainer-approved
     architecture commitment.**
   - **§C-1b — streaming effect DSP core (pure, unit-tested — BUILDABLE NOW,
     no backend needed).** Stateful, seam-continuous, live-parameter effects that
     process a PCM stream block-by-block keeping filter state across blocks (so a
     swept cutoff never clicks): first a bipolar LP↔HP `StreamingFilter`
     (Direct-Form-I RBJ, own coeffs so cutoff is live-tunable — `Biquad` bakes its
     coeffs at construction and hides its state, so it can't sweep), then stutter/
     tape-stop/echo/crush. Flutter-free like `synth.dart`; unit-tested against
     synth tones (LP attenuates highs, HP attenuates lows, one-block == two-block
     for continuity, a sweep stays bounded). **S–M each. This is the slice I can
     ship headlessly today.**
   - **§C-1c — the FX-strip UI.** Hold-to-apply / swipe-to-sweep pads wired to the
     §C-1b effects over the §C-1a sink. Needs both above. **M.**
2. **One-knob "make it sound produced" master filter.** ✅ SHIPPED (offline,
   seam-swap `biquadFx`) by loop-mixer-3efg — the cheap version of the filter that
   works on the existing baked-WAV path (a knob re-renders + swaps at the seam).
   The §C-1 streaming path upgrades this to zero-latency once the backend lands.
3. **Quantized launch with an "armed/queued" glow.** Toggling a card (or a
   section, §G) never fires instantly — it pulses "waiting" and snaps in on the
   next bar. The seam scheduler already swaps at the boundary; this just exposes
   it as *felt* feedback, so stabs always land on beat. **S.**
4. **Dice / "surprise me".** One button rolls a fresh always-good groove: a random
   in-style enabled set + variants (+ maybe key/kit). Instant gratification and a
   cold-start for a kid who doesn't know where to begin. Recombines existing
   content. **S.**

### §D. Visual juice — make the sound visible
1. **Beat- & level-reactive cards.** Every enabled card pulses on its own hits and
   glows to its live level (drive from the rendered stem's per-step energy, which
   the engine already computes). The biggest single cause of the "static form"
   feel is that nothing reacts to the audio. Procedural — no art assets. **S–M.**
2. **Embodied parts — each stem as a little performer.** Replace/augment the
   slider-cards with a small animated character per stem that visibly performs its
   loop (bobs on the beat, "sings" when active, goes still when muted) so the
   arrangement is legible to a non-reader at a glance. Reuse the app's existing
   mascot visual language for art direction. Biggest perceived transformation;
   mostly art + choreography over the existing `mixStems`. **M–L** (needs an
   art-direction call).
3. **Step-resolution playhead + mini-visualizer.** Upgrade the beat-dot row to a
   step playhead over a light waveform/level lane so you can watch the loop
   breathe. **S.**

### §E. Discovery & game shape — pull replay
1. **Secret combos.** A small data table: certain enabled-stem sets (or set +
   key/style) unlock a one-off bonus — a special animation and/or an extra
   musical layer/fill you can't get otherwise. Show a "found 1/3" tracker per
   style. Turns an open sandbox into a hunt; the retention engine. Sits on the
   existing `spec → WAV` caching. **S–M** (data + a reveal animation).
2. **Gentle band-challenges.** Optional zero-pressure prompts ("add something high
   and sparkly", "make it feel calm") that nudge exploration without a score,
   matching the app's no-fail stance. **S.**

### §F. Play & improvise — add a *play* verb
1. **Scale-locked smear pad (solo surface).** A pad where dragging a finger plays
   only in-key notes over the running groove (horizontal = pitch, vertical =
   rhythm/density). Impossible to hit a wrong note; lets a child improvise a lead,
   captured into a layer. **M.**
2. **Record-your-own-sound → a playable part.** Extend the shipped mic capture so
   a sampled voice/clap/mouth-sound is auto-chopped and joins the mix as its own
   card/character ("that's MY voice in the song!"). Builds on `groove_capture` /
   `beat_capture`. **M.**

### §G. Build-a-song & keep it — arrangement + pride of authorship
1. **Section/scene grid.** Columns are song sections (intro / groove / drop /
   outro); tapping a section launches its whole layer set at once, quantized;
   chain sections to auto-advance into a full arranged track. The direct answer to
   "it's just one loop." Composes §C-3. **M–L.**
2. **Record & replay the performance.** Capture a whole session (cards toggling,
   effect swipes, sections) as a timeline you can play back and export as one
   arranged track — not just the 2/4-bar loop. Extends the shipped WAV/MP3
   export; gate any sharing behind the parental-control stance. **M–L.**
3. **Save slots / preset shelf.** In-app named groove slots (the share token
   already serializes the spec) so a kid can keep and revisit their bands. **S.**

## Ideas backlog for the next agent (Jul 2026 handoff)

Brain-dump of every game/feature idea still on the table after the Jul-2026
web-safe batch, ranked roughly by value ÷ effort. **All are web-safe (no native
FFI) unless flagged.** Reuse the existing scaffolds — a new game is one `GameInfo`
in `game_registry.dart` + a screen + a `kStarThresholds` bracket in
`core/tuning.dart` + ARB keys (EN/DE) + a widget test. Follow the strict
`dart format` → `flutter analyze` (whole project) → `flutter test` → commit →
push → watch-CI loop, and keep the board above in sync (parallel agents!).

**Reusable scaffolds proven this batch (copy them, don't reinvent):**
- *Two-basket sort* — `pitch_sort_screen.dart` / `accidental_sort_screen.dart`
  (Draggable→DragTarget, `onWillAcceptWithDetails` gates the drop). Test drives
  real drags and tries each basket until one accepts (`pitch_sort_test.dart`).
- *Binary ear* — `direction_ear_screen.dart` (replay button + two answer
  buttons; `@visibleForTesting` tester interface exposes the correct answer so
  the test taps it).
- *Binary staff-read* — `step_skip_screen.dart` (staff card + two buttons).
- *Swipe/tap card* — `in_scale_screen.dart` (swipe + tap labels + arrow keys).
- *Connect-a-line* — add a `ConnectMode` case to `connect_line_screen.dart`.
- All staff-based tests **must** use `pumpGame`/`useGameSurface` (CI's 800×600
  surface throws `getElementPoint` otherwise — see the board's ✅ note).

### A. Tap-robust minigames that fill a real skill gap (best value)
- [x] **Whole-step or Half-step?** — **shipped** (Noten lesen): read a 2nd on the
  staff and tap tone vs semitone (half steps hide at E–F/B–C), and hear the
  interval; treble at 1★, +bass at 2★. SRI `reading.tone.<whole|half>`. See
  [HISTORY.md](HISTORY.md#crisp_notation-powered--shipped).
- [x] **Same or Different?** (binary ear) — **shipped** (Tonleitern): two notes
  play → same pitch or different; clear leap → subtler gaps at 2★. SRI
  `pitch.hear.<same|diff>`. See [HISTORY.md](HISTORY.md#crisp_notation-powered--shipped).
- [x] **Which Clef?** (binary) — **shipped** (Noten lesen): a bare clef on an
  empty staff; tap Treble or Bass, widening to Alto/Tenor at 2★. SRI
  `reading.clef.<name>`. See [HISTORY.md](HISTORY.md#crisp_notation-powered--shipped).
- [x] **Dotted or Not?** (two-basket sort) — **shipped** (Notenwerte): drag note
  glyphs into Dotted/Plain baskets by reading the augmentation dot (value varies
  so shape alone doesn't give it away). SRI `note_values.dot.<dotted|plain>`. See
  [HISTORY.md](HISTORY.md#gamified-formats--shipped).
- [x] **Ascending or Descending?** (binary ear) — **shipped** (Tonleitern): a 3–4
  note run plays → climbs up or steps down; 4 notes at 2★. A step past Higher or
  Lower?. SRI `pitch.hear.<asc|desc>`. See
  [HISTORY.md](HISTORY.md#gamified-formats--shipped).
- [x] **Count the Notes** (ear) — **shipped** (Tonleitern): a phrase of 2/3/4
  distinct notes plays → tap how many you heard. Aural attention, no staff, three
  answer buttons, `playPhrase`. SRI `pitch.hear.count<n>`. See
  [HISTORY.md](HISTORY.md).

### B. Cheap depth — widen games that already exist (S effort each)
- [~] **Bass-clef variants** of the new sorts/readers — a `clef` constructor
  param + a second `GameInfo` doubles the content (mirror how `note_reading` /
  `place_note` ship treble + bass). **Shipped:** ✅ *Step or Skip? (bass)*
  (`step_skip_bass`) · ✅ *High or Low? (bass)* (`pitch_sort_bass`) — each with
  its own `progressId` so treble progress is untouched. · ✅ *Sharp or Flat?
  (bass)* (`accidental_sort_bass`). · ✅ *Find the Key (bass)* (`key_find_bass`,
  keyboard) — the staff→piano bridge, bass clef: the `PianoKeyboard` shifts two
  octaves down (C2..B3) so the low staff naturals (G2..A3) land on real keys;
  own `progressId`, and the SRI token carries the octave so bass items never
  collide with treble. (`Connect the Notes` already ships `connect_line_bass`.)
- [x] **Step, Skip, or Leap?** — **shipped**: `step_skip` (and its bass variant)
  becomes a 3-way at 2★ — Step (2nd) / Skip (3rd–4th) / Leap (5th+), a third
  answer button + `reading.motion.leap`; below 2★ it stays the binary drill.
- [x] **3-basket sorts** — **shipped**: *Sharp or Flat?* (`accidental_sort`, +bass)
  widens to a **Sharp / Natural / Flat** 3-basket sort at 2★; below 2★ it stays
  the binary ♯/♭ drill (mirrors Step→Skip→Leap). The natural glyph (♮) is real —
  crisp_notation renders it via `NoteElement.showAccidental` on an unaltered
  pitch (`alter:0 + showAccidental:true → accidentalNatural`, verified at the
  layout level). Card sign refactored bool→`int alter` (+1/0/-1). SRI gains
  `accidentals.sign.natural`.
- [~] **More Connect modes** — note↔piano-key, rest↔note-value, Italian-term↔
  meaning, dynamic-mark↔meaning, instrument↔clef. Each is one `ConnectMode` case.
  **Shipped:** ✅ *Connect the Dynamics* (`connect_dynamics`, note_values) — match
  each dynamic mark glyph (pp…ff) to its meaning word (very soft…very loud); 4
  clear steps for beginners, mp/mf join at 2★. SRI `reading.dynamics.*` (shared
  with `dynamics_duel`, so the reading and compare-loudness drills reinforce one
  skill). ✅ *Connect the Rests* (`connect_rests`, note_values) — match each rest
  glyph to the note it equals in length (quarter rest ↔ "quarter note"); whole/
  half/quarter/eighth for beginners, sixteenth at 2★. SRI `note_values.rest.*`.
  ✅ *Connect the Tempo Words* (`connect_tempo`, note_values) — match each Italian
  tempo word to its meaning (Largo ↔ "very slow"); Largo/Adagio/Allegro/Presto
  for beginners, the middle terms (Andante/Moderato/Vivace) at 2★. SRI
  `reading.tempo.*` (shared with `tempo_duel`). ✅ *Connect the Beats*
  (`connect_beats`, note_values) — match each note-value glyph to how many beats
  it lasts in 4/4 (whole 4 / half 2 / quarter 1 / eighth ½; sixteenth ¼ at 2★).
  SRI `note_values.beats.*` — the duration-in-beats twin of the symbols mode
  (which teaches the *name*). Remaining Connect idea worth doing: instrument↔clef
  — but awkward cardinality (few clefs, many instruments) makes a weak 4-pair
  round; parked. NB the **note↔piano-key** bridge is already its own game, not a
  Connect mode: `key_find` (staff note → tap the key) now ships treble **and**
  bass, both on the reusable `lib/shared/widgets/piano_keyboard.dart`
  (`PianoKeyboard`, already used across ~7 games).

### C. Reading vocabulary the curriculum wants but we don't drill
- [x] **Louder or Softer?** — **shipped** (`dynamics_duel`, note_values): two
  SMuFL dynamic glyphs (pp…ff) as cards, tap the louder; a compare-two duel like
  Faster or Slower?. SRI `reading.dynamics.<mark>`. (`charades` covers the aural
  side; this is the reading side.)
- [x] **Faster or Slower?** — **shipped** (`tempo_duel`, note_values): two Italian
  tempo terms (Largo…Presto) as cards, tap the faster; a compare-two duel like
  Duration Duel but text-based. SRI `reading.tempo.<term>`.
- [x] **Tie or Slur?** — **shipped** (`tie_slur`, note_reading): read the curve —
  same pitch (tie, `NoteElement.tieToNext`) vs different pitch (slur,
  `Score.slurs`); a binary staff-read like Step or Skip?. SRI
  `reading.curve.<tie|slur>`.
- [x] **Beam or Flag?** — **shipped** (`beam_flag`, note_reading): read the two
  looks of eighths — joined by a beam (two eighths on one beat) vs each keeping
  its flag (eighths split by an eighth rest). A binary staff-read; the beam/flag
  contrast was verified at the crisp_notation layout level (same-beat eighths →
  1 beam; eighth-rest between → 0 beams). SRI `reading.beam.<beamed|flagged>`.

### D. Ear-training expansion (mic infra is shipped — exploit it)
- [x] **Sing/play the interval** — **shipped** (`sing_interval`, chords): two
  notes play (root→top), the interval's name is shown, and the child sings the
  TOP note back; the mic grades it octave-agnostic (pitch class), held briefly —
  reusing the `sing_back` capture harness. Third/fourth/fifth for beginners,
  second+sixth at 2★. SRI `intervals.sing.<name>` — the sung twin of Interval
  Ear. (Built on crisp_notation's `Interval` + `Pitch.transposeBy`.)
- [x] **Rhythm echo by tap** — **already shipped** as `rhythm_tap` (Notenwerte):
  a one-measure rhythm plays and is shown as notation, the child taps it back on
  a pad, and timing is graded onset-by-onset relative to the first tap (so the
  absolute start doesn't matter). SRI `note_values.rhythm.p<index>`. (Kept the
  onset-diff grader rather than the `beat_runner` falling-lane clock — for a
  call-and-response echo, comparing relative onsets is the right model.)
- [x] **Chord-quality-by-ear widening** — **done**: `major_minor_ear` widens from
  major/minor to a 4-way (adds **diminished + augmented** as a 2×2 grid) at 2★;
  below 2★ it stays the binary drill. The **dominant-7 tier** shipped as its own
  binary ear game — *Triad or Seventh?* (`triad_seventh`, chords): a major triad
  vs a dominant-7 (triad + a minor 7th), tap which. No 7th-chord *builder* was
  needed — the dom7 is built app-side from the major `Triad`'s pitches +
  `root.transposeBy(Interval.minorSeventh)`. SRI `chords.hear.<triad|seventh>`.

### E. Creative / toy modes (higher ceiling, higher effort)
- [x] **Loop mixer** — tap cards that trigger synced loops (bass/chords/melody/
  drums). **Shipped** as **Loop Mixer 2.0** (the groovebox ladder — GrooveSpec
  spec→WAV engine, seam-scheduled synced stems, sing-a-track, beatbox, graded jam
  mode). See the "Loop Mixer 2.0" roadmap section + HISTORY.md.
- [x] **Grid composer for pre-readers** — **shipped**: *Colour Melody*
  (`grid_composer`, composition) — a 5-colour (C-pentatonic) × 8-beat grid; taps
  place notes that render live to a real `Score` (StaffView underneath), and play
  back with rests intact (`playChordSequence`, empty beats = silence). A sandbox
  like My Melody (no stars). The bridge to notation for non-readers.
- [x] **Melody doodle → hear it back** — **shipped** (`melody_doodle`,
  composition): draw a contour → it quantises to the same C-pentatonic grid as
  *Colour Melody* and plays back. The gesture twin of `grid_composer`.
- [ ] **Drumkit mode — live play + record + auto-clean → tracks/score** (user
  request 2026-07-18). A **playable drum kit** (tap pads — kick/snare/hats/toms/
  cymbals; reuse the SFXR/`renderDrumPattern` drum voices + the Drums corner's
  pad) that is fun to (a) **play live** and (b) **record**. A recorded take is a
  timestamped hit stream (pad + ms), which is then **automatically CLEANED**
  before it becomes editable data:
  - **Quantize / cleanup parameters**, difficulty-scaled: a *Relevanzschwelle*
    (relevance threshold) — the max deviation from the exact grid that still
    snaps — plus the **grid resolution ceiling** (beginners snap to **1/4 or
    1/8**; advanced allows 1/16+ and finer), a swing/groove-preserve toggle, and
    a velocity/ghost threshold (drop hits below a level). Reuse the onset/timing
    machinery already in `beat_capture.dart` (beatbox→drum rows, onset from the
    brightest loud frame) and the Loop Mixer's eighth-step data-pattern grid.
  - **Output routing (the point):** the cleaned pattern drops into
    - the **Tracker** as drum rows — **both Beginner** (the pentatonic grid's
      drum lane) **and Advanced** (`TrackerSong` percussion channels; the
      per-cell model already exists), and
    - a **Score** (the neutral **percussion staff** — the Drums corner already
      reads/writes it), and/or a Loop Mixer beat row / GrooveSpec.
  - **Scope note:** the capture+quantize core is Flutter-free and unit-testable
    (synth a hit stream with jitter → assert it snaps to the intended grid at
    each Relevanzschwelle); the pads + record UI is a screen; the routing reuses
    existing tracker/score/groove writers. Big-ish (L) but decomposes cleanly:
    (1) quantize core + tests, (2) kit + live play, (3) record + cleanup UI,
    (4) the three output bridges. Coordinate with the tracker agents (drum
    channels) before touching `tracker_song.dart`.

### F. Infrastructure / platform (not kid-facing games)
- [x] **Web-safe OMR-tokens import bridge** — **shipped** (2026-07-15): the
  Workshop ⋮ menu → **"Paste notation tokens…"** parses pasted **bekern** via
  `importBekern` = `MultiPartScore.fromStaffSystem(bekernToStaffSystem(text))`, so
  a multi-spine paste seeds one instrument part per spine (reuses the G6
  multi-part doc); a single spine loads into the active part. Pure helper
  unit-tested (1-/2-spine) + a widget test pastes tokens → notes. Localized
  de/en. (The image→tokens OMR recognition stays native/out-of-scope.)
- [~] **`showNoteNames` scaffold** — an accessibility/beginner toggle overlaying
  letter names on noteheads. **Unblocked** — crisp_notation now exposes
  `showNoteNames`/`noteNameStyle` on every multi-part view (`MultiSystemView`,
  `InteractiveMultiPartView`, `InteractiveGrandStaffView` in 0.4.2; the static
  `MultiPartView` in 0.4.4). The app-side toggle is **actively claimed** on the
  board (`opus (workshop-inspector)` — persisted `SettingsService.showNoteNames`
  + a `ReadingStaffView` wrapper wired into games where the note's name isn't the
  task). Still to decide there: how it reads the app's `noteNaming` setting
  (German H/B vs English vs Solfège).
- [x] **7th chords in Roman Numerals** — **shipped**: crisp_notation_core gained a
  `SeventhChord(root, ChordType, {inversion})` builder (0.4.5, `61266be`) and
  `roman_numeral_screen.dart` now mixes dominant/major/minor/ø7 chords into the
  widened pool at 2★ in major keys (`b439011`), round-tripping through
  `romanNumeralOf` (V7 / ii7 / viiø7 / V6/5).
- [x] **Leland / Leipzig font options** — **shipped** (`9d94d6f`): the binary
  "handwritten notes" toggle is now a 4-way **Notation font** picker (Bravura /
  Petaluma / Leland / Leipzig, all SIL OFL 1.1), vendored app-side under
  `assets/smufl/` with metadata + OFL. See `shared/score_theme.dart`
  (`ScoreFont`/`musicFontFor`) + `notation_fonts_test`.
- [ ] **MIDI input** — the one real-instrument input still open (mic side shipped).
  *L, big swing.*
- [ ] **Parent view + multi-child profiles** and **Teacher / LMS layer** — see the
  Opportunity backlog above; both are product-level, per-seat monetisable.

### G. Polish / cross-cutting (small, always welcome)
- [ ] New games should adopt the just-landed **per-game tutorial** hook on
  `GameInfo` and the **mascot-as-guide** in `RoundHeader` (UX agent's work — check
  `game_widgets.dart` for the current API before wiring). NB the on-demand "?"
  help is *already universal*: `helpPrimerFor` falls back to the game's module
  primer, and all 13 modules have one — so a missing `GameInfo.tutorial` only
  means no first-run auto-show, never an empty "?". This item is about the richer
  per-game curation + mascot, not basic coverage.
- [x] Audit the new games for the **sound on/off toggle** + **reduced-motion**
  paths — **audited 2026-07-17, all clean.** Sound: every playback path routes
  through `AudioService._play`, which no-ops when `soundOn` is false — no game
  bypasses it (only 1 game imports `synth` directly and it still goes via the
  service). Motion: no game uses a looping `.repeat()` animation; the only
  significant-motion screens (`note_whack`, `falling_notes`) plus the shared
  `note_mascot` already gate on `MediaQuery.disableAnimations`. Nothing to fix.
- [ ] Consider grouping the fast-growing `note_reading` module (it's large) or
  surfacing the new binary drills as a "Warm-ups" strip for the youngest.
