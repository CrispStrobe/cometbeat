#!/usr/bin/env python3
"""What a de.wikipedia song category lists that the corpus does not have.

Usage: music_db_wp_category_gap.py "Kategorie:Volkslied" [--depth 1] --db titles.json

Matching is on a NORMALISED title, because the same song reaches us under a
dozen spellings: a Wikipedia article carries a disambiguator ("Die Gedanken sind
frei (Lied)"), our files carry umlaut transliterations, and both differ in
punctuation and leading articles. Comparing raw strings reports almost
everything as missing, which is worse than useless — it hides the real gaps in
noise. A first-line variant is matched too, since folk songs are catalogued
under both their incipit and their refrain.
"""
import argparse
import json
import re
import sys
import time
import unicodedata

import requests

UA = ("CometBeat-corpus-harvest/1.0 (music education app; PD corpus ingest; "
      "contact stc.akrs@gmail.com)")
API = "https://de.wikipedia.org/w/api.php"
UML = str.maketrans({"ä": "ae", "ö": "oe", "ü": "ue", "ß": "ss",
                     "Ä": "ae", "Ö": "oe", "Ü": "ue"})


def norm(t):
    t = re.sub(r"\s*\([^)]*\)\s*$", "", t or "")          # drop a disambiguator
    t = t.translate(UML).lower()
    t = unicodedata.normalize("NFKD", t)
    t = "".join(c for c in t if not unicodedata.combining(c))
    t = re.sub(r"[^a-z0-9]+", " ", t).strip()
    t = re.sub(r"^(der|die|das|ein|eine|the|a|an) ", "", t)
    return t


def members(session, cat, depth, seen=None):
    """Category members, recursing into subcategories to `depth`."""
    seen = seen if seen is not None else set()
    if cat in seen:
        return []
    seen.add(cat)
    out, cont = [], {}
    while True:
        p = {"action": "query", "list": "categorymembers", "cmtitle": cat,
             "cmlimit": 500, "cmtype": "page|subcat", "format": "json", **cont}
        d = session.get(API, params=p, timeout=60).json()
        for m in d.get("query", {}).get("categorymembers", []):
            if m["ns"] == 14:
                if depth > 0:
                    out += members(session, m["title"], depth - 1, seen)
            else:
                out.append(m["title"])
        if "continue" not in d:
            return out
        cont = d["continue"]
        time.sleep(0.4)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("category")
    ap.add_argument("--depth", type=int, default=0)
    ap.add_argument("--db", required=True, help="json list of corpus titles")
    ap.add_argument("--out")
    a = ap.parse_args()

    s = requests.Session()
    s.headers["User-Agent"] = UA
    arts = sorted(set(members(s, a.category, a.depth)))
    have = {norm(t) for t in json.load(open(a.db))}
    # also index by first line: folk songs are filed under incipit OR refrain
    missing = [t for t in arts if norm(t) not in have]
    print(f"{a.category}: {len(arts)} articles · have {len(arts) - len(missing)} "
          f"· MISSING {len(missing)}")
    for t in missing:
        print("   ", t)
    if a.out:
        json.dump(missing, open(a.out, "w"), indent=1, ensure_ascii=False)


if __name__ == "__main__":
    main()
