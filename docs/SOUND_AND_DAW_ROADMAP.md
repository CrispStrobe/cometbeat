# Sound production & DAW capabilities — roadmap

Scoping doc (design only). Goal: real **generate-your-own-sound → shape it →
arrange it multitrack** capability that feels like a professional linear
studio. Compares the app's audio stack against our own MIT repos
(**crispfxr-app**, **crispaudio** — which contains the "voicelab" Voice
Processor — and **glint**) and charts a phased path. No third-party product
names appear in the codebase or docs, by policy.

## 0. The one-line strategic read

We already have a **broad, pure-Dart synthesis + DSP library** and three
sequencing surfaces (tracker, loop groovebox, notation). The wall between
"toy/tracker" and "DAW" is **two load-bearing facts**, not missing effects:

1. **Everything is offline-render-then-play** (`mixStems` → one WAV →
   `audioplayers`). Every edit re-renders the whole buffer and swaps players
   (`GaplessLoopPlayer`). There is no real-time streaming graph, no live faders,
   no live-playable instruments, no automation response.
2. **Arrangement is pattern/order-list + loop-toggle only.** There is no
   free-form linear timeline where clips sit at arbitrary positions on
   independent lanes.

Almost every DAW gap (real-time mixing, automation lanes, sends/returns, clip
editing, project save/load) descends from those two. So the roadmap is:
**harvest the cheap wins the current architecture already supports**, then do
**the two rewrites in the right order** — coordinated with the tracker agents'
in-flight audio arc (`docs/TRACKER_GUI_HANDOFF_IDEAS.md` §E already claims the
real-time engine).

## 1. Where we are (baseline)

**Synthesis (all pure Dart, `lib/core/audio/`)** — additive (`synth.dart`),
sfxr/retro (`crisp_dsp/sfxr.dart`), Karplus-Strong (`karplus.dart`), 2-op FM
(`fm.dart`), subtractive (`subtractive.dart`), noise percussion, SF2 soundfont
(`sf2/`, uncompressed only), `SampleInstrument`/`MultiSampleInstrument`, bundled
CC0 samples (`sound_library.dart`), and kid voice-FX presets (`voice_fx.dart`).

**DSP (`crisp_dsp/`, all same-length offline `Float64List` transforms)** —
Freeverb (`reverb.dart`), delay/chorus/flanger (`modulated_delay.dart`), ring
mod, distortion (4 curves), **cepstral formant shift** (`formant_shift.dart`),
**granular pitch shift** (`pitch_shift.dart`), **WSOLA time-stretch**
(`time_stretch.dart`), resample (linear/cubic/glide), ADSR+pitch envelope,
sample-edit primitives (trim/normalize/fade/reverse), AEC (`aec_*`), per-channel
insert chain (`TrackerChannelEffect`). A **Dart MP3 encoder** exists in `mp3/`
(golden-tested) but is **not wired to any export**.

**Arrangement** — Tracker (`tracker_song.dart`: patterns + order list +
per-channel gain/pan/mute/solo/insert-chain/volume+pan envelopes; full effect
columns via `tracker_replayer.dart`), Loop Mixer (`loop_engine.dart`:
`GrooveSpec`, euclidean, chord lane, master send), Score Workshop (notation),
DrumKit (`DrumRowsPattern`).

**Mixing** — `mixStems`/`mixStemsStereo` (unit-peak × gain → tanh soft-knee,
constant-power pan), per-track gain/pan/mute/solo, VU meters, one master
reverb/delay send in the Loop Mixer. **Offline mixdown, not a live mixer.**

**I/O** — read+write MusicXML/ABC/MIDI/MOD/XM/S3M/IT; export MEI/kern/LilyPond/
Braille/MuseScore/PDF; SF2 read-only; MP3 not exposed.

