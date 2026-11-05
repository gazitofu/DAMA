#!/usr/bin/env python3
"""Read saved Qwen output and replay only character/time mapping, without models.

Output contains aggregate counts and hashes, never transcript text. Input stays
unchanged; an existing output is never overwritten.
"""
import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path

from qwen_worker import map_alignment


def diagnose(path):
    raw = path.read_bytes()
    data = json.loads(raw)
    words, causes = [], Counter()
    chunks = data['chunks']
    for chunk in chunks:
        duration_us = round((chunk['endFrame'] - chunk['startFrame']) * 1e6 / 16000)
        mapped = map_alignment(chunk['text'], chunk['alignment'],
                               round(chunk['startFrame'] * 1e6 / 16000), duration_us)
        previous_start = -1
        for item in chunk['alignment']:
            start, end = item['start_time'], item['end_time']
            # Exclusive reason priority follows validity constraints in the worker.
            if not math.isfinite(start) or not math.isfinite(end): cause = 'nonfinite'
            elif start < 0: cause = 'negative'
            elif end == start: cause = 'zeroDuration'
            elif end < start: cause = 'reversed'
            elif start < previous_start: cause = 'backwardStart'
            elif end * 1e6 > duration_us: cause = 'pastChunkEnd'
            else: cause = 'valid'
            causes[cause] += 1
            previous_start = start
        if words and mapped:
            mapped[0]['text'] = '\n' + mapped[0]['text']
        words.extend(mapped)
    assert words == data['words'], 'stored word mapping changed'
    assert ''.join(word['text'] for word in words) == data['text'], 'text changed'
    assert path.read_bytes() == raw, 'input changed during measurement'
    return {
        'format': 'dama-qwen-alignment-diagnostic-v1',
        'rawSHA256': hashlib.sha256(raw).hexdigest(),
        'workerSHA256': hashlib.sha256(Path(__file__).with_name('qwen_worker.py').read_bytes()).hexdigest(),
        'mappingExact': True, 'textExact': True, 'inputUnchanged': True,
        'chunks': len(chunks),
        'eosCompleteChunks': sum(c['finish_reason'] == 'eos' and not c['truncated'] for c in chunks),
        'alignmentItems': sum(len(c['alignment']) for c in chunks),
        'alignmentTimeReasonsExclusive': dict(sorted(causes.items())),
        'wordMappingReasons': dict(sorted(Counter(w['reason'] or 'aligned' for w in words).items())),
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('raw', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    report = diagnose(args.raw)
    with args.output.open('x') as output:
        json.dump(report, output, indent=2, allow_nan=False)
        output.write('\n')
    print(json.dumps(report, sort_keys=True))
