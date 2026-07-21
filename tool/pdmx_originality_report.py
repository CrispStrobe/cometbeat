import csv, os, re, sys, json
from collections import Counter
csv.field_size_limit(sys.maxsize)
want=set(f[:-5] for f in os.listdir("/mnt/volume1/pdmx-cc0-midi/json"))
def clean(v):
    v=(v or "").strip(); return "" if v in ("","NA") else v
JUNK=re.compile(r"^(composer|unknown|anonymous|n/?a|\.+|-+|\?+|traditional|various|me|myself|test|pr|bh|jb.*|.{1,2})$",re.I)
STRIP=re.compile(r"\(?\b1[0-9]{3}\s*[-–—]?\s*(1[0-9]{3}|20[0-2][0-9])?\)?|"
                 r"\b(arr\.?|arrgt|arrangement|arranged by|transcri\w*|adapted by|"
                 r"music by|words and music by|composed by|m[uú]sica|harm)\b[:\.]?",re.I)
INLINE=re.compile(r"\(?\b(1[0-9]{3}|20[0-2][0-9])\s*[-–—]\s*(1[0-9]{3}|20[0-2][0-9])\b\)?")
INLINE2=re.compile(r"\b(1[0-9]{3}|20[0-2][0-9])(1[0-9]{3}|20[0-2][0-9])\b")
ARR=re.compile(r"\barr\b|arrang|transcri|adapt|inspired|based on|cover",re.I)
def normalize(c):
    c=re.split(r"[/;]|harm:|arr\.|arrgt|adapted by",c,flags=re.I)[0]
    c=STRIP.sub(" ",c); c=re.sub(r"[^A-Za-zÀ-ÿ.\s'\-]"," ",c)
    return re.sub(r"\s+"," ",c).strip(" .-")
cls=json.load(open("/tmp/pdmx_classify.json"))
title={}
rows=[]
for x in csv.DictReader(open("/mnt/volume1/pdmx-cc0-midi/zenodo/PDMX.csv")):
    h=(x.get("path") or "").split("/")[-1].replace(".json","")
    if h not in want: continue
    title[h]=clean(x.get("title")) or clean(x.get("song_name")) or h[:10]
    comp=clean(x.get("composer_name")); up=clean(x.get("artist_name"))
    if comp and up and comp.lower()!=up.lower():
        rows.append((h,comp,up))
def bucket(h,comp):
    m=INLINE.search(comp) or INLINE2.search(comp)
    if m:
        return ("clean_pd_inline" if int(m.group(2))<=1955 else "problematic",
                None,None,int(m.group(2)))
    if JUNK.match(comp.strip()): return ("false_positive_junk",None,None,None)
    nm=normalize(comp)
    toks=[t for t in nm.split() if len(t)>=2 and re.search(r"[A-Za-zÀ-ÿ]",t)]
    if not (len(toks)>=2 and len(nm)<=50):
        return ("unclear_odd_name",None,None,None)
    v=cls.get(nm)
    if not v or v.get("status") in ("ERROR",None): return ("unresolved_error",None,None,None)
    st=v["status"]
    fin={"PD":"clean_pd_composer","RECENT":"problematic","ALIVE":"problematic",
         "UNKNOWN":"likely_original_unknown"}[st]
    return (fin,v.get("label"),v.get("birth"),v.get("death"))
per=Counter(); prob=[]
for h,comp,up in rows:
    b,lab,by,dy=bucket(h,comp)
    per[b]+=1
    if b=="problematic":
        prob.append({"hash":h,"title":title.get(h),"composer":comp,"uploader":up,
                     "match":lab,"birth":by,"death":dy})
print("=== final buckets of the 4,174 third-party-composer entries ===")
for k,v in per.most_common(): print(f"  {k:26} {v}")
clean_ct=per["clean_pd_composer"]+per["clean_pd_inline"]+per["false_positive_junk"]+per["likely_original_unknown"]
print(f"\n  => LIKELY-CLEAN (PD/junk/amateur): ~{clean_ct}")
print(f"  => PROBLEMATIC (named in-copyright): {per['problematic']}")
print(f"  => unresolved/odd (manual): {per['unresolved_error']+per['unclear_odd_name']}")
prob.sort(key=lambda x:(x['death'] or 9999, x['title'] or ''))
json.dump(prob,open("/mnt/volume1/music-db/pdmx_problematic.json","w"),indent=1,ensure_ascii=False)
print(f"\nwrote {len(prob)} problematic -> music-db/pdmx_problematic.json")
print("\n=== sample problematic (title | composer field | matched | dates) ===")
for p in prob[:40]:
    print(f"  {(p['title'] or '')[:30]:31} | {p['composer'][:22]:23} | {(p['match'] or '')[:20]:21} {p['birth']}-{p['death']}")
