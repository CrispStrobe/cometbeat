#!/usr/bin/env python3
"""Stage the de.wikipedia <score> melodies as Tier C rows.

Tier C = held locally, never emitted to the shipped catalog. The wiki text these
come from is CC BY-SA, so the ENGRAVING is share-alike; whether a faithful
transcription of a public-domain melody carries any new authorship at all is a
maintainer call that has not been made. Until it is, share-alike governs.

Because Tier C never ships, axis 2 is recorded as UNASSESSED rather than
guessed. That is deliberate: writing a confident "axis2=PD (traditional)" on a
row nobody checked would be the exact failure the Ebersberger pass was built to
avoid, and it would silently become load-bearing the day someone promotes these
to Tier B.
"""
import json
import re
import sys
from pathlib import Path


def slug(t):
    return re.sub(r"[^a-z0-9]+", "-", t.lower()).strip("-")


def main():
    rows = json.loads(Path(sys.argv[1]).read_text())
    staged = Path(sys.argv[2])
    out = []
    for r in rows:
        fn = re.sub(r"[^A-Za-z0-9]+", "_", r["title"]) + ".ly"
        if not (staged / fn).exists():
            print("!! no staged file for", r["title"])
            continue
        body = (staged / fn).read_text()
        out.append({
            "id": "commons-wp-ly-" + slug(r["title"]),
            "title": r["title"],
            "author": None, "composer": None, "poet": None, "year": None,
            "instrument": None, "instruments": ["voice"], "editor": None,
            "ensemble": False,
            "licence": "CC-BY-SA-4.0",
            "source": "Wikipedia (de) <score>",
            "source_url": r["source_url"],
            "attribution": "de.wikipedia.org contributors, CC BY-SA 4.0",
            "format": "lilypond",
            "rights_status": "CC-BY-SA (Tier C — local only, not shipped)",
            "rights_method": (
                "axis1=CC BY-SA 4.0, the licence of the wiki text the <score> "
                "block is embedded in. axis2=UNASSESSED — the underlying melody "
                "is very likely long-PD but no life+70 check was run, because a "
                "Tier C row never reaches the catalog. Assess axis 2 BEFORE any "
                "promotion to Tier A/B."),
            "path": f"commons-wp-ly/{fn}",
            "bytes": len(body.encode()),
        })
    Path(sys.argv[3]).write_text(json.dumps(out, indent=1, ensure_ascii=False))
    print(f"wrote {len(out)} Tier C rows -> {sys.argv[3]}")


if __name__ == "__main__":
    main()
