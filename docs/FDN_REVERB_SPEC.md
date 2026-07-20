# FDN reverb — clean-room build spec

Build a **Feedback Delay Network (FDN) reverb** as a drop-in, wider/smoother
alternative to the existing Freeverb in `lib/core/audio/crisp_dsp/reverb.dart`.

**Clean-room rule (important):** implement this from THIS spec and your own
knowledge of the *public, textbook* FDN algorithm only. Do **not** read
fluidsynth's, Freeverb's, or any other reverb's source code. The reference
targets below were measured from a reference's *output* (a black box); match the
behaviour, not anyone's code.

## What an FDN is (public algorithm)

An FDN late-reverberator is standard DSP (Jot & Chaigne 1991; Stautner &
Puckette; see Julius O. Smith, *Physical Audio Signal Processing*,
ccrma.stanford.edu/~jos/pasp/, "Feedback Delay Networks"). The structure:

```
        in ──► [input gain] ──►(+)──►[delay D0]──►┐
                                (+)──►[delay D1]──►┤
                                 …                 ├─► N delay outputs s[0..N-1]
                                (+)──►[delay D_{N-1}]┘
                                 ▲                        │
                                 │   ┌──────────────┐     │
                                 └───┤ feedback      │◄────┘  each fed back via a
                                     │ matrix  A     │        per-line damping
                                     │ (unitary)·g   │        low-pass first
                                     └──────────────┘
        out_L = Σ cL[i]·s[i]          out_R = Σ cR[i]·s[i]   (decorrelated taps)
```

- **N delay lines** (use N = 8), lengths **mutually co-prime** (choose primes),
  in a spread roughly 1000–4000 samples at 44.1 kHz, scaled by
  `sampleRate/44100`. Co-prime, spread lengths maximise echo density and avoid a
  periodic (metallic) tail.
- **Unitary feedback matrix A** (energy-preserving) so the network is stable and
  the tail is smooth. A **Householder reflection** `A = I − (2/N)·1·1ᵀ` (all
  entries computable on the fly: `y[i] = x[i] − (2/N)·Σx`) or a **normalised
  Hadamard** matrix are both standard, cheap, and unitary. The feedback is
  `A` scaled by a global gain `g < 1` that sets the decay.
- **Damping**: before feeding a line's output back, run it through a one-pole
  low-pass `y = (1−d)·x + d·y_prev`. Higher damping ⇒ high frequencies decay
  faster than lows (natural room absorption).
- **Input**: distribute the mono input into all N lines (a small input gain,
  e.g. 0.1–0.3, keeps the summed feedback from clipping).
- **Stereo output**: sum the N delay outputs into L and R with **different**
  weight/sign patterns per channel (e.g. L uses `+ + − − + + − −`, R a rotated
  or sign-flipped pattern) so L and R are **decorrelated** → a wide tail. This
  decorrelation is the whole point of choosing an FDN.

## Interface contract (exact)

New file `lib/core/audio/crisp_dsp/fdn_reverb.dart`, Flutter-free, pure Dart,
no new dependencies, deterministic (no `Random`/`DateTime`):

```dart
/// A stereo Feedback-Delay-Network reverb: mono in → stereo (left, right) out.
/// Returns ONLY the wet signal (the caller mixes it with the dry). [roomSize]
/// 0..1 lengthens the tail; [damping] 0..1 darkens it. Same length as [input].
(Float64List left, Float64List right) fdnReverb(
  Float64List input, {
  double roomSize = 0.7,
  double damping = 0.4,
  int sampleRate = 44100,
});
```

- `input.isEmpty` → return two empty lists.
- Output lists have the SAME length as `input` (the tail is truncated to the
  input length — the caller pads the input with the trailing silence it wants).
- Clamp `roomSize`/`damping` to `[0,1]`; guard NaN.

## Parameter mappings (standard)

- **roomSize → decay.** Use the standard RT60↔gain relation on the *mean* delay
  length: for a delay of `Dsec` seconds fed back with gain `g`, the level after
  time `t` is `g^(t/Dsec)`; RT60 (−60 dB) is `t` where that = 0.001, i.e.
  `g = 10^(−3·Dmean_sec / RT60)`. Map `roomSize` 0..1 to `RT60` ≈ **0.5 s … 4 s**
  and derive `g` from the mean delay length. Keep `g < 1` (stability).
- **damping → one-pole coefficient** `d` in ~`[0, 0.7]` (0 = bright, no HF loss).

## Acceptance criteria — validated against the reference oracle

An automated test (`test/fdn_reverb_test.dart`, written for you below) feeds a
unit impulse through `fdnReverb` and asserts, at `roomSize: 0.7, damping: 0.4`:

1. **Wide/decorrelated tail** — side/mid energy ratio `> 0.25`, and L/R
   correlation `< 0.8`. *(This is the headline goal — the existing Freeverb sits
   near 0.03; the reference FDN measured **side/mid 0.38, correlation 0.55**.)*
