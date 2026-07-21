"""Pure-stdlib MusicXML(.mxl) -> Standard MIDI. Reuses the PDMX SMF writer.
Handles: parts->tracks, per-measure divisions, chords, backup/forward (voices),
ties (extend, no re-articulation), tempo, midi program. Not a full engraver —
a faithful *playback* MIDI. Every file wrapped in try/except by the caller."""
import io, zipfile, struct, math
import xml.etree.ElementTree as ET

STEP = {"C":0,"D":2,"E":4,"F":5,"G":7,"A":9,"B":11}

def _vlq(n):
    n=max(int(n),0); b=[n&0x7F]; n>>=7
    while n>0: b.append((n&0x7F)|0x80); n>>=7
    return bytes(reversed(b))

def _tag(e): return e.tag.rsplit("}",1)[-1]

def _root_xml(data):
    z=zipfile.ZipFile(io.BytesIO(data))
    try:
        c=ET.fromstring(z.read("META-INF/container.xml"))
        rf=c.find(".//{*}rootfile").get("full-path")
        return z.read(rf)
    except Exception:
        for n in z.namelist():
            if n.endswith(".xml") and not n.startswith("META-INF"):
                return z.read(n)
    raise ValueError("no score xml in mxl")

def _text(e,path,default=None):
    x=e.find(path)
    return x.text if x is not None and x.text is not None else default

def mxl_to_midi(data, ppq=480):
    xml=_root_xml(data)
    root=ET.fromstring(xml)
    ns={"":""}
    def find(e,tag): return [c for c in e.iter() if _tag(c)==tag]
    # part programs from part-list
    prog={}
    for sp in root.iter():
        if _tag(sp)=="score-part":
            pid=sp.get("id")
            mi=[c for c in sp.iter() if _tag(c)=="midi-program"]
            prog[pid]=(int(mi[0].text)-1) if mi and mi[0].text else 0
    parts=[p for p in root.iter() if _tag(p)=="part"]
    tempo_us=500000  # 120 bpm default
    tracks=[]
    for pi,part in enumerate(parts):
        pid=part.get("id")
        ch=pi if pi<9 else pi+1
        if ch>15: ch=15
        events=[]  # (tick, order, bytes)
        events.append((0,-1,bytes([0xC0|ch, (prog.get(pid,0))&0x7F])))
        divisions=1; pos=0; last_onset=0
        open_notes={}  # (voice,pitch)->index into notelist for tie extend
        notelist=[]    # [on,off,pitch]
        for m in part:
            if _tag(m)!="measure": continue
            for el in m:
                t=_tag(el)
                if t=="attributes":
                    d=[c for c in el if _tag(c)=="divisions"]
                    if d and d[0].text: divisions=int(d[0].text)
                elif t=="direction":
                    for s in el.iter():
                        if _tag(s)=="sound" and s.get("tempo"):
                            nonlocal_tempo=float(s.get("tempo"))
                            tempo_us=int(round(60000000/nonlocal_tempo))
                elif t=="sound" and el.get("tempo"):
                    tempo_us=int(round(60000000/float(el.get("tempo"))))
                elif t=="backup":
                    dd=_text(el,"{*}duration") or _text(el,"duration")
                    dur=[c for c in el if _tag(c)=="duration"]
                    v=int(dur[0].text) if dur and dur[0].text else 0
                    pos-=int(round(v/divisions*ppq))
                elif t=="forward":
                    dur=[c for c in el if _tag(c)=="duration"]
                    v=int(dur[0].text) if dur and dur[0].text else 0
                    pos+=int(round(v/divisions*ppq))
                elif t=="note":
                    kids={_tag(c):c for c in el}
                    is_chord="chord" in kids
                    is_grace="grace" in kids
                    durn=[c for c in el if _tag(c)=="duration"]
                    dv=int(durn[0].text) if durn and durn[0].text else 0
                    dticks=int(round(dv/divisions*ppq))
                    voice=(kids.get("voice").text if "voice" in kids else "1")
                    if "rest" in kids:
                        if not is_chord: last_onset=pos; pos+=dticks
                        continue
                    if "pitch" not in kids:
                        if not is_chord and not is_grace: pos+=dticks
                        continue
                    p=kids["pitch"]
                    step=_text(p,"{*}step") or "".join(c.text for c in p if _tag(c)=="step")
                    stepc=[c.text for c in p if _tag(c)=="step"][0]
                    alterl=[c.text for c in p if _tag(c)=="alter"]
                    octl=[c.text for c in p if _tag(c)=="octave"]
                    alter=int(alterl[0]) if alterl and alterl[0] else 0
                    octave=int(octl[0]) if octl and octl[0] else 4
                    midi=(octave+1)*12+STEP.get(stepc,0)+alter
                    if midi<0: midi=0
                    if midi>127: midi=127
                    onset = last_onset if is_chord else pos
                    # tie handling
                    ties=[c.get("type") for c in el if _tag(c)=="tie"]
                    key=(voice,midi)
                    if "stop" in ties and key in open_notes:
                        idx=open_notes[key]; notelist[idx][1]=onset+max(dticks,1)
                        if "start" not in ties: open_notes.pop(key,None)
                    else:
                        idx=len(notelist)
                        notelist.append([onset,onset+max(dticks,1),midi])
                        if "start" in ties: open_notes[key]=idx
                    if not is_chord and not is_grace:
                        last_onset=pos; pos+=dticks
        for on,off,pitch in notelist:
            v=80
            events.append((on,1,bytes([0x90|ch,pitch,v])))
            events.append((max(off,on+1),0,bytes([0x80|ch,pitch,0])))
        events.sort(key=lambda e:(e[0],e[1]))
        body=bytearray(); prev=0
        for tick,_,d in events:
            body+=_vlq(tick-prev)+d; prev=tick
        body+=_vlq(0)+b"\xFF\x2F\x00"
        tracks.append(bytes(body))
    # meta track (tempo)
    meta=bytearray()
    meta+=_vlq(0)+b"\xFF\x51\x03"+tempo_us.to_bytes(3,"big")
    meta+=_vlq(0)+b"\xFF\x2F\x00"
    out=bytearray(b"MThd")+struct.pack(">IHHH",6,1,len(tracks)+1,ppq)
    out+=b"MTrk"+struct.pack(">I",len(meta))+meta
    for t in tracks:
        out+=b"MTrk"+struct.pack(">I",len(t))+t
    return bytes(out)

if __name__=="__main__":
    import sys,os,glob
    # test: convert a few Lieder mxl, count note-ons vs <note><pitch> in xml
    files=glob.glob("/mnt/volume1/music-db/raw/Lieder/scores/**/*.mxl",recursive=True)[:5]
    for f in files:
        data=open(f,"rb").read()
        try:
            midi=mxl_to_midi(data)
            # count note-ons in output
            ons=midi.count(0x90) # rough (status bytes across channels vary) - better parse
            xml=_root_xml(data); r=ET.fromstring(xml)
            xnotes=sum(1 for n in r.iter() if _tag(n)=="note" and any(_tag(c)=="pitch" for c in n))
            print(f"{os.path.basename(f):22} bytes={len(midi):6} xml_pitched_notes={xnotes}")
        except Exception as e:
            print(f"{os.path.basename(f)}: FAIL {type(e).__name__}: {e}")
