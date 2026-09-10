#!/usr/bin/env python3
"""Offline contract/regression checks. No audio, API calls, or ASR inference.

Python 3.9+ standard library suffices (measured on 3.9.6). If jsonschema is installed, the full
Draft 2020-12 schema is checked too; otherwise that optional check is reported.
The simple reference matcher is a specification oracle, not production DSP.
"""
from __future__ import annotations
import copy
import json
import math
import re
import sys
import tempfile
import unittest
from collections import Counter
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]


def documentation_paths(root: Path) -> list[Path]:
    # Build products and private diagnostic inputs aren't project documentation.
    return [path for path in root.rglob("*.md")
            if path.relative_to(root).parts[0] not in {".build", "DerivedData", ".git"}]


def load(name: str) -> Any:
    return json.loads((ROOT / name).read_text(encoding="utf-8"))


def intersection(a: int, b: int, c: int, d: int) -> int:
    return max(0, min(b, d) - max(a, c))


def union_length(intervals: list[tuple[int, int]]) -> int:
    total = 0
    current: list[int] | None = None
    for start, end in sorted(intervals):
        if end <= start:
            continue
        if current is None:
            current = [start, end]
        elif start <= current[1]:
            current[1] = max(current[1], end)
        else:
            total += current[1] - current[0]
            current = [start, end]
    return total + (current[1] - current[0] if current else 0)


def valid_time(word: dict[str, Any]) -> bool:
    a, b = word.get("startUs"), word.get("endUs")
    return type(a) is int and type(b) is int and 0 <= a < b


def match_word(word: dict[str, Any], exclusive: list[dict[str, Any]],
               regular: list[dict[str, Any]]) -> dict[str, Any]:
    empty = {"speaker": None, "topCandidate": None, "score": None, "overlap": False}
    if not valid_time(word):
        return empty
    a, b = word["startUs"], word["endUs"]
    per_speaker: dict[str, list[tuple[int, int]]] = {}
    for item in exclusive:
        start, end = max(a, item["startUs"]), min(b, item["endUs"])
        if end > start:
            per_speaker.setdefault(item["speaker"], []).append((start, end))
    scores = [(union_length(parts) / (b - a), speaker)
              for speaker, parts in per_speaker.items()]
    scores.sort(key=lambda x: (-x[0], x[1]))  # Deterministic tie candidate only.
    overlaps = any(
        x["speaker"] != y["speaker"] and
        max(a, x["startUs"], y["startUs"]) < min(b, x["endUs"], y["endUs"])
        for i, x in enumerate(regular) for y in regular[i + 1:]
    )
    if not scores:
        return {**empty, "score": 0.0, "overlap": overlaps}
    first, top = scores[0]
    second = scores[1][0] if len(scores) > 1 else 0.0
    eligible = first >= 0.60 - 1e-12 and first - second >= 0.20 - 1e-12 and not overlaps
    return {"speaker": top if eligible else None, "topCandidate": top,
            "score": first, "overlap": overlaps}


def can_merge(previous: dict[str, Any], current: dict[str, Any],
              diarization: list[dict[str, Any]], max_gap: int = 300_000) -> bool:
    if not valid_time(previous) or not valid_time(current):
        return False
    if previous["speakerId"] != current["speakerId"]:
        return False
    # A missing turn between two words is a barrier even when it has no text.
    if current["startUs"] - previous["endUs"] > max_gap:
        return False
    left, right = min(previous["startUs"], current["startUs"]), max(previous["endUs"], current["endUs"])
    return not any(d["speakerId"] != current["speakerId"] and
                   intersection(left, right, d["startUs"], d["endUs"]) > 0
                   for d in diarization)


def missing_turns(diarization: list[dict[str, Any]], words: list[dict[str, Any]]) -> list[str]:
    return [d["id"] for d in diarization if not any(
        valid_time(w) and w.get("tokenKind", "lexical") == "lexical" and
        intersection(d["startUs"], d["endUs"], w["startUs"], w["endUs"]) > 0
        for w in words)]


