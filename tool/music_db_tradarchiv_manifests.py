#!/usr/bin/env python3
"""Manifests for the other two TradArchiv manuscript collections.

  Dreysser 1720  -> Bayerische Staatsbibliothek Mus.ms. 1578, dated 1720
  Arendsee       -> a lost Mecklenburg manuscript, tunes est. 1760-1820

Same Tier B basis as Dahlhoff: the TradArchiv notice asserts no copyright over
the archive's holdings but forbids passing them on without naming the source.

Two differences from the Dahlhoff builder, both learned the hard way there:
  * `X:` here is a plain per-file counter (Dreysser's first file is `X:1`), so
    it is useless as a key. Ids come from the filename stem, which is unique by
    construction.
  * Titles carry LaTeX-style diacritic escapes (`Drey\\sser`, `\\"Ahnlich`) that
    would otherwise reach the catalog raw.
"""
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

COLLECTIONS = {
    "dreysser": {
        "dir": "dreysser",
        "source": "Handschrift Dreysser 1720 (TradArchiv)",
        "base_url": "http://simonwascher.info/TradArchiv/Dreysser_1720/",
        "id_prefix": "dreysser",
        "attribution": (
            'Handschrift "Dantz Buechlein", Johann Friedrich Dreysser 1720, '
            "Bayerische Staatsbibliothek Mus.ms. 1578; abc transcription by "
            "Simon Wascher; from Simon Wascher's TradArchiv"
        ),
        "axis2": (
            "axis2=manuscript dated 1720 (Bayerische Staatsbibliothek "
            "Mus.ms. 1578); tunes anonymous ('Urheber unbekannt, 1720 belegt')"
        ),
        "origin": "Germany",
    },
    "arendsee": {
        "dir": "arendsee",
        "source": "Handschrift aus Arendsee (TradArchiv)",
        "base_url": "http://simonwascher.info/TradArchiv/Arendsee/",
        "id_prefix": "arendsee",
        "attribution": (
            '"Handschrift aus Arendsee" (Mecklenburg), as copied by Richard '
            "Wossidlo in 1900 and published in facsimile by Heike Muens, "
            "Rostock 1987; abc transcription by Simon Wascher; from Simon "
            "Wascher's TradArchiv"
        ),
        "axis2": (
            "axis2=anonymous Mecklenburg dance tunes, first attested "
            "1760-1820 by the transcriber's estimate. Chain of custody: the "
            "original manuscript is LOST; Richard Wossidlo (d.1939, PD since "
            "2010) copied 69 of its 109 tunes in 1900, and that copy was "
            "reproduced in facsimile in Heike Muens, 'Taenze, Stuecke und "
            "Lieder aus Musizierhandschriften in Mecklenburg' (1987). A "
            "facsimile of a public-domain manuscript creates no new right in "
            "the music, and any UrhG-71 editio-princeps term running from "
            "1987 expired in 2012; Wascher transcribed the music, not Muens' "
            "editorial apparatus"
        ),
        "origin": "Germany; Mecklenburg; Arendsee",
    },
}

LICENCE = "Public Domain transcription - attribution required"

# ABC files in this archive spell diacritics the LaTeX way.
TEX = [
    (r'\\"a', "ä"), (r'\\"o', "ö"), (r'\\"u', "ü"),
    (r'\\"A', "Ä"), (r'\\"O', "Ö"), (r'\\"U', "Ü"),
    (r"\\ss", "ß"), (r"\\'e", "é"), (r"\\`e", "è"), (r"\\'a", "á"),
    (r"\\^o", "ô"), (r"\\^a", "â"), (r"\\c c", "ç"),
]


def detex(s):
    for pat, rep in TEX:
        s = re.sub(pat, rep, s)
    return s.replace("\\", "").strip()


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def read_text(path):
    data = open(path, "rb").read()
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("latin-1")


def abc_fields(text):
    out = {}
    for line in text.splitlines():
        m = re.match(r"^([A-Za-z]):\s?(.*)$", line)
        if not m:
            continue
        out.setdefault(m.group(1), []).append(m.group(2).strip())
        if m.group(1) == "K":
            break
    return out


def safe_name(name):
    stem, ext = name[:-4], name[-4:]
    for a, b in (("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss"), ("à", "a")):
        stem = stem.replace(a, b)
    return re.sub(r"[^A-Za-z0-9._-]+", "_", stem).strip("_") + ext


