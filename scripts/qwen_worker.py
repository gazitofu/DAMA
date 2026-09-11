# -*- coding: utf-8 -*-
"""DAMA local Qwen worker. No network, diarization or cloud credentials.

Checkpoint identity includes audio, settings, runtime revisions and worker bytes.
Only EOS-completed chunks are reusable. Raw ASR text survives alignment cleaning.
"""
import argparse
import dataclasses
import gc
import hashlib
import json
import math
import os
from pathlib import Path
import signal
import sys
import time
import unicodedata

VERSION = 'qwen-worker-v1'

def digest(data):
    return hashlib.sha256(data).hexdigest()

def write_json(path, data):
    path = Path(path)
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, ensure_ascii=False, allow_nan=False))
    temporary.replace(path)

def kept(ch):
    return ch == "'" or unicodedata.category(ch)[0] in ('L', 'N')

def map_alignment(text, items, offset_us, duration_us):
    """Strict, sequential character mapping, never text search/deduplication.

    Alignment may remove punctuation/space but must retain exactly all letters
    and numbers in order. Otherwise retain the whole original chunk as unaligned.
    """
    positions = [i for i, c in enumerate(text) if kept(c)]
    canonical = ''.join(text[i] for i in positions)
    parts = [''.join(c for c in x['text'] if kept(c)) for x in items]
    if not text:
        return []
    if not parts or any(not p for p in parts) or ''.join(parts) != canonical:
        return [{'text': text, 'startUs': None, 'endUs': None, 'reason': 'alignment_text_mismatch'}]
    result, cursor, previous_start = [], 0, -1
    for i, (item, part) in enumerate(zip(items, parts)):
        start_char = 0 if i == 0 else positions[cursor]
        cursor += len(part)
        end_char = positions[cursor] if cursor < len(positions) else len(text)
        s, e = item['start_time'], item['end_time']
        valid = math.isfinite(s) and math.isfinite(e) and 0 <= s < e and s >= previous_start and e*1e6 <= duration_us
        previous_start = s
        result.append({'text': text[start_char:end_char],
            'startUs': offset_us + round(s*1e6) if valid else None,
            'endUs': offset_us + round(e*1e6) if valid else None,
            'reason': None if valid else 'invalid_alignment_time'})
    assert ''.join(x['text'] for x in result) == text
    return result

