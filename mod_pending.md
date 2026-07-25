# Tracker module audit

This is the current audit of the MOD, XM, S3M, and IT reader, writer, neutral
module model, renderer, and editor. It distinguishes format preservation from
what the application can actually play and edit.

**Refreshed 2026-07-25.** Main includes the long-render fixes (`d2c1cf47`,
`948e99b5`) and the Advanced Tracker command/stereo-editor pass
(`17b79485`). The local downloaded audit corpus is deliberately not part of the
branch; see `test/fixtures/README.md` and `docs/CORPUS_LICENSING.md`.

## 2026-07-25 update — `feature/tracker-complete` (performance + coverage pass)

This pass closed several audited gaps across the reader, writer, renderer, and
editor, each shipped as a small verified commit and merged to `main`. Every
change was gated so the fast/uniform/no-fadeout paths stay **byte-identical**
(verified by rendering the 10-module corpus and comparing WAV checksums), and
each shipped with focused unit tests.

**Performance (renderer allocation).** The offline render allocated a fresh
whole-song `Float64List` per note-run and, for native IT/XM voices, held every
overlapping NNA voice's whole-song buffer at once — O(voices × songLength).
- `renderChannelPerNote` now reuses one scratch buffer per channel instead of
  allocating a whole-song buffer per note (byte-identical). *(perf commit)*
- `_renderNativeTickZoneVoices` is now two-pass (build voice metadata, then
  render+mix one voice at a time), so per-voice buffers are no longer
  co-resident — peak drops from O(voices × song) to O(song) for overlapping
  native songs, byte-identical. *(perf commit)*
- A render-throughput benchmark (`bin/bench_render.dart`) was added to track it.
- **Remaining:** the per-voice *transient* render buffer is still whole-song, so
  very long native IT renders (e.g. a 570 s song) are still heavier/slower than a
  streaming mixer would be. The full block-streaming renderer + bounded
  range/streaming WAV export (mod_pending item “Long-song render …”) is the
  remaining large perf item; the cuts above reduce, but do not eliminate, the
  whole-song working set.

**Renderer correctness.** The per-tick sample voice applied a hardcoded 30 ms
key-off release, ignoring the instrument’s IT/XM fadeout. It now uses the real
`nativeFadeout` decay (matching the native-zone path); notes without a fadeout
are unchanged. *(fadeout commit)*

**Reader/writer coverage.**
- **S3M**: the reader now reads **stereo** sample data (`pcmRight`), recognizes
  **AdLib/OPL** (type-2) instruments instead of silently dropping them, and reads
  the previously-ignored **pack** byte (packed blocks are preserved, not misread
  as raw PCM); the writer round-trips stereo. *(s3m commit)*
- **MOD**: 4-channel modules with **> 64 patterns** now emit the ProTracker
  `M!K!` tag (≤ 64 patterns still write `M.K.`). *(writer commit)*
- **XM**: verified that 16-bit source samples already export as 16-bit XM
  (the earlier audit note was stale). *(writer commit)*

**Editor.** A **format export-loss report** (`moduleExportLossReport`) now lists,
before export, what the chosen target format cannot represent (channels > 4 and
8-bit/mono/effect/envelope losses for MOD, IT re-encode/message/MIDI-macro
losses, cross-format provenance loss, etc.) and is surfaced as a confirmation in
the Advanced Tracker export flow. *(export-report commit)*

### Second pass (continuation, same day) — further gaps closed

Continuing the same cadence, the following also shipped to `main`, each gated and
unit-tested:
- **Cross-format effects**: S3M/IT `S1x`/`S2x`/`S3x`/`S4x` (glissando control,
  set-finetune, vibrato/tremolo waveform) now map bidirectionally cross-format via
  the replayer’s `Exy` commands; genuinely-unmappable ones (`S0`/`S5`/`S7`/`S9`/
  `SA`/`Z`-MIDI) still drop and are now named by the export-loss report.
- **Bounded streaming / range export**: `renderOrderChunksPcm` /
  `streamSongWavToFile` / `renderOrderRangeWav` + CLI `--stream` / `--from-order`
  / `--to-order` / `--chunk-orders`. Peak RSS on a long MOD dropped ~41 %
  (611 → 362 MB) in stream mode; byte-identical to the default render for
  uniform/non-command songs; a full-length single chunk reproduces the exact
  render. (The *default* full render is unchanged.)
- **S3M DP30 ADPCM** packed samples now decode to PCM (libopenmpt algorithm;
  algorithm/roundtrip-verified, no real packed `.s3m` fixture; degenerate input
  falls back to preserve-only).
