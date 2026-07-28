#!/usr/bin/env python3
"""Emit the (page scan -> MusicXML) pairing as a named OMR evaluation corpus.

WHY THIS IS WORTH MORE THAN THE SCORES. Every derived Jukebox item pairs the
original page scan with the symbolic transcription of that exact page, under
CC Public Domain Mark 1.0. That is a licence-clean image->symbolic corpus we can
NAME in tracked docs — unlike every OMR control archive we currently hold, which
is licence-unclear and may not be named or shipped.

⚠️ IT IS SILVER, NOT GOLD. The MusicXML is Soundslice OMR output with human
post-processing of unknown depth. Treat it as a strong reference, not ground
truth: it is fair for regression tracking and relative comparison, and NOT fair
for publishing an absolute accuracy number for any engine — least of all for
Soundslice itself, which produced it (measuring an engine against its own output
scores its self-consistency, not its accuracy).

Scans are NOT downloaded here — only the pairing is recorded, since the scans
are large and the DB never ships them. Fetch on demand from `scan_url`.
"""
import json
import sys
from pathlib import Path

HARVEST = Path(sys.argv[1] if len(sys.argv) > 1 else "jukebox")


def main():
    index = json.loads((HARVEST / "jukebox-index.json").read_text())
    report = json.loads((HARVEST / "jukebox-parse-report.json").read_text()) \
        if (HARVEST / "jukebox-parse-report.json").exists() else {"rows": []}
    parsed = {r["file"]: r for r in report.get("rows", [])}

    pairs, no_scan = [], 0
    for it in index:
        xmls = it["files"].get("musicxml") or []
        if not xmls:
            continue
        if not it.get("scan_urls"):
            no_scan += 1
            continue
        x = xmls[0]
        stat = parsed.get(x["path"], {})
        pairs.append({
            "identifier": it["identifier"],
            "title": it.get("title"),
            "creator": it.get("creator"),
            "date": it.get("date"),
            "licence": it.get("licenseurl"),
            "scan_url": it["scan_urls"][0],
            "all_scan_urls": it["scan_urls"],
            "musicxml": x["path"],
            "musicxml_url": x["url"],
            "midi": (it["files"].get("midi") or [{}])[0].get("path"),
            "parse_status": stat.get("status"),
            "parts": stat.get("parts"),
            "measures": stat.get("measures"),
            "notes": stat.get("notes"),
        })

    out = {
        "name": "Internet Jukebox OMR eval pairs",
        "source": "Internet Archive / Public Resource — collection:PublicJukebox",
        "licence": "CC Public Domain Mark 1.0 (per item)",
        "quality": ("SILVER — Soundslice OMR output with human post-processing of "
                    "unknown depth. Valid for regression tracking and relative "
                    "comparison; NOT valid as ground truth for an absolute "
                    "accuracy claim, and never for scoring Soundslice itself."),
        "pairs": len(pairs),
        "items": pairs,
    }
    (HARVEST / "jukebox-omr-eval.json").write_text(
        json.dumps(out, indent=1, ensure_ascii=False))
    print(f"jukebox-omr-eval.json: {len(pairs)} (scan -> musicxml) pairs "
          f"({no_scan} items had no scan alongside)")
    okc = sum(1 for p in pairs if p["parse_status"] == "ok")
    print(f"  of which parse ok: {okc}")


if __name__ == "__main__":
    main()
