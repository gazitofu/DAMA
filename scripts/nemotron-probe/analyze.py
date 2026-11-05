"""Compare stored Nemotron-3 probabilities with stored Soniox tokens and Precision-2 intervals.

Offline only (2026-10-30). Reads the app's run folders and the probe output; writes counts,
times and IDs only. Transcript text is read solely to tell punctuation from lexical tokens and
is never written. Usage: python3 -I analyze.py <SessionsDir> <probeOutDir>
"""
import array
import glob
import json
import math
import os
import sys
import unicodedata
from collections import Counter, defaultdict

THRESHOLD = 0.5  # FluidAudio/NeMo default binarization, not tuned for Korean.
CH = 8
FRAME_MS = 10


def lexical(text):
    return any(unicodedata.category(c)[0] in "LN" for c in text)


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def runs(session_dir):
    out = []
    for run in glob.glob(os.path.join(session_dir, "runs", "*")):
        try:
            st = load_json(os.path.join(run, "state.json"))
        except Exception:
            continue
        out.append((st.get("createdAt") or "", run, st))
    return sorted(out)


def shares(counter):
    tot = sum(counter.values()) or 1
    return sorted((round(100 * v / tot, 1) for v in counter.values()), reverse=True)


def p2_choice(start, end, exclusive):
    """Largest exclusive overlap; ties or none -> None (same spirit as soniox-p2-timeline-v3)."""
    if end <= start:
        hits = [s for (a, b, s) in exclusive if a <= start < b]
        return hits[0] if len(set(hits)) == 1 else None
    cov = defaultdict(float)
    for a, b, s in exclusive:
        o = min(b, end) - max(a, start)
        if o > 0:
            cov[s] += o
    if not cov:
        return None
    best = sorted(cov.items(), key=lambda x: -x[1])
    if len(best) > 1 and math.isclose(best[0][1], best[1][1]):
        return None
    return best[0][0]


