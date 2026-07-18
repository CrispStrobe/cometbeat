# MP3 port — glint comparison harness

Validates the pure-Dart MP3 encoder DSP (`lib/core/audio/mp3/`) against glint's
C++ reference (`~/code/glint`, MIT clean-room), for **bit-exactness** and
**speed**. `bench/glint_ref.cpp` and `bin/mp3_bench.dart` feed the SAME
deterministic LCG input through the subband filter + MDCT + alias reduction.

## Reproduce
```bash
# 1. build glint (once)
cmake -S ~/code/glint -B /tmp/glint -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/glint --target glint_static

# 2. C++ reference + benchmark (dumps ref.txt, prints granules/s to stderr)
c++ -O3 -std=c++17 -march=native bench/glint_ref.cpp \
    -I ~/code/glint/src -I ~/code/glint/include /tmp/glint/libglint.a -o /tmp/glint_ref
/tmp/glint_ref 20000 /tmp/ref.txt

# 3. Dart: compare to the reference + benchmark
dart run bin/mp3_bench.dart /tmp/ref.txt 20000
```

## Results (2026-07-18, Apple Silicon)
- **Accuracy — machine-equivalent.** subband max abs err **5.3e-15**, MDCT
  **6.7e-16** (signal peak ~11.5 → **relative ~5e-16**, the double-precision
  floor). `acc` matches glint exactly. NOT literally bit-identical only because
  glint builds with `-ffast-math`/FMA (reassociates float ops); the Dart port
  is strict IEEE double. `test/mp3_golden_test.dart` pins glint's dumped values
  in CI (no glint needed).
- **Speed.** glint C++ (`-O3 -march=native`) ≈ **95,640 granules/s**; Dart JIT
  (`dart run`) ≈ **4,000 granules/s** → **~24× slower**. A granule is 576
  samples = **13 ms of audio**, so even JIT is **~52× realtime**; release
  builds are AOT (faster). Encoding a 3-min song ≈ 13,850 granules ≈ 3.5 s JIT.
  (AOT `dart compile exe` is blocked here by the app's native-asset deps, so
  the in-app release-mode number will sit between JIT and glint.)

## End-to-end encode validation (slice 5c/6)
`mp3EncodeMono(pcm)` → a complete MPEG-1 Layer III (mono, CBR) file, verified
with a real-world decoder:
```
# encode 3 s of 440+880 Hz from a bin/ script, then:
ffmpeg -v error -i out.mp3 -f s16le out.pcm      # exit 0, no errors
ffprobe out.mp3   # codec_name=mp3 sample_rate=44100 channels=1
                  # duration=3.004 bit_rate=127999
```
Decoded audio is real (peak 23770/32768, RMS 1553, 99 % non-zero) — the tones
survived. Header `FF FB 90 C4` = valid MPEG-1 LIII 128 k/44.1 k mono. First cut:
zero scalefactors + no bit reservoir (valid, lower quality); scalefactors +
reservoir + the rate-optimal region search are quality follow-ups.

## A/B vs glint using glint's OWN harness (`bench/ab_vs_glint.py`)
Reuses glint `tests/benchmark_encoder.py`'s deterministic speech signal +
`tests/measure_audio.py`'s objective metrics, so the Dart encoder is judged on
the same reference and yardstick as glint. Both run mono; 30 s.
Setup: a py3.12 venv with numpy+scipy; `glint/build-bench/glint_cli`.
```
python bench/ab_vs_glint.py -b 128        # or -b 256, --seconds N
```

**Are we bit-perfect?** The DSP *front-end* is machine-equivalent to glint —
subband 5.3e-15, MDCT 6.7e-16 rel. error (see the golden test). The full
encoded bitstream is NOT bit-identical: ours is a deliberately simpler encoder
(zero scalefactors + no bit reservoir + non-optimal region split), so it emits
a valid, decodable, but lower-fidelity stream. Same *size* (CBR fills the same
frames), different *contents*.

**How much slower?** ~3–4× slower in Dart JIT, still ~28× realtime:

| bitrate | glint       | dart        | ratio |
|---------|-------------|-------------|-------|
| 128 k   | 88× rt      | 28× rt      | 3.1×  |
| 256 k   | 106× rt     | 27× rt      | 3.9×  |

**Quality gap (and its cause).** measure_audio, 128 k / 256 k:

| metric            | glint 128 | dart 128 | glint 256 | dart 256 |
|-------------------|-----------|----------|-----------|----------|
| SNR dB            | 32.1      | 8.1      | 36.6      | 8.0      |
| NMR mean dB (≤0=masked) | −11.4 | +10.4  | −26.6     | +10.4    |
| NMR>0 % (audible) | 0.0       | 66.7     | 0.0       | 66.5     |

The Dart line is **flat across bitrate** — extra bits don't help, because
without scalefactors we can't push quantization noise under the masking
threshold (`global_gain` alone already fits the frame budget, so the surplus
bits go unused). glint's noise is fully masked (NMR ≤ 0); ours is audible in
66 % of Bark bands. => **scalefactors + bit reservoir + a distortion-driven
(psychoacoustic) rate loop is THE quality follow-up**, and it's now quantified.
The current output is correct and standards-compliant, just not yet transparent.

