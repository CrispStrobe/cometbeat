# Handover — PDMX JSON → MIDI converter

**For a fresh agent/session. Self-contained: every path, URL, schema, and gotcha
is here. You need no prior context.** NOT legal advice.

## Objective

Produce **MIDI files for the 7,548 CC0-original PDMX scores** and add them to the
clean-licensed music collection on the VPS. Then **validate** the conversion
(roundtrip: the MIDI's notes must equal the source JSON's notes).

## Why this task exists (the finding that led here)

**PDMX** (Public Domain MusicXML dataset, from MuseScore user uploads;
`openmusic/pdmx` on HuggingFace) is a corpus of ~254,000 scores. Its metadata
CSV lists per-score `mid/…` and `mxl/…` paths — **but the actual distribution
tarball contains ONLY `.json` files** (verified: a full scan of `PDMX.tar.gz`
found 508,154 `.json`, **0 `.mid`, 0 `.mxl`**). So there is no MIDI to download;
it must be **converted from PDMX's JSON score format**, which is
**muspy-compatible** (has `resolution`, `tempos`, `tracks[].notes[]`, etc.), so
the conversion is straightforward.

We want only the **license-clean subset**: `cc-zero` (CC0) **AND** no
`license_conflict` **AND** `is_original` (the uploader's own composition, so no
third-party work underneath) = **7,549 rows / 7,548 unique files**. CC0 + original
is clean on both axes (licence of the encoding AND the underlying work). Caveat:
`is_original` is self-attested, so this is "defensible", not "cleared" — a
dup/plagiarism pass is wise before shipping, but not required to build the MIDIs.

## Inputs — all persistent, on the VPS unless noted

**VPS:** host `REDACTED-VPS-IP`, user `root` (already in `~/.ssh/config`; plain
`ssh REDACTED-VPS-IP` works).

| What | Location |
|---|---|
| The 1.5 GB tarball (kept, 508k `.json`) | **VPS** `/mnt/volume1/pdmx-cc0-midi/PDMX.tar.gz` |
| CC0-original target list (7,549 lines) | **VPS** `/mnt/volume1/pdmx_cc0_mid.txt` |
| HF source (re-download if needed; NOT gated) | `https://huggingface.co/datasets/openmusic/pdmx/resolve/main/PDMX.tar.gz` |
| Metadata CSV (to re-derive the list) | inside the tarball (1 `.csv`), or re-download PDMX.csv from the HF dataset |
| Suggested MIDI output dir | **VPS** `/mnt/volume1/pdmx-cc0-midi/mid/` |

**`/mnt/volume1/pdmx_cc0_mid.txt`** — each line is a path like
`mid/1/11/QmbbmCapzTHpsmd3eLRuefXJ94Ms7avxPBy7v6tXSxYDkX.mid`. The **basename** is
a content hash; the matching JSON basename is the same hash with `.json`
(`Qmbbm….json`). Match JSON members to this list by **basename**, robustly,
regardless of the tar's internal prefix.

**Re-deriving the list from the CSV** (if ever needed) — the filter is exactly:
```python
license == "cc-zero" and license_conflict == "False" and is_original == "True"
# → 7,549 rows; take the `mid` column, basename, swap .mid→.json
```

## The JSON schema (muspy-format — verified from a real CC0 file)

Top-level keys:
`metadata, resolution, tempos, key_signatures, time_signatures, beats,
barlines, lyrics, annotations, tracks, song_length, infer_velocity,
absolute_time`

- **`resolution`** — ticks per quarter note (e.g. `480`). This is the MIDI
  division (PPQ).
- **`tempos`** — `[{name, time, qpm, measure, text}]`. `time` in ticks, `qpm` =
  quarter-notes/min (BPM). May be empty → default 120.
- **`time_signatures`** — `[{name, time, numerator, denominator, measure}]`
  (verified from a real file — e.g. `{time:0, numerator:4, denominator:4}`).
- **`tracks`** — `[{name, program, is_drum, notes, chords, lyrics, annotations}]`.
  - `program` — MIDI program 0–127.
  - `is_drum` — bool → MIDI channel 9 (0-indexed).
  - **`notes`** — `[{name, time, pitch, duration, velocity, pitch_str, measure,
    is_grace}]`. `time` = onset ticks, `pitch` = MIDI 0–127, `duration` = ticks,
    `velocity` = 0–127. `is_grace` notes may have tiny/zero duration.