def nemo_choice(start_ms, end_ms, probs, frames):
    lo = max(0, min(frames - 1, start_ms // FRAME_MS))
    hi = max(lo + 1, min(frames, -(-end_ms // FRAME_MS)))
    means = [0.0] * CH
    for f in range(lo, hi):
        base = f * CH
        for c in range(CH):
            means[c] += probs[base + c]
    n = hi - lo
    active = [c for c in range(CH) if means[c] / n > THRESHOLD]
    if len(active) == 1:
        return active[0], "assigned"
    return None, ("overlap" if active else "silence")


def greedy_agreement(pairs):
    table = Counter(pairs)
    used_a, used_b, agree = set(), set(), 0
    for (a, b), n in table.most_common():
        if a in used_a or b in used_b:
            continue
        used_a.add(a); used_b.add(b); agree += n
    total = sum(table.values())
    return (round(100 * agree / total, 1) if total else None), total


def spread(pairs, key_index):
    """For each label on one side, how its tokens spread over labels on the other side."""
    by = defaultdict(Counter)
    for p in pairs:
        by[p[key_index]][p[1 - key_index]] += 1
    out = {}
    for k, c in by.items():
        tot = sum(c.values())
        out[str(k)] = [round(100 * v / tot, 1) for _, v in c.most_common(3)] + [tot]
    return out


def analyze(session_dir, probe_dir):
    meta = load_json(os.path.join(probe_dir, "meta.json"))
    probs = array.array("f")
    with open(os.path.join(probe_dir, "probs.f32"), "rb") as f:
        probs.frombytes(f.read())
    frames = meta["frameCount"]
    assert len(probs) == frames * CH

    active = [0] * CH
    quarters = [[0] * 4 for _ in range(CH)]
    first = [None] * CH
    last = [None] * CH
    for fr in range(frames):
        q = min(3, 4 * fr // frames)
        base = fr * CH
        for c in range(CH):
            if probs[base + c] > THRESHOLD:
                active[c] += 1
                quarters[c][q] += 1
                if first[c] is None:
                    first[c] = fr
                last[c] = fr
    total_active = sum(active) or 1
    channels = [
        {
            "ch": c,
            "activeSeconds": round(active[c] * FRAME_MS / 1000, 1),
            "share": round(100 * active[c] / total_active, 1),
            "firstSeconds": None if first[c] is None else round(first[c] * FRAME_MS / 1000, 1),
            "lastSeconds": None if last[c] is None else round(last[c] * FRAME_MS / 1000, 1),
            "quarterSeconds": [round(x * FRAME_MS / 1000) for x in quarters[c]],
        }
        for c in range(CH) if active[c] > 0
    ]

    expected, soniox, p2, p2_req, hashes = None, None, None, None, set()
    for _, run, st in runs(session_dir):
        if st.get("sourceAudioSHA256"):
            hashes.add(st["sourceAudioSHA256"])
        inp = st.get("input") or {}
        if inp.get("speakerCount"):
            expected = inp["speakerCount"]
        s = os.path.join(run, "raw", "soniox-response.json")
        p = os.path.join(run, "raw", "pyannote-response.json")
        if os.path.exists(s):
            soniox = s
        if os.path.exists(p):
            out = (load_json(p).get("output") or {})
            if out.get("exclusiveDiarization"):
                p2 = out["exclusiveDiarization"]
                try:
                    p2_req = load_json(os.path.join(run, "request.json")).get("numSpeakers")
                except Exception:
                    pass

    result = {
        "session": os.path.basename(session_dir)[:8],
        "durationMin": round(meta["durationSeconds"] / 60, 1),
        "processingSeconds": round(meta["processingSeconds"], 1),
        "audioHashMatchesRuns": (meta["audioSHA256"] in hashes) if hashes else None,
        "expected": expected,
        "nemotronChannels": len(channels),
        "nemotronShares": sorted((c["share"] for c in channels), reverse=True),
        "channels": channels,
    }
    exclusive = None
    if p2:
        exclusive = [(x["start"] * 1000, x["end"] * 1000, x["speaker"]) for x in p2]
        dur = Counter()
        for a, b, s in exclusive:
            dur[s] += b - a
        result["p2Requested"] = p2_req
        result["p2Speakers"] = len(dur)
        result["p2Shares"] = shares(dur)
    if not soniox:
        return result

    tokens = load_json(soniox).get("tokens") or []
    sp = Counter(t["speaker"] for t in tokens if t.get("speaker") is not None)
    result["sonioxSpeakers"] = len(sp)
    result["sonioxShares"] = shares(sp)
    status = Counter()
    nem_vs_p2, nem_vs_son = [], []
    p2_null = 0
    lex = 0
    for t in tokens:
        if not lexical(t.get("text") or ""):
            continue
        s, e = t.get("start_ms"), t.get("end_ms")
        if s is None or e is None or e < s:
            status["invalidTime"] += 1
            continue
        lex += 1
        n, why = nemo_choice(s, e, probs, frames)
        status[why] += 1
        if t.get("speaker") is not None and n is not None:
            nem_vs_son.append((n, t["speaker"]))
        if exclusive is not None:
            p = p2_choice(s, e, exclusive)
            if p is None:
                p2_null += 1
            elif n is not None:
                nem_vs_p2.append((n, p))
    result["lexicalTokens"] = lex
    result["nemotronTokenStatus"] = {k: round(100 * v / (lex or 1), 1) for k, v in status.items()}
    if exclusive is not None:
        result["p2NullPercent"] = round(100 * p2_null / (lex or 1), 1)
        result["agreeNemotronP2"], result["bothAssigned"] = greedy_agreement(nem_vs_p2)
        result["p2SpeakerOverNemotron"] = spread(nem_vs_p2, 1)
        result["nemotronOverP2"] = spread(nem_vs_p2, 0)
    result["agreeNemotronSoniox"], _ = greedy_agreement(nem_vs_son)
    return result


def main():
    sessions_dir, out_dir = sys.argv[1], sys.argv[2]
    results = []
    for probe_dir in sorted(glob.glob(os.path.join(out_dir, "*", "meta.json"))):
        probe_dir = os.path.dirname(probe_dir)
        sid = os.path.basename(probe_dir)
        session = os.path.join(sessions_dir, sid)
        if os.path.isdir(session):
            results.append(analyze(session, probe_dir))
    with open(os.path.join(out_dir, "summary.json"), "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=1)
    rows = ["| 세션 | 길이(분) | 예상 | Soniox | P2(요청) | Nemotron | Nemotron 비중 | 단어 일치 N-P2 | 단어 일치 N-Soniox | N 미배정(무음/겹침) |",
            "|---|---|---|---|---|---|---|---|---|---|"]
    for r in sorted(results, key=lambda r: r["session"]):
        st = r.get("nemotronTokenStatus") or {}
        rows.append("| {s} | {d} | {e} | {so} | {p2} | {n} | {ns} | {a1} | {a2} | {sil}/{ov} |".format(
            s=r["session"], d=r["durationMin"], e=r["expected"], so=r.get("sonioxSpeakers", "-"),
            p2=f'{r["p2Speakers"]}({r["p2Requested"]})' if "p2Speakers" in r else "-",
            n=r["nemotronChannels"], ns=r["nemotronShares"], a1=r.get("agreeNemotronP2", "-"),
            a2=r.get("agreeNemotronSoniox", "-"), sil=st.get("silence", "-"), ov=st.get("overlap", "-")))
    with open(os.path.join(out_dir, "summary.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(rows) + "\n")
    print("\n".join(rows))


if __name__ == "__main__":
    main()