## The frequency-inversion bug (why the port measured 8 dB before)
The first shaped encoder still measured SNR 8 dB end-to-end while every stage
checked out: our streaming MDCT matched glint's to 4.6e-16 even at granule 20,
our quantizer produced byte-identical `ix` to glint (0/576 diff on speech), the
Huffman bitstream round-tripped (≤2 `ix`/granule), and the MDCT-domain
reconstruction was 34.7 dB. Yet a standard decoder (ffmpeg AND glint's own
decoder, in agreement) returned 8 dB, 2.1× too loud, with excess HF — and the
damage was band-selective (a 200→3000 Hz sweep decoded at 1.8 dB; a chord at
47 dB).

Root cause: the golden test pinned `MDCT::process`, but glint's ENCODER calls
`MDCT::process_strided`, which folds in MPEG **frequency inversion** — negate
odd subbands at odd time slots — that `process()` omits. Without it the decoder
synthesis reconstructs every odd subband spectrally flipped; band 0 (even) is
untouched, so pure low tones survived and masked the bug. Fix: pre-invert the
subband samples before `Mp3Mdct.process` (mp3_encoder.dart). Result:

| metric        | broken | glint  | dart (fixed) |
|---------------|--------|--------|--------------|
| SNR dB        | 8.0    | 32.1   | **35.2**     |
| bandSNR 0-1k  | 11.1   | 36.3   | **40.6**     |
| NMR mean dB   | +10.4  | −11.4  | −5.8         |
| sweep SNR dB  | 1.8    | —      | **78.4**     |

Our raw SNR now exceeds glint's; NMR (perceptual) trails because our region
optimizer spends more bits (leaving less for shaping) — the remaining quality
follow-up. `test/mp3_decode_roundtrip_test.dart` is the ffmpeg-gated regression
(a sweep crossing every subband) that would have caught this.

## Huffman region optimizer (closing the NMR gap)
Ported glint's `huffman_select_and_count`: `region0/1_count` from the `max_band`
formula, and per-region + count1 table chosen by ACTUAL bit cost (LUT-driven,
`_kPairCostLut`) instead of a max-value heuristic. `Mp3HuffRegions.bits` carries
the total so the gain search reads it instead of re-emitting. Speech 128k mono:

| metric      | pre-optimizer | glint  | with optimizer |
|-------------|---------------|--------|----------------|
| SNR dB      | 35.2          | 32.1   | 36.2           |
| NMR mean dB | −5.8          | −11.4  | −6.7           |
| NMR>0 %     | 10.3          | 0.0    | 7.7            |

Fewer Huffman bits free budget for shaping, but most of it currently goes to a
finer global_gain (raising SNR) rather than more aggressive shaping. The
remaining NMR gap to glint is the **bit reservoir** — glint borrows bits across
granules to shape hard granules harder; our frames are self-contained
(`main_data_begin = 0`). That's the next quality lever (a larger feature).
Speed: the optimizer's per-candidate search runs inside the gain loop; the LUT
keeps it at ~1.6× realtime (JIT) for the -q best broadband path.

## Bit reservoir
Ported glint's ReservoirStream (`mp3_reservoir.dart`): main data spills across
frame slots via the 9-bit `main_data_begin` back-pointer, so a hard granule can
spend more than its slot (finer noise shaping) while easy granules bank the
surplus. Speech 128k mono:

| metric      | region-opt | +reservoir | glint  |
|-------------|------------|------------|--------|
| NMR mean dB | −6.7       | **−7.1**   | −11.4  |
| NMR>0 %     | 7.7        | **6.5**    | 0.0    |
| SNR dB      | 36.2       | 36.7       | 32.1   |

A CBR gain-floor *anchor* (glint's rc_anchor) was tried and measured WORSE
(−4.9 dB) — forcing easy granules coarser added noise faster than shaping
recovered it. Letting hard granules borrow the *naturally*-banked surplus (no
floor) is the win. The `gainFloor` param stays threaded through the quantizer
for VBR's constant-quality target. The remaining gap to glint's −11.4 is its
tuned adaptive rate control (rc_anchor EMA + tonal-mask offsets at low rate) —
high effort for diminishing returns.

## Stereo + VBR
- **Stereo** (`mp3EncodeStereo`): channel-general core, each channel its own
  subband+MDCT, 32-byte stereo side info, even bit split across 2 granules × 2
  channels. Verified: ffmpeg decodes to two distinct channels.
- **VBR** (`mp3EncodeMonoVbr`/`mp3EncodeStereoVbr`, quality 0–9): self-contained
  frames (no reservoir), quantized to `vbr_target_gain[quality]`, each frame at
  the smallest bitrate that fits (`_vbrPickFrameSize`); shaping budget capped at
  unshaped×1.25 so a big ceiling can't balloon a frame. Quiet passages shrink.
  Follow-up: a Xing/Info header so players report exact VBR duration/seek (the
  audio is correct now; only the estimated duration is approximate without it).

## VBR Xing header
`mp3EncodeMonoVbr`/`mp3EncodeStereoVbr` now prepend a Xing header frame (a silent
64 kbps frame carrying "Xing" + frame count + byte count + a 100-entry seek TOC).
Players report exact duration and can seek. Verified: ffprobe reads 4.02 s for a
4 s clip (was an inaccurate estimate before the header).
