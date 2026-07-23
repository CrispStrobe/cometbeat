"""Mutopia ship-tier life+70 — thin wrapper over shared wikidata_deaths. Mutopia
author tokens are `SurnameInitials` (SchubertF, BachJS) -> split to a surname
before resolving. Occupation bar = ARTS. NO_AUTHOR for Traditional/Anonymous."""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wikidata_deaths as wd
NO_AUTHOR = {"traditional", "anonymous", "unknown", ""}
def split_token(tok):
    m = re.match(r"^([A-Z][a-z]+(?:[A-Z][a-z]+)?)([A-Z][a-zA-Z]*)$", tok)
    if m:
        return re.sub(r"(?<!^)(?=[A-Z])", " ", m.group(1)).strip()
    return tok
def classify(tok):
    if tok.strip().lower() in NO_AUTHOR: return ("NO_AUTHOR", None, None, None, None)
    return wd.verdict(split_token(tok), occ_bar=wd.ARTS)
if __name__ == "__main__":
    toks = json.load(open("/tmp/mutopia_authors.json")) if os.path.exists("/tmp/mutopia_authors.json") else {}
    out = {}
    for t in toks:
        out[t] = dict(zip(("status", "qid", "label", "birth", "death"), classify(t)))
    wd.save(); json.dump(out, open("/tmp/mutopia_classify.json", "w"), ensure_ascii=False)
    from collections import Counter
    print("MUTOPIA DONE:", dict(Counter(v["status"] for v in out.values())), flush=True)
