#!/usr/bin/env python3
"""Build music-db manifests for the two new 2026-07-29 sources.

  Tanzsammlung Dahlhoff (TradArchiv)  -> Tier B, ABC, 18th-c. manuscript
  Project Gutenberg Sheet Music       -> Tier A, MusicXML/LilyPond/MIDI

Both manifests feed `bin/append_manifest.py <manifest> <Source>` on the VPS,
which asserts `dangling == 0`, so `path` must be relative to the music-db root.
"""
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

DAHLHOFF_SRC = "Tanzsammlung Dahlhoff (TradArchiv)"
DAHLHOFF_URL = "http://simonwascher.info/TradArchiv/Dahlhoff/"
# Tier B: the transcribers assert no copyright but REQUIRE the source be named
# ("Die Weitergabe des Notenmaterials ... ohne Angabe der Quelle ist verboten").
# The word "attribution" is what puts emit_catalog's _tier() in bucket B.
DAHLHOFF_LICENCE = "Public Domain transcription - attribution required"

PG_SRC = "Project Gutenberg Sheet Music"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def read_text(path):
    """ABC carries no encoding declaration; this corpus is mixed UTF-8/Latin-1."""
    data = open(path, "rb").read()
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("latin-1")


def abc_fields(text):
    """Collect ABC header lines by letter, in order."""
    out = {}
    for line in text.splitlines():
        m = re.match(r"^([A-Za-z]):\s?(.*)$", line)
        if not m:
            continue
        out.setdefault(m.group(1), []).append(m.group(2).strip())
        if m.group(1) == "K":  # body starts after the key line
            break
    return out


def safe_name(name):
    """Filenames go into `path`, and from there into HF URLs.

    25 of these carry `? | [ ] ; ' ( ) , = +` or a bare `à` — `?` alone would
    truncate a served URL at the query separator. Content is untouched and the
    authoritative provenance is the per-file Staatsbibliothek scan resolver in
    `source_url`, so renaming the container costs nothing.
    """
    stem, ext = name[:-4], name[-4:]
    stem = stem.replace("à", "a")
    stem = re.sub(r"[^A-Za-z0-9._-]+", "_", stem).strip("_")
    return stem + ext


def stage_dahlhoff():
    """Copy the download into a staging dir under URL-safe names."""
    src = os.path.join(HERE, "dahlhoff")
    dst = os.path.join(HERE, "dahlhoff_stage")
    os.makedirs(dst, exist_ok=True)
    mapping, seen = {}, {}
    for name in sorted(os.listdir(src)):
        if not name.endswith(".abc"):
            continue
        safe = safe_name(name)
        if safe in seen:  # collision after sanitising — keep both, distinctly
            n = seen[safe] = seen[safe] + 1
            safe = f"{safe[:-4]}-{n}.abc"
        else:
            seen[safe] = 1
        with open(os.path.join(src, name), "rb") as a, \
             open(os.path.join(dst, safe), "wb") as b:
            b.write(a.read())
        mapping[safe] = name
    renamed = sum(1 for s, o in mapping.items() if s != o)
    print(f"staged {len(mapping)} files ({renamed} renamed for URL safety)")
    return dst, mapping


