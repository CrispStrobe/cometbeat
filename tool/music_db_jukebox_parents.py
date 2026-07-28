#!/usr/bin/env python3
"""Attach each item's PARENT BOOK creators to the harvest index.

WHY THIS IS NOT OPTIONAL. Public Resource split multi-song books into one IA
item per song, and the child item credits only that song's arranger. The BOOK's
compiler/editor is recorded on the parent item and is invisible to the child.

That silently under-reports rights. `140folksongsrote00unse` — 55 of our items —
is "140 Folk-Songs For Grades I, II, And III" (E. C. Schirmer, 1922), compiled
and edited by Archibald T. Davison (d. 1961) and Thomas Whitney Surette
(d. 1941). Davison is EU-protected until the end of 2031. Judging those songs on
the per-song arranger alone cleared some of them; judging them with the book's
editors does not.

Legal nuance, stated so the conservatism is a choice and not an accident: a
collection copyright (§4 UrhG, Sammelwerk) protects the selection and
arrangement OF THE COLLECTION, and lifting a single song does not necessarily
touch it. But "compiled and edited" plausibly also means editorial work on each
individual setting (§3 Bearbeitung, life+70 of the editor), and we cannot tell
which from metadata. Fails closed: the parent's creators gate the child.

Parent identifiers are derived by stripping the per-song suffix
(`<parent>.<page>.omr`, `<parent>_omr`) and confirmed to exist before use.
"""
import json
import re
import sys
import time
from pathlib import Path

import requests

HARVEST = Path(sys.argv[1] if len(sys.argv) > 1 else "jukebox")
UA = ("CometBeat-corpus-harvest/1.0 (music education app; PD corpus ingest; "
      "contact stc.akrs@gmail.com)")
S = requests.Session()
S.headers["User-Agent"] = UA
CACHE = HARVEST / "_parents"


def parent_candidates(ident):
    """Plausible parent identifiers, most specific first."""
    out = []
    m = re.match(r"^(.*?)\.[0-9]+[a-z]?(?:-[0-9]+)?\.omr$", ident)
    if m:
        out.append(m.group(1))
    if ident.endswith("_omr"):
        out.append(ident[:-4])
    if ident.endswith(".omr"):
        out.append(ident[:-4])
    m = re.match(r"^(.*?)\.[0-9]+[a-z]?(?:-[0-9]+)?$", ident)
    if m:
        out.append(m.group(1))
    seen, uniq = set(), []
    for c in out:
        if c and c != ident and c not in seen:
            seen.add(c)
            uniq.append(c)
    return uniq


def fetch(ident):
    fp = CACHE / f"{ident}.json"
    if fp.exists():
        return json.loads(fp.read_text())
    for attempt in range(5):
        r = S.get(f"https://archive.org/metadata/{ident}", timeout=60)
        if r.status_code in (429, 500, 502, 503, 504):
            time.sleep(15 * (attempt + 1))
            continue
        r.raise_for_status()
        data = r.json()
        fp.write_text(json.dumps(data, indent=1))
        time.sleep(0.6)
        return data
    return {}


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    index = json.loads((HARVEST / "jukebox-index.json").read_text())

    resolved = {}
    for n, it in enumerate(index, 1):
        ident = it["identifier"]
        found = None
        for cand in parent_candidates(ident):
            if cand in resolved:
                found = resolved[cand]
                break
            meta = fetch(cand).get("metadata")
            if meta:
                found = {
                    "identifier": cand,
                    "title": meta.get("title"),
                    "creator": meta.get("creator"),
                    "date": meta.get("date"),
                    "publisher": meta.get("publisher"),
                }
                resolved[cand] = found
                break
            resolved[cand] = None
        it["parent"] = found
        if found:
            print(f"[{n}/{len(index)}] {ident} -> parent {found['identifier']} "
                  f"| {str(found.get('creator'))[:60]}", flush=True)

    (HARVEST / "jukebox-index.json").write_text(
        json.dumps(index, indent=1, ensure_ascii=False))
    withp = sum(1 for i in index if i.get("parent"))
    print(f"\n{withp}/{len(index)} items have a parent book "
          f"({len([r for r in resolved.values() if r])} distinct parents)")
    for p in {json.dumps(r, sort_keys=True) for r in resolved.values() if r}:
        d = json.loads(p)
        cnt = sum(1 for i in index
                  if (i.get("parent") or {}).get("identifier") == d["identifier"])
        print(f"  {cnt:3} items  {d['identifier'][:40]:40} "
              f"{str(d.get('creator'))[:52]}")


if __name__ == "__main__":
    main()