def stage(key, cfg):
    src = os.path.join(HERE, cfg["dir"])
    dst = os.path.join(HERE, cfg["dir"] + "_stage")
    os.makedirs(dst, exist_ok=True)
    mapping, seen = {}, {}
    for name in sorted(os.listdir(src)):
        if not name.endswith(".abc"):
            continue
        s = safe_name(name)
        if s in seen:
            seen[s] += 1
            s = f"{s[:-4]}-{seen[s]}.abc"
        else:
            seen[s] = 1
        with open(os.path.join(src, name), "rb") as a, \
             open(os.path.join(dst, s), "wb") as b:
            b.write(a.read())
        mapping[s] = name
    print(f"{key}: staged {len(mapping)} "
          f"({sum(1 for s, o in mapping.items() if s != o)} renamed)")
    return dst, mapping


def rows_for(key, cfg, empty):
    d, mapping = stage(key, cfg)
    rows, used = [], set()
    for name in sorted(os.listdir(d)):
        if not name.endswith(".abc") or name in empty:
            continue
        full = os.path.join(d, name)
        f = abc_fields(read_text(full))

        titles = [detex(t) for t in f.get("T", [])]
        title = next((t.split(":", 1)[1].strip().rstrip(";").strip()
                      for t in titles
                      if t.lower().startswith("bezeichnung standardisiert")),
                     None)
        if not title:
            title = next((t for t in titles if not t.startswith("[ID")), None)
        if not title:
            title = detex(name[:-4].replace("_", " "))

        author, year = None, None
        for c in f.get("C", []):
            m = re.match(r"^Urheber:\s*(.+)$", detex(c))
            if m and "unbekannt" not in m.group(1).lower():
                author = m.group(1).strip()
            y = re.search(r"\b(1[5-9]\d{2})\b", c)
            if y and year is None:
                year = y.group(1)

        credit = "; ".join(detex(z) for z in f.get("Z", [])
                           if not re.match(r"^(Erfassungsdatum|[\d.-]+$)", z))
        editors = [n for n, pat in (
            ("Simon Wascher", r"Wascher"),
            ("Jan Kristof Schliep", r"Schliep"),
            ("Thomas Behr", r"Behr"),
            ("Richmud Rollenbeck", r"Rollenbeck"),
            ("Joergen Lang", r"Lang,? Joergen|Joergen Lang"),
        ) if re.search(pat, credit)]

        stmt = "; ".join(detex(s) for s in f.get("S", []) + f.get("B", []))
        scan = next((s.split("Scan online:", 1)[1].strip()
                     for s in f.get("S", []) if "Scan online:" in s), None)

        # X: is a bare counter in these collections -> key on the filename.
        row_id = f"{cfg['id_prefix']}-" + re.sub(r"\.abc$", "", name)[:80]
        assert row_id not in used, row_id
        used.add(row_id)

        rows.append({
            "id": row_id,
            "title": title,
            "author": author,
            "poet": None,
            "year": year,
            "instrument": "dance melody",
            "instruments": ["traditional"],
            "editor": ", ".join(editors) or None,
            "ensemble": False,
            "licence": LICENCE,
            "source": cfg["source"],
            "source_url": scan or (cfg["base_url"] + mapping[name]),
            "attribution": cfg["attribution"],
            "format": "abc",
            "rights_status": "PD_BY_SOURCE",
            "rights_method": (
                "axis1=no copyright asserted by the transcribers; the "
                "TradArchiv notice states the archive holdings are "
                "'Denkmaeler der Volksmusik und unterliegen daher nicht dem "
                "Urheberschutz' and conditions redistribution only on naming "
                "the source (Angabe der Quelle) -> Tier B, attribution "
                f"carried. {cfg['axis2']}. provenance=transcriber-published; "
                f"in-file source statement: {stmt}"
                + (f"; in-file transcription credit: {credit}" if credit else "")
                + (f"; original filename: {mapping[name]}"
                   if mapping[name] != name else "")
            ),
            "path": f"{cfg['dir']}/{name}",
            "kind": "score",
            "sha256": sha256(full),
            "bytes": os.path.getsize(full),
        })
    return rows


def main():
    for key, cfg in COLLECTIONS.items():
        if not os.path.isdir(os.path.join(HERE, cfg["dir"])):
            print(f"{key}: not downloaded yet, skipping")
            continue
        empty = set()
        rep = os.path.join(HERE, f"{key}-parse-report.json")
        if os.path.exists(rep):
            empty = {r["file"] for r in json.load(open(rep))
                     if r.get("status") != "ok"}
            if empty:
                print(f"{key}: skipping {len(empty)} note-less transcriptions")
        rows = rows_for(key, cfg, empty)
        out = os.path.join(HERE, f"{key}-manifest.json")
        json.dump(rows, open(out, "w"), indent=1, ensure_ascii=False)
        print(f"{key}-manifest.json: {len(rows)} rows "
              f"(year {sum(1 for r in rows if r['year'])}, "
              f"editor {sum(1 for r in rows if r['editor'])})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
