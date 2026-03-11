## [LRN-20260311-001] correction

**Logged**: 2026-03-11T00:00:00+08:00
**Priority**: medium
**Status**: pending
**Area**: tests

### Summary
Do not treat imported HYBRID paged documents as required `pdf-fragment` sessions when page-aware `pages[]` is present.

### Details
An acceptance review overcalled a blocker by assuming `DocumentType.HYBRID` imports must persist `pageKind: 'pdf-fragment'`. In the current M2 design, imported PDF/HYBRID documents both persist real paged `pages[]` and open through the page-aware path. The native `documentType == "hybrid" -> "pdf-fragment"` mapping in `napi_init.cpp` is a compatibility fallback for non-page-aware open configs, not the main path for imported schema v2 paged documents.

### Suggested Action
When reviewing HYBRID import behavior, distinguish page-aware persisted semantics from compat fallback semantics before filing a blocker.

### Metadata
- Source: user_feedback
- Related Files: entry/src/main/ets/services/DocumentLibraryService.ets, entry/src/main/cpp/napi_init.cpp
- Tags: review, hybrid, paged-import, fallback

---

## [LRN-20260311-002] best_practice

**Logged**: 2026-03-11T00:00:00+08:00
**Priority**: medium
**Status**: pending
**Area**: config

### Summary
For this HarmonyOS project, the correct simulator build entry is project-level `assembleApp` with `product=simulator`, not root `assembleHap`.

### Details
The build log showed the real successful chain was `:entry:simulator@... -> :entry:assembleHap -> ::assembleApp`. Running `hvigorw.bat assembleHap --mode project -p product=simulator` failed with "Task ['assembleHap'] was not found in the project MyApplication." The working command was `hvigorw.bat assembleApp --mode project -p product=simulator --info`.

### Suggested Action
When validating simulator UI changes from the project root, use the project-level `assembleApp` target and pass `-p product=simulator`.

### Metadata
- Source: error
- Related Files: .hvigor/outputs/build-logs/build.log
- Tags: build, hvigor, simulator

---
