import json,sys,numpy as np,collections
run=sys.argv[1]
doc=json.load(open(run+'/normalized/model.json')); meta=json.load(open(run+'/raw/nemotron-meta.json'))
p=np.fromfile(run+'/raw/nemotron-probabilities.f32',dtype='<f4').reshape(meta['frameCount'],8)
spk={s['id']:int(s['providerId'].split('-')[1]) for s in doc['speakers']}
words=doc['words']; lex=[i for i,w in enumerate(words) if w['tokenKind']=='lexical']
pairs=collections.Counter(); margins=[]; agree=0; ovl=[]
for k,i in enumerate(lex):
    w=words[i]
    if w['speakerId'] is not None or w['startUs'] is None or w['endUs'] is None or w['startUs']>=w['endUs']: continue
    f0=w['startUs']//10000; f1=max(f0+1,-(-w['endUs']//10000)); seg=p[f0:f1]; act=seg>0.5
    if not ((act.sum(1)>=2).all()): continue
    mean=seg.mean(0); order=np.argsort(-mean); top,sec=order[0],order[1]
    pairs[tuple(sorted((int(top),int(sec))))]+=1; margins.append(mean[top]-mean[sec])
    # neighbours: nearest assigned lexical before/after
    prev=next((words[j]['speakerId'] for j in reversed(lex[:k]) if words[j]['speakerId']),None)
    nxt=next((words[j]['speakerId'] for j in lex[k+1:] if words[j]['speakerId']),None)
    ovl.append((top,prev,nxt))
print('overlap-only unassigned',len(margins))
print('top channel pairs',pairs.most_common(6))
m=np.array(margins)
for t in (0.05,0.1,0.2,0.3,0.5): print('mean-prob margin >= %.2f: %d (%.0f%%)'%(t,(m>=t).sum(),100*(m>=t).mean()))
same=sum(1 for top,a,b in ovl if a and b and a==b and spk[a]==top)
print('top channel equals both neighbour speakers (same on both sides):',same)
both=sum(1 for top,a,b in ovl if a and b and a==b)
print('neighbours agree with each other:',both)
# overall overlap frame share
act=p>0.5; print('frames with 2+ active: %.1f%% of frames with any active'%(100*(act.sum(1)>=2).sum()/max(1,(act.sum(1)>=1).sum())))
