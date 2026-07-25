# Tracker Audit Fixtures

The large module files in this directory are a local debugging corpus. They are
intentionally not committed until each source has a documented redistribution
licence and attribution record. Their presence in a developer checkout does not
grant the project permission to ship them.

Current local-only corpus:

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

The committed codec tests use synthetic and explicitly licensed fixtures. The
local corpus is exercised by the CLI and OpenMPT A/B workflows described in
`docs/ORACLE.md` and `mod_pending.md`.
