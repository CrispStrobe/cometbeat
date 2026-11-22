// Synchronous Ogg-Vorbis decode for Flutter web: pre-load the glint wasm module
// once (async), then decode each .sf3 sample stream SYNCHRONOUSLY (wasm calls are
// sync once instantiated) — so it fits Sf2SoundFont.parse's sync VorbisDecode.
import { loadGlint } from './glint_codec.mjs';
let _m = null;
export async function glintVorbisInit() { _m = await loadGlint(); return true; }
export function glintVorbisReady() { return _m != null; }
// Decode ONE Ogg-Vorbis stream → interleaved Float32Array (or null). channels in
// out[0..1] not needed; caller downmixes. Returns {pcm, channels, frames}.
export function glintVorbisDecodeSync(bytes) {
  const m = _m;
  if (!m) return null;
  const inPtr = m._malloc(bytes.length);
  m.HEAPU8.set(bytes, inPtr);
  const sr = m._malloc(4), ch = m._malloc(4), fr = m._malloc(4);
  const ptr = m._glint_vorbis_decode(inPtr, bytes.length, sr, ch, fr);
  m._free(inPtr);
  if (!ptr) { m._free(sr); m._free(ch); m._free(fr); return null; }
  const channels = m.getValue(ch, 'i32'), frames = m.getValue(fr, 'i32');
  m._free(sr); m._free(ch); m._free(fr);
  const pcm = new Float32Array(m.HEAPF32.buffer, ptr, frames * channels).slice();
  m._glint_free(ptr);
  return { pcm, channels, frames };
}
