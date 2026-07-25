# Tracker module audit

This is the current audit of the MOD, XM, S3M, and IT reader, writer, neutral
module model, renderer, and editor. It distinguishes format preservation from
what the application can actually play and edit.

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
| S3M | Native order/header/default-pan data, pattern raw data, and PCM sample data are supported, including zero-length patterns. | Tested same-format output preserves the supported native data. | Yes for supported PCM/sample/effect behavior. | No native S3M header, channel-setting, or command editor. | Non-PCM instruments and packed sample decoding are not implemented as a complete native path; format-specific effects and metadata can be approximated or dropped. |
| IT | Native headers, instruments, envelopes, sample blocks, compression, stereo/raw PCM metadata, and pattern semantics are read. | Native sample/header/instrument data is retained; patterns are semantically re-encoded rather than guaranteed byte-identical. | Yes for the supported sample/effect subset, including imported stereo samples, sample gain, per-pattern lengths, native note-to-sample zones, common envelopes, bounded NNA/DCT/DCA old-note actions, and effect-bearing stereo sample paths, including sampled multi-zone tick effects. | Advanced Tracker can select/edit embedded native zones and preserves them in its song codec and target IT export. | Exact multi-voice allocation and several IT effects remain incomplete. |

## Feature audit

| Feature | Read / write state | Actual audio state | Editable state | Could be rendered? | Priority |
| --- | --- | --- | --- | --- | --- |
| Mono PCM samples | Read and written for all four formats in the supported paths. | Rendered. | Can be selected and borrowed through the app's sample model. | Already supported; expand edge-case encoding coverage. | Medium |
| Stereo samples | IT/XM right-channel PCM is parsed, written, resampled, and carried by `SampleInstrument`. | Ordinary and effect-bearing sampled playback preserve the native left/right image on uniform and variable-timing paths. | No stereo waveform editor. | Yes. Add an editor for both waveforms and native channel metadata. | High |
| Sample volume and pan | Native sample volume/global volume and default pan are mapped into the neutral/imported instrument. | Imported sample gain is applied before mixing; channel/sample pan and native pan envelopes are applied on the supported sampled paths. | Basic channel/instrument controls exist, but not all native sample controls. | Yes. Add explicit per-sample gain/pan controls and cover all per-tick paths. | High |
| Instrument keymaps and zones | XM/IT keymap data is read and retained in native codec data; IT lookup is used in import resolution. | Note-to-zone selection renders for ordinary notes and sampled/additive effect-bearing uniform/variable paths; other non-sample zones still use the generic fallback for tick effects. | Native key mappings can now be added, removed, and remapped in the instrument editor; velocity ranges and non-sample zone replacement remain absent. | Yes. Add velocity ranges and per-zone replacement for the remaining instrument types. | High |
| XM/IT volume and pan envelopes | Read and written in native instrument data; sampled imports carry volume/pan envelopes and loop/sustain indices. | Per-note sampled playback evaluates the active instrument envelope, including sustain hold and envelope looping on ordinary sampled paths; shared samples now receive per-zone envelopes in native pools. | Advanced Tracker can edit channel envelopes and zone sample/voice metadata; native envelope point editing and flags remain limited. | Yes. Expose native envelope points and flags directly in the zone editor. | High |
| IT NNA/DCT/DCA and fadeout | Native fields are read and written; imported sample voices and editable zone samples retain NNA/DCT/DCA/fadeout metadata. | Bounded old-note actions render for fixed sampled voices, including duplicate-note matching; native multi-zone playback is polyphonic, but exact per-channel voice allocator semantics and fade timing remain incomplete. | Advanced Tracker exposes NNA/DCT/DCA/fadeout controls in the sample/zone editor. | Yes. Move this state into a real per-channel voice allocator and expose instrument-level metadata. | High |
| Sample loops and sustain loops | Common loop metadata is read and written; IT sustain-loop offsets and direction now survive neutral and IT roundtrips. | Ordinary loops and held-note IT sustain loops render on normal and effect-bearing uniform/variable sample paths; sampled tick voices now enter a release envelope and ordinary loop after key-off, but exact tracker release timing is still approximate. | Basic sample editing is not a native loop editor. | Yes. Match format-specific release curves and expose sustain/release controls in the editor. | Medium |
| Pattern lengths | Native lengths are readable/writable in codec data. | Module import now preserves each pattern's native row count and the renderer's variable-length path schedules them. | Advanced Tracker already has a per-pattern length control. | Add stronger mixed-length flow/export coverage. | Medium |
| Order and flow | Jumps, breaks, loops, speed, and tempo are handled for the tested subset. | Tested arrangements render correctly, but unsupported flow/effect combinations can diverge. | App exposes simplified pattern slots/order, not all native flow commands. | Yes. Add a native flow timeline and remaining command semantics. | High |
| Common tracker effects | A substantial MOD/XM/S3M/IT subset is mapped to the neutral model and replay engine. | Arpeggio, portamento, vibrato, tremolo, volume/pan changes, jumps/breaks, speed/tempo, note cut/delay/retrigger, loops, and several extended commands render. | Only a limited generic effect model is editable. | Yes. Implement remaining mappings and native effect memory. | High |
| Format-specific effects | Raw/native information is retained in the song bridge for same-format exports. | XM/S3M/IT tremor, IT/S3M tempo slides, IT/S3M panbrello, and IT channel-volume command provenance now have distinct internal mappings; MIDI hardware behavior and some pattern-delay/retrigger variants remain approximated or dropped. | Native command provenance is retained, but the visible editor still exposes the generic command model. | Mostly yes, command by command; MIDI hardware behavior is not necessarily renderable. | High |
| Percussion and drum kits | Samples and note tracks can be imported. | Sample-based drums render, but native kit/keymap semantics are not fully preserved. | Simplified drum grid is editable. | Yes. Add native drum mappings and per-note zones. | Medium |
| S3M non-PCM and packed samples | Non-PCM instruments are recognized but not decoded as playable samples; packed sample path is incomplete. | These cases do not render correctly. | Not editable as native data. | Yes for known encodings; otherwise preserve and report unsupported payloads. | Medium |
| Native command bytes and effect memory | Same-format codecs preserve more raw/native information than the neutral model. | Renderer consumes the normalized subset, not every original byte/state transition. | Exact tracker command editing is absent. | Yes where playback semantics are implemented. | High |

