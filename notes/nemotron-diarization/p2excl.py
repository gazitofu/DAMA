import json,sys,glob,os
root=sys.argv[1]; tot_ov=tot_cov=0; n=0
for f in glob.glob(os.path.join(root,'*','runs','*','raw','pyannote-response.json')):
    st=json.load(open(os.path.join(os.path.dirname(os.path.dirname(f)),'state.json')))
    if (st.get('input') or {}).get('transcriptionProvider')!='precision': continue
    o=json.load(open(f))['output']; reg=o['diarization']; ex=o.get('exclusiveDiarization') or []
    # 10ms grid
    end=int(max(x['end'] for x in reg)*100)+1
    cnt=[0]*end; exc=[0]*end
    for x in reg:
        for i in range(int(x['start']*100),int(x['end']*100)): cnt[i]+=1
    for x in ex:
        for i in range(int(x['start']*100),min(end,int(x['end']*100))): exc[i]+=1
    ov=[i for i in range(end) if cnt[i]>=2]; cov=sum(1 for i in ov if exc[i]==1)
    tot_ov+=len(ov); tot_cov+=cov; n+=1
    # does exclusive pick the speaker active in regular? sample check speakers
print('P2 runs',n,'regular-overlap frames',tot_ov,'covered by exactly one exclusive speaker: %.1f%%'%(100*tot_cov/max(1,tot_ov)))
