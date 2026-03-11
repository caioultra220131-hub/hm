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

## [LRN-20260311-004] correction

**Logged**: 2026-03-11T18:50:00+08:00
**Priority**: high
**Status**: pending
**Area**: docs

### Summary
Do not claim a Codex thread wake-up message was successfully sent unless the automation actually clicked the chat composer, inserted the text, and submitted it.

### Details
I incorrectly treated visible UI text as evidence that the wake-up flow had completed, even though the script had not reliably focused the chat composer or entered the message. The correct acceptance standard is stricter: after switching threads, wait 5 seconds, click the fixed composer hotspot, input the exact message, and then submit it. Anything short of that is not a successful send.

### Suggested Action
Keep the wake-up script on a deterministic path: detached process, thread switch, 5-second wait, fixed composer click, input text, send, then verify against the intended post-send signal instead of assuming success from partial UI evidence.

### Metadata
- Source: user_feedback
- Related Files: run-thread-work.ps1
- Tags: correction, codex, thread-dispatch, verification

---

## [LRN-20260311-005] correction

**Logged**: 2026-03-11T19:05:00+08:00
**Priority**: high
**Status**: pending
**Area**: docs

### Summary
For Codex wake-up automation, the message must be entered only after a fixed-position click on the chat composer; do not rely on inferred input controls.

### Details
The user explicitly clarified that the dialog input area is in a fixed position and must be clicked directly before entering text. I had still left UIA-driven input targeting in the script, which meant the automation could click or focus the wrong control and then incorrectly claim the send path had been fixed. The correct behavior is deterministic: switch thread, wait 5 seconds, click the fixed composer hotspot once, input the exact message, then send.

### Suggested Action
Keep the send path hard-coded around the fixed composer hotspot and verify from the resulting thread behavior, not from inferred input-control matches.

### Metadata
- Source: user_feedback
- Related Files: run-thread-work.ps1
- Tags: correction, codex, fixed-click, composer

---

## [LRN-20260311-006] correction

**Logged**: 2026-03-11T19:12:00+08:00
**Priority**: high
**Status**: pending
**Area**: docs

### Summary
Thread agents should execute wake-up thread-switch commands themselves after writing mailbox files, instead of asking the user to run those commands manually.

### Details
The user explicitly wants H/A/B/Test to proactively run the wake-up command as part of their own workflow. Returning a PowerShell snippet for the user to execute is the wrong interaction model here. The correct behavior is: write the mailbox file, request desktop-automation permission if needed, run the wake-up script directly, and only report success or failure.

### Suggested Action
Keep the thread instruction files and README aligned around self-executed wake-up commands, and avoid prompting the user to manually run known thread-switch steps.

### Metadata
- Source: user_feedback
- Related Files: 线程调度/H线程调度流程说明.txt, 线程调度/A线程.txt, 线程调度/B线程.txt, 线程调度/T线程.txt, 线程调度/README.md
- Tags: correction, thread-dispatch, wake-up, automation

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

## [LRN-20260311-003] best_practice

**Logged**: 2026-03-11T18:35:00+08:00
**Priority**: medium
**Status**: pending
**Area**: docs

### Summary
Codex thread wake-up automation must treat sidebar thread entries and the chat composer as custom UI elements, not as exact-name list items plus a standard `Edit` box.

### Details
The visible thread entries were exposed to UI Automation as time-suffixed list items such as `H1 小时`, `Test1 小时`, `B1 小时`, and `A+-1 小时`, so exact matches against logical names like `A` or `Test` failed. The message composer also was not exposed as a normal large `Edit`; instead, the reliable target in Codex was a wide, focusable `Group`, while the actual `Edit` that UIA surfaced was the terminal input at the very bottom. The working approach was: restrict the search to the `Codex` window, match sidebar thread items by prefix with sidebar-biased ranking, click the composer group, and paste text from a detached PowerShell process so the integrated terminal does not steal focus.

### Suggested Action
When reusing `run-thread-work.ps1`, keep the `Codex` window filter, prefix/sidebar thread matching, wide-focusable-group composer targeting, and detached-process execution path.

### Metadata
- Source: conversation
- Related Files: run-thread-work.ps1, 线程调度/run-thread-work.ps1
- Tags: codex, ui-automation, composer, sendkeys, thread-dispatch

---
