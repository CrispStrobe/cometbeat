#!/usr/bin/env python3
"""Attach the reference `.mid` to each Internet Jukebox row, additively.

append_manifest.py builds files{} from the single `format` field, so the MIDI
that ships beside each MusicXML would be dropped. Same situation as the
Ebersberger MIDI backfill: run this straight after the append, purely additive,
and assert 0 dangling before writing.

Runs ON THE VPS (it edits db.json in place).
"""
import json
import os
import sys

ROOT = "/mnt/volume1/music-db"
SOURCE = "Internet Jukebox (Public Resource)"


def main():
    manifest = sys.argv[1] if len(sys.argv) > 1 else "jukebox-manifest.json"
    db = json.load(open(f"{ROOT}/db.json"))
    rows = {r["id"]: r for r in json.load(open(f"{ROOT}/{manifest}"))}

    attached = missing = 0
    for x in db:
        if x.get("source") != SOURCE:
            continue
        src = rows.get(x.get("id"))
        if not src:
            continue
        extra = src.get("files_extra") or {}
        mid = extra.get("midi")
        if not mid:
            continue
        if not os.path.exists(os.path.join(ROOT, mid)):
            print("!! midi missing on disk, not attaching:", mid)
            missing += 1
            continue
        x.setdefault("files", {})["midi"] = mid
        attached += 1

    dangling = sum(
        1 for x in db
        for p in list((x.get("files") or {}).values()) + ([x["path"]] if x.get("path") else [])
        if not os.path.exists(os.path.join(ROOT, p)))
    assert dangling == 0, f"{dangling} dangling paths — aborting write"

    json.dump(db, open(f"{ROOT}/db.json", "w"), indent=1)
    print(f"attached files.midi to {attached} rows ({missing} skipped); "
          f"db.json now {len(db)}; dangling=0")


if __name__ == "__main__":
    main()
