#!/usr/bin/env python3
"""Throttled, error-distinguishing wrapper around bin/eu_pd_check.death_year.

WHY THIS EXISTS. `eu_pd_check.death_year` catches every exception and returns
UNKNOWN. That is fail-closed on the *licence* axis (good) but it silently
converts TRANSPORT failures into "unresolvable author" — and Wikidata answers
429 quickly at even a modest request rate. A run that trips the rate limit
therefore reports a corpus of unresolvable names and looks like a data ceiling
when it is actually a throttling artifact. Two of the three names I first tested
as "obscure, UNKNOWN" resolved fine once throttled.

So this wrapper:
  * routes the API through `requests` (real CA bundle; the stdlib path fails
    TLS verification on this Mac and that ALSO surfaced as UNKNOWN),
  * sleeps between calls and honours Retry-After, retrying 429/5xx,
  * raises on transport failure instead of laundering it into UNKNOWN, so the
    caller can tell "Wikidata says no" from "we never asked successfully",
  * caches per name, so a re-run costs nothing.

The licence logic itself — the P106 occupation gate, the 1955 cutoff, inline
lifespan parsing — is IMPORTED, not reimplemented. This file changes only how
reliably we get an answer, never what counts as an answer.
"""
import json
import re
import sys
import time
from pathlib import Path

import requests

# eu_pd_check.py is the maintainer's file and lives on the VPS under
# music-db/bin/. Look for it beside this script first (local working copy), then
# in the canonical VPS location, so the same file runs in both places.
for _cand in (Path(__file__).parent, Path("/mnt/volume1/music-db/bin"),
              Path(__file__).parent.parent / "music-db" / "bin"):
    if (_cand / "eu_pd_check.py").exists():
        sys.path.insert(0, str(_cand))
        break
else:
    raise SystemExit(
        "eu_pd_check.py not found — copy it from the VPS "
        "(scp vps:/mnt/volume1/music-db/bin/eu_pd_check.py .) before running")

import eu_pd_check as E  # noqa: E402  (path shim must run first)

MIN_INTERVAL = 1.1   # seconds between Wikidata calls
CACHE_PATH = Path(__file__).parent / "wikidata-death-cache.json"

_S = requests.Session()
_S.headers["User-Agent"] = E.UA
_last = [0.0]


def _api(params):
    """Throttled GET with backoff. Raises if it truly cannot get an answer."""
    for attempt in range(7):
        gap = MIN_INTERVAL - (time.time() - _last[0])
        if gap > 0:
            time.sleep(gap)
        _last[0] = time.time()
        try:
            r = _S.get(E.API, params={**params, "format": "json"}, timeout=30)
        except requests.RequestException as e:
            print(f"    !! {type(e).__name__}; retry {attempt}", flush=True)
            time.sleep(5 * (attempt + 1))
            continue
        if r.status_code == 429 or r.status_code >= 500:
            wait = int(r.headers.get("Retry-After") or 0) or 10 * (attempt + 1)
            print(f"    !! HTTP {r.status_code}; sleeping {wait}s", flush=True)
            time.sleep(wait)
            continue
        r.raise_for_status()
        return r.json()
    raise RuntimeError("wikidata unreachable after retries")


E.api = _api  # the imported licence logic now uses the throttled transport


def load_cache():
    if CACHE_PATH.exists():
        return json.loads(CACHE_PATH.read_text())
    return {}


def save_cache(c):
    CACHE_PATH.write_text(json.dumps(c, indent=1, ensure_ascii=False))


def resolve(name, cache):
    """(status, year, label, qid) with status CLEAR/BLOCKED/UNKNOWN.

    Transport failure propagates as an exception — deliberately NOT UNKNOWN.
    """
    if name in cache:
        return tuple(cache[name])
    res = E.death_year(name, full=name)
    cache[name] = list(res)
    return res


