import json,sys,numpy as np,collections
run=sys.argv[1]
doc=json.load(open(run+'/normalized/model.json')); meta=json.load(open(run+'/raw/nemotron-meta.json'))
p=np.fromfile(run+'/raw/nemotron-probabilities.f32',dtype='<f4').reshape(meta['frameCount'],8)
issues={i['id']:i['kind'] for i in doc['reviewIssues']}
lex=[w for w in doc['words'] if w['tokenKind']=='lexical']
un=[w for w in lex if w['speakerId'] is None]
print('lexical',len(lex),'unassigned',len(un),'(%.2f%%)'%(100*len(un)/len(lex)))
cat=collections.Counter(); maxp=[]
for w in un:
    s,e=w['startUs'],w['endUs']
    if s is None or e is None or s>=e: cat['invalid/zero-length time']+=1; continue
    f0,f1=s//10000,max(s//10000+1,-(-e//10000))
    seg=p[f0:f1]; act=(seg>0.5)
    perframe=act.sum(1)
    kinds=set(issues[i] for i in w['reviewIssueIds'])
    if perframe.max()==0:
        cat['Nemotron silence (no channel > 0.5 over token)']+=1; maxp.append(seg.max())
    elif (perframe==1).sum()==0: cat['only overlap frames (2+ channels)']+=1
    else:
        ch=set(np.nonzero(act[perframe==1])[1])
        cat['exclusive frames of %s channel(s), tie/boundary'%('1' if len(ch)==1 else '2+')]+=1
print(dict(cat))
m=np.array(maxp)
for t in (0.4,0.3,0.2,0.1): print('silence tokens whose max channel prob > %.1f: %d'%(t,(m>t).sum()))
dur=[(w['endUs']-w['startUs'])/1000 for w in un if w['startUs'] is not None and w['endUs'] and w['endUs']>w['startUs']]
print('unassigned token duration ms: median %.0f, p90 %.0f'%(np.median(dur),np.percentile(dur,90)))
# words: fraction of 어절 (prefix-delimited) partially assigned
