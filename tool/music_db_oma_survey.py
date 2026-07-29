#!/usr/bin/env python3
"""Estimate how much of Open Music Academy is SYMBOLIC music vs prose/media.

Educandu ships `abc-notation` and `music-xml-viewer` plugins, so OMA documents
CAN carry symbolic music. The question is whether they usually do, and whether
what they carry is whole pieces or two-bar teaching examples — the difference
between a score corpus and a textbook.

Enumerates via the public search API, then reads each document's embedded
`window.__initalState__` and counts section plugin types. Gentle: sequential,
sleeps, small sample.
"""
import collections
import json
import re
import sys
import time

import requests

S = requests.Session()
S.headers.update({
    "User-Agent": ("CometBeat-corpus-survey/1.0 (music education app; "
                   "licence survey; contact stc.akrs@gmail.com)"),
    "Accept": "application/json",
})
API = "https://openmusic.academy/api/v1/search?query="
QUERIES = ["kadenz", "melodie", "akkord", "rhythmus", "tonleiter",
           "intervall", "bach", "volkslied", "harmonielehre", "notation"]
LIMIT = int(sys.argv[1]) if len(sys.argv) > 1 else 30


def main():
    docs = {}
    for q in QUERIES:
        try:
            r = S.get(API + q, timeout=40)
            r.raise_for_status()
            for d in r.json():
                docs.setdefault(d["_id"], d)
        except Exception as e:
            print("  search failed", q, e)
        time.sleep(1.0)
    print(f"documents discovered via search: {len(docs)}")

    sample = list(docs.values())[:LIMIT]
    types = collections.Counter()
    abc_docs = xml_docs = 0
    abc_lens = []
    for i, d in enumerate(sample, 1):
        url = f"https://openmusic.academy/docs/{d['_id']}/{d.get('slug','x')}"
        try:
            html = S.get(url, timeout=40,
                         headers={"Accept": "text/html"}).text
        except Exception as e:
            print("  fetch failed", e)
            continue
        m = re.search(r'window\.__initalState__\s*=\s*(\{.*?\});\s*\n', html, re.S)
        state = None
        if m:
            try:
                state = json.loads(m.group(1))
            except Exception:
                state = None
        found = re.findall(r'"type":"([a-z0-9-]+)"', html)
        for t in found:
            types[t] += 1
        has_abc = "abc-notation" in found
        has_xml = "music-xml-viewer" in found
        abc_docs += has_abc
        xml_docs += has_xml
        # Measure ABC payload size — a whole piece vs a two-bar example.
        for a in re.findall(r'"abcCode":"((?:[^"\\]|\\.)*)"', html):
            abc_lens.append(len(a))
        print(f"[{i}/{len(sample)}] {str(d.get('title'))[:44]:44} "
              f"abc={has_abc} xml={has_xml}")
        time.sleep(0.8)

    print(f"\ndocs sampled: {len(sample)}")
    print(f"  with abc-notation:    {abc_docs}")
    print(f"  with music-xml-viewer:{xml_docs}")
    print(f"  section types seen: {dict(types.most_common(12))}")
    if abc_lens:
        abc_lens.sort()
        print(f"  abc snippets: n={len(abc_lens)} "
              f"median={abc_lens[len(abc_lens)//2]} chars "
              f"max={abc_lens[-1]} chars")


if __name__ == "__main__":
    main()
