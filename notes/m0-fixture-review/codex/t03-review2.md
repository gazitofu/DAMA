# T-03 final integration review

Continue the same limited task; main read the last review diff/tests. Allowed only FileSessionRepository.swift, FileSessionRepositoryTests.swift and t03-result.md. All other dirty files are main-owned prompts or current T03 output. Do not reread unchanged global/domain/rule bodies already read in this session. Read this task and changed code. Keep the report current, run check.sh, then finish promptly.

Three concrete remaining boundary defects:

1. `isFirstInitialization` checks only the incoming Run's raw/model/revision plus pointer. If an existing session's pointer was lost and a different new Run is imported, all four may be absent and it falsely takes the first-initialization path, bypassing recovery of existing valid edits. Determine whether this is a genuinely new session before creating its directories, or inspect preexisting session revisions. Test: existing edited Run1, delete pointer, import different Run2 with older savedAt => keep/recover Run1 active and emit missing-pointer notice; brand-new session still zero notices.
2. `sameTurnEvidence` preserves marker fields and same-model membership, but allows reordering whole speech Turns or moving an unchanged marker to the wrong place. Preserve flattened model Word order and nondecreasing original model Turn positions including markers; subdivisions may share a model position. Test moving t-marker before t1 and swapping t1/t2: typed validator alone accepts these, repository must reject them without changing active. Positive subdivision plus Undo restoration remains allowed.
3. `modelDocument` only validates schema/identity. It should also reject stored model.json with humanEdited=true or baseRevisionId!=nil, so corrupt edited snapshots are not presented/used as automatic originals. Test direct corruption of the injected test model and loadModel failure. Original SSOT/fixtures remain untouched.

No additional features, cross-process locking or broad refactors. Do not weaken assertions. Run bash scripts/check.sh, record actual counts and classifications in t03-result.md. No signing, notarization, xcodebuild test or native UI launch.