**Gap in the DSP library itself** (fillable now, no rewrite): **no biquad /
parametric EQ, no compressor/limiter/gate** (only the mixer's tanh knee), **no
convolution reverb**.

## 2. What our own repos bring (and portability)

All three are **MIT** — freely reusable/relicensable into this MIT app.

### crispfxr-app (`github.com/CrispStrobe/crispfxr-app`)
A one-file (`src/App.js`) sfxr-style **SFX generator**: oscillators (sq/saw/
sine/noise + duty), ASD+punch envelope, freq slide/vibrato/FM/LFO/arp, and a
full effect set (distortion tanh, bit-crush, one-pole LPF/HPF, sub-bass,
ring-mod, chorus, delay, flanger, pink/brown noise), **16 presets + randomize +
mutate + A/B morph + per-param lock**, WAV (8/16-bit) export, **base64 param
share**. The DSP is a **pure per-sample loop** (no Web Audio in the render) →
**near-1:1 Dart port**. Caveat: `reverb`, `phaser`, filter-ramp/resonance,
`freq_limit/dramp`, `sample_reduction` are UI sliders with **no
implementation** — port them properly or drop them.

> We already have `crisp_dsp/sfxr.dart` (a partial port: chorus/delay/phaser
> declared-but-unapplied). crispfxr is the **complete** engine + the
> **generator UX** (presets/mutate/morph/lock/share) we lack.

### crispaudio (`github.com/CrispStrobe/crispaudio`) — a TS+Tauri workstation
- **Voice Processor ("voicelab")** — a voice-changer chain: granular
  pitch-shift, OLA time-stretch, formant shift, vocoder, ring-mod, tremolo,
  delay, chorus, compressor, biquad filters, **convolution reverb with a
  synthesized IR**, bit-crush, distortion (5 curves), noise gate, **9 character
  presets** (Robot/Alien/Chipmunk/Cyborg/Radio/Demon…). We already have most of
  this (`voice_fx.dart` covers the characters; `formant_shift`/`pitch_shift`/
  `time_stretch` exist). **New from it: vocoder, tremolo, noise gate,
  convolution reverb, and the decoupled pitch/time UI.**
- **Linear timeline editor** (`TimelineEngine.ts`) — canvas waveform, clip
  cut/copy/paste/split/reorder, **fades (linear/exp/s-curve), auto-crossfade on
  overlap, per-segment FX, snap-to-grid, offline render→WAV**. This is the
  **linear-arranger surface the app lacks** (gaps §3.1, §3.7).
- **Radix-2 FFT + spectrum/RMS/peak-dB** viz (we have an FFT in
  `chroma_analysis.dart`).

### glint (`github.com/CrispStrobe/glint`) — codecs, C++17
Clean-room **MP3 + AAC-LC + Opus** encode **and** decode (all 12 Opus test
vectors pass), shipping a **C ABI + Dart bindings**. → link via `dart:ffi`
(native) / the same `.wasm` (web). **Do not reimplement codecs in Dart** — the
in-progress `mp3/` Dart encoder is a fine web-safe fallback, but glint is the
robust path and adds Opus/AAC.

**Portability summary:** the sfxr engine, the voice DSP, the FFT, the fade/
crossfade math, biquad/compressor/convolution algorithms are all plain
`Float32List`/`Float64List` math → **pure-Dart reimplement** (the class of code
already in `crisp_dsp/`). Only the codecs are **FFI/WASM**. The timeline
editor's *algorithms* are trivial; its *architecture* (a clip model + a render)
is the real work.

## 3. The DAW gap list

Fillable **now** (current offline architecture): parametric/graphic **EQ**,
**compressor/limiter/gate**, **convolution reverb**; an **SFX generator** UX; a
**Voice Lab** UX; **compressed export** (MP3/Opus). 

Blocked on the **real-time engine** rewrite: live mixing/faders, live-playable
instruments, input monitoring, real automatable/bypassable insert chains,
sends/returns/buses. 

Blocked on the **linear arranger** rewrite: a clip timeline (drag/trim/split/
move on a ruler), clip fades/crossfades/gain, comping/take lanes, timeline
automation lanes, markers/loop-region/punch, project save/load with embedded
samples, project-wide undo, quantize/groove/humanize on captured input.

## 4. Roadmap (phased, with ownership)

### Phase 0 — cheap wins in today's architecture (no rewrite; mostly my lane)
These need **no** engine change — they're pure-Dart DSP + new screens that
render offline like everything else.

- **P0.1 — Fill the DSP library** (pure Dart, reusable everywhere): a **biquad**
  module (LP/HP/BP/notch/peaking/shelf → parametric EQ), a **dynamics** module
  (compressor/limiter/gate, RMS/peak detector, attack/release/knee/ratio), and a
  **convolution reverb** with a **synthesized IR** (port crispaudio's IR
  generator). New files under `crisp_dsp/`; unit-tested against known responses.
  These slot into the existing `TrackerChannelEffect` chain + `mixStems`.
- **P0.2 — Sound Lab (SFX generator screen).** Port crispfxr's full engine into
  `crisp_dsp/` (completing `sfxr.dart`), then a screen: presets → sliders →
  **mutate / A-B morph / per-param lock / randomize**, live waveform+spectrum,
  **base64 share token**, and **"Save to Sound Library / use as a track
  instrument."** New feature area (like the tab editor was) — low collision.
- **P0.3 — Voice Lab screen.** Record (or pick) a clip → **character presets**
  (reuse `voice_fx.dart`) + **decoupled pitch-shift / time-stretch** sliders
  (reuse `pitch_shift`/`time_stretch`) + the **new** vocoder/tremolo/noise-gate
  (small pure-Dart adds) → save as a `SampleInstrument`. Most DSP already exists.
- **P0.4 — Compressed export.** Wire the in-progress Dart **MP3** encoder into
  `music_export.dart` (web-safe), and/or adopt **glint** via `dart:ffi` for
  MP3/Opus/AAC on native. Adds compressed share/export the app lacks.

### Phase 1 — persistence & the Sound Library (needs one engine seam)
- **P1.1 — Instrument `toJson`/`fromJson`** for `SampleInstrument` (base64 PCM),
  `SfxrInstrument` (params), `MultiSampleInstrument` (zones). **This is the
  `[needs-engine]` D2 item already filed for @tracker-replayer** — coordinate,
  don't duplicate. Once it lands:
- **P1.2 — A persistent `SoundLibraryService`** (save/recall generated SFX,
  recorded/edited samples, voice-lab sounds across sessions), consumable by the
  Tracker, Loop Mixer, DrumKit, and the Sound/Voice Labs. Screen-side is mine.

### Phase 2 — the DAW leap (the two load-bearing rewrites; heavily coordinated)
Sequence matters: the real-time engine unlocks live mixing/automation; the
arranger unlocks clips. Both are large and one (the engine) is **already claimed
by the tracker arc (§E3)** — this doc scopes, it does not claim them.

- **P2.1 — Real-time streaming audio engine** (the crux of "feels live"):
  replace offline-render-then-play with a streamed graph (a native mixer via
  FFI, or a Dart ring-buffer feeding a low-latency sink). Unlocks: live faders,
  live-playable instruments, input monitoring, per-block insert processing,
  automation that responds. **Owner: the tracker audio arc (§E3 in their ideas
  doc).** Everything below assumes it.
- **P2.2 — Linear clip arranger.** A `Timeline` model (lanes × clips at
  arbitrary positions; audio clips + pattern/MIDI clips + automation clips) and
  a ruler UI with drag/trim/split/move, clip fades + crossfades + gain. Port
  crispaudio's `TimelineEngine` clip/fade/crossfade logic; the render composites
  clips (offline first, real-time once P2.1 lands). Bridges to the existing
  tracker patterns (a pattern becomes a clip) and Song Book scores (a score
  becomes a MIDI clip).
- **P2.3 — Automation lanes** (volume/pan/effect-param/tempo drawn against the
  timeline; read/write/latch) — depends on P2.1 + P2.2.
- **P2.4 — Buses / sends / returns / submixes** and real **automatable,
  reorderable, bypassable insert chains** — depends on P2.1.
- **P2.5 — Project save/load** (one format embedding arrangement + samples +
  effect settings + automation) and **project-wide undo** (a command/transaction
  model over the whole project).

## 5. Coordination map

- **Mine to take now (Phase 0):** the DSP-library adds (P0.1), the Sound Lab
  (P0.2) and Voice Lab (P0.3) screens, compressed export (P0.4). New feature
  areas + `crisp_dsp/` + a screen — low collision, fully verifiable offline,
  no engine dependency.
- **Coordinate with @tracker-replayer:** instrument `toJson` (P1.1, their
  `[needs-engine]` D2), and the real-time engine (P2.1, their §E3).
- **Coordinate with @tracker-ui/@tracker-adv:** anything touching
  `advanced_tracker_screen.dart`; the Sound/Voice Labs and Sound Library expose
  seams they can consume (like the CC0 "Browse free sounds" hook already did),
  so most integration stays additive.
- **crispaudio's timeline** is the reference design for P2.2; the arranger is a
  cross-cutting new surface best done after P2.1, jointly.

## 6. Recommended first slice

**P0.1 (DSP: biquad EQ + compressor + convolution reverb) then P0.2 (Sound
Lab).** Rationale: P0.1 is pure-Dart, unit-testable against known responses,
fills the clearest DSP gaps, and immediately upgrades the existing tracker/mixer
insert chain and `mixStems`; P0.2 turns our own crispfxr into a real
generate-your-own-sound feature with the full mutate/morph/share UX, feeding
everything downstream. Both are in my lane, verifiable offline today, and set up
the Sound Library (P1) and the DAW leap (P2) without pre-committing the rewrites.
