"""Fetch Mutopia per-piece PDF (A4) + LilyPond .ly from the FTP dirs. Resumable
(skips existing), polite (0.4s), retries w/ backoff. Free/PD source."""
import json, os, sys, time, re, urllib.request
ROOT="/mnt/volume1/music-db"
UA="cometbeat-corpus/1.0 (music-education PD archive; stc.akrs@gmail.com)"
def get(url, timeout=45):
    req=urllib.request.Request(url, headers={"User-Agent":UA})
    for a in range(4):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r: return r.read()
        except Exception:
            if a==3: raise
            time.sleep(2**a)
d=json.load(open(f"{ROOT}/db.json"))
mut=[x for x in d if x["source"]=="Mutopia Project"]
ok=skip=fail=pdf_n=ly_n=0
for i,x in enumerate(mut,1):
    su=x["source_url"].rstrip("/")
    parts=x["path"].split("/")
    try: idx=parts.index("midi"); cat="/".join(parts[1:idx])
    except ValueError: cat="misc"
    name=parts[-1].rsplit(".",1)[0]
    pdf_dst=f"{ROOT}/mutopia/ship/{cat}/pdf/{name}.pdf"
    ly_dst =f"{ROOT}/mutopia/ship/{cat}/ly/{name}.ly"
    if os.path.exists(pdf_dst) and os.path.exists(ly_dst): skip+=1; continue
    try:
        listing=get(su+"/").decode("utf-8","replace")
        hrefs=re.findall(r'href="([^"?/][^"]*)"', listing)
        pdfs=[h for h in hrefs if h.lower().endswith(".pdf")]
        a4=[h for h in pdfs if "-a4" in h] or pdfs
        lys=[h for h in hrefs if h.lower().endswith(".ly")]
        os.makedirs(os.path.dirname(pdf_dst), exist_ok=True)
        os.makedirs(os.path.dirname(ly_dst), exist_ok=True)
        if a4 and not os.path.exists(pdf_dst):
            open(pdf_dst,"wb").write(get(su+"/"+a4[0])); pdf_n+=1
        if lys and not os.path.exists(ly_dst):
            open(ly_dst,"wb").write(get(su+"/"+lys[0])); ly_n+=1
        ok+=1
    except Exception as e:
        fail+=1; print(f"FAIL {name}: {type(e).__name__}: {e}", flush=True)
    time.sleep(0.4)
    if i%50==0: print(f"...{i}/{len(mut)} ok={ok} skip={skip} fail={fail} (pdf={pdf_n} ly={ly_n})", flush=True)
print(f"MUTOPIA DONE ok={ok} skip={skip} fail={fail} pdf={pdf_n} ly={ly_n}")
