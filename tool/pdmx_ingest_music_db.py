"""Ingest the PDMX CC0-original clean subset into the DB manifest schema.

PDMX (openmusic/pdmx, github.com/pnlong/PDMX) is ~254k MuseScore community
uploads. We take ONLY the license-clean slice: license == cc-zero AND no
license_conflict AND is_original (the uploader's own composition). That is clean
on BOTH axes — the CC0 waiver covers the engraving, is_original the underlying
work. BUT is_original is SELF-ATTESTED, so this is "defensible, not cleared": the
set demonstrably contains mislabels (e.g. "Crimson Peak – Edith's Theme", an
in-copyright film cue marked original). Hence a distinct source + a rights_method
that says so, so these stay filterable and never masquerade as hand-verified.

Ships the note-exact MIDIs we built from the muspy JSON (validated vs muspy at
99.9997%; more faithful than PDMX's own muspy-written .mid). Metadata (title,
uploader) from PDMX.csv; instruments derived from the GM programs in each score.
"""
import csv
import json
import os
import shutil
import sys
from collections import Counter
from pathlib import Path

csv.field_size_limit(sys.maxsize)

SOURCE = "PDMX"
SOURCE_URL = "https://github.com/pnlong/PDMX"


def gm_family(prog, is_drum):
    if is_drum:
        return "drums"
    if prog in (40, 110):
        return "violin"
    if prog == 41:
        return "viola"
    if prog == 42:
        return "cello"
    if prog in (52, 53, 54, 85):
        return "voice"
    table = [
        (0, "piano"), (8, "chromatic-percussion"), (16, "organ"),
        (24, "guitar"), (32, "bass"), (40, "strings"), (48, "ensemble"),
        (56, "brass"), (64, "reed"), (72, "pipe"), (80, "synth-lead"),
        (88, "synth-pad"), (96, "synth-fx"), (104, "ethnic"),
        (112, "percussive"), (120, "sound-fx"),
    ]
    name = "piano"
    for start, n in table:
        if prog >= start:
            name = n
    return name


def instruments_of(json_path):
    try:
        d = json.load(open(json_path))
    except Exception:
        return []
    fams = []
    for tr in d.get("tracks", []):
        if not tr.get("notes"):
            continue
        fams.append(gm_family(int(tr.get("program") or 0), bool(tr.get("is_drum"))))
    # preserve a stable, de-duplicated order
    seen = []
    for f in fams:
        if f not in seen:
            seen.append(f)
    return seen, len([t for t in d.get("tracks", []) if t.get("notes")])


def clean(v):
    v = (v or "").strip()
    return None if v in ("", "NA") else v


def main():
    csv_path = Path(sys.argv[1])       # zenodo/PDMX.csv
    json_dir = Path(sys.argv[2])       # pdmx-cc0-midi/json
    mid_src = Path(sys.argv[3])        # pdmx-cc0-midi/mid  (our built MIDIs)
    ship_dir = Path(sys.argv[4])       # music-db/pdmx/ship/midi
    out_path = Path(sys.argv[5])       # music-db/pdmx-manifest.json

    # The clean subset = the hashes we actually built MIDIs for, MINUS the
    # quarantine list (entries whose named composer resolved to an in-copyright
    # person — see tool/pdmx_originality_check; written to pdmx_exclude.json).
    have = {p.stem for p in mid_src.glob("*.mid")}
    excl_path = out_path.parent / "pdmx_exclude.json"
    exclude = set(json.loads(excl_path.read_text())) if excl_path.exists() else set()
    have -= exclude
    ship_dir.mkdir(parents=True, exist_ok=True)

    items, copied, skipped = [], 0, 0
    with open(csv_path) as f:
        for x in csv.DictReader(f):
            h = (x.get("path") or "").split("/")[-1].replace(".json", "")
            if h not in have:
                continue
            # defence in depth: re-assert the license filter from the row itself
            if not (x.get("license") == "cc-zero"
                    and str(x.get("license_conflict")).strip() == "False"
                    and str(x.get("is_original")).strip() == "True"):
                skipped += 1
                continue
            inst, n_parts = instruments_of(json_dir / f"{h}.json")
            title = clean(x.get("title")) or clean(x.get("song_name")) or h[:12]
            composer = clean(x.get("composer_name"))
            uploader = clean(x.get("artist_name"))
            src = mid_src / f"{h}.mid"
            dst = ship_dir / f"{h}.mid"
            if not dst.exists():
                shutil.copyfile(src, dst)
            copied += 1
            items.append({
                "id": f"pdmx_{h}",
                "title": title[:180],
                "author": composer or uploader,
                "author_full": composer or uploader,
                "poet": None,
                "year": None,
                "transcribed": None,
                "instrument": ", ".join(inst),
                "instruments": inst,
                "editor": "tab" if inst == ["guitar"] else "score",
                "ensemble": n_parts > 1,
                "licence": "CC0-1.0",
                "source": SOURCE,
                "source_url": SOURCE_URL,
                # Credit the uploader even though CC0 needs none.
                "attribution": uploader,
                "format": "midi",
                "tier": "ship",
                "rights_status": "CC0",
                "rights_method": "PDMX cc-zero + is_original (self-attested, "
                                 "UNVERIFIED — wants a dedup/originality pass)",
                "verified_from": "PDMX.csv",
                "path": f"pdmx/ship/midi/{h}.mid",
            })

    out_path.write_text(json.dumps(items, indent=1))
    print(f"PDMX clean entries: {len(items)}  (copied {copied}, skipped {skipped})")
    print("with title:", sum(1 for i in items if i["title"]))
    print("with composer_name:", sum(1 for i in items if clean_author(i)))
    print("ensemble:", sum(1 for i in items if i["ensemble"]))
    print("instruments:", dict(Counter(x for i in items for x in i["instruments"]).most_common(12)))
    print("editor:", dict(Counter(i["editor"] for i in items)))


def clean_author(i):
    return i["author"]


if __name__ == "__main__":
    main()
