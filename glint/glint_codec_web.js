// Synchronous whole-buffer ENCODE + DECODE for Flutter web, over the same glint
// wasm module the Vorbis shim already loads.
//
// Why this exists: glint.wasm has always exported the FULL codec surface
// (_glint_encode_audio, _glint_decode_audio), but only _glint_vorbis_decode was
// ever wired through to Dart. So the bundle shipped an MP3/AAC/Opus encoder and
// a five-format decoder that nothing could reach. This exposes them.
//
// Same shape as glint_vorbis_web.js: load the module once (async), then every
// call is SYNCHRONOUS — wasm calls are sync once instantiated — so these fit
// Dart's synchronous EncodeAudio / decode typedefs without making the whole
// export path async.
//
// Memory: every call frees its wasm-side buffers, and the returned typed arrays
// are .slice() copies, so nothing points into HEAP after we return (the heap can
// be detached by a later grow).
import { loadGlint } from './glint_codec.mjs';

let _m = null;

/** Load the wasm module once. Safe to call repeatedly. */
export async function glintCodecInit() {
  if (!_m) _m = await loadGlint();
  return true;
}

export function glintCodecReady() {
  return _m != null;
}

/**
 * Encode interleaved Float32 PCM (±1.0).
 * format: 0=MP3 1=AAC 2=Opus. Returns Uint8Array, or null on failure.
 */
export function glintEncodeSync(pcm, channels, sampleRate, format, bitrateKbps,
                                vbrQuality, quality) {
  const m = _m;
  if (!m || !pcm || channels < 1) return null;
  const frames = (pcm.length / channels) | 0;
  if (frames < 1) return null;

  const pcmPtr = m._malloc(pcm.length * 4);
  const outSizePtr = m._malloc(4);
  try {
    m.HEAPF32.set(pcm, pcmPtr >> 2);
    const ptr = m._glint_encode_audio(
      pcmPtr, frames, channels, sampleRate, format,
      bitrateKbps, vbrQuality, quality, outSizePtr);
    if (!ptr) return null;
    const size = m.getValue(outSizePtr, 'i32');
    if (size <= 0) { m._glint_free(ptr); return null; }
    const out = new Uint8Array(m.HEAPU8.buffer, ptr, size).slice();
    m._glint_free(ptr);
    return out;
  } catch (_) {
    return null;
  } finally {
    m._free(pcmPtr);
    m._free(outSizePtr);
  }
}

/**
 * Decode a complete encoded stream — MP3, AAC, Ogg-Opus, Ogg-Vorbis or FLAC,
 * auto-detected from the header by glint itself.
 * Returns {pcm: Float32Array interleaved, sampleRate, channels, frames} or null.
 */
export function glintDecodeSync(bytes) {
  const m = _m;
  if (!m || !bytes || bytes.length === 0) return null;

  const inPtr = m._malloc(bytes.length);
  const sr = m._malloc(4), ch = m._malloc(4), fr = m._malloc(4);
  try {
    m.HEAPU8.set(bytes, inPtr);
    const ptr = m._glint_decode_audio(inPtr, bytes.length, sr, ch, fr);
    if (!ptr) return null;
    const sampleRate = m.getValue(sr, 'i32');
    const channels = m.getValue(ch, 'i32');
    const frames = m.getValue(fr, 'i32');
    if (channels < 1 || frames < 1) { m._glint_free(ptr); return null; }
    const pcm = new Float32Array(m.HEAPF32.buffer, ptr, frames * channels).slice();
    m._glint_free(ptr);
    return { pcm, sampleRate, channels, frames };
  } catch (_) {
    return null;
  } finally {
    m._free(inPtr);
    m._free(sr);
    m._free(ch);
    m._free(fr);
  }
}