- **S3M AdLib/OPL** (type-2) instruments are now **audible** via a static 2-op FM
  approximation of the patch at import (documented as an approximation, not a
  cycle-exact OPL2 emulator); the instrument still re-exports byte-identically.
- **Native flow/order timeline**: a pure `songFlowTimeline` (from `walkFlow`) plus
  a read-only Advanced Tracker view showing the played order sequence with its
  jump/break/loop/speed/tempo commands.

**Still genuinely open (documented, not done):** a **fully byte-identical
continuous streaming renderer** for command-heavy songs (the bounded export above
resets voice state at chunk boundaries; true cross-chunk continuity needs the
whole channel×row×block loop transposed — a large rewrite); the remaining unmapped
cross-format effects (`S0`/`S5`/`S7`/`S9`/`SA`/`Z`); MOD tag-alias preservation
(FLT8/OCTA); a cycle-exact OPL emulator (vs the FM approximation shipped); and the
deeper native editors (raw effect-memory, native S3M header, velocity zones,
in-place flow *editing*). See the feature audit below for per-feature state.

## Verification status

| Item | Result | Scope and qualification |
| --- | --- | --- |
| Focused codec/conversion/tracker tests | PASS | Current focused suites pass, including MOD, XM, S3M, IT, writers, conversion, roundtrip, native-zone codec/replay, and Advanced Tracker UI tests. |
| External audio comparison | PASS | 10 MOD, 10 XM, 10 S3M, and 10 IT files were rendered with OpenMPT and compared with our X1 renders in `/tmp/tracker_listen_final`. All 40 source-to-X1 comparisons passed the current automated thresholds. |
| Same-format structural roundtrips | PASS | The tested corpus passed source -> X1 -> X2 checks, including IT compressed samples and native metadata cases. |
| Full test suite | NOT GREEN | The full suite still has unrelated environment/UI failures, including the missing Kokoro voice pack and a tracker UI sample assertion. This audit does not claim the full suite is green. |
| Meaning of PASS | LIMITED | The corpus is evidence against the recent regressions; it is not complete format conformance. Rare commands and unusual files still need coverage. |

## Format matrix

| Format | Reads correctly | Writes correctly | Renders in the app | Editable in the app | Pending / loss |
| --- | --- | --- | --- | --- | --- |
| MOD | Classic 4-channel and supported channel tags, 31 samples, 64-row patterns, notes, volumes, and common effects. | Canonical MOD output and same-format tested roundtrips work. | Yes for the supported sample/effect subset. | Only through the simplified tracker grid and neutral model. | Cross-format export is canonical 4-channel MOD; channels above 4, unsupported effects, stereo, envelopes, arbitrary row counts, and instrument semantics cannot survive. |
| XM | Native headers, packed patterns, instruments, samples, raw PCM, and tracker metadata are retained for same-format conversion. | Native same-format output preserves the retained raw data; canonical XM is emitted from the neutral model. XM tremor, imported stereo samples, native per-note sample zones, and effect-bearing stereo sample paths render on the supported paths, including sampled multi-zone tick effects. | Advanced Tracker can select/edit embedded native zones and preserves them in its song codec and target XM export. | Some XM-specific behaviors and exact native command editing remain incomplete. |
| S3M | Native order/header/default-pan data, pattern raw data, and PCM sample data are supported, including zero-length patterns. Stereo sample data (`pcmRight`) is now read; AdLib/OPL (type-2) instruments are recognized and preserved instead of dropped; the pack byte is read and packed blocks preserved (not misread as raw PCM). | Tested same-format output preserves the supported native data; default-pan tables now affect imported channels and are emitted from editable channel pan state; stereo samples round-trip. | Yes for supported PCM/sample/effect behavior (OPL/packed samples are preserved but not synthesized/decoded). | No native S3M header, channel-setting, or command editor. | DP30 ADPCM decode and OPL synthesis are not implemented (payloads preserved, not sounded); format-specific effects and metadata can be approximated or dropped. |
| IT | Native headers, instruments, envelopes, sample blocks, compression, stereo/raw PCM metadata, and pattern semantics are read. | Native sample/header/instrument data is retained; patterns are semantically re-encoded rather than guaranteed byte-identical. Imported channel pan/volume headers now affect playback and round-trip from editable mixer state. | Yes for the supported sample/effect subset, including imported stereo samples, sample gain, per-pattern lengths, native note-to-sample zones, common envelopes, native IT NNA/DCT/DCA old-note actions for ordinary and effect-bearing sampled zone playback, and effect-bearing stereo sample paths. | Advanced Tracker can select/edit embedded native zones and preserves them in its song codec and target IT export. | Per-tick key-off release now follows the native IT/XM `nativeFadeout` rate (was a fixed 30 ms); some IT effects and exact envelope-release curves remain incomplete. |

