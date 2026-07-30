#!/usr/bin/env python3
"""For a list of de.wikipedia articles, say which carry engravable notation.

Splits a "we lack these" list into the part that is actionable today (the
article embeds a <score> block we can read) and the part that is a genuine
content gap (no notation on the page at all — someone would have to source or
write the melody). Without that split a gap list is just a wish list.
"""
import json
import re
import sys
import time

import requests

API = "https://de.wikipedia.org/w/api.php"
UA = ("CometBeat-corpus-harvest/1.0 (music education app; PD corpus ingest; "
      "contact stc.akrs@gmail.com)")
MUSIC = re.compile(r"\\relative|\\new\s+(Staff|Voice)")


def main():
    titles = json.load(open(sys.argv[1]))
    s = requests.Session()
    s.headers["User-Agent"] = UA
    withscore, plain = [], []
    for i in range(0, len(titles), 20):
        batch = titles[i:i + 20]
        d = s.get(API, params={"action": "query", "prop": "revisions",
                               "rvprop": "content", "rvslots": "main",
                               "titles": "|".join(batch), "format": "json",
                               "formatversion": 2}, timeout=90).json()
        for p in d.get("query", {}).get("pages", []):
            try:
                wt = p["revisions"][0]["slots"]["main"]["content"]
            except (KeyError, IndexError):
                plain.append(p["title"])
                continue
            blocks = [b for b in re.findall(r"<score[^>]*>(.*?)</score>", wt, re.S)
                      if MUSIC.search(b)]
            (withscore if blocks else plain).append(p["title"])
        print(f"  [{min(i + 20, len(titles))}/{len(titles)}] "
              f"score={len(withscore)} none={len(plain)}", flush=True)
        time.sleep(0.4)
    json.dump({"with_score": sorted(withscore), "no_notation": sorted(plain)},
              open(sys.argv[2], "w"), indent=1, ensure_ascii=False)
    print(f"\nharvestable now (<score> on the page): {len(withscore)}")
    print(f"no notation on the page:                {len(plain)}")


if __name__ == "__main__":
    main()
