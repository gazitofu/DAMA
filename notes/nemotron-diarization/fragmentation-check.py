import sys,os,json,glob,numpy as np
root=sys.argv[1]; nm=sys.argv[2]; sess=set()
for f in glob.glob(os.path.join(root,'*','runs','*','raw','pyannote-response.json')):
    st=json.load(open(os.path.join(os.path.dirname(os.path.dirname(f)),'state.json')))
    if (st.get('input') or {}).get('transcriptionProvider')=='precision' and os.path.exists(os.path.join(nm,f.split('/')[-5],'meta.json')): sess.add(f.split('/')[-5])
H=R=S=E=0
for s in sess:
    meta=json.load(open(os.path.join(nm,s,'meta.json'))); p=np.fromfile(os.path.join(nm,s,'probs.f32'),dtype=np.float32).reshape(meta['frameCount'],8)>0.5
    H+=meta['durationSeconds']/3600
    for c in range(8):
        dx=np.diff(np.concatenate([[0],p[:,c].astype(np.int8),[0]])); st=np.where(dx==1)[0]; en=np.where(dx==-1)[0]
        R+=len(st); S+=int(((en-st)<20).sum())
    dx=np.diff(np.concatenate([[0],(p.sum(1)==1).astype(np.int8),[0]])); E+=int((dx==1).sum())
print('Nemotron same %d sessions hours %.2f regular/h %.0f exclusive/h %.0f regular<200ms/h %.0f'%(len(sess),H,R/H,E/H,S/H))