## Feature audit

| Feature | Read / write state | Actual audio state | Editable state | Could be rendered? | Priority |
| --- | --- | --- | --- | --- | --- |
| Mono PCM samples | Read and written for all four formats in the supported paths. | Rendered. | Can be selected and borrowed through the app's sample model. | Already supported; expand edge-case encoding coverage. | Medium |
| Stereo samples | IT/XM right-channel PCM is parsed, written, resampled, and carried by `SampleInstrument`. | Ordinary and effect-bearing sampled playback preserve the native left/right image on uniform and variable-timing paths. | The native instrument editor now displays both waveforms and auditions them in stereo; destructive right-channel DSP is still absent. | Yes. Add channel-aware sample DSP and native channel metadata. | Medium |
| Sample volume and pan | Native sample volume/global volume and default pan are mapped into the neutral/imported instrument. | Imported sample gain is applied before mixing; channel/sample pan and native pan envelopes are applied on the supported sampled paths. | Basic channel/instrument controls exist, but not all native sample controls. | Yes. Add explicit per-sample gain/pan controls and cover all per-tick paths. | High |
| Instrument keymaps and zones | XM/IT keymap data is read and retained in native codec data; IT lookup is used in import resolution. | Note-to-zone selection renders for ordinary notes and sampled/additive effect-bearing uniform/variable paths; other non-sample zones still use the generic fallback for tick effects. | Native key mappings can now be added, removed, and remapped in the instrument editor; velocity ranges and non-sample zone replacement remain absent. | Yes. Add velocity ranges and per-zone replacement for the remaining instrument types. | High |
| XM/IT volume, pan, and IT pitch envelopes | Read and written in native instrument data; sampled imports carry volume/pan envelopes, IT pitch envelopes, and loop/sustain indices. Disabled IT envelopes and their loop/sustain flags are distinguished from enabled envelopes. | Per-note sampled playback evaluates active volume/pan envelopes and IT pitch envelopes, including sustain hold and envelope looping on ordinary and sampled tick paths; shared samples receive per-zone envelopes in native pools. | Advanced Tracker edits native volume, pan, and pitch points plus sustain/loop indices; exact tracker release timing remains approximate. | Yes. Match the remaining tracker-specific release/curve behavior. | High |
| IT NNA/DCT/DCA and fadeout | Native fields are read and written; imported sample voices and editable zone samples retain NNA/DCT/DCA/fadeout metadata. | Native IT multi-zone playback now has a shared voice allocator with cut, note-off, fade, and duplicate matching on ordinary, uniform tick, and variable-timing sampled paths. | Advanced Tracker exposes NNA/DCT/DCA/fadeout controls in the sample/zone editor. | Yes. Match tracker-specific fade/release timing and cover remaining non-sampled native voices. | High |
| Sample loops and sustain loops | Common loop metadata is read and written; IT sustain-loop offsets and direction now survive neutral and IT roundtrips. | Ordinary loops and held-note IT sustain loops render on normal and effect-bearing uniform/variable sample paths; sampled tick voices now enter a release envelope and ordinary loop after key-off, but exact tracker release timing is still approximate. | Basic sample editing is not a native loop editor. | Yes. Match format-specific release curves and expose sustain/release controls in the editor. | Medium |
| Pattern lengths | Native lengths are readable/writable in codec data. | Module import now preserves each pattern's native row count and the renderer's variable-length path schedules them. | Advanced Tracker already has a per-pattern length control. | Add stronger mixed-length flow/export coverage. | Medium |
| Order and flow | Jumps, breaks, loops, speed, and tempo are handled for the tested subset. | Tested arrangements render correctly, but unsupported flow/effect combinations can diverge. | App exposes simplified pattern slots/order, not all native flow commands. | Yes. Add a native flow timeline and remaining command semantics. | High |
| Common tracker effects | A substantial MOD/XM/S3M/IT subset is mapped to the neutral model and replay engine. | Arpeggio, portamento, vibrato, tremolo, volume/pan changes, jumps/breaks, speed/tempo, note cut/delay/retrigger, loops, and several extended commands render. | Only a limited generic effect model is editable. | Yes. Implement remaining mappings and native effect memory. | High |
| Format-specific effects | Raw/native information is retained in the song bridge for same-format exports. | XM tremor and representable XM volume-column mini-commands, S3M/IT tremor, row-delay (`S6x`/`SEx`), coarse pan (`S8x`), IT/S3M tempo slides, IT/S3M panbrello, and IT channel-volume command provenance have distinct internal mappings; MIDI hardware behavior and some retrigger variants remain approximated or dropped. | Native command provenance is retained, but the visible editor still exposes the generic command model. | Mostly yes, command by command; MIDI hardware behavior is not necessarily renderable. | High |
| Percussion and drum kits | Samples and note tracks can be imported. | Sample-based drums render, but native kit/keymap semantics are not fully preserved. | Simplified drum grid is editable. | Yes. Add native drum mappings and per-note zones. | Medium |
| S3M non-PCM and packed samples | Non-PCM instruments are recognized but not decoded as playable samples; packed sample path is incomplete. | These cases do not render correctly. | Not editable as native data. | Yes for known encodings; otherwise preserve and report unsupported payloads. | Medium |
| Native command bytes and effect memory | Same-format codecs preserve more raw/native information than the neutral model. | Renderer consumes the normalized subset, not every original byte/state transition; sparse S3M physical channel IDs now map correctly through codec roundtrips. | Advanced Tracker now exposes all currently normalized command families, including pan, sample offset, retrigger, tremor, and panbrello; raw format-specific provenance editing remains absent. | Yes where playback semantics are implemented. | High |
| Long-song render memory and throughput | Module data is retained without truncating the order or pattern rows. | Improved (2026-07-25): per-note render buffers are reused per channel and native NNA voices are rendered one at a time (no longer co-resident), so a 570 s native IT render dropped from ~3.0 GB to ~2.8 GB peak while staying byte-identical. Still allocates whole-song mixes and per-voice transient buffers, so very long command-heavy stereo songs remain heavy/slow. Track with `bin/bench_render.dart`. | No user-facing render range or streaming export control in the app. | Partly done. Remaining: a block-streaming renderer that keeps cross-row/voice state per chunk (eliminating whole-song working set), then expose bounded preview/streaming export. | High |

