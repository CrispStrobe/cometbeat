// Render -> encode -> decode -> assert for the glint WASM codec shim, driven
// exactly as the browser drives it: init() once, then synchronous calls.
//
// This is the web counterpart of native/glint/test/encode_roundtrip_test.cpp,
// and it matters because the web path shares NO code with the FFI path above
// Dart — different bindings, different memory model (a wasm heap that can be
// detached by a grow), different float width (the wasm ABI is float32).
//
// Run:  node web/glint/codec_roundtrip_test.mjs
// CI:   .github/workflows/glint-native.yml (web-codec job)

import {
  glintCodecInit, glintCodecReady, glintEncodeSync, glintDecodeSync,
} from './glint_codec_web.js';

let failures = 0;
const check = (ok, what) => {
  console.log(`  [${ok ? 'PASS' : 'FAIL'}] ${what}`);
  if (!ok) failures++;
};

const FORMAT = { MP3: 0, AAC: 1, OPUS: 2 };
const NAME = { 0: 'MP3', 1: 'AAC', 2: 'Opus' };

/** Interleaved sine; `freq` may be an array of one frequency per channel. */
function tone(freq, seconds, rate = 48000, channels = 1, amp = 0.5) {
  const n = Math.round(rate * seconds);
  const a = new Float32Array(n * channels);
  for (let i = 0; i < n; i++) {
    for (let c = 0; c < channels; c++) {
      const f = Array.isArray(freq) ? freq[c] : freq;
      a[i * channels + c] = amp * Math.sin(2 * Math.PI * f * i / rate);
    }
  }
  return a;
}

// Autocorrelation pitch estimate. Same two traps as the native version: every
// lag must correlate the SAME number of terms (else long lags are inflated and
// an 880 Hz tone reads as 80 Hz), and a periodic signal correlates as well at
// 2T as at T, so take the first strong peak. Parabolic interpolation because an
// 880 Hz period is 54.5 samples at 48 kHz.
function estimatePitch(pcm, channels, channel, rate) {
  const frames = pcm.length / channels;
  const skip = Math.min(frames >> 2, rate >> 2);
  const n = Math.min(frames - skip, rate >> 1);
  if (n < 2048) return 0;
  const x = new Float64Array(n);
  for (let i = 0; i < n; i++) x[i] = pcm[(skip + i) * channels + channel];

  const minLag = (rate / 2000) | 0;
  let maxLag = (rate / 50) | 0;
  if (maxLag >= n >> 1) maxLag = (n >> 1) - 1;
  if (maxLag <= minLag) return 0;
  const terms = n - maxLag;
  const r = new Float64Array(maxLag + 1);
  let peak = 0;
  for (let lag = minLag; lag <= maxLag; lag++) {
    let s = 0;
    for (let i = 0; i < terms; i++) s += x[i] * x[i + lag];
    r[lag] = s;
    if (s > peak) peak = s;
  }
  if (peak <= 0) return 0;
  let best = 0;
  for (let lag = minLag + 1; lag < maxLag; lag++) {
    if (r[lag] >= 0.85 * peak && r[lag] >= r[lag - 1] && r[lag] >= r[lag + 1]) {
      best = lag;
      break;
    }
  }
  if (!best) return 0;
  const y0 = r[best - 1], y1 = r[best], y2 = r[best + 1];
  const d = 2 * (2 * y1 - y0 - y2);
  return rate / (d ? best + (y2 - y0) / d : best);
}

function rms(pcm, channels, channel) {
  const frames = pcm.length / channels;
  let s = 0;
  for (let i = 0; i < frames; i++) {
    const v = pcm[i * channels + channel];
    s += v * v;
  }
  return frames ? Math.sqrt(s / frames) : 0;
}

// --- the instrument, before we measure the codec with it --------------------
console.log('Pitch estimator self-test (undecoded tones)');
for (const f of [110, 440, 880, 1318.5]) {
  const got = estimatePitch(tone(f, 1.0), 1, 0, 48000);
  check(Math.abs(got - f) < 1.0, `reads ${f} Hz as ${got.toFixed(2)}`);
}

// --- before init, everything must decline, not throw ------------------------
console.log('Before init: declines rather than throwing');
check(glintCodecReady() === false, 'ready() is false');
check(glintEncodeSync(tone(440, 0.1), 1, 48000, FORMAT.OPUS, 96, -1, 5) === null,
  'encodeSync returns null');
