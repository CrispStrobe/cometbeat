"""Add a multi-format `files` map to every db.json entry from what's on disk.
Paths use the SAME per-source relative root as `path` (OpenScore->raw/,
Mutopia->mutopia/, PDMX->music-db root). Only existing files are listed.
Idempotent; run AFTER merge_db.py and after any format-fetch/derive jobs."""
import json, os
from collections import Counter
ROOT="/mnt/volume1/music-db"
d=json.load(open(f"{ROOT}/db.json"))
def swap(path, ext): return path.rsplit(".",1)[0]+"."+ext
for x in d:
    src, path = x["source"], x["path"]
    if src=="PDMX":
        prefix=ROOT; h=path.rsplit("/",1)[-1].rsplit(".",1)[0]
        cand={"midi":f"pdmx/ship/midi/{h}.mid","mxl":f"pdmx/ship/mxl/{h}.mxl",
              "json":f"pdmx/ship/json/{h}.json","pdf":f"pdmx/ship/pdf/{h}.pdf"}
    elif src.startswith("OpenScore"):
        prefix=f"{ROOT}/raw"
        cand={"mscx":path,"mxl":swap(path,"mxl"),"mscz":swap(path,"mscz"),
              "midi":swap(path,"mid")}   # derived by job_mxl2midi
    else:  # Mutopia
        prefix=f"{ROOT}/mutopia"
        cand={"midi":path,
              "pdf":path.replace("/midi/","/pdf/").replace(".mid",".pdf"),
              "ly": path.replace("/midi/","/ly/").replace(".mid",".ly")}
    x["files"]={f:p for f,p in cand.items() if os.path.exists(os.path.join(prefix,p))}
json.dump(d,open(f"{ROOT}/db.json","w"),indent=1)
fmt=Counter(f for x in d for f in x["files"])
nper=Counter(len(x["files"]) for x in d)
print("format availability:", dict(fmt))
print("formats-per-entry:", dict(sorted(nper.items())))
for s in ["PDMX","OpenScore Lieder","OpenScore String Quartets","Mutopia Project"]:
    e=next(x for x in d if x["source"]==s)
    print(f"  {s:28} -> {sorted(e['files'])}")
