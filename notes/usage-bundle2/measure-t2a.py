"""T2a 실측 (메타데이터만). 제목·본문·이름 출력 없음. ID는 앞 8자.
사용: python3 -I notes/usage-bundle2/measure-t2a.py <internal_root> <scripts_dir> <out_json>
"""
import json, os, sys, glob, time, zlib, collections

root, scripts_dir, out = sys.argv[1], sys.argv[2], sys.argv[3]
EPOCH2001 = 978307200

def short(x):
    return (x or '')[:8]

# 1. runs
runs = {}
for p in glob.glob(os.path.join(root, 'Sessions', '*', 'runs', '*', 'state.json')):
    try:
        r = json.load(open(p))
    except Exception:
        continue
    inp = r.get('input') or {}
    runs[r['id']] = dict(id=r['id'], sid=r.get('sessionID'), stage=r.get('stage'), parent=r.get('parentRunID'),
                         soniox=r.get('sonioxRunID'), precision=r.get('precisionRunID'), nemotron=r.get('nemotronRunID'),
                         provider=inp.get('transcriptionProvider') or 'pyannote', created=r.get('createdAt'),
                         sonioxSource=inp.get('sonioxSourceRunID'), precisionSource=inp.get('precisionSourceRunID'),
                         qwenDiar=inp.get('qwenDiarizationRunID'))

HUMAN_KEYS = ['turnTexts', 'turnNames', 'turnSpeakerIDs', 'registeredSpeakers', 'deletedParagraphs',
              'paragraphBreaks', 'paragraphEdits', 'reviewRecords', 'nameHistory']

def legacy_human(transcript):
    n = 0
    for t in transcript.get('turns', []) or []:
        if t.get('humanEdited'):
            n += 1
    for w in transcript.get('words', []) or []:
        if w.get('editedText') is not None:
            n += 1
    return n

# 2. scripts
scripts = {}
for p in glob.glob(os.path.join(scripts_dir, '*.dama.json')):
    size = os.path.getsize(p)
    s = json.load(open(p))
    tr = s.get('transcript') or {}
    human = {k: len(s.get(k) or {}) for k in HUMAN_KEYS if s.get(k)}
    lh = legacy_human(tr)
    if lh:
        human['legacy'] = lh
    corr = s.get('correction')
    scripts[s['id']] = dict(id=s['id'], sid=tr.get('sessionId'), engine=(tr.get('provenance') or {}).get('engine'),
                            created=s.get('createdAt'), size=size, human=human,
                            versions=[v.get('revisionID') for v in (s.get('versions') or [])],
                            versionHashes={v.get('revisionID'): v.get('sha256') for v in (s.get('versions') or [])},
                            correction=(corr or {}).get('state'), revisionID=s.get('revisionID'),
                            baseRevs=[e.get('baseRevisionID') for e in (s.get('paragraphEdits') or [])])

# 3. generations per session
def members(run):
    ids = {run['id']}
    for k in ('soniox', 'sonioxSource'):
        if run.get(k):
            ids.add(run[k])
    return ids

sessions = collections.defaultdict(lambda: dict(scripts=[], gens=[]))
for s in scripts.values():
    sessions[s['sid']]['scripts'].append(s['id'])
for r in runs.values():
    if r['parent'] is None and r['stage'] == 'readyForReview' and r['id'] in scripts:
        sessions[r['sid']]['gens'].append(r['id'])

keep_ids, delete_ids, unclassified = set(), set(), set()
per_session = []
for sid, d in sessions.items():
    gens = sorted(d['gens'], key=lambda g: scripts[g]['created'], reverse=True)
    kept = gens[:2]
    kept_members = set().union(*[members(runs[g]) for g in kept]) if kept else set()
    old_members = set().union(*[members(runs[g]) for g in gens[2:]]) if gens[2:] else set()
    sids = set(d['scripts'])
    for x in sids:
        if x in kept_members:
            keep_ids.add(x)
        elif x in old_members:
            if scripts[x]['human']:
                keep_ids.add(x)
            else:
                delete_ids.add(x)
        else:
            unclassified.add(x)
    per_session.append(dict(sid=short(sid), scripts=len(sids), gens=len(gens),
                            delete=len(sids & delete_ids), unclassified=len(sids & unclassified),
                            human=sum(1 for x in sids if scripts[x]['human'])))

