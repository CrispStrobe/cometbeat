#!/usr/bin/env python3
"""Download the axis-1 + axis-2 cleared Commons MIDI and write its manifest.

Runs on the VPS, where db.json lives, so the duplicate check is against the
real corpus rather than a copy. Commons already reached us once through a
single-contributor harvest, so a general sweep re-finds a few hundred files we
have — appending them would produce two rows for one work with different ids,
which is worse than a miss because nothing downstream can tell them apart.

Pacing is deliberate: Commons serves this for free.
"""
import json
import os
import re
import sys
import time
import urllib.parse

import requests

ROOT = "/mnt/volume1/music-db"
DEST = f"{ROOT}/commons-midi"
UA = ("CometBeat-corpus-harvest/1.0 (music education app; PD corpus ingest; "
      "contact stc.akrs@gmail.com)")


def slug(t):
    return re.sub(r"[^a-z0-9]+", "-", t.lower()).strip("-")


def main():
    rows = json.load(open(sys.argv[1]))["cleared"]
    db = json.load(open(f"{ROOT}/db.json"))
    have = set()
    for r in db:
        u = r.get("source_url") or ""
        if "commons.wikimedia.org" in u:
            have.add(urllib.parse.unquote(u).split(":", 2)[-1]
                     .replace("_", " ").lower())

    os.makedirs(DEST, exist_ok=True)
    s = requests.Session()
    s.headers["User-Agent"] = UA
    out, dup, fail = [], 0, 0
    for i, r in enumerate(rows, 1):
        name = r["title"][5:]                       # strip "File:"
        if name.replace("_", " ").lower() in have:
            dup += 1
            continue
        fn = re.sub(r"[^A-Za-z0-9._-]+", "_", name)
        path = f"{DEST}/{fn}"
        if not os.path.exists(path):
            try:
                resp = s.get(r["url"], timeout=90)
                resp.raise_for_status()
                open(path, "wb").write(resp.content)
            except Exception as e:                  # noqa: BLE001
                print("!! failed", name, e)
                fail += 1
                continue
            time.sleep(1.0)
        out.append({
            "id": "commons-midi-" + slug(name),
            "title": os.path.splitext(name)[0],
            "author": None, "composer": None, "poet": None, "year": None,
            "instrument": None, "instruments": [], "editor": None,
            "ensemble": False,
            "licence": "CC0-1.0" if r["tier"] == "A" else "CC-BY-4.0",
            "source": "Wikimedia Commons (MIDI)",
            "source_url": "https://commons.wikimedia.org/wiki/"
                          + urllib.parse.quote(r["title"].replace(" ", "_")),
            "attribution": None if r["tier"] == "A" else (r.get("artist") or None),
            "format": "midi",
            "rights_status": "PD/CC0" if r["tier"] == "A" else "CC-BY",
            "rights_method": f"{r['rights_method']} axis2={r['rule']}: "
                             f"{r['axis2_reason']}",
            "path": f"commons-midi/{fn}",
            "kind": "score",
            "bytes": os.path.getsize(path),
        })
        if i % 25 == 0:
            print(f"  [{i}/{len(rows)}] kept={len(out)} dup={dup} fail={fail}",
                  flush=True)
    json.dump(out, open(f"{ROOT}/commons-midi-manifest.json", "w"), indent=1,
              ensure_ascii=False)
    print(f"\nkept {len(out)} · already in db {dup} · failed {fail}")


if __name__ == "__main__":
    main()