def dahlhoff_rows():
    d, mapping = stage_dahlhoff()

    # Only ship files we have VERIFIED carry music. Ten entries are faithful
    # transcriptions of BLANK manuscript pages - some say so in a %%text note
    # ("keine Notation, nur leere Notenzeilen"), others encode it as ABC
    # invisible rests (`X8X8` + `%%staffnonote`) or an "[ohne Noten]" title.
    # They are correct transcriptions and correct parses; they are just not
    # songs, so a catalog row for them would be dead weight.
    empty = set()
    report = os.path.join(HERE, "dahlhoff-parse-report.json")
    if os.path.exists(report):
        empty = {r["file"] for r in json.load(open(report))
                 if r.get("status") != "ok"}
        print(f"skipping {len(empty)} note-less (blank-page) transcriptions")

    rows = []
    used_ids = {}
    for name in sorted(os.listdir(d)):
        if not name.endswith(".abc") or name in empty:
            continue
        full = os.path.join(d, name)
        text = read_text(full)
        f = abc_fields(text)

        titles = f.get("T", [])
        title = None
        for t in titles:
            if t.lower().startswith("bezeichnung standardisiert"):
                title = t.split(":", 1)[1].strip().rstrip(";").strip()
                break
        if not title:
            title = next((t for t in titles if not t.startswith("[ID")), None)
        if not title:
            title = name[:-4].replace("_", " ")

        # C: is used for BOTH "Urheber: X" and dating lines.
        author = None
        year = None
        for c in f.get("C", []):
            m = re.match(r"^Urheber:\s*(.+)$", c)
            if m and "unbekannt" not in m.group(1).lower():
                author = m.group(1).strip()
            if "Datum" in c or "Erstbeleg" in c:
                y = re.search(r"\b(1[5-8]\d{2})\b", c)
                if y and year is None:
                    year = y.group(1)

        # Z: carries the transcription credit in ~8 different wordings, and the
        # majority route is a THREE-person chain (Capella -> MusicXML -> abc).
        # Rather than parse the prose, scan for the five people who actually
        # worked on this corpus — the full set, confirmed by grouping every Z:
        # line in the 703 files.
        credit_lines = [z for z in f.get("Z", [])
                        if not re.match(r"^(Erfassungsdatum|[\d-]+$)", z)]
        credit = "; ".join(credit_lines)
        editors = [n for n, pat in (
            ("Simon Wascher", r"Wascher"),
            ("Jan Kristof Schliep", r"Schliep"),
            ("Thomas Behr", r"Behr"),
            ("Richmud Rollenbeck", r"Rollenbeck"),
            ("Joergen Lang", r"Lang,? Joergen|Joergen Lang"),
        ) if re.search(pat, credit)]
        editor = ", ".join(editors) or None

        # The S: lines are the required source statement; keep them verbatim.
        source_stmt = "; ".join(f.get("S", []))
        scan = next((s.split("Scan online:", 1)[1].strip()
                     for s in f.get("S", []) if "Scan online:" in s), None)

        ident = f.get("X", ["?"])[0]
        row_id = f"dahlhoff-{ident}"
        if row_id in used_ids:
            tag = re.sub(r"^id_|\.abc$", "", mapping[name]).split("_")[0]
            row_id = f"dahlhoff-{ident}-{tag}"
            n = used_ids.get(row_id, 0)
            if n:
                row_id = f"{row_id}-{n + 1}"
            used_ids[row_id] = n + 1
        used_ids.setdefault(row_id, 1)
        rows.append({
            "id": row_id,
            "title": title,
            "author": author,
            "poet": None,
            "year": year,
            "instrument": "dance melody",
            "instruments": ["traditional"],
            "editor": editor,
            "ensemble": False,
            "licence": DAHLHOFF_LICENCE,
            "source": DAHLHOFF_SRC,
            "source_url": scan or (DAHLHOFF_URL + mapping[name]),
            "attribution": (
                '"Tanzsammlung Dahlhoff", Staatsbibliothek zu Berlin, '
                "Musiksammlung, Mus. ms. 40182"
                + (f"; abc transcription by {editor}" if editor else "")
                + "; from Simon Wascher's TradArchiv"
            ),
            "format": "abc",
            "rights_status": "PD_BY_SOURCE",
            "rights_method": (
                "axis1=no copyright asserted by the transcribers; the TradArchiv "
                "notice states the archive holdings are 'Denkmaeler der Volksmusik "
                "und unterliegen daher nicht dem Urheberschutz' and conditions "
                "redistribution only on naming the source (Angabe der Quelle) -> "
                "Tier B, attribution carried. "
                "axis2=18th-century manuscript, Staatsbibliothek zu Berlin Mus. ms. "
                "40182, dated 'vermutlich vor 1767'; named composers where present "
                "are long PD (Telemann d.1767, Hasse d.1783, Jommelli d.1774, "
                "Campra d.1744). "
                f"provenance=transcriber-published; in-file source statement: {source_stmt}"
                + (f"; in-file transcription credit: {credit}" if credit else "")
                + (f"; original filename: {mapping[name]}"
                   if mapping[name] != name else "")
            ),
            "path": f"dahlhoff/{name}",  # staged (URL-safe) name
            "kind": "score",
            "sha256": sha256(full),
            "bytes": os.path.getsize(full),
        })
    return rows


