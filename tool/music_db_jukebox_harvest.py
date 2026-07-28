#!/usr/bin/env python3
"""Harvest the symbolic layer of the Internet Archive / Public Resource
"Internet Jukebox" (collection:PublicJukebox).

WHY only the symbolic layer: the DB takes symbolic music only (MIDI/MusicXML/
kern/ABC/tracker), never rendered audio. Each derived Jukebox item publishes
.musicxml + .mid NEXT TO mp3/flac/wav — we take the first two and skip the rest.

Licence read (recorded per row later): every item carries
licenseurl = https://creativecommons.org/publicdomain/mark/1.0/ (CC PDM 1.0),
creator "Public Resource", and a description dedicating the OMR derivation
("created using the Soundslice Optical Music Recognition facility with
subsequent post-processing by Martin R. Lucas of Public Resource").
PDM is an ASSERTION, not a warranty, and IA determines PD on the US pre-1930
rule — so axis-2 (the underlying composition under EU life+70) is NOT settled
here; that is the promotion pass's job.

Also captures the PAGE SCAN alongside, because a (page image -> MusicXML) pair
under PDM is a licence-clean OMR eval corpus, which is worth more to the OMR
effort than the scores are to the DB.

Gentle by construction: sequential, sleeps between requests, resumes by
file-existence, backs off on 429/503.
"""
import json
import os
import random
import sys
import time
import urllib.parse
from pathlib import Path

import requests

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "jukebox")
META = OUT / "_meta"
SEARCH = "https://archive.org/advancedsearch.php"
UA = ("CometBeat-corpus-harvest/1.0 (music education app; PD corpus ingest; "
      "contact stc.akrs@gmail.com)")
S = requests.Session()
S.headers["User-Agent"] = UA

# The symbolic payload we ingest, plus the scan we keep for OMR eval.
WANT_SUFFIX = (".musicxml", ".mid", ".midi")
SCAN_SUFFIX = (".pdf",)


def get(url, **kw):
    """One request with polite backoff.

    Archive.org's storage nodes return a transient 500 often enough that it has
    to be retried like a 503 — an earlier run died at item 31 of 211 on exactly
    that. Anything still failing after the retries raises, and the CALLER
    decides whether one bad file should kill a 200-item harvest (it should not).
    """
    for attempt in range(6):
        try:
            r = S.get(url, timeout=120, **kw)
        except requests.RequestException as e:
            print(f"   !! {type(e).__name__}, retry {attempt}", flush=True)
            time.sleep(20 * (attempt + 1))
            continue
        if r.status_code in (429, 500, 502, 503, 504):
            wait = int(r.headers.get("Retry-After") or 0) or 30 * (attempt + 1)
            print(f"   !! HTTP {r.status_code}, backing off {wait}s", flush=True)
            time.sleep(wait)
            continue
        r.raise_for_status()
        return r
    raise RuntimeError(f"gave up on {url}")


