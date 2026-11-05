"""Aggregate-only measurement for usage-bundle1 spec. Prints counts, never text.
Usage: python3 -I measure-b1.py <Scripts dir> <library-index.json>
       python3 -I measure-b1.py --selftest
Reads user files read-only. Never prints transcript or title text.
"""
import json, os, re, sys, collections

SELFTEST = len(sys.argv) > 1 and sys.argv[1] == "--selftest"
if not SELFTEST:
    scripts_dir, index_path = sys.argv[1], sys.argv[2]

DIGIT_MAG = set("0123456789십백천만억조")
UNITS = ["%", "퍼센트", "프로", "원", "달러", "불", "엔", "유로", "위안", "배",
         "kwh", "kw", "mwh", "mw", "gwh", "gw", "kg", "mg", "km", "cm", "mm", "톤",
         "명", "개월", "개", "건", "년", "시간", "분기"]
UNITS.sort(key=len, reverse=True)
NEG_SUB = ["않", "없", "아니", "아닌", "아냐", "아님", "말고", "마세요", "마라", "말아", "못"]
NEG_TOK_PREFIX = ["안되", "안돼", "안해", "안했", "안하", "못하", "못해", "못했"]
NEG_TOK = {"안", "못"}
EN_NEG = {"not", "no", "never"}
COND_SUB = ["면", "거든", "경우", "만약", "만일", "조건", "한해", "한하여", "한정", "이상", "이하", "미만", "초과", "까지", "부터", "전제"]
EN_COND = {"if", "unless"}


def num_sig(s):
    t = re.sub(r"\s", "", s).replace(",", "")
    out = []
    for i, c in enumerate(t):
        if c in DIGIT_MAG:
            out.append(c)
        elif c == "." and 0 < i < len(t) - 1 and t[i-1].isdigit() and t[i+1].isdigit():
            out.append(c)
    return "".join(out)


def unit_sig(s):
    t = s.replace(",", "")
    out = []
    i = 0
    low = t.lower()
    while i < len(t):
        if t[i] in DIGIT_MAG:
            j = i
            while j < len(t) and (t[j] in DIGIT_MAG or t[j] == "."):
                j += 1
            k = j
            if k < len(t) and t[k] == " ":
                k += 1
            unit = next((u for u in UNITS if low.startswith(u, k)), "")
            out.append(unit)
            i = j
        else:
            i += 1
    return tuple(out)


def neg_sig(s):
    c = collections.Counter()
    t = re.sub(r"\s", "", s)
    for m in NEG_SUB:
        c[m] = t.count(m)
    c["word-start-an"] = len(re.findall(r"(?<![\w])안", s))
    for tok in s.split():
        lw = tok.strip(".,?!~\"'()[]").lower()
        if lw in EN_NEG or lw.endswith("n't"):
            c["en:" + lw] += 1
    return {k: v for k, v in c.items() if v}


def cond_sig(s):
    t = re.sub(r"\s", "", s)
    c = {m: t.count(m) for m in COND_SUB if t.count(m)}
    for tok in s.split():
        lw = tok.strip(".,?!~\"'()[]").lower()
        if lw in EN_COND:
            c["en:" + lw] = c.get("en:" + lw, 0) + 1
    return c


def canon(s):
    # Mirrors ContextCorrection.canonicalFormat (ScriptCorrection.swift:221) on the change text.
    v = s.strip()
    v = re.sub(r"(?<![0-9.,])([0-9]{1,3})(?: *, *[0-9]{3})+(?![0-9.,]| +[0-9,])", lambda m: m.group(0).replace(" ", ""), v)
    v = re.sub(r"(?<![\w])안 *(되니까|되는데|해도)(?![\w])", r"안\1", v)
    v = re.sub(r"(?<=[0-9])([조억만천백]) +원", r"\1원", v)
    return v