# Only the full-score files become rows; the per-part extractions are redundant
# copies of the same music and would inflate the corpus with duplicates.
PG_WORKS = {
    "11001": ("String Quartet No. 5 in A major, Op. 18 No. 5",
              "Ludwig van Beethoven", "1801", "11001-Complete.xml", "xml"),
    "11755": ("String Quartet No. 10 in E-flat major, Op. 74 ('Harp')",
              "Ludwig van Beethoven", "1809", "11755-Complete.xml", "xml"),
    "12149": ("String Quartet No. 3 in D major, Op. 18 No. 3",
              "Ludwig van Beethoven", "1798", "12149-Complete.xml", "xml"),
    "12695": ("String Quartet No. 4 in C minor, Op. 18 No. 4",
              "Ludwig van Beethoven", "1801", "12695-complete.xml", "xml"),
    "13153": ("String Quartet No. 15 in A minor, Op. 132",
              "Ludwig van Beethoven", "1825", "13153-all.xml", "xml"),
    "13473": ("String Quartet No. 6 in B-flat major, Op. 18 No. 6",
              "Ludwig van Beethoven", "1800", "13473-all.xml", "xml"),
    "30156": ("Second Overture in Solomon, HWV 67",
              "George Frideric Handel", "1748", "30156-ly.ly", "ly"),
}
# 13078 (Op. 127) was published as SEPARATE PARTS only - there is no combined
# score file - so it contributes four part rows rather than one score row.
PG_PARTS_ONLY = {
    "13078": ("String Quartet No. 12 in E-flat major, Op. 127",
              "Ludwig van Beethoven", "1825",
              ["13078-ViolinI-xml.xml", "13078-ViolinII-xml.xml",
               "13078-Viola-xml.xml", "13078-Violoncello-xml.xml"], "xml"),
}


def pg_row(ident, title, author, year, fname, fmt, part=None):
    full = os.path.join(HERE, "gutenberg", fname)
    return {
        "id": f"gutenberg-{ident}" + (f"-{part.lower()}" if part else ""),
        "title": title + (f" ({part})" if part else ""),
        "author": author,
        "poet": None,
        "year": year,
        "instrument": "string quartet" if "Quartet" in title else "orchestra",
        "instruments": ["violin", "viola", "cello"] if "Quartet" in title
                       else ["orchestra"],
        "editor": None,
        "ensemble": True,
        "licence": "Public Domain",
        "source": PG_SRC,
        "source_url": f"https://www.gutenberg.org/ebooks/{ident}",
        "attribution": None,
        "format": fmt,
        "rights_status": "PD",
        "rights_method": (
            "axis1=Project Gutenberg US public domain, 'no warnings or "
            "restrictions of any kind'; the PG Licence's only hook is the "
            "Project Gutenberg trademark, which does not attach to the "
            "music data. "
            f"axis2=composer {author} long PD "
            f"({'d.1827' if 'Beethoven' in author else 'd.1759'}); "
            "engraving volunteer-made for PG. provenance=PG Sheet Music Project"
        ),
        "path": f"gutenberg/{fname}",
        "kind": "score",
        "sha256": sha256(full),
        "bytes": os.path.getsize(full),
    }


def gutenberg_rows():
    rows = []
    for ident, (title, author, year, fname, fmt) in sorted(PG_WORKS.items()):
        rows.append(pg_row(ident, title, author, year, fname, fmt))
    for ident, (title, author, year, fnames, fmt) in sorted(PG_PARTS_ONLY.items()):
        for fname in fnames:
            part = re.sub(r"^\d+-|-xml$", "", fname[:-4])
            rows.append(pg_row(ident, title, author, year, fname, fmt, part=part))
    return rows


def main():
    dh = dahlhoff_rows()
    pg = gutenberg_rows()
    json.dump(dh, open(os.path.join(HERE, "dahlhoff-manifest.json"), "w"),
              indent=1, ensure_ascii=False)
    json.dump(pg, open(os.path.join(HERE, "gutenberg-manifest.json"), "w"),
              indent=1, ensure_ascii=False)
    print(f"dahlhoff-manifest.json: {len(dh)} rows")
    print(f"  with author:   {sum(1 for r in dh if r['author'])}")
    print(f"  with year:     {sum(1 for r in dh if r['year'])}")
    print(f"  with editor:   {sum(1 for r in dh if r['editor'])}")
    print(f"gutenberg-manifest.json: {len(pg)} rows")
    return 0


if __name__ == "__main__":
    sys.exit(main())