def enumerate_items():
    """Identifiers in the collection that actually carry a symbolic derivation.

    Queried by format rather than by the `.omr` identifier convention: the
    Sousa block (InternetJukebox.JPS.*) has MusicXML without following it.
    """
    ids = {}
    for fmt in ("MusicXML", "MIDI"):
        rows = 500
        params = {
            "q": f'collection:PublicJukebox AND format:"{fmt}"',
            "fl[]": ["identifier", "title", "creator", "date", "licenseurl",
                     "publisher", "subject"],
            "rows": rows, "page": 1, "output": "json",
        }
        r = get(SEARCH + "?" + urllib.parse.urlencode(params, doseq=True))
        resp = r.json()["response"]
        print(f"  {fmt}: numFound={resp['numFound']}")
        for d in resp["docs"]:
            ids.setdefault(d["identifier"], d).setdefault("_fmts", []).append(fmt)
        time.sleep(1)
    return ids


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    META.mkdir(parents=True, exist_ok=True)

    print("== enumerating collection:PublicJukebox ==")
    docs = enumerate_items()
    print(f"== {len(docs)} distinct items with a symbolic derivation ==")

    index = []
    for n, (ident, doc) in enumerate(sorted(docs.items()), 1):
        mpath = META / f"{ident}.json"
        if mpath.exists():
            meta = json.loads(mpath.read_text())
        else:
            meta = get(f"https://archive.org/metadata/{ident}").json()
            mpath.write_text(json.dumps(meta, indent=1))
            time.sleep(random.uniform(0.4, 1.2))

        md = meta.get("metadata", {})
        files = meta.get("files", [])
        picked = {"musicxml": [], "midi": [], "scan": []}
        for f in files:
            name = f.get("name", "")
            low = name.lower()
            if low.endswith(".musicxml"):
                picked["musicxml"].append(f)
            elif low.endswith((".mid", ".midi")):
                picked["midi"].append(f)
            elif low.endswith(SCAN_SUFFIX):
                picked["scan"].append(f)

        if not picked["musicxml"] and not picked["midi"]:
            print(f"[{n}/{len(docs)}] {ident}: no symbolic file, skipping")
            continue

        got, failed = {}, []
        # Scans are large; record their URL for the eval corpus but do not pull
        # them in this pass (the DB never ships them).
        for kind in ("musicxml", "midi"):
            for f in picked[kind]:
                name = f["name"]
                dest = OUT / ident / name
                dest.parent.mkdir(parents=True, exist_ok=True)
                url = (f"https://archive.org/download/{ident}/"
                       + urllib.parse.quote(name))
                if not dest.exists() or dest.stat().st_size == 0:
                    try:
                        r = get(url)
                    except Exception as e:
                        # One unavailable file must not abort the harvest. It is
                        # recorded and simply stays absent; a re-run retries it.
                        print(f"   !! FAILED {name}: {e}", flush=True)
                        failed.append({"name": name, "error": str(e)[:200]})
                        continue
                    dest.write_bytes(r.content)
                    time.sleep(random.uniform(0.4, 1.2))
                got.setdefault(kind, []).append({
                    "name": name,
                    "path": dest.relative_to(OUT).as_posix(),
                    "bytes": dest.stat().st_size,
                    "url": url,
                })
        if not got:
            print(f"[{n}/{len(docs)}] {ident}: all files failed, skipping")
            continue

        index.append({
            "identifier": ident,
            "title": md.get("title") or doc.get("title"),
            "creator": md.get("creator") or doc.get("creator"),
            "date": md.get("date") or doc.get("date"),
            "year": md.get("year"),
            "licenseurl": md.get("licenseurl") or doc.get("licenseurl"),
            "rights": md.get("rights"),
            "description": md.get("description"),
            "publisher": md.get("publisher"),
            "subject": md.get("subject"),
            "uploader": md.get("uploader"),
            "collection": md.get("collection"),
            "source_url": f"https://archive.org/details/{ident}",
            "files": got,
            "failed_files": failed,
            "scan_urls": [f"https://archive.org/download/{ident}/"
                          + urllib.parse.quote(f["name"])
                          for f in picked["scan"]],
        })
        nx, nm = len(got.get("musicxml", [])), len(got.get("midi", []))
        print(f"[{n}/{len(docs)}] {ident}: {nx} musicxml, {nm} midi"
              f"  — {str(md.get('creator'))[:40]}")

    (OUT / "jukebox-index.json").write_text(
        json.dumps(index, indent=1, ensure_ascii=False))
    lic = {}
    for it in index:
        lic[it["licenseurl"]] = lic.get(it["licenseurl"], 0) + 1
    print(f"\n== harvested {len(index)} items -> {OUT}/jukebox-index.json ==")
    print("licenceurl histogram:", json.dumps(lic, indent=1))
    print("musicxml files:", sum(len(i['files'].get('musicxml', [])) for i in index))
    print("midi files:    ", sum(len(i['files'].get('midi', [])) for i in index))


if __name__ == "__main__":
    main()
