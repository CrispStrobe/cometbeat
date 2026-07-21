"""Derive playback MIDI from every OpenScore .mxl (sibling of the .mscx).
Resumable; per-file try/except; logs failures. Uses the validated mxl2midi."""
import json, os, sys
sys.path.insert(0, "/mnt/volume1/music-db/bin")
import mxl2midi as M
ROOT="/mnt/volume1/music-db"
d=json.load(open(f"{ROOT}/db.json"))
targets=[x for x in d if x["source"].startswith("OpenScore") and "mxl" in x.get("files",{})]
ok=skip=fail=0
for i,x in enumerate(targets,1):
    src=os.path.join(ROOT,"raw",x["files"]["mxl"])
    dst=src.rsplit(".",1)[0]+".mid"
    if os.path.exists(dst): skip+=1; continue
    try:
        open(dst,"wb").write(M.mxl_to_midi(open(src,"rb").read())); ok+=1
    except Exception as e:
        fail+=1; print(f"FAIL {x['files']['mxl']}: {type(e).__name__}: {e}", flush=True)
    if i%200==0: print(f"...{i}/{len(targets)} ok={ok} skip={skip} fail={fail}", flush=True)
print(f"MXL2MIDI DONE ok={ok} skip={skip} fail={fail}")