Real example note:
`{"name":"Note","time":0,"pitch":70,"duration":1920,"velocity":64,
"pitch_str":"Bb","measure":1,"is_grace":false}`

## Step 1 — extract the 7,548 CC0 JSON from the tarball

Stream the tar once, matching `.json` members by basename against the CC0 list
(swap the list's `.mid`→`.json`). Reference (VPS `python3`, stdlib only):

```python
import tarfile, os
os.chdir("/mnt/volume1/pdmx-cc0-midi")
want = set(l.strip().split("/")[-1].replace(".mid", ".json")
           for l in open("/mnt/volume1/pdmx_cc0_mid.txt"))
os.makedirs("json", exist_ok=True)
n = 0
with tarfile.open("PDMX.tar.gz", "r:gz") as t:
    for m in t:
        if m.isfile() and m.name.endswith(".json") and m.name.split("/")[-1] in want:
            open("json/" + m.name.split("/")[-1], "wb").write(t.extractfile(m).read())
            n += 1
print("extracted", n, "of", len(want))   # expect ~7548
```
(Verified: tar members look like `PDMX/data/f/D/QmfDk….json` — a `PDMX/data/…`
tree — but basename-matching sidesteps the prefix entirely. This exact pattern
was verified to find the JSONs.)

## Step 2 — convert JSON → MIDI

**Try muspy first (authoritative — PDMX was built with it).** muspy's
`save_json` produces this exact structure, so `load_json` reads it and
`write_midi` handles all edge cases (channels, tempo, grace):
```bash
pip install muspy         # local or VPS venv; VPS has only /usr/bin/python3, no pip pkgs
```
```python
import muspy, glob, os
os.makedirs("mid", exist_ok=True)
for f in glob.glob("json/*.json"):
    try:
        muspy.load_json(f).write("mid/" + os.path.basename(f).replace(".json", ".mid"))
    except Exception as e:
        print("SKIP", f, e)
```
⚠ PDMX uses a muspy subclass **"MusicRender"** (repo: `github.com/pnlong/PDMX`).
Plain `muspy.load_json` should read the core fields; if it chokes on a
PDMX-specific field, either strip unknown keys before loading, or use the
`github.com/pnlong/PDMX` repo's own `load`/`write` helpers, or fall back to the
minimal writer below.

**Fallback — a minimal, dependency-free MIDI writer** (runs on the VPS's bare
`python3`; no muspy needed). This is a *starting point* — test + harden it:
```python
import struct, math

def _vlq(n):
    n = max(int(n), 0)
    b = [n & 0x7F]; n >>= 7
    while n > 0: b.append((n & 0x7F) | 0x80); n >>= 7
    return bytes(reversed(b))

def json_to_midi(d):
    res = int(d.get("resolution", 480))
    tracks = []
    # --- meta track: tempos + time signatures ---
    ev = []
    for t in (d.get("tempos") or [{"time": 0, "qpm": 120}]):
        us = int(round(60_000_000 / (t.get("qpm") or 120)))
        ev.append((int(t.get("time", 0)), 0, b"\xFF\x51\x03" + us.to_bytes(3, "big")))
    for ts in (d.get("time_signatures") or []):
        num = int(ts.get("numerator", 4)); den = int(ts.get("denominator", 4))
        dd = int(round(math.log2(den))) if den > 0 else 2
        ev.append((int(ts.get("time", 0)), 0, b"\xFF\x58\x04" + bytes([num, dd, 24, 8])))
    ev.sort(key=lambda e: (e[0], e[1]))
    buf = bytearray(); prev = 0
    for tick, _, data in ev:
        buf += _vlq(tick - prev) + data; prev = tick
    buf += _vlq(0) + b"\xFF\x2F\x00"
    tracks.append(buf)
    # --- one MIDI track per JSON track ---
    ci = 0
    for tr in d.get("tracks", []):
        if tr.get("is_drum"):
            ch = 9
        else:
            ch = ci if ci < 9 else ci + 1   # skip channel 9 for pitched tracks
            ci += 1
            if ch > 15: ch = 15             # >15 tracks: reuse last channel
        prog = int(tr.get("program") or 0) & 0x7F
        notes = []
        for n in tr.get("notes", []):
            on = int(n["time"]); dur = max(int(n.get("duration", 1)), 1)
            p = int(n["pitch"]) & 0x7F; v = int(n.get("velocity", 64)) & 0x7F
            notes.append((on, 1, 0x90 | ch, p, v))       # note-on
            notes.append((on + dur, 0, 0x80 | ch, p, 0)) # note-off (sorts before on at same tick)
        notes.sort(key=lambda e: (e[0], e[1]))
        b = bytearray(); b += _vlq(0) + bytes([0xC0 | ch, prog]); prev = 0
        for tick, _, status, p, v in notes:
            b += _vlq(tick - prev) + bytes([status, p, v]); prev = tick
        b += _vlq(0) + b"\xFF\x2F\x00"
        tracks.append(b)
    out = bytearray(b"MThd") + struct.pack(">IHHH", 6, 1, len(tracks), res)
    for t in tracks:
        out += b"MTrk" + struct.pack(">I", len(t)) + bytes(t)
    return bytes(out)
```
Edge cases to handle/verify: grace notes (`is_grace`, may be dur 0 → clamp),
tracks with no notes (skip or emit empty), `program`/`velocity`/`pitch` bounds,
>15 non-drum tracks (channel reuse), and multiple tempo/timesig changes.

## Step 3 — VALIDATE (mandatory — do a roundtrip, like we did for Guitar-TECHS)

Parse each produced MIDI back and confirm its notes equal the JSON's notes.
Compare, per file, the multiset of `(track_index_or_channel, pitch, onset_tick)`
from the JSON vs from the MIDI. Target: **100%** note match (allow a small
tolerance only for grace/rounding, and report anything dropped). Use `mido`
(`pip install mido`) or a stdlib MIDI parser. A file-level summary like
"N files, X% notes matched, Y perfect files, ROUNDTRIP PASS/FAIL" is the bar.
(Precedent: this repo's Guitar-TECHS roundtrip caught a 0.1% note-drop bug — do
the same here before declaring done.)

## Output + naming

MIDIs → **`/mnt/volume1/pdmx-cc0-midi/mid/<hash>.mid`** (basename = the content
hash, matching `pdmx_cc0_mid.txt`). ~7,548 files, each small (a few KB).

## Environment gotchas (learned the hard way)

- **VPS python is `/usr/bin/python3` (3.12), STDLIB ONLY — no pip packages, NO
  miniconda.** Do NOT reference `~/miniconda3` on the VPS (that path is the local
  Mac's, not the VPS's — it caused a silent failure here). For muspy/mido on the
  VPS, make a venv (`python3 -m venv`), or run the stdlib minimal writer, or do
  the conversion on the local Mac (`~/miniconda3/bin/python`, has numpy) and
  rsync the MIDIs to the VPS.
- **ssh + backgrounding hangs** (the remote background job holds ssh's fds, so
  ssh never returns). For long jobs, either run them **foreground over a
  kept-alive ssh from a local *background* task** (this worked reliably), or use
  `nohup … </dev/null >log 2>&1 &` and poll the log in a *separate* ssh.
- **Disk:** `/mnt/volume1` is VPS-local (~80 GB free) — use it for work.
  `/mnt/storage` is a CIFS Storage Box (2.4 TB, but slow for many small files and
  loses POSIX semantics) — only for final archival, via rsync.
- The tarball scan of 1.5 GB gzip takes a few minutes; stream once, don't
  re-open per file.

## Licence provenance (record with the output)

The 7,548 are **CC0 1.0** (`cc-zero`) with no `license_conflict` and
`is_original=True` (uploader's own composition). Clean on both axes. `is_original`
is self-attested → "defensible, not cleared"; note this and consider a
dup-detection pass before any shipping use. The MIDIs are **derived from CC0
source**, so the MIDIs are redistributable.

## Where to record results

- Add a line to **`docs/CORPUS_LICENSING.md`** (this repo) under the PDMX entry:
  "PDMX ships JSON-only; N CC0 MIDIs built + roundtrip-verified at
  `/mnt/volume1/pdmx-cc0-midi/mid/`."
- If you keep the converter, put it in the repo (e.g. `tool/pdmx_json_to_midi.py`)
  with the roundtrip validator alongside.

## Definition of done

7,548 (± the handful with unconvertible/empty scores, logged) `.mid` files in
`/mnt/volume1/pdmx-cc0-midi/mid/`, **roundtrip-validated ≥ ~99.9% note match**,
provenance recorded in `docs/CORPUS_LICENSING.md`.
