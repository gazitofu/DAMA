"""Download public, revision-pinned weights. Never reads meeting files."""
import json
import pathlib
import sys
from huggingface_hub import snapshot_download

root = pathlib.Path(__file__).resolve().parents[1]
target = root / '.build/qwen-runtime.json'
models = {}
for key, repo, revision in [
    ('asr', 'Qwen/Qwen3-ASR-1.7B', '7278e1e70fe206f11671096ffdd38061171dd6e5'),
    ('aligner', 'Qwen/Qwen3-ForcedAligner-0.6B', 'c7cbfc2048c462b0d63a45797104fc9db3ad62b7')]:
    print(key, revision, flush=True)
    path = snapshot_download(repo, revision=revision, cache_dir=str(root / '.build/qwen-models'),
        allow_patterns=['*.json', '*.safetensors', '*.txt', '*.tiktoken', '*.model'])
    models[key] = {'id': repo, 'revision': revision, 'path': path}
config = {'version': 1, 'python': sys.executable,
          'worker': str(root / 'scripts/qwen_worker.py'),
          'upstreamCommit': '1e28932dac8e2c68b34c29f32e2be338ffc1c852',
          'models': models}
target.write_text(json.dumps(config, indent=2))
print('runtime_ready', target, flush=True)
