# turn-continuity AC-12 (읽기 전용, 네트워크 0). 저장 확률(원본)과 입력 음량 v1 확률(앱 실행기)을 Soniox lexical 시간 기준으로 비교한다.
# 자는 스펙 §01 표 3과 같다: 무음 판정 단어 = 토큰 구간에 0.5 초과 채널 프레임이 하나도 없는 lexical ÷ lexical 전체
# (시간 없음·0길이는 따로), 유지 = 원본·맞춤 둘 다 단독 배정인 단어를 채널 탐욕 1:1 대응한 뒤의 일치율 (정답 아님).
# 출력은 숫자와 ID 앞 8자만. 사용: python3 level_compare.py <Sessions> <run8> <probs dir> [<out.json>]
import collections, json, os, sys

import numpy as np


def parent(sessions, run8):
    for session in os.listdir(sessions):
        runs = os.path.join(sessions, session, 'runs')
        if os.path.isdir(runs):
            for name in os.listdir(runs):
                if name.startswith(run8):
                    return os.path.join(runs, name)
    raise SystemExit(f'{run8}: run not found')


def classify(p, words):
    act = p > 0.5
    n = act.sum(1)
    out = []
    for w in words:
        s, e = w['startUs'], w['endUs']
        if s is None or e is None or e <= s:
            out.append(('zero', None)); continue
        f0, f1 = s // 10000, max(s // 10000 + 1, -(-e // 10000))
        nn = n[f0:f1]
        if len(nn) == 0 or nn.max() == 0:
            out.append(('silence', None))
        elif (nn == 1).sum() == 0:
            out.append(('overlap', None))
        else:
            single = act[f0:f1][nn == 1]
            out.append(('single', int(np.bincount(np.nonzero(single)[1], minlength=p.shape[1]).argmax())))
    return out


def main():
    sessions, run8, probs = sys.argv[1], sys.argv[2], sys.argv[3]
    run = parent(sessions, run8)
    doc = json.load(open(os.path.join(run, 'normalized/model.json')))
    words = [w for w in doc['words'] if w['tokenKind'] == 'lexical']
    stored_meta = json.load(open(os.path.join(run, 'raw/nemotron-meta.json')))
    stored = np.fromfile(os.path.join(run, 'raw/nemotron-probabilities.f32'), dtype='<f4').reshape(stored_meta['frameCount'], stored_meta['channels'])
    meta = json.load(open(os.path.join(probs, 'meta.json')))
    new = np.fromfile(os.path.join(probs, 'probs.f32'), dtype='<f4').reshape(meta['frameCount'], meta['channels'])
    a, b = classify(stored, words), classify(new, words)
    ca, cb = collections.Counter(k for k, _ in a), collections.Counter(k for k, _ in b)
    table = collections.Counter((x[1], y[1]) for x, y in zip(a, b) if x[0] == 'single' and y[0] == 'single')
    mapping, used = {}, set()
    for (x, y), _ in table.most_common():
        if x not in mapping and y not in used:
            mapping[x] = y; used.add(y)
    both = sum(table.values())
    agree = sum(k for (x, y), k in table.items() if mapping.get(x) == y)
    report = {
        'run': run8, 'minutes': round(doc['durationUs'] / 6e7, 1), 'lexical': len(words),
        'gainDb': meta['inputLevel']['gainDb'], 'p90Dbfs': meta['inputLevel']['p90Dbfs'],
        'byteIdenticalToStored': bool(meta.get('byteIdenticalToReference')),
        'silentPctStored': round(100 * ca['silence'] / len(words), 2), 'silentPctLevel': round(100 * cb['silence'] / len(words), 2),
        'soleBoth': both, 'soleAgreementPct': round(100 * agree / max(1, both), 1),
        'channelsStored': int((stored > 0.5).any(0).sum()), 'channelsLevel': int((new > 0.5).any(0).sum()),
    }
    print(json.dumps(report, ensure_ascii=False))
    if len(sys.argv) > 4:
        json.dump(report, open(sys.argv[4], 'w'), ensure_ascii=False, indent=2)


if __name__ == '__main__':
    main()