def validate_document(doc: dict[str, Any]) -> None:
    """Cross-field invariants; complements rather than replaces JSON Schema."""
    def require(condition: bool, message: str) -> None:
        if not condition:
            raise ValueError(message)
    def indexed(items: list[dict[str, Any]], name: str) -> dict[str, dict[str, Any]]:
        out = {x["id"]: x for x in items}
        require(len(out) == len(items), f"duplicate {name} ID")
        return out
    duration = doc["durationUs"]
    require(type(duration) is int and duration >= 0, "durationUs")
    speakers = indexed(doc["speakers"], "speaker")
    intervals = indexed(doc["diarization"] + doc["exclusiveDiarization"], "interval")
    words = indexed(doc["words"], "word")
    turns = indexed(doc["turns"], "turn")
    issues = indexed(doc["reviewIssues"], "issue")
    require(doc["revision"]["sourceRunId"] == doc["runId"], "revision run mismatch")
    def times(item: dict[str, Any], allow_null: bool = True) -> None:
        a, b = item["startUs"], item["endUs"]
        if a is None or b is None:
            require(allow_null and a is None and b is None, "timestamps must both be null")
        else:
            require(type(a) is int and type(b) is int and 0 <= a <= b <= duration,
                    "invalid normalized interval")
    for i in intervals.values():
        times(i, False)
        require(i["endUs"] > i["startUs"], "empty diarization interval")
        require(i["speakerId"] in speakers, "interval speaker reference")
        if i["confidence"] is not None:
            require(isinstance(i["confidence"], dict), "confidence must be a map")
            require(all(type(x) in (int, float) and math.isfinite(x) and 0 <= x <= 100
                        for x in i["confidence"].values()), "confidence range")
    exclusive = doc["exclusiveDiarization"]
    for pos, x in enumerate(exclusive):
        for y in exclusive[pos + 1:]:
            require(x["speakerId"] == y["speakerId"] or intersection(
                x["startUs"], x["endUs"], y["startUs"], y["endUs"]) == 0,
                "exclusive timeline contains different-speaker overlap")
    ordinals = [w["ordinal"] for w in doc["words"]]
    require(ordinals == sorted(set(ordinals)), "word ordinal uniqueness/order")
    for w in words.values():
        times(w)
        for key in ("speakerId", "modelSpeakerId"):
            require(w[key] is None or w[key] in speakers, "word speaker reference")
        require(all(i in issues for i in w["reviewIssueIds"]), "word issue reference")
        require(all(i in intervals for i in w["sourceIntervalIds"]), "word interval reference")
        if w["assignmentSource"] == "unknown":
            require(w["speakerId"] is None, "unknown assignment cannot assert speaker")
        if w["editedText"] is not None:
            require(w["timingOrigin"] != "model", "edited text timing provenance")
    ownership: Counter[str] = Counter()
    for t in turns.values():
        times(t)
        require(t["speakerId"] is None or t["speakerId"] in speakers, "turn speaker reference")
        require(all(i in issues for i in t["reviewIssueIds"]), "turn issue reference")
        if t["kind"] == "missingSpeech":
            require(not t["wordIds"] and bool(t["markerText"]), "missing marker cannot own words")
            continue
        require(bool(t["wordIds"]) and t["markerText"] is None, "invalid speech turn")
        selected = []
        for wid in t["wordIds"]:
            require(wid in words, "turn word reference")
            w = words[wid]
            ownership[wid] += 1
            require(w["speakerId"] == t["speakerId"], "mixed speakers inside turn")
            selected.append(w)
            if w["startUs"] is not None:
                require(t["startUs"] is not None and t["endUs"] is not None and
                        t["startUs"] <= w["startUs"] <= w["endUs"] <= t["endUs"],
                        "turn does not contain word time")
        require([w["ordinal"] for w in selected] == sorted(w["ordinal"] for w in selected),
                "turn word order")
        for previous, current in zip(selected, selected[1:]):
            if valid_time(previous) and valid_time(current):
                require(can_merge(previous, current, doc["diarization"]),
                        "turn crosses gap or another speaker barrier")
    require(set(ownership) == set(words) and all(n == 1 for n in ownership.values()),
            "every word must belong to exactly one speech turn")
    for i in issues.values():
        times(i)
        require(all(w in words for w in i["wordIds"]), "issue word reference")
        require(all(x in intervals for x in i["sourceIntervalIds"]), "issue interval reference")


class ContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.doc = load("fixtures/normalized-transcript.json")

    def test_normalized_invariants(self):
        validate_document(self.doc)

    def test_json_round_trip(self):
        self.assertEqual(self.doc, json.loads(json.dumps(self.doc, ensure_ascii=False)))

    def test_confidence_is_map_not_scalar_or_distribution(self):
        raw = load("fixtures/pyannote-job-succeeded.synthetic.json")
        confidence = raw["output"]["diarization"][0]["confidence"]
        self.assertIsInstance(confidence, dict)
        self.assertGreater(sum(confidence.values()), 100)
        validate_document(self.doc)

    def test_absent_confidence_remains_null(self):
        self.assertIsNone(self.doc["diarization"][-1]["confidence"])

    def test_missing_backchannel_marker(self):
        missing = missing_turns(self.doc["diarization"], self.doc["words"])
        self.assertIn("d2", missing)
        markers = [t for t in self.doc["turns"] if t["kind"] == "missingSpeech"]
        self.assertEqual(len(markers), 1)
        self.assertEqual(markers[0]["wordIds"], [])

    def test_missing_backchannel_blocks_merge(self):
        prev, nxt = self.doc["words"][1], self.doc["words"][2]
        # Narrow the gap to <= 300ms; the barrier, not the gap, must block merging.
        prev, nxt = copy.deepcopy(prev), copy.deepcopy(nxt)
        prev["endUs"], nxt["startUs"] = 800_000, 1_000_000
        self.assertFalse(can_merge(prev, nxt, self.doc["diarization"]))
        self.assertTrue(can_merge(prev, nxt, [d for d in self.doc["diarization"] if d["id"] != "d2"]))

    def test_adjacent_same_speaker_merges(self):
        self.assertTrue(can_merge(self.doc["words"][0], self.doc["words"][1], self.doc["diarization"]))

    def test_repeated_text_is_not_deduplicated(self):
        self.doc["words"][0]["text"] = "네"
        self.doc["words"][1]["text"] = "네"
        validate_document(self.doc)
        self.assertEqual(sum(w["text"] == "네" for w in self.doc["words"][:2]), 2)

    def test_dangling_speaker_rejected(self):
        self.doc["words"][0]["speakerId"] = "not-present"
        with self.assertRaises(ValueError): validate_document(self.doc)

    def test_duplicate_id_rejected(self):
        self.doc["words"][1]["id"] = self.doc["words"][0]["id"]
        with self.assertRaises(ValueError): validate_document(self.doc)

    def test_mixed_turn_rejected(self):
        self.doc["words"][0]["speakerId"] = "speaker-b"
        with self.assertRaises(ValueError): validate_document(self.doc)

    def test_negative_time_rejected(self):
        self.doc["words"][0]["startUs"] = -1
        with self.assertRaises(ValueError): validate_document(self.doc)

    def test_double_word_ownership_rejected(self):
        self.doc["turns"][0]["wordIds"].append("w1")
        with self.assertRaises(ValueError): validate_document(self.doc)

    def test_edited_text_requires_timing_provenance(self):
        self.doc["words"][0]["editedText"] = "저희 회사가"
        with self.assertRaises(ValueError): validate_document(self.doc)
        self.doc["words"][0]["timingOrigin"] = "inheritedUnaligned"
        validate_document(self.doc)

    def test_exclusive_overlap_rejected(self):
        self.doc["exclusiveDiarization"][1]["startUs"] = 700_000
        with self.assertRaises(ValueError): validate_document(self.doc)

    def test_schema_if_available(self):
        try:
            import jsonschema
        except ImportError:
            self.skipTest("optional jsonschema module not installed; semantic checks still ran")
        schema = load("ssot/contracts/transcript.v1.schema.json")
        jsonschema.Draft202012Validator.check_schema(schema)
        jsonschema.Draft202012Validator(schema, format_checker=jsonschema.FormatChecker()).validate(self.doc)

    def test_relative_markdown_links_exist(self):
        for path in documentation_paths(ROOT):
            for target in re.findall(r"\]\(([^)]+)\)", path.read_text(encoding="utf-8")):
                if target.startswith(("https://", "http://", "mailto:", "#")):
                    continue
                candidate = (path.parent / target.split("#")[0]).resolve()
                self.assertTrue(candidate.exists(), f"broken link in {path.name}: {target}")

    def test_documentation_scope_keeps_source_and_excludes_diagnostic_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ["README.md", "ssot/source.md", ".build/private/review.md", "DerivedData/product.md"]:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("[broken](missing.md)", encoding="utf-8")
            paths = documentation_paths(root)
            self.assertEqual({p.relative_to(root).as_posix() for p in paths}, {"README.md", "ssot/source.md"})
            # A broken source link is still included and fails the same existence predicate.
            for path in paths:
                target = re.findall(r"\]\(([^)]+)\)", path.read_text(encoding="utf-8"))[0]
                self.assertFalse((path.parent / target).exists())


def add_case(case: dict[str, Any]) -> None:
    def test(self):
        actual = match_word(case["word"], case["exclusive"], case["regular"])
        for key, expected in case["expected"].items():
            if key == "score" and expected is not None:
                self.assertAlmostEqual(actual[key], expected, places=9)
            else:
                self.assertEqual(actual[key], expected)
    test.__name__ = "test_match_" + case["name"]
    setattr(ContractTests, test.__name__, test)


for fixture_case in load("fixtures/reconciliation-cases.json"):
    add_case(fixture_case)

if __name__ == "__main__":
    unittest.main(verbosity=2)
