# Tracker Audit Fixtures

Two kinds of fixture live here, and the difference matters: a few we **author
and commit**, and a larger corpus that is **local-only** because we have no
right to redistribute it.

## Committed — ours, licence-clean

| File | Format | Use |
| --- | --- | --- |
| `musical.mod` | MOD | **the A/B fidelity reference.** 4 channels, 2 patterns × 64 rows, 15.4 s, a *looped* 256-sample band-limited saw, melody spanning two octaves. Regenerate with `dart run tool/make_musical_fixture.dart` (deterministic — identical bytes every run). |
| `golden.mod` `.xm` `.it` `.s3m` | modules | **parser** fixtures — round-trip and byte-stability tests. |

⚠️ **`golden.*` are not audio references.** Each is a *single note playing a
five-sample waveform*, so comparing level, duration or spectrum against another
engine measures edge-case handling, not musical fidelity — two players differ by
16 dB there purely over how to interpolate five samples. The OpenMPT A/B
therefore runs them **report-only** and gates on `musical.mod` and the local
corpus instead.

`musical.mod` exists because of that. It was added when the A/B turned out to
have nothing musical to judge, and on its first run it exposed a one-sample
rounding error that had silently disabled sample looping for ordinary modules.

## Local-only — not ours to redistribute

Intentionally uncommitted until each source has a documented redistribution
licence and attribution record. Their presence in a developer checkout does not
grant the project permission to ship them.

| File | Format | Use |
| --- | --- | --- |
| `_dont_look_back_.xm` | XM | XM import/render/round-trip audit |
| `buddhia3.it` | IT | long-render, native voice, NNA audit |
| `wonderfulpain.it` | IT | native instrument and envelope audit |
| `mobile.mod` | MOD | instrument mapping and drum-start regression |
| `mulju_the_clown.mod` | MOD | short MOD render audit |
| `powerbase.mod` | MOD | opening instrument and mix audit |
| `golden.mod.wav` | WAV | reference render generated from a local MOD audit |

Do not stage these files by accident. A fixture may be promoted to the
repository only after its source URL, checksum, licence, attribution, and
redistribution permission are recorded in `docs/CORPUS_LICENSING.md`.

⚠️ **Never commit a rendered WAV as a byte-compared reference.**
`golden.mod.wav` is fine as a local scratch artifact, but our render is only
guaranteed deterministic *per platform* — the limiter's `tanh` is built on
`exp()`, which is platform libm. We develop on macOS and CI runs Linux, so a
committed golden render compared byte-exactly is an intermittent red waiting to
happen. Compare two renders made in the SAME run (see
`test/tracker_render_determinism_test.dart`), or compare at signal level with
`test/support/audio_compare.dart`. Committing golden module **bytes** is fine:
parse→write is integer work with no libm anywhere near it.

The committed codec tests use synthetic and explicitly licensed fixtures. The
local corpus is exercised by the CLI and OpenMPT A/B workflows described in
`docs/ORACLE.md` and `mod_pending.md`.
