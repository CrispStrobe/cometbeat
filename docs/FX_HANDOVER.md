# Audio FX — improvement effort (handover)

**Status:** planned / unclaimed. Goal: broaden and improve the app's audio effects
everywhere they're used — the sfxr chiptune instruments, the sampled/recorded-voice
instruments, the Tracker's per-note effects, the Loop Mixer, and feedback SFX —
by drawing from **our own MIT repos** and from **OpenMPT / libopenmpt (BSD-3,
permissive → portable)**.

Delegate the same way that worked for the `.mod`/`.s3m` codecs and the tracker
gaps: **the maintainer writes the contract + a test suite per DSP unit; one agent
implements one pure-Dart file** in `lib/core/audio/crisp_dsp/`; the maintainer
integrates. Every unit is Flutter-free and unit-tested like `sfxr_test.dart`.

## Sources to draw from
- **`CrispStrobe/crispaudio`** (MIT, ours) — the fullest reference. `src/audio/`
  has a complete effects chain we only PARTIALLY ported.
- **`CrispStrobe/CrispFXR-web`** (MIT) — the fuller sfxr param set (FM/LFO/phaser).
- **`CrispStrobe/voicelab`** (MIT) — voice presets (robot/alien/demon/cyborg/
  radio/chipmunk…) + PSOLA time-stretch + granular pitch, mobile-tuned.
- **OpenMPT / libopenmpt** (BSD-3-Clause, permissive — we can *port*, not just
  read) — high-quality sample interpolation, a resonant filter, reverb, instrument
  envelopes, tempo "swing/groove."

## What's already ported (don't redo)
`crisp_dsp/`: `sfxr.dart` (focused: wave + ADSR + freq gesture + duty/arp/vib +
1-pole LP/HP + tanh distortion + bit-crush + sub-bass), `pitch_shift.dart`
(granular), `formant_shift.dart`, `voice_fx.dart` (chipmunk/monster/deep via
formant; robot via ring-mod + bit-crush), `resample.dart` (LINEAR). `tracker_
effects.dart` (arp/vibrato/slide). See auto-memory `tracker-effort`.

## The gaps to fill (each a delegatable pure-DSP unit + test)
1. **Complete the crispaudio effect chain** (Tier-B units skipped in the first
   pass). ✅ **DONE — `delayFx`/`chorusFx`/`flangerFx`** (`crisp_dsp/
   modulated_delay.dart`, shared fractional delay line) **+ `reverbFx`** (`crisp_dsp/
   reverb.dart`, Freeverb: 8 combs + 4 allpass). All same-length pure transforms
   with `mix==0` = dry identity; tests in `modulated_delay_test.dart`/`reverb_test.dart`
   (echo lands at D/2D/3D, reverb impulse → decaying tail, finite/bounded/det).
   Remaining here: standalone `ring_mod`, the full `distortion` set
   (hardClip/softClip/fuzz/wavefold), the sfxr params we dropped (FM, LFO), and an
   optional FFT-convolution reverb. Each: a pure `Float64List → Float64List`
   transform (or per-sample fn), unit-tested (bounded, finite, changes-the-signal,
   deterministic). ✅ **Integration DONE:** a per-channel effect in the Tracker —
   `TrackerChannelEffect` + `applyChannelEffect` applied to the stem before
   `mixStems` (`setChannelEffect` + cache-invalidate), with a `graphic_eq` app-bar
   FX-picker sheet (EN/DE). (A per-channel *chain* of multiple effects is a future
   extension; today it's one insert effect per channel.)
2. **Better sample interpolation** — replace `resample.dart`'s linear interp with
   **cubic Hermite** (port from OpenMPT's resampler). Directly improves the
   **recorded-voice instrument** (the flagship) — smoother pitch-shifting. Small,
   high-value, drop-in (same signature).
3. **Richer voice FX** (from voicelab) — more `VoiceEffect` presets (alien / cyborg
   / radio / demon) + port `TimeStretcher` (PSOLA) so a recorded clip can be
   slowed/sped without pitch change. Extend `voice_fx.dart` + its test.
4. **Instrument envelopes** (from OpenMPT/IT) — optional volume/pitch envelopes on
   sampled/sfxr instruments for expressiveness. New model + render hook.
5. **Groove / swing** — a tempo-swing option in the Tracker/Loop Mixer timing (from
   OpenMPT's tempo swing). Small timing change, kid-friendly feel.

## Where the FX plug in (integration, maintainer)
- **Instruments:** an optional **per-channel effect chain** in the Tracker (a small
  list of the above effects applied to the channel stem before `mixStems`), and
  richer per-instrument character (sfxr FM/LFO, envelopes).
- **Voice:** the record → effect flow (`voice_fx.dart`) gains the new presets +
  time-stretch; cubic interp improves every sampled note.
- **Loop Mixer / SFX:** optional reverb/delay send.

## Suggested order (effort → value)
1. **Cubic interpolation** (tiny, improves the voice feature immediately).
2. **Reverb + delay + chorus** (the effects players most notice; crispaudio has
   the code).
3. **voicelab presets + PSOLA time-stretch** (deepens the voice-sampling toy).
4. Distortion set + ring-mod + FM/LFO (chiptune richness).
5. Envelopes, then swing (expressive polish).

## Testing (same discipline as the codecs)
Each DSP unit gets a unit test: right output length, finite + bounded, the effect
actually changes the signal vs. dry, deterministic under a seed. Integration adds
an engine test (an effected channel differs from dry) + a screen tester-seam test.
No external audio in tests — all synthetic buffers, like `sample_dsp_test.dart`.
