"""Polish-scores composer life+70 — thin wrapper over shared wikidata_deaths.
'Anonim'/'Anonymous'/... -> NO_AUTHOR (no death clock)."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wikidata_deaths as wd
ANON = {"anonim", "anonymous", "anon", "anon.", "traditional", "trad.", "incerti auctoris", ""}
names = json.load(open("/tmp/polish_composers.json"))
try: out = json.load(open("/tmp/polish_classify.json"))
except Exception: out = {}
todo = [n for n in names if n not in out or out[n].get("status") in ("ERROR", None)]
print(f"classifying {len(todo)} of {len(names)} (shared cache)", flush=True)
for i, nm in enumerate(todo, 1):
    if nm.strip().lower() in ANON:
        out[nm] = {"count": names[nm], "status": "NO_AUTHOR", "qid": None, "label": None, "birth": None, "death": None}
    else:
        st, qid, lab, b, d = wd.verdict(nm, occ_bar=wd.ARTS)
        out[nm] = {"count": names[nm], "status": st, "qid": qid, "label": lab, "birth": b, "death": d}
    if i % 40 == 0: wd.save(); json.dump(out, open("/tmp/polish_classify.json", "w"), ensure_ascii=False)
wd.save(); json.dump(out, open("/tmp/polish_classify.json", "w"), ensure_ascii=False)
from collections import Counter
print("POLISH DONE:", dict(Counter(v["status"] for v in out.values())), flush=True)