if SELFTEST:
    # Positive (hold) 7 and negative (pass) 4 pairs from the spec §02-4 table.
    pairs = [("삼십억", "30억", True), ("1.5배", "15배", True), ("30억원", "30억 달러", True), ("10%", "10퍼센트", True),
             ("안 됩니다", "됩니다", True), ("할 수 없다", "할 수 있다", True), ("하면 된다", "하고 된다", True),
             ("1 ,000억", "1,000억", False), ("에스엠알", "SMR", False), ("안 되니까", "안되니까", False), ("측면", "측면에서", False)]
    ok = 0
    for q, r, hold in pairs:
        held = canon(q) != canon(r) and any(f(q) != f(r) for f in (num_sig, unit_sig, neg_sig, cond_sig))
        ok += held == hold
        print(q, "->", r, "held" if held else "pass", "OK" if held == hold else "MISMATCH")
    print(f"selftest {ok}/{len(pairs)}")
    sys.exit(0 if ok == len(pairs) else 1)

totals = collections.Counter()
per_corr = []
for name in sorted(os.listdir(scripts_dir)):
    if not name.endswith(".dama.json"):
        continue
    with open(os.path.join(scripts_dir, name), "rb") as f:
        doc = json.load(f)
    corr = doc.get("correction")
    if not corr:
        continue
    totals["corrections:" + corr.get("state", "?")] += 1
    if corr.get("state") != "completed":
        continue
    c = collections.Counter()
    for edit in corr.get("edits", []):
        for d in edit.get("changes") or []:
            ch = d["change"]
            q, r = ch["quote"], ch["replacement"]
            c["changes"] += 1
            if not d.get("applied"):
                c["held_existing"] += 1
                continue
            c["applied"] += 1
            if canon(q) == canon(r):
                c["format_equal"] += 1
                continue
            hits = []
            if num_sig(q) != num_sig(r):
                hits.append("number")
            if unit_sig(q) != unit_sig(r):
                hits.append("unit")
            if neg_sig(q) != neg_sig(r):
                hits.append("negation")
            if cond_sig(q) != cond_sig(r):
                hits.append("condition")
            if hits:
                c["would_hold"] += 1
                for h in hits:
                    c["hit_" + h] += 1
        if edit.get("changes") is None:
            c["legacy_edits"] += 1
    per_corr.append(dict(c))

print("correction states:", dict(t for t in totals.items()))
print("completed corrections (new-format counts):")
for i, c in enumerate(per_corr):
    print(" ", i, c)
agg = collections.Counter()
for c in per_corr:
    agg.update(c)
print("aggregate:", {k: agg.get(k, 0) for k in ["changes", "applied", "held_existing", "format_equal", "would_hold", "hit_number", "hit_unit", "hit_negation", "hit_condition"]})

# Title linkage (counts only)
with open(index_path, "rb") as f:
    index = json.load(f)
speech_title = {e["id"]: e["title"] for e in index}
by_session = collections.defaultdict(list)
for name in sorted(os.listdir(scripts_dir)):
    if not name.endswith(".dama.json"):
        continue
    with open(os.path.join(scripts_dir, name), "rb") as f:
        doc = json.load(f)
    by_session[doc["transcript"]["sessionId"]].append(doc["title"])
linked = {s: t for s, t in by_session.items() if s in speech_title}
print("index entries:", len(index), "script sessions:", len(by_session), "linked sessions:", len(linked),
      "unlinked script sessions:", len(by_session) - len(linked))
print("scripts per linked session:", dict(collections.Counter(len(v) for v in linked.values())))
renamed_sessions = sum(1 for s, ts in linked.items() if any(t != speech_title[s] for t in ts))
divergent = sum(1 for s, ts in linked.items() if len(set(ts)) > 1)
print("linked sessions with any script title != speech title:", renamed_sessions)
print("linked sessions whose scripts disagree among themselves:", divergent)
print("index entries having keys:", sorted(set(k for e in index for k in e.keys())))
