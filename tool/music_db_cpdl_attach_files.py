#!/usr/bin/env python3
"""Attach the secondary formats to each CPDL row, additively.

append_manifest.py builds files{} from the single `format` field, so the MIDI
(and any .ly/.mscz) sitting beside the primary .mxl would be dropped. Same shape
as the Ebersberger and Jukebox MIDI backfills: run straight after the append,
purely additive, assert 0 dangling before writing.

Runs ON THE VPS (it edits db.json in place).
"""
import json
import os
import sys

ROOT = "/mnt/volume1/music-db"
SOURCE = "CPDL (Choral Public Domain Library)"


def main():
    manifest = sys.argv[1] if len(sys.argv) > 1 else "cpdl-manifest.json"
    db = json.load(open(f"{ROOT}/db.json"))
    rows = {r["id"]: r for r in json.load(open(f"{ROOT}/{manifest}"))}

    attached = added = missing = 0
    for x in db:
        if x.get("source") != SOURCE:
            continue
        src = rows.get(x.get("id"))
        if not src:
            continue
        extra = src.get("files_extra") or {}
        for fmt, path in extra.items():
            if x.get("files", {}).get(fmt):
                continue
            if not os.path.exists(os.path.join(ROOT, path)):
                missing += 1
                continue
            x.setdefault("files", {})[fmt] = path
            added += 1
        attached += 1

    dangling = sum(
        1 for x in db
        for p in list((x.get("files") or {}).values())
        + ([x["path"]] if x.get("path") else [])
        if not os.path.exists(os.path.join(ROOT, p)))
    assert dangling == 0, f"{dangling} dangling paths — aborting write"

    json.dump(db, open(f"{ROOT}/db.json", "w"), indent=1)
    print(f"touched {attached} rows, added {added} file entries "
          f"({missing} absent); db.json now {len(db)}; dangling=0")


if __name__ == "__main__":
    main()
