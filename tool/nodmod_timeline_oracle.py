#!/usr/bin/env python3
"""Freeze an INDEPENDENT flow/timing oracle for the replay-fidelity ladder (X5).

Our own codec tests are self round-trips, and the audio A/B needs three external
renderers and never runs on CI. This fills the gap in between: NodMOD
(github.com/erodola/nodmod, MIT) walks a module's order list in Python and
yields every visited row with its onset, speed and tempo. Comparing our
`resolveTimingMap` against that is pure arithmetic — no audio, no binaries — so
the resulting test runs everywhere.

The oracle is FROZEN into `test/fixtures/flow/nodmod_timeline.json` rather than
shelled out to at test time, which is what keeps the test CI-able. Regenerate it
only when the fixtures change, and re-read the caveats below when you do.

    pip install nodmod          # or clone it and use its src/ on PYTHONPATH
    python3 tool/nodmod_timeline_oracle.py

⚠️ VERIFY THE ORACLE BEFORE TRUSTING IT. Generating this file found two places
where NodMOD is not ground truth, and both were caught by checking its totals
against libopenmpt and libxmp rather than by assuming:

  * `pattern_loop_E6x.s3m` — NodMOD's S3M walker handles A/T/B/C/SE but NOT
    `SBx`, S3M's pattern loop, so it reports 128 rows where the loop should make
    it 146. Both audio references render 17.5 s, agreeing with 146. The entry is
    SKIPPED here, by name, rather than silently pinning our correct behaviour to
    an incomplete oracle.
  * `pattern_loop_E6x.xm` — libopenmpt renders 16.66 s and libxmp 17.52 s. The
    REFERENCES disagree with each other about FastTracker II's loop-counter
    semantics, so there is no ground truth to freeze. Recorded, not gated.

IT is absent entirely: NodMOD ships MOD/XM/S3M walkers and no IT one, which is
why the ladder calls IT the highest-risk reader — it has the fewest oracles and
the most features.
"""

import json
import os
import sys

FIXTURES = "test/fixtures/flow"
OUT = os.path.join(FIXTURES, "nodmod_timeline.json")

# (fixture, reason) pairs excluded from the frozen oracle. Keeping the reason
# here means a future reader does not have to rediscover why.
SKIP = {
    "pattern_loop_E6x.s3m": "NodMOD's S3M walker does not model SBx pattern loop "
    "(reports 128 rows; libopenmpt and libxmp both agree with 146)",
    "pattern_loop_E6x.xm": "libopenmpt (16.66 s) and libxmp (17.52 s) disagree "
    "about FT2 loop-counter semantics, so there is no ground truth to freeze",
}

SUPPORTED = (".mod", ".xm", ".s3m")


def main() -> int:
    try:
        from nodmod.loader import load_song
    except ImportError:
        print(
            "nodmod not importable. `pip install nodmod`, or clone it and run:\n"
            "  PYTHONPATH=<clone>/src python3 tool/nodmod_timeline_oracle.py",
            file=sys.stderr,
        )
        return 1

    out = {"_source": "nodmod (MIT) iter_playback_rows", "_skipped": SKIP, "songs": {}}
    for name in sorted(os.listdir(FIXTURES)):
        if not name.endswith(SUPPORTED) or name in SKIP:
            continue
        song = load_song(os.path.join(FIXTURES, name))
        rows = list(song.iter_playback_rows())
        # Flat quads keep the file a third the size of a list of objects, and it
        # is machine-written anyway.
        flat = []
        for r in rows:
            flat += [
                r.sequence_idx,
                r.pattern_idx,
                r.row,
                int(round(r.start_sec * 1000)),
            ]
        out["songs"][name] = {"rows": len(rows), "quads": flat}
        print(f"  {name:26s} {len(rows):4d} rows, ends {rows[-1].end_sec:8.3f}s")

    with open(OUT, "w") as fh:
        json.dump(out, fh, separators=(",", ":"))
        fh.write("\n")
    print(f"wrote {OUT} ({os.path.getsize(OUT)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