## What the current app actually edits

| Editable today | Not directly editable today |
| --- | --- |
| Simplified notes in four pattern slots; channel selection; note volume/accent; limited generic note effects; channel instrument selection; sample borrowing; insert effect chains; simplified order/slot arrangement; tempo and swing controls; drum-grid notes. | Native MOD/XM/S3M/IT command columns and effect memory; exact pattern row lengths; native order markers and flow commands; XM/IT keymaps and multi-sample zones; IT NNA/DCT/DCA/fadeout; envelope points and sustain behavior; stereo sample channels; native S3M channel/header settings; compression/encoding flags; format-specific metadata and unsupported effects. |

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
| Tracker render fix branch | Merged to `main` and pushed as part of merge commit `bd2295fe`. |
| Debugging stash | Keep as a safety/reference stash. Do not merge wholesale: it mixes useful logging with behavior-changing renderer edits and incompatible intermediate APIs. |
| `audiveris/` | Unrelated complete source tree; do not merge. |
| Downloaded fixtures and generated WAV | Useful local audit corpus, but not application changes. Keep out of the main branch unless deliberately adding a fixture set. |

The practical conclusion is that the recent regression set is addressed for the
tested corpus, and the renderer now preserves more native sample state. The
application is still a normalized tracker editor rather than a complete native
MOD/XM/S3M/IT editor. The largest remaining audible gaps are command-heavy
stereo voice paths, shared samples with distinct native instrument envelopes,
IT voice actions, sustain/envelope flags, and the unmapped effect families above.