# 4. revisions
rev_dir = os.path.join(root, 'LibraryRevisions')
rev_files = sorted(glob.glob(os.path.join(rev_dir, '*.dama.json')))
t0 = time.time()
revs = {}
for p in rev_files:
    size = os.path.getsize(p)
    s = json.load(open(p))
    revs[os.path.basename(p).split('.')[0]] = dict(script=s.get('id'), size=size, snapshot=s.get('snapshotTitle') is not None)
decode_s = time.time() - t0

existing = set(scripts)
orphan = {k: v for k, v in revs.items() if v['script'] not in existing}
live = {k: v for k, v in revs.items() if v['script'] in existing}
of_deleted_by_rule = {k: v for k, v in live.items() if v['script'] in delete_ids}
remaining = {k: v for k, v in live.items() if v['script'] not in delete_ids}
version_refs = set(r for s in scripts.values() for r in s['versions'])
base_refs = set(r for s in scripts.values() for r in s['baseRevs'] if r)
active_refs = set(s['revisionID'] for s in scripts.values())

# 5. compression sample over remaining (zlib level 5 = Apple COMPRESSION_ZLIB level; raw deflate)
t1 = time.time()
comp_total = 0
raw_total = 0
for k, v in remaining.items():
    data = open(os.path.join(rev_dir, k + '.dama.json'), 'rb').read()
    c = zlib.compressobj(5, zlib.DEFLATED, -15)
    comp = c.compress(data) + c.flush()
    assert zlib.decompress(comp, -15) == data
    comp_total += len(comp)
    raw_total += len(data)
comp_s = time.time() - t1

def mb(n):
    return round(n / 1e6, 1)

res = dict(
    measured_at=time.strftime('%Y-%m-%dT%H:%M:%S%z'),
    runs=len(runs), runs_top_ready=sum(1 for r in runs.values() if r['parent'] is None and r['stage'] == 'readyForReview'),
    scripts=len(scripts), scripts_mb=mb(sum(s['size'] for s in scripts.values())),
    scripts_without_run=sum(1 for s in scripts if s not in runs),
    scripts_human=sum(1 for s in scripts.values() if s['human']),
    human_field_counts=collections.Counter(k for s in scripts.values() for k in s['human']),
    scripts_with_versions=sum(1 for s in scripts.values() if s['versions']),
    engines=collections.Counter(s['engine'] for s in scripts.values()),
    sessions_with_scripts=len(sessions), sessions_gt2_gens=sum(1 for p in per_session if p['gens'] > 2),
    rule_delete_scripts=len(delete_ids), rule_delete_mb=mb(sum(scripts[x]['size'] for x in delete_ids)),
    rule_keep_scripts=len(keep_ids), rule_unclassified_scripts=len(unclassified),
    rule_kept_by_human=sum(1 for x in keep_ids if scripts[x]['human']),
    per_session=sorted(per_session, key=lambda p: -p['scripts']),
    revisions=len(revs), revisions_mb=mb(sum(v['size'] for v in revs.values())), revision_decode_s=round(decode_s, 1),
    revisions_snapshots=sum(1 for v in revs.values() if v['snapshot']),
    orphan_revisions=len(orphan), orphan_mb=mb(sum(v['size'] for v in orphan.values())),
    orphan_scripts=len(set(v['script'] for v in orphan.values())),
    revisions_of_rule_deleted=len(of_deleted_by_rule), revisions_of_rule_deleted_mb=mb(sum(v['size'] for v in of_deleted_by_rule.values())),
    remaining_revisions=len(remaining), remaining_mb=mb(raw_total),
    remaining_zlib5_mb=mb(comp_total), zlib_ratio=round(raw_total / comp_total, 2) if comp_total else None, compress_s=round(comp_s, 1),
    version_refs=len(version_refs), version_refs_present=len(version_refs & set(revs)),
    base_refs=len(base_refs), base_refs_present=len(base_refs & set(revs)),
    active_rev_present=len(active_refs & set(revs)),
    per_script_revisions_max=max(collections.Counter(v['script'] for v in remaining.values()).values() or [0]),
)
json.dump(res, open(out, 'w'), ensure_ascii=False, indent=1, default=list)
print(json.dumps({k: v for k, v in res.items() if k != 'per_session'}, ensure_ascii=False, default=list))