2. **RT60 in `[0.8, 2.6] s`** *(reference ≈ 1.6 s).*
3. **Diffuse, non-metallic** — the early response (first 60 ms after onset) has a
   peak/RMS crest `< 6` *(reference ≈ 2.4; a metallic FDN spikes high).*
4. **Damping works** — with `damping: 0.8` the tail's high band (>4 kHz) decays
   faster than its low band (<800 Hz).
5. **Stable & clean** — no `NaN`/`Inf` for silence, a unit impulse, and white
   noise; output stays bounded (`|x| < 8`); the impulse tail decays monotonically
   in RMS to `< peak/100` before the buffer ends.
6. **Empty in → empty out.**
7. **Smooth, non-metallic tail (NEW — the current build FAILS this).** The tail's
   spectral flatness (geomean/mean of the power spectrum over 200 Hz–10 kHz,
   measured on the active decay region of the impulse response) must be `> 0.35`.
   A static FDN with long fixed delays reads ~0.27 — a peaky comb that sounds
   *metallic/ringy*, worst on percussion. On identical input the reference reads
   ~2× flatter (~0.36). See "## Update" below for how to fix it.

## Update — kill the metallic ringing (criterion 7)

The first build passed criteria 1–6 but its tail **rings** (fixed comb → low
spectral flatness → metallic, especially on drums). Two standard, public
techniques close the gap. **Clean-room still applies: implement these from the
public/textbook descriptions and this spec only — do NOT read fluidsynth's,
Freeverb's, or any reverb's source.**

1. **Modulate the delay-line read positions (the key fix).** Slowly vary each
   line's effective delay length with a low-frequency oscillator, reading the
   line at a *fractional* position (linear or first-order all-pass interpolation).
   This continuously de-tunes the modal comb so successive round-trips decorrelate
   and the metallic ringing smears into a smooth tail. This is a well-documented
   reverb technique (delay-line modulation / "chorused" FDN; see Dattorro 1997,
   *Effect Design Part 1*, and Julius O. Smith, PASP). Design targets (these are
   just parameters, not anyone's code):
   - a **slow rate**, ~0.7–1.5 Hz, with a **different phase per line** (e.g. spread
     360°/N across the N lines) so the lines never modulate in lockstep;
   - a **small depth**, ~3–8 samples peak (enough to move across several samples,
     small enough not to audibly pitch-bend sustained tones);
   - update the modulated read index at a modest control rate (e.g. every ~32–64
     samples) with fractional interpolation between updates — full per-sample is
     also fine.
   Keep it deterministic (no `Random`): drive the LFO from a sample counter.
2. **Shorter, denser delay lines.** The current `[1009…3407]` are long and sparse
   → audible discrete echoes and a coarse comb. Use **shorter** mutually co-prime
   lengths (roughly the **~500–1500 sample** range at 44.1 kHz) so the echo
   density is higher and the tail is denser/smoother. (You may also raise N to 12
   if helpful, but 8 modulated + short is expected to be enough.)

Preserve everything that already passes: the unitary Householder feedback, the
one-pole damping, the RT60/roomSize mapping, and the shared-mono + decorrelated
stereo blend (`out = a·mono + b·decorr`) that hit the width/correlation band.
Modulation is *magnitude-neutral* on average, so RT60 and width should hold; if a
metric drifts, re-tune rather than abandon the modulation.

## Reference oracle (black box, for your A/B — do not read its code)

`scratchpad/fdn/oracle_ir.wav` is the reference reverb's impulse-ish response
(its output minus the dry signal for a short bright note). Use it only to *hear*
and *measure* the target character; the numeric targets above are already
distilled from it. `scratchpad/fdn/measure_ir.dart` measures RT60 / width /
correlation / crest of any stereo WAV — run it on your own rendered IR to
compare. `scratchpad/fdn/ring_metrics.dart` measures the **tail spectral
flatness** (criterion 7) of any stereo WAV; `scratchpad/fdn/oracle_crash_ir.wav`
is the reference reverb's response to a broadband hit (flatness **0.364**) — your
target for smoothness. The unit test already checks flatness on the impulse, so
you don't strictly need these, but they let you A/B the *character*.

## Deliverables

1. `lib/core/audio/crisp_dsp/fdn_reverb.dart` implementing the contract.
2. `test/fdn_reverb_test.dart` passing (provided; do not weaken its thresholds —
   fix the implementation).
3. `dart format` clean, `flutter analyze` "No issues found!" on both files.
4. A one-paragraph note on the delay lengths, matrix, and mappings you chose and
   the measured RT60/width/crest you achieved vs the targets.

Do NOT wire it into `midi_render` yet — that swap is a separate step done by the
requester after acceptance.
