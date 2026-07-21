"""Resume the PDMX composer classifier: retry ONLY names that errored, with
exponential backoff + Wikidata maxlag, at a polite rate."""
import json, re, time, urllib.parse, urllib.request, urllib.error
API="https://www.wikidata.org/w/api.php"
UA="CometBeat-corpus-licence-check/1.0 (music-education PD verification; contact stc.akrs@gmail.com)"
MUSIC={"Q36834","Q639669","Q486748","Q1259917","Q753110","Q49757","Q482980",
       "Q1350157","Q158852","Q177220","Q855091","Q584301","Q2643890"}
CUTOFF=1955
def api(params):
    url=API+"?"+urllib.parse.urlencode({**params,"format":"json","maxlag":"5"})
    req=urllib.request.Request(url,headers={"User-Agent":UA})
    last=None
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req,timeout=30) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            last=e
            wait=int(e.headers.get("Retry-After") or 0) or (2**attempt)
            time.sleep(min(wait,30))
        except Exception as e:
            last=e; time.sleep(2**attempt)
    raise last
def yr(claim):
    try: return int(re.sub(r"^[+-]","",claim[0]["mainsnak"]["datavalue"]["value"]["time"])[:4])
    except Exception: return None
def classify(name):
    hits=api({"action":"wbsearchentities","search":name,"language":"en","limit":6}).get("search",[])
    if not hits: return ("UNKNOWN",None,None,None,None)
    ids="|".join(h["id"] for h in hits)
    ents=api({"action":"wbgetentities","ids":ids,"props":"claims|labels","languages":"en"}).get("entities",{})
    best=None
    for qid,ent in ents.items():
        cl=ent.get("claims",{})
        occ={o["mainsnak"].get("datavalue",{}).get("value",{}).get("id") for o in cl.get("P106",[])}
        if not (occ & MUSIC): continue
        d=yr(cl.get("P570",[])); b=yr(cl.get("P569",[]))
        lab=ent.get("labels",{}).get("en",{}).get("value",name)
        score=(d is not None)+(b is not None)
        if best is None or score>best[0]: best=(score,qid,lab,b,d)
    if best is None: return ("UNKNOWN",None,None,None,None)
    _,qid,lab,b,d=best
    if d is not None: st="PD" if d<=CUTOFF else "RECENT"
    elif b is not None: st="ALIVE" if b>=1900 else "PD"
    else: st="UNKNOWN"
    return (st,qid,lab,b,d)
out=json.load(open("/tmp/pdmx_classify.json"))
todo=[n for n,v in out.items() if v.get("status") in ("ERROR",None)]
print(f"retrying {len(todo)} errored names",flush=True)
for i,nm in enumerate(todo,1):
    try:
        st,qid,lab,b,d=classify(nm)
        out[nm].update(status=st,qid=qid,label=lab,birth=b,death=d)
    except Exception as e:
        out[nm].update(status="ERROR",err=str(e)[:60])
    if i%25==0:
        json.dump(out,open("/tmp/pdmx_classify.json","w"))
        print(f"...{i}/{len(todo)}",flush=True)
    time.sleep(0.4)
json.dump(out,open("/tmp/pdmx_classify.json","w"))
from collections import Counter
byname=Counter(v["status"] for v in out.values())
print("RETRY DONE. unique-name status:",dict(byname),flush=True)
