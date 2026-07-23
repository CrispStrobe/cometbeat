"""OpenScore composer+poet life+70 — now a thin wrapper over the shared
bin/wikidata_deaths.py resolver + wikidata_deaths.json cache (was a hand-rolled
duplicate of the same Wikidata classify). Occupation bar = ARTS (musician OR
writer/poet, since OpenScore checks both composers and poets)."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wikidata_deaths as wd
names = json.load(open("/tmp/os_cand.json"))["names"]
try: out = json.load(open("/tmp/os_classify.json"))
except Exception: out = {}
todo = [n for n in names if n not in out or out[n].get("status") in ("ERROR", None)]
print(f"classifying {len(todo)} of {len(names)} (shared cache)", flush=True)
for i, nm in enumerate(todo, 1):
    st, qid, lab, b, d = wd.verdict(nm, occ_bar=wd.ARTS)
    out[nm] = {"count": names[nm], "status": st, "qid": qid, "label": lab, "birth": b, "death": d}
    if i % 40 == 0:
        wd.save(); json.dump(out, open("/tmp/os_classify.json", "w"), ensure_ascii=False)
        print(f"...{i}/{len(todo)}", flush=True)
wd.save(); json.dump(out, open("/tmp/os_classify.json", "w"), ensure_ascii=False)
from collections import Counter
print("OS CLASSIFY DONE:", dict(Counter(v["status"] for v in out.values())), flush=True)
