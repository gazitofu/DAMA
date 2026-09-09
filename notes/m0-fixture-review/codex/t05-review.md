# T05 main integration review

Within original T05 scope, no other refactors/SSOT/plan/git. Reuse unchanged context, update t05-result.md and run check.sh after fixes.

Main read initial TranscriptExporting.swift and repository/editor deltas. The session-scoped isExporting lock and explicit identity validation are appropriate. Review the TXT evidence presentation before integration:

1. Current TXT flattens confidence dictionaries across intervals into one list. Repeated provider labels then lose their source interval, while missing maps become an unspecific 'some missing' line. Preserve interval identity/time and each interval's own sorted map, with explicit '미제공' for a nil map; don't normalize or merge scores. If confidence is included, it must be interpretable as the original map for each interval. Resolve referenced regular/exclusive intervals and marker issue source IDs consistently with contract IDs, or clearly omit unavailable evidence rather than manufacture it. Test w5 d4 B65/C60 and d5 nil as separately labeled intervals, plus a marker source interval and repeated provider labels in distinct intervals.

2. TXT containing editedText inherits original Word times. Add an explicit '시간 재정렬 안 됨' annotation outside transcript content for affected blocks, so edited words are not implicitly claimed to be freshly aligned. Preserve exact prefix + replacement text, no trimming or correction. Test current edited TXT carries it and automatic original does not.

3. Header should say '공급자 화자 점수와 시간 정렬 점수는 정답 확률이 아닙니다.' without a percentage symbol. Raw scores remain raw values. This avoids a confusing percent presentation and keeps Korean output understandable.

4. Initial tests exercise export during an in-flight save, but not an actual failed dirty save. Inject real repository failure, invoke session.export for both automatic/current while dirty and assert neither file is written; after retry or cancel, export should work. Test successful replacement of an existing destination as well as existing failure preservation.

5. The initial metadata test declares destination/credential sentinels but never gives either to any relevant dependency, so those negative assertions add no evidence. Ground the path assertion in a real session.export destination/storage root containing the synthetic sentinel, then read the output. Keep the positive transcript containing `Authorization=사용자 발화` to prove no accidental redaction. There are no credential inputs in M0; describe that interface fact instead of implying a credential-handling path was exercised.

6. The measured nonexistent-leaf symlink resolution bug also warrants checking T03's `ensureContained`, which resolves a potentially nonexistent full URL before `createDirectory`. Add a regression with the existing `Sessions` parent symlinked outside root and a NEW nonexistent session below it; an import must reject before creating even an empty outside session directory. If it fails, fix the shared containment resolution to resolve existing ancestors before appending missing components. This is the same measured filesystem behavior, not a request for cross-process TOCTOU hardening. Also test the final selected export filename itself being a symlink into repository: either reject consistently with the documented guard or explicitly document that atomic rename replaces only the alias; do not claim full symlink refusal while only inspecting parents.

Do not sanitize user transcript text based on suspicious-looking words/URLs; only prevent app-owned metadata leakage. Existing raw text preservation and marker/order/four-combination/atomic destination tests must remain.
