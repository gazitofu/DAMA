# r3 (nemotron-diarization, 2026-10-30): simulate the r3 split-어절 neighbour rule on stored v2 documents. Reads only.
# Usage: python3 -I word-unify-sim.py <folder of v2 normalized JSON documents> [totals.json]
# Self-check: recomputed v2 provider_disagreement and unrepresented_speaker must equal each document's issue counts.
# Variant "keep-nil": unify assigned fragments only; "fill-nil": also give the 어절's unassigned fragments the speaker.
import json,sys,glob,collections
END=set(".?!。？！…")
CLOSING=set(".,?!。？！…，、:;\"'”’)]}」』") | {" "}
def groups(ws):
    G=[];cur=[]
    for k,w in enumerate(ws):
        t=w["prefix"]+w["text"]
        if (t[:1].isspace() or "\n" in t) and cur: G.append(cur);cur=[]
        cur.append(k)
        if t[-1:].isspace(): G.append(cur);cur=[]
    if cur: G.append(cur)
    return G
def metrics(ws,sp,diar):
    lex=[k for k,w in enumerate(ws) if w["tokenKind"]=="lexical"]
    un=sum(sp[k] is None for k in lex)
    pd=0;prev=None
    for k in lex:
        a=ws[k]["asrSpeakerLabel"];b=sp[k]
        if a is None or b is None: prev=None;continue
        if prev is not None and ((a!=ws[prev]["asrSpeakerLabel"])!=(b!=sp[prev])): pd+=1
        prev=k
    split=0
    for g in groups(ws):
        L=[k for k in g if ws[k]["tokenKind"]=="lexical"]
        if len({sp[k] for k in L if sp[k] is not None})>1: split+=1
    # unrepresented: regular intervals with overlapping lexical words but none of their speaker
    starts=sorted((ws[k]["startUs"],ws[k]["endUs"],k) for k in lex if ws[k]["startUs"] is not None and ws[k]["endUs"] is not None)
    import bisect
    keys=[s for s,_,_ in starts]; unrep=0
    for d in diar:
        i=bisect.bisect_left(keys,d["startUs"]-60_000_000); m=[]
        for s,e,k in starts[i:]:
            if s>=d["endUs"]: break
            hit = (d["startUs"]<=s<d["endUs"]) if s==e else (max(s,d["startUs"])<min(e,d["endUs"]))
            if hit: m.append(k)
        if m and not any(sp[k]==d["speakerId"] for k in m): unrep+=1
    return dict(lexical=len(lex),unassigned=un,disagreement=pd,split=split,unrepresented=unrep)
def apply(ws,sp,fill,prevOnly=False):
    G=[g for g in groups(ws) if any(ws[k]["tokenKind"]=="lexical" for k in g)]
    info=[]
    for g in G:
        L=[k for k in g if ws[k]["tokenKind"]=="lexical"]
        s={sp[k] for k in L}; a={ws[k]["asrSpeakerLabel"] for k in L}
        info.append(dict(L=L,g=g,one=(next(iter(s)) if len(s)==1 else None),asr=(next(iter(a)) if len(a)==1 else None),
            end=any(c in END for k in g for c in ws[k]["text"]) or any("\n" in ws[k]["prefix"]+ws[k]["text"] for k in g),
            split=len({sp[k] for k in L if sp[k] is not None})>1))
    new=list(sp); changed=0; decided=0
    for n,e in enumerate(info):
        if not e["split"] or e["asr"] is None: continue
        cand=[]
        if n>0 and not info[n-1]["end"]: cand.append(info[n-1])
        if n+1<len(info) and not e["end"] and not prevOnly: cand.append(info[n+1])
        cand=[x for x in cand if x["one"] is not None and x["asr"]==e["asr"]]
        s={x["one"] for x in cand}
        if len(s)!=1: continue
        who=next(iter(s)); decided+=1
        for k in e["L"]:
            if sp[k] is None and not fill: continue
            if new[k]!=who: changed+=1; new[k]=who
    # closing punctuation follows the preceding lexical token
    last=None
    for k,w in enumerate(ws):
        t=w["prefix"]+w["text"]
        if "\n" in t or "\r" in t: last=None
        if w["tokenKind"]=="lexical": last=k; continue
        if t and all(c in CLOSING for c in t) and last is not None: new[k]=new[last]
    return new,changed,decided
tot=collections.defaultdict(collections.Counter)
for f in sorted(glob.glob(sys.argv[1]+"/*.json")):
    d=json.load(open(f)); ws=d["words"]; sp=[w["speakerId"] for w in ws]
    base=metrics(ws,sp,d["diarization"])
    docpd=sum(i["kind"]=="provider_disagreement" for i in d["reviewIssues"]); docun=sum(i["kind"]=="unrepresented_speaker" for i in d["reviewIssues"])
    assert base["disagreement"]==docpd and base["unrepresented"]==docun, (f,base,docpd,docun)
    row=[f.split("/")[-1][:8], "v2", base]
    tot["v2"].update(base)
    for fill,prevOnly in ((False,False),(True,False),(False,True)):
        new,ch,dec=apply(ws,sp,fill,prevOnly); m=metrics(ws,new,d["diarization"]); m["changedLexical"]=ch; m["decided"]=dec
        tag=("fill-nil" if fill else "keep-nil")+("/prev-only" if prevOnly else "/both"); tot[tag].update(m); row.append((tag,m))
    print(row)
print("\nTOTAL")
for k,v in tot.items(): print(k, dict(v))
if len(sys.argv)>2:
    out={"v2":dict(tot["v2"]),"both":dict(tot["keep-nil/both"]),"prev":dict(tot["keep-nil/prev-only"]),"fill":dict(tot["fill-nil/both"]),"files":len(glob.glob(sys.argv[1]+"/*.json"))}
    out["fill"]["unassigned_delta"]=out["both"]["unassigned"]-out["fill"]["unassigned"]
    json.dump(out,open(sys.argv[2],"w"),indent=1)