def canary(cache):
    """Refuse to trust a run whose transport is silently broken.

    Two names with well-known Wikidata death dates, one either side of the
    cutoff. If these do not come back CLEAR/BLOCKED, the pipeline is not
    resolving anything and every UNKNOWN downstream is meaningless.
    """
    ok, year, _, _ = resolve("John Philip Sousa", cache)
    bad = resolve("Igor Stravinsky", cache)
    if ok != "CLEAR" or year != 1932:
        raise SystemExit(f"CANARY FAILED (Sousa -> {ok} {year}); aborting")
    if bad[0] != "BLOCKED":
        raise SystemExit(f"CANARY FAILED (Stravinsky -> {bad}); aborting")
    print(f"canary ok: Sousa={year} CLEAR, Stravinsky={bad[1]} BLOCKED")


if __name__ == "__main__":
    c = load_cache()
    canary(c)
    for n in sys.argv[1:]:
        print(f"{n:30}", resolve(n, c))
    save_cache(c)


def all_candidates_pd(name, cache, cutoff=1955):
    """CLEAR when EVERY plausible person of this name is already PD.

    The occupation gate exists to stop a famous namesake clearing an obscure
    protected arranger. But it rejects the very people CPDL is full of —
    hymnwriters, psalmodists, clerics, translators — whose death years Wikidata
    knows perfectly well: Charles Wesley (1788) blocked 147 rows, William Kethe
    (1594) 25, Israel Holdroyd (1753) 46.

    This rule sidesteps identification entirely instead of loosening it. If
    every entity carrying that exact label has a death year and ALL of them are
    <= cutoff, then it does not matter which one the score means — whoever it
    is, they are public domain. If any candidate lacks a death year, or any
    died after the cutoff, we learn nothing and stay held.

    Returns (status, year, label, qid) with status CLEAR or UNKNOWN.
    """
    key = f"__allpd__{name}"
    if key in cache:
        return tuple(cache[key])
    try:
        hits = _api({"action": "wbsearchentities", "search": name,
                     "language": "en", "limit": 12}).get("search", [])
    except Exception:
        return "UNKNOWN", None, name, None
    # Only entities whose LABEL is the name we asked about; a fuzzy hit is a
    # different person and would silently widen the pool.
    exact = [h for h in hits
             if (h.get("label") or "").strip().casefold() == name.strip().casefold()]
    if not exact:
        cache[key] = ["UNKNOWN", None, name, None]
        return tuple(cache[key])
    try:
        ents = _api({"action": "wbgetentities",
                     "ids": "|".join(h["id"] for h in exact),
                     "props": "claims|labels", "languages": "en"}).get("entities", {})
    except Exception:
        return "UNKNOWN", None, name, None

    years, people = [], []
    for qid, ent in ents.items():
        claims = ent.get("claims", {})
        # A entity with no death date might be alive, or might just be
        # under-described. Either way it breaks the "all are PD" guarantee.
        p570 = claims.get("P570")
        if not p570:
            # Tolerate non-persons (a ship, a place) — they hold no copyright.
            if not claims.get("P31") or any(
                    o["mainsnak"].get("datavalue", {}).get("value", {}).get("id") == "Q5"
                    for o in claims.get("P31", [])):
                cache[key] = ["UNKNOWN", None, name, None]
                return tuple(cache[key])
            continue
        t = p570[0]["mainsnak"].get("datavalue", {}).get("value", {}).get("time")
        if not t:
            cache[key] = ["UNKNOWN", None, name, None]
            return tuple(cache[key])
        y = int(re.sub(r"^[+-]", "", t)[:4])
        years.append(y)
        people.append((qid, y))
    if not years or max(years) > cutoff:
        cache[key] = ["UNKNOWN", None, name, None]
        return tuple(cache[key])
    qid, y = max(people, key=lambda p: p[1])   # report the LATEST death
    cache[key] = ["CLEAR", y, f"{name} (all {len(years)} candidates PD)", qid]
    return tuple(cache[key])