def chunk_ranges(samples, rate):
    """60..120s, cut at a 200ms low-energy window; no discarded samples."""
    import numpy as np
    ranges, start = [], 0
    while len(samples)-start > 120*rate:
        candidates = range(start+60*rate, start+120*rate, rate//5)
        boundary = min(candidates, key=lambda x: float(np.mean(samples[x:x+rate//5]**2))) + rate//10
        ranges.append((start, boundary)); start = boundary
    ranges.append((start, len(samples)))
    return ranges

def run(request_path, runtime_path):
    os.environ['HF_HUB_OFFLINE'] = '1'
    os.environ['HF_HUB_DISABLE_TELEMETRY'] = '1'
    os.environ['TOKENIZERS_PARALLELISM'] = 'false'
    request = json.loads(Path(request_path).read_text())
    runtime = json.loads(Path(runtime_path).read_text())
    work = Path(request['workDirectory']); work.mkdir(parents=True, exist_ok=True)
    lock = work / 'worker.lock'
    # flock is released on crashes; a paused task can safely resume checkpoints.
    import fcntl
    lock_handle = lock.open('a')
    fcntl.flock(lock_handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    start_wall = time.monotonic()
    identity = digest(Path(request_path).read_bytes() + Path(runtime_path).read_bytes() + Path(__file__).read_bytes())
    def progress(stage, index=0, total=0):
        write_json(work/'progress.json', {'stage': stage, 'index': index, 'total': total,
                   'elapsedSeconds': time.monotonic()-start_wall})
        print(json.dumps({'stage': stage, 'index': index, 'total': total}), flush=True)
    progress('loading')
    import mlx.core as mx
    import numpy as np
    import soundfile as sf
    from mlx_qwen3_asr.session import Session
    from mlx_qwen3_asr.audio import compute_features
    from mlx_qwen3_asr.generate import generate_with_info, GenerationConfig
    from mlx_qwen3_asr.tokenizer import parse_asr_output
    from mlx_qwen3_asr.forced_aligner import ForcedAligner, ForcedAlignTextProcessor
    ForcedAlignTextProcessor._get_ko_tokenizer() # Fail closed if Korean backend absent.
    path = Path(request['audio'])
    if digest(path.read_bytes()) != request['audioSHA256']:
        raise ValueError('sourceChanged')
    samples, rate = sf.read(path, dtype='float32')
    if rate != 16000 or samples.ndim != 1 or round(len(samples)*1e6/rate) != request['durationUs']:
        raise ValueError('audioContract')
    ranges = chunk_ranges(samples, rate)
    context = request.get('context', '')
    language = request.get('language') or 'Korean'
    if language not in ('Korean',):
        raise ValueError('unsupportedPilotLanguage')
    cache = []
    session = None
    def transcribe_chunk(start, end, index, depth=0):
        nonlocal session
        chunk_file = work / f'chunk-{start}-{end}.json'
        if chunk_file.exists():
            chunk = json.loads(chunk_file.read_text())
            if chunk.get('identity') != identity:
                raise ValueError('checkpointIdentityChanged')
        else:
            chunk = {'identity': identity, 'startFrame': start, 'endFrame': end}
        if chunk.get('finish_reason') != 'eos' or chunk.get('truncated', True):
            progress('transcribing', index+1, len(ranges))
            if session is None:
                session = Session(runtime['models']['asr']['path'], dtype=mx.float16)
            # Explicit single chunk generation avoids upstream's hidden 30s split.
            mel, lens = compute_features(samples[start:end])
            features, _ = session.model.audio_tower(mel.astype(mx.float16), lens)
            prompt = session.tokenizer.build_prompt_tokens(n_audio_tokens=features.shape[1], language=language, context=context)
            ids = mx.array([prompt]); pos = mx.arange(ids.shape[1])[None, :]
            budget = 4096 # Per chunk, not shared across the meeting. Experimental cap.
            signal.alarm(900) # Conservative initial per-stage watchdog; refine after pilot.
            generation = generate_with_info(model=session.model, input_ids=ids, audio_features=features,
                position_ids=mx.stack([pos,pos,pos], axis=1), config=GenerationConfig(max_new_tokens=budget, temperature=0.0))
            signal.alarm(0)
            raw_decode = session.tokenizer.decode(generation.tokens)
            lang, text = parse_asr_output(raw_decode, user_language=language)
            chunk.update({'rawDecode': raw_decode, 'text': text, 'language': lang,
                'finish_reason': generation.finish_reason, 'truncated': generation.truncated,
                'generatedTokens': generation.generated_tokens, 'maxNewTokens': budget,
                'contextSHA256': digest(context.encode())})
            write_json(chunk_file, chunk)
            del mel, lens, features, ids, pos, generation
            mx.clear_cache()
        if chunk['truncated'] or chunk['finish_reason'] != 'eos':
            # Keep failed parent raw output. At most two subdivision levels.
            if depth>=2 or end-start<30*rate:
                progress('incomplete',index+1,len(ranges))
                raise ValueError('generationIncomplete')
            low=start+(end-start)//3; high=start+2*(end-start)//3
            boundary=min(range(low,high,rate//5),key=lambda x:float(np.mean(samples[x:x+rate//5]**2)))+rate//10
            progress('retrying_shorter_chunk',index+1,len(ranges))
            transcribe_chunk(start,boundary,index,depth+1)
            transcribe_chunk(boundary,end,index,depth+1)
        else:
            cache.append(chunk)
    for i,(start,end) in enumerate(ranges):
        transcribe_chunk(start,end,i)
        progress('transcribed',i+1,len(ranges))
    del session
    gc.collect(); mx.clear_cache()
    aligner = ForcedAligner(runtime['models']['aligner']['path'], dtype=mx.float16)
    words = []
    for i,chunk in enumerate(cache):
        start,end=chunk['startFrame'],chunk['endFrame']
        if 'alignment' not in chunk:
            progress('aligning', i+1, len(cache)); signal.alarm(900)
            alignment = aligner.align(samples[start:end], chunk['text'], language) if chunk['text'].strip() else []
            signal.alarm(0)
            chunk['alignment'] = [dataclasses.asdict(item) for item in alignment]
            write_json(work/f'chunk-{start}-{end}.json', chunk)
            mx.clear_cache()
        mapped = map_alignment(chunk['text'],chunk['alignment'],round(start*1e6/rate),round((end-start)*1e6/rate))
        if words and mapped:
            mapped[0]['text'] = '\n' + mapped[0]['text']
        words.extend(mapped)
        progress('aligned',i+1,len(cache))
    text = '\n'.join(chunk['text'] for chunk in cache if chunk['text'])
    # Include chunk separators in raw text mapping without inventing word content.
    if ''.join(w['text'] for w in words) != text:
        raise ValueError('textPreservation')
    import resource
    result = {'version': VERSION, 'status': 'complete', 'audioSHA256': request['audioSHA256'],
        'durationUs': request['durationUs'], 'text': text, 'words': words, 'chunks': cache,
        'language': language, 'dtype': 'float16', 'contextSHA256': digest(context.encode()),
        'asrRevision': runtime['models']['asr']['revision'], 'alignerRevision': runtime['models']['aligner']['revision'],
        'upstreamCommit': runtime['upstreamCommit'], 'elapsedSeconds': time.monotonic()-start_wall,
        'peakRSSBytes': resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
        'peakMLXBytes': mx.get_peak_memory()}
    write_json(work/'result.json',result)
    progress('complete',len(cache),len(cache))

if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--request',required=True); parser.add_argument('--runtime',required=True)
    args=parser.parse_args()
    try:
        run(args.request,args.runtime)
    except Exception as error:
        # Never leak audio text, context, model dump or arbitrary exception detail.
        print(json.dumps({'error':type(error).__name__}),file=sys.stderr,flush=True)
        sys.exit(1)