## What the current app actually edits

| Editable today | Not directly editable today |
| --- | --- |
| Simplified notes in four pattern slots; channel selection; note volume/accent; limited generic note effects; channel instrument selection; sample borrowing; insert effect chains; simplified order/slot arrangement; tempo and swing controls; drum-grid notes. | Native MOD/XM/S3M/IT command columns and effect memory; exact pattern row lengths; native order markers and flow commands; XM/IT keymaps and multi-sample zones; IT NNA/DCT/DCA/fadeout; exact native release behavior; stereo sample channels; native S3M channel/header settings; compression/encoding flags; format-specific metadata and unsupported effects. |

## Recommended implementation order

| Order | Work | Reason |
| --- | --- | --- |
| 1 | Preserve and render stereo samples, including `pcmRight`, sample gain, and default pan. | Implemented for ordinary and per-tick uniform/variable sample playback; editor coverage remains. |
| 2 | Add per-instrument zones/keymaps and per-voice XM/IT envelopes. | This fixes wrong sounds and envelope behavior without collapsing native instruments. |
| 3 | Implement IT voice allocation and NNA/DCT/DCA/fadeout. | Required for faithful overlapping-note playback. |
| 4 | Preserve native pattern lengths and arrangement timing. | Prevents padding/truncation changes in mixed-pattern songs. |
| 5 | Fill out effect mappings and effect-memory behavior. | Covers the remaining audible tracker-command deviations. |
| 6 | Add a format-aware native tracker editor and export-loss report. | Makes the remaining limitations visible and actually editable. |
| 7 | Complete S3M packed/non-PCM sample support. | Needed for broader S3M corpus coverage. |

## Merge and worktree disposition

| Item | Decision |
| --- | --- |
| Tracker render fixes | Merged to `main` and pushed as `d2c1cf47` and `948e99b5`. |
| Advanced editor fixes | Merged to `main` and pushed as `17b79485`; documentation refresh is `c91215c1`. |
| Debugging stash / nested clones | Do not merge. They are intermediate or unrelated worktrees, not application changes. |
| Downloaded fixtures and generated WAV | Keep local-only. No provenance/licence record exists; do not add them to `origin/main`. |

The practical conclusion is that the recent regression set is addressed for the
tested corpus, and the renderer now preserves more native sample state. The
application is still a normalized tracker editor rather than a complete native
MOD/XM/S3M/IT editor. The largest remaining audible gaps are command-heavy
stereo voice paths, shared samples with distinct native instrument envelopes,
IT voice actions, sustain/envelope flags, and the unmapped effect families above.
