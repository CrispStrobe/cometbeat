#!/usr/bin/env python3
"""Turn the CLEARED Internet Jukebox items into db.json rows.

Runs on the VPS (or locally against a staged tree) AFTER:
  1. jukebox_harvest.py   — downloaded the symbolic files
  2. parse sweep          — proved every .musicxml reads through crisp_notation
  3. jukebox_promote.py   — decided axis 2 per item

Only `clearance == "cleared"` rows are emitted. Held items live exclusively in
jukebox-probation.json and never reach db.json — the same model as ModArchive's
module-clearance and Ebersberger's probation ledger, so a future re-run of the
promotion pass can widen the cleared set without a rebuild.

One row per ITEM (not per file): `.musicxml` is the primary payload, the `.mid`
travels in files{} as a reference rendering. Audio is never referenced.
"""
import hashlib
import json
import re
import sys
from pathlib import Path

HARVEST = Path(sys.argv[1] if len(sys.argv) > 1 else "jukebox")
DEST_PREFIX = sys.argv[2] if len(sys.argv) > 2 else "jukebox"
ROOT = Path(sys.argv[3]) if len(sys.argv) > 3 else HARVEST

SOURCE = "Internet Jukebox (Public Resource)"

AXIS1 = ("axis1=CC-PDM-1.0 — item marked Public Domain Mark 1.0 by Public "
         "Resource, who also dedicate the derivation (OMR via Soundslice + "
         "post-processing by Martin R. Lucas); a faithful transcription of a PD "
         "print carries no new authorship (no §70 scholarly edition, UK "
         "typographical-arrangement term long expired on these prints)")


def as_list(v):
    return [] if v is None else (v if isinstance(v, list) else [v])


def first(v):
    xs = as_list(v)
    return xs[0] if xs else None


def slug(s):
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", (s or "").lower())).strip("-")[:70]


def year_of(item):
    for f in ("date", "year"):
        for v in as_list(item.get(f)):
            m = re.search(r"\b(1[5-9][0-9]{2}|20[0-2][0-9])\b", str(v))
            if m:
                return m.group(1)
    return None


def main():
    cleared = json.loads((HARVEST / "jukebox-clearance.json").read_text())
    rows, skipped = [], 0

    for it in cleared:
        xmls = it["files"].get("musicxml") or []
        mids = it["files"].get("midi") or []
        if not xmls:
            skipped += 1
            print(f"!! no musicxml, skipping {it['identifier']}")
            continue
        primary = xmls[0]
        src = HARVEST / primary["path"]
        if not src.exists():
            skipped += 1
            print(f"!! missing file, skipping {it['identifier']}")
            continue

        rel = f"{DEST_PREFIX}/{primary['path']}"
        files = {"musicxml": rel}
        if mids:
            files["midi"] = f"{DEST_PREFIX}/{mids[0]['path']}"

        names = it.get("names") or []
        row = {
            "id": f"jukebox-{slug(it['identifier'])}",
            "title": first(it.get("title")),
            "author": "; ".join(names) if names else None,
            "poet": None,
            "year": year_of(it),
            "instrument": None,
            "instruments": None,
            "editor": "Public Resource (OMR: Soundslice; post-processing: "
                      "Martin R. Lucas)",
            "ensemble": None,
            "licence": "Public Domain Mark 1.0",
            "source": SOURCE,
            "source_url": it["source_url"],
            "attribution": None,          # PDM requires none
            "format": "musicxml",
            "rights_status": "PD",
            "rights_method": f"{AXIS1}; axis2={it['rule']}: {it['axis2_reason']}",
            "path": rel,
            "kind": "score",
            "sha256": hashlib.sha256(src.read_bytes()).hexdigest(),
            "bytes": src.stat().st_size,
            "files_extra": files,
        }
        rows.append(row)

    out = HARVEST / "jukebox-manifest.json"
    out.write_text(json.dumps(rows, indent=1, ensure_ascii=False))
    print(f"\njukebox-manifest.json: {len(rows)} rows ({skipped} skipped)")
    by_rule = {}
    for c in cleared:
        by_rule[c.get("rule")] = by_rule.get(c.get("rule"), 0) + 1
    print("cleared by rule:", by_rule)
    for r in rows[:12]:
        print(f"  {r['id'][:44]:44} {str(r['title'])[:34]:34} "
              f"{r['year'] or '-':>5}  {r['author'] or 'anon'}")


if __name__ == "__main__":
    main()