check(glintDecodeSync(new Uint8Array([1, 2, 3])) === null,
  'decodeSync returns null');

await glintCodecInit();
check(glintCodecReady() === true, 'ready() after init');

// --- round trip, every codec ------------------------------------------------
console.log('Round trip (440 Hz mono)');
for (const fmt of [FORMAT.MP3, FORMAT.AAC, FORMAT.OPUS]) {
  const enc = glintEncodeSync(tone(440, 2.0), 1, 48000, fmt, 128, -1, 5);
  if (!enc || enc.length < 1000) { check(false, `${NAME[fmt]} encoded`); continue; }
  const d = glintDecodeSync(enc);
  if (!d) { check(false, `${NAME[fmt]} decoded back`); continue; }
  const f = estimatePitch(d.pcm, d.channels, 0, d.sampleRate);
  check(Math.abs(f - 440) < 4,
    `${NAME[fmt]}: ${enc.length} B -> ${d.sampleRate} Hz ${d.channels}ch, pitch ${f.toFixed(1)} Hz`);
}

console.log('Stereo integrity (L=440, R=880)');
{
  const enc = glintEncodeSync(tone([440, 880], 2.0, 48000, 2), 2, 48000,
    FORMAT.OPUS, 128, -1, 5);
  const d = glintDecodeSync(enc);
  check(!!d && d.channels === 2, 'stayed stereo');
  if (d && d.channels === 2) {
    const L = estimatePitch(d.pcm, 2, 0, d.sampleRate);
    const R = estimatePitch(d.pcm, 2, 1, d.sampleRate);
    check(Math.abs(L - 440) < 5, `left is 440 Hz (${L.toFixed(1)})`);
    check(Math.abs(R - 880) < 7, `right is 880 Hz (${R.toFixed(1)}) — a swap reads 440`);
  }
}

console.log('Hard pan (L tone, R silent)');
{
  const pcm = tone([440, 440], 1.5, 48000, 2);
  for (let i = 1; i < pcm.length; i += 2) pcm[i] = 0;
  const d = glintDecodeSync(
    glintEncodeSync(pcm, 2, 48000, FORMAT.OPUS, 128, -1, 5));
  check(!!d && d.channels === 2, 'decoded stereo');
  if (d && d.channels === 2) {
    const l = rms(d.pcm, 2, 0), r = rms(d.pcm, 2, 1);
    check(l > 0.2, `left carries the tone (${l.toFixed(3)})`);
    check(r < l * 0.1, `right stayed quiet (${r.toFixed(4)})`);
  }
}

console.log('Bad input is rejected, not crashed on');
check(glintDecodeSync(new Uint8Array(64)) === null, 'junk bytes');
check(glintDecodeSync(new Uint8Array(0)) === null, 'empty buffer');
check(glintDecodeSync(null) === null, 'null buffer');
check(glintEncodeSync(new Float32Array(0), 1, 48000, FORMAT.OPUS, 96, -1, 5) === null,
  'empty PCM');
check(glintEncodeSync(tone(440, 0.5), 0, 48000, FORMAT.OPUS, 96, -1, 5) === null,
  'zero channels');
check(glintEncodeSync(tone(440, 0.5), 1, 48000, 99, 96, -1, 5) === null,
  'unknown format');

// A wasm heap can be REPLACED by a grow, so a stale view would read garbage or
// throw. Every call here must still be correct after many allocations.
console.log('Repetition: 100 encode/decode cycles');
{
  let ok = true;
  for (let i = 0; i < 100; i++) {
    const e = glintEncodeSync(tone(440, 0.25), 1, 48000, FORMAT.OPUS, 96, -1, 5);
    if (!e || e.length < 100) { ok = false; break; }
  }
  check(ok, 'every iteration encoded');
  const f = estimatePitch(
    glintDecodeSync(glintEncodeSync(tone(440, 1.0), 1, 48000, FORMAT.OPUS, 96, -1, 5)).pcm,
    1, 0, 48000);
  check(Math.abs(f - 440) < 4, `still correct afterwards (${f.toFixed(1)} Hz)`);
}

console.log(`\n${failures === 0 ? 'ALL PASS' : 'FAILED'} (${failures} failure${failures === 1 ? '' : 's'})`);
process.exit(failures === 0 ? 0 : 1);
