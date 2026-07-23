"""Shared Wikidata death-date resolver + cache for ALL CometBeat life+70 tools
(OpenScore, NIFC-Polish, Mutopia, PDMX). One store, `wikidata_deaths.json`, keyed
by the queried name → RAW facts, so:
  * classification logic can change WITHOUT re-querying Wikidata, and
  * a composer resolved by one tool is never re-queried by another.

`resolve(name)` → {"qid","label","birth","death","occ":[qid…],"human":bool};
qid=None when no plausible *person* entity is found (fails closed). Callers apply
their own occupation bar (MUSIC vs WRITER vs ARTS) + name-sanity.
"""
import json
import re
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path("/mnt/volume1/music-db")
CACHE = ROOT / "wikidata_deaths.json"
API = "https://www.wikidata.org/w/api.php"
UA = "CometBeat-corpus/1.0 (music-education PD verification; stc.akrs@gmail.com)"
HUMAN = "Q5"

# occupation QIDs, split so each caller picks its bar
MUSIC = {"Q36834", "Q639669", "Q753110", "Q855091", "Q486748", "Q1259917",
         "Q158852", "Q765778", "Q1350189", "Q3922505", "Q806349", "Q2490358",
         "Q584301", "Q1198887"}  # composer/musician/songwriter/guitarist/pianist/
#                                  singer/conductor/organist/violinist/cellist/…
COMPOSER = {"Q36834", "Q753110"}  # composer, songwriter (strict bar for 1-token names)
WRITER = {"Q49757", "Q482980", "Q36180", "Q214917", "Q6625963", "Q4853732",
          "Q18844224", "Q12144794", "Q1930187"}  # poet/writer/author/librettist/…
ARTS = MUSIC | WRITER

_cache = None


def _load():
    global _cache
    if _cache is None:
        _cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    return _cache


def save():
    if _cache is not None:
        CACHE.write_text(json.dumps(_cache, ensure_ascii=False, indent=1))


def norm(s):
    s = unicodedata.normalize("NFKD", str(s or "")).encode("ascii", "ignore").decode().lower()
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9 ]+", " ", s)).strip()


def _api(params):
    url = API + "?" + urllib.parse.urlencode({**params, "format": "json", "maxlag": "5"})
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    last = None
    for a in range(6):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            last = e
            time.sleep(min(int(e.headers.get("Retry-After") or 0) or 2 ** a, 30))
        except Exception as e:
            last = e
            time.sleep(2 ** a)
    raise last


def _yr(cl):
    try:
        return int(re.sub(r"^[+-]", "", cl[0]["mainsnak"]["datavalue"]["value"]["time"])[:4])
    except Exception:
        return None


def resolve(name):
    """Best-matching PERSON entity for `name`, cached. Prefers human + music, then
    human + arts, then human with dates. Stores raw facts; None-qid = no person."""
    c = _load()
    if name in c:
        return c[name]
    fact = {"qid": None, "label": None, "birth": None, "death": None,
            "occ": [], "human": False}
    hits = _api({"action": "wbsearchentities", "search": name, "language": "en",
                 "limit": 7}).get("search", [])
    if hits:
        ents = _api({"action": "wbgetentities", "ids": "|".join(h["id"] for h in hits),
                     "props": "claims|labels", "languages": "en"}).get("entities", {})
        best = None
        for qid, ent in ents.items():
            cl = ent.get("claims", {})
            inst = {o["mainsnak"].get("datavalue", {}).get("value", {}).get("id")
                    for o in cl.get("P31", [])}
            occ = {o["mainsnak"].get("datavalue", {}).get("value", {}).get("id")
                   for o in cl.get("P106", []) if o["mainsnak"].get("datavalue")}
            human = HUMAN in inst
            d = _yr(cl.get("P570", []))
            b = _yr(cl.get("P569", []))
            lab = ent.get("labels", {}).get("en", {}).get("value", name)
            rank = (human, bool(occ & MUSIC), bool(occ & ARTS),
                    d is not None, b is not None)
            if best is None or rank > best[0]:
                best = (rank, {"qid": qid, "label": lab, "birth": b, "death": d,
                               "occ": sorted(o for o in occ if o), "human": human})
        if best and best[0][0]:  # require a human match
            fact = best[1]
    c[name] = fact
    return fact


def verdict(name, cutoff=1955, occ_bar=None):
    """Shared EU life+70 verdict from the cached facts — the common core the
    OpenScore / Polish / Mutopia life70 tools now call instead of hand-rolling
    their own Wikidata classify(). occ_bar = required occupation set (default ARTS,
    i.e. musician OR writer/poet). Returns (status, qid, label, birth, death) with
    status in PD / RECENT / ALIVE / UNKNOWN. Fails closed (UNKNOWN) when unresolved.
    """
    bar = occ_bar or ARTS
    f = resolve(name)
    if not f["qid"] or not (set(f["occ"]) & bar):
        return ("UNKNOWN", None, None, None, None)
    d, b = f["death"], f["birth"]
    if d is not None:
        st = "PD" if d <= cutoff else "RECENT"
    elif b is not None:
        st = "ALIVE" if b >= 1900 else "PD"
    else:
        st = "UNKNOWN"
    return (st, f["qid"], f["label"], b, d)
