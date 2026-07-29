#!/usr/bin/env python3
"""Gently mirror the Tanzsammlung Dahlhoff ABC corpus from TradArchiv.

Small personal site -> deliberate slow pacing, resume by file existence,
back off hard on any error. Files are ~2 KB each (1.4 MB total for all 703).
"""
import os
import random
import re
import sys
import time
import urllib.parse
import urllib.request

BASE = "http://simonwascher.info/TradArchiv/Dahlhoff/"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dahlhoff")
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
     "(KHTML, like Gecko) Chrome/120.0 Safari/537.36"

MIN_DELAY, MAX_DELAY = 3.0, 6.0


def get(url, timeout=45):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def main():
    os.makedirs(OUT, exist_ok=True)

    index_path = os.path.join(OUT, "_index.html")
    if os.path.exists(index_path):
        index = open(index_path, "rb").read()
    else:
        index = get(BASE)
        open(index_path, "wb").write(index)

    html = index.decode("utf-8", "replace")
    names = []
    seen = set()
    for m in re.finditer(r'href="([^"]*\.abc)"', html):
        n = m.group(1)
        if n not in seen:
            seen.add(n)
            names.append(n)
    print(f"{len(names)} abc files listed", flush=True)

    # Also grab the PDF-of-everything reference and the notes pages once.
    for extra in ("dhf_text.htm", "findung.htm", "dhf_list_concordances.htm"):
        p = os.path.join(OUT, extra)
        if not os.path.exists(p):
            try:
                open(p, "wb").write(get(BASE + extra))
            except Exception as e:
                print(f"  ! {extra}: {e}", flush=True)
            time.sleep(random.uniform(MIN_DELAY, MAX_DELAY))

    ok = skip = fail = 0
    failures = []
    for i, name in enumerate(names, 1):
        local = os.path.join(OUT, urllib.parse.unquote(name))
        if os.path.exists(local) and os.path.getsize(local) > 0:
            skip += 1
            continue
        url = BASE + urllib.parse.quote(urllib.parse.unquote(name), safe="")
        try:
            data = get(url)
            if not data.strip():
                raise ValueError("empty body")
            open(local, "wb").write(data)
            ok += 1
        except Exception as e:
            fail += 1
            failures.append((name, str(e)))
            print(f"  ! [{i}/{len(names)}] {name}: {e}", flush=True)
            time.sleep(60)  # back off hard, the site is small
            continue
        if ok % 25 == 0:
            print(f"  [{i}/{len(names)}] ok={ok} skip={skip} fail={fail}", flush=True)
        time.sleep(random.uniform(MIN_DELAY, MAX_DELAY))

    print(f"DONE ok={ok} skip={skip} fail={fail}", flush=True)
    if failures:
        with open(os.path.join(OUT, "_failures.txt"), "w") as f:
            for n, e in failures:
                f.write(f"{n}\t{e}\n")
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
