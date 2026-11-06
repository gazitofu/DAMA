"""T2a 보관 규칙 시뮬레이션 (메타데이터만, 쓰기 없음). 사용: python3 -I notes/usage-bundle2/retention-sim.py <internal_root> <scripts_dir> [keep=2]"""
import json, os, glob, sys
from collections import defaultdict

root, sdir = sys.argv[1], sys.argv[2]
KEEP = int(sys.argv[3]) if len(sys.argv) > 3 else 2
HUMAN = ['turnTexts', 'turnNames', 'turnSpeakerIDs', 'registeredSpeakers', 'deletedParagraphs',
         'paragraphBreaks', 'paragraphEdits', 'reviewRecords', 'nameHistory']

runs = {}
for p in glob.glob(os.path.join(root, 'Sessions', '*', 'runs', '*', 'state.json')):
    r = json.load(open(p)); runs[r['id']] = r
scripts = {}
for p in glob.glob(os.path.join(sdir, '*.dama.json')):
    s = json.load(open(p))
    tr = s['transcript']
    legacy = any(t.get('humanEdited') for t in tr.get('turns') or []) or any(w.get('editedText') is not None for w in tr.get('words') or [])
    scripts[s['id']] = dict(sid=tr['sessionId'], created=s['createdAt'], size=os.path.getsize(p),
                            human=legacy or any(s.get(k) for k in HUMAN))

def is_child(i):
    return i in runs and runs[i].get('parentRunID') is not None

by = defaultdict(list)
for i, s in scripts.items():
    by[s['sid']].append(i)

tot_del, tot_mb, rows = 0, 0, []
for sid, ids in by.items():
    present = set(ids)
    primaries = [i for i in ids if not is_child(i)]
    gens = []
    referenced = set()
    for p in primaries:
        mem = {p}
        c = (runs.get(p) or {}).get('sonioxRunID')
        if c and c in present:
            mem.add(c); referenced.add(c)
        gens.append((scripts[p]['created'], p, mem))
    for c in ids:
        if is_child(c) and c not in referenced:
            gens.append((scripts[c]['created'], c, {c}))   # 부모 결과가 없는 자식 = 홀로 선 세대
    gens.sort(key=lambda g: (g[0], [-ord(ch) for ch in g[1]]), reverse=True)
    keep = set().union(*[g[2] for g in gens[:KEEP]]) if gens else set()
    delete = [i for i in ids if i not in keep and not scripts[i]['human']]
    tot_del += len(delete); tot_mb += sum(scripts[i]['size'] for i in delete)
    rows.append((sid[:8], len(ids), len(gens), len(delete), sum(1 for i in ids if i not in keep and scripts[i]['human'])))

print('KEEP', KEEP, 'recordings', len(by), 'delete_scripts', tot_del, 'delete_mb', round(tot_mb / 1e6, 1))
print('rows(sid, scripts, gens, delete, kept_only_by_human)', [r for r in rows if r[2] > KEEP or r[3] or r[4]])
