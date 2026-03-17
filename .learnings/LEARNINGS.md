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
- Related Files: 绾跨▼璋冨害/H绾跨▼璋冨害娴佺▼璇存槑.txt, 绾跨▼璋冨害/A绾跨▼.txt, 绾跨▼璋冨害/B绾跨▼.txt, 绾跨▼璋冨害/T绾跨▼.txt, 绾跨▼璋冨害/README.md
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
The visible thread entries were exposed to UI Automation as time-suffixed list items such as `H1 灏忔椂`, `Test1 灏忔椂`, `B1 灏忔椂`, and `A+-1 灏忔椂`, so exact matches against logical names like `A` or `Test` failed. The message composer also was not exposed as a normal large `Edit`; instead, the reliable target in Codex was a wide, focusable `Group`, while the actual `Edit` that UIA surfaced was the terminal input at the very bottom. The working approach was: restrict the search to the `Codex` window, match sidebar thread items by prefix with sidebar-biased ranking, click the composer group, and paste text from a detached PowerShell process so the integrated terminal does not steal focus.

### Suggested Action
When reusing `run-thread-work.ps1`, keep the `Codex` window filter, prefix/sidebar thread matching, wide-focusable-group composer targeting, and detached-process execution path.

### Metadata
- Source: conversation
- Related Files: run-thread-work.ps1, 绾跨▼璋冨害/run-thread-work.ps1
- Tags: codex, ui-automation, composer, sendkeys, thread-dispatch

---

## [LRN-20260313-002] correction

**Logged**: 2026-03-13T00:44:07.2555775+08:00
**Priority**: high
**Status**: pending
**Area**: docs

### Summary
In this workspace, H-thread wake-up should use the hidden background `Start-Process ... -Wait | Out-Null` pattern instead of invoking `run-thread-work.ps1` directly in the foreground shell.

### Details
The user provided the exact reference form for H-side wake-up:
`Start-Process -FilePath powershell -WindowStyle Hidden -ArgumentList '-ExecutionPolicy','Bypass','-File','C:\Users\lasrorder\hw\MyApplication\run-thread-work.ps1','-ThreadName','B','-ExecutorThreadName','H','-WindowTitleRegex','^Codex$' -Wait | Out-Null`

This correction matters because the detached hidden process avoids Codex UI focus interference and matches the user's expected thread-switching procedure. For future H wake-ups, preserve this structure and only substitute the target thread / executor pair as needed.

### Suggested Action
When H needs to wake another thread, use the hidden `Start-Process powershell ... -Wait | Out-Null` wrapper rather than calling the script directly from the active shell session.

### Metadata
- Source: user_feedback
- Related Files: run-thread-work.ps1, .learnings/LEARNINGS.md
- Tags: correction, thread-dispatch, wake-up, powershell

---

## [LRN-20260312-001] best_practice

**Logged**: 2026-03-12T21:40:08.0050907+08:00
**Priority**: low
**Status**: pending
**Area**: docs

### Summary
In this workspace PowerShell flow, do not use `&&` to chain `git` commands; run them as separate shell invocations.

### Details
Attempting `git add ... && git commit ...` failed with `鏍囪鈥?&鈥濅笉鏄鐗堟湰涓殑鏈夋晥璇彞鍒嗛殧绗︺€俙 in the current PowerShell environment. For Codex terminal actions here, stage and commit should be sent as separate commands instead of relying on Bash-style separators.

### Suggested Action
When issuing sequential Git operations from PowerShell in this workspace, run `git add` and `git commit` as separate `shell_command` calls.

### Metadata
- Source: error
- Related Files: N/A
- Tags: powershell, git, command-execution

---

## [LRN-20260313-002] correction

**Logged**: 2026-03-13T00:48:56.4530242+08:00
**Priority**: high
**Status**: pending
**Area**: docs

### Summary
Treat "don't execute" for a thread wake-up as a one-off override unless the user explicitly asks to change the standing workflow.

### Details
I incorrectly generalized a one-time instruction into a persistent rule and changed the thread-dispatch docs to "record but do not execute" for wake-ups targeting `H`. The user clarified that this applied only to that one instance. The standing workflow remains unchanged: A/B/T should normally execute the wake-up step for `H`, and only skip execution when the user explicitly asks for that specific action.

### Suggested Action
Keep `绾跨▼璋冨害/README.md` and the A/B/T thread instruction files aligned on this rule: after writing the mailbox result for `H`, record the wake-up command and clearly mark it as "recorded, not executed."

### Metadata
- Source: user_feedback
- Related Files: 绾跨▼璋冨害/README.md, 绾跨▼璋冨害/A绾跨▼.txt, 绾跨▼璋冨害/B绾跨▼.txt, 绾跨▼璋冨害/T绾跨▼.txt
- Tags: correction, thread-dispatch, H-thread, record-only
- See Also: LRN-20260311-001

---
## [LRN-20260313-001] correction

**Logged**: 2026-03-13T01:05:00+08:00
**Priority**: high
**Status**: pending
**Area**: config

### Summary
执行分支汇总到 main 时，必须排除线程合并脚本相关分支；当前线程合并实现保持原样，不做改动。

### Details
用户在要求“将全部分支合并到main，然后删除全部分支”后补充约束：不要动线程合并脚本的分支，现在的线程合并就是用户想要的结果。因此后续主线收口只能处理 editor/业务分支，不能调整线程调度/线程合并脚本分支或其实现。

### Suggested Action
合并前先按分支用途分类；涉及线程调度、线程唤醒、线程合并脚本的分支默认排除，除非用户再次明确点名。

### Metadata
- Source: user_feedback
- Related Files: AGENTS.md, 线程调度/README.md
- Tags: branch-management, thread-scheduling, correction

---
## [LRN-20260313-002] correction

**Logged**: 2026-03-13T01:12:00+08:00
**Priority**: high
**Status**: pending
**Area**: config

### Summary
线程控制相关分支不再保留，需要直接删除。

### Details
用户最新指令覆盖了之前“不要动线程合并脚本的分支”的约束：现在对于线程控制相关分支，直接删除，不再保留作为特殊例外。

### Suggested Action
后续在做分支收口时，若线程控制相关分支仍存在，按用户要求与其他任务分支一样直接删除；不要再默认豁免。

### Metadata
- Source: user_feedback
- Related Files: AGENTS.md, .learnings/LEARNINGS.md
- Tags: branch-management, thread-control, correction

---
## [LRN-20260313-003] correction

**Logged**: 2026-03-13T01:40:00+08:00
**Priority**: high
**Status**: pending
**Area**: tests

### Summary
当 Test 因 simulator/runtime 验证能力不足而给出 inconclusive 型 failed 时，H 线程不能停在汇报，需要立刻派 owner 线程补齐可验证性。

### Details
这次默认单指滚动/手指书写模式分支在 x86_64 simulator-stub 上，large-page free pan 和 actual finger-writing 无法得出结论。用户明确指出，头线程不应只汇报环境缺口，而应安排其他线程继续解决。后续遇到类似“不是明确代码回归，但环境无法完成验收”的情况，H 应直接派 native/runtime owner 修复 simulator 可验证链路，再回给 Test。

### Suggested Action
把 simulator-stub、native bridge、debug/repro path 的可验证性问题直接派给 owner 线程，不要在 inconclusive 状态下停止流转。

### Metadata
- Source: user_feedback
- Related Files: .learnings/LEARNINGS.md, 线程调度/H_A_H/H_A.txt
- Tags: correction, orchestration, simulator-validation

---
## [LRN-20260313-004] correction

**Logged**: 2026-03-13T02:15:00+08:00
**Priority**: high
**Status**: pending
**Area**: tests

### Summary
只要还有未收口项，H 线程要主动补派或续派对应线程，不等用户再次提醒。

### Details
用户明确要求：如果有内容没做完，需要安排线程去执行的，就直接安排。后续不能因为某条链路已经派过一次就默认停止跟进；如果任务单缺失、验收链路断开或仍有未完成分支，H 需要主动补挂任务并继续推进。

### Suggested Action
每次收到这类提醒后，先检查当前 H_A/H_B/H_t 是否仍有有效任务单；若验收或修复链路断开，立即重写任务单并唤醒对应线程。

### Metadata
- Source: user_feedback
- Related Files: .learnings/LEARNINGS.md, 线程调度/H_A_H/H_A.txt, 线程调度/H_B_H/H_B.txt, 线程调度/H_T_H/H_t.txt
- Tags: correction, orchestration, follow-through

---
## [LRN-20260313-004] correction

**Logged**: 2026-03-13T14:26:00+08:00
**Priority**: high
**Status**: pending
**Area**: tests

### Summary
If H sends new mailbox content while T is already executing, T must re-check `H_t.txt` during the same run and treat it as additional work or sync information, not ignore it until the next round.

### Details
The user clarified that an in-flight message from H means there may be more work to complete together or information that needs to be synchronized immediately. The test thread should not assume the mailbox is static after the initial read/clear step when the head thread is actively coordinating.

### Suggested Action
During long-running validations, re-check `绾跨▼璋冨害/H_T_H/H_t.txt` at meaningful boundaries and incorporate any new H content into the current run before writing `T_H.txt`.

### Metadata
- Source: user_feedback
- Related Files: 绾跨▼璋冨害/T绾跨▼.txt, 绾跨▼璋冨害/H_T_H/H_t.txt, .learnings/LEARNINGS.md
- Tags: correction, thread-scheduling, mailbox-sync

---
## [LRN-20260313-003] best_practice

**Logged**: 2026-03-13T15:18:00+08:00
**Priority**: medium
**Status**: pending
**Area**: frontend

### Summary
ArkTS editor state updates in this workspace cannot use object spread syntax.

### Details
A hotfix in `entry/src/main/ets/pages/EditorWorkspace.ets` initially used object spread to clone `DocumentRecord` and `DocumentPreviewSnapshot` during local active-page sync. `hvigorw.bat assembleApp --mode project -p product=simulator --info` failed with `arkts-no-spread`. The safe pattern here is to reuse existing explicit helpers such as `applyDocumentActivePage()` or manually construct typed objects instead of using `{ ...obj }`.

### Suggested Action
Avoid object spread in ArkTS page/state code for this project. Prefer explicit object construction or existing helper methods when updating `@State`-backed records.

### Metadata
- Source: error
- Related Files: entry/src/main/ets/pages/EditorWorkspace.ets
- Tags: arkts, compiler, state-sync
- Pattern-Key: arkts.no_object_spread
- Recurrence-Count: 1
- First-Seen: 2026-03-13
- Last-Seen: 2026-03-13

---
## [LRN-20260313-005] best_practice

**Logged**: 2026-03-13T18:15:00+08:00
**Priority**: medium
**Status**: pending
**Area**: tests

### Summary
On this Harmony x86_64 simulator, snapshot_display is a more reliable screenshot path than uitest screenCap during editor transitions.

### Details
During immersive editor validation on codex/bugfix/immersive-canvas-minimal-rail-b, hdc shell uitest screenCap -p ... intermittently failed with Failed to get display pixelMap, especially right after entering the editor. The system-level command hdc shell snapshot_display -f ... succeeded consistently for the same screens and produced usable JPEG evidence without blocking the test flow.

### Suggested Action
Prefer snapshot_display for simulator screenshot capture in T-thread Harmony validations. Keep uitest dumpLayout for structure/text extraction, but do not rely on uitest screenCap as the primary capture method when collecting acceptance evidence.

### Metadata
- Source: error
- Related Files: tmp/t_filter_hotfix_after_open.jpeg, tmp/t_filter_hotfix_notes_selected.jpeg
- Tags: harmony, simulator, screenshots, best_practice

---
## [LRN-20260313-006] knowledge_gap

**Logged**: 2026-03-13T20:53:38.8371570+08:00
**Priority**: medium
**Status**: pending
**Area**: docs

### Summary
Branch and merge status from handoff notes must be verified against the live git graph before reuse.

### Details
During the B-thread handoff, `context_handoff.md` still stated that the accepted editor, immersive, rail, and autosave chain had not been merged back to `main` and pointed to feature branches as the authoritative baseline. Live git checks showed a different reality: local `main` was already at `eeed52c`, and `aca47d9` from the accepted quiet-autosave chain was an ancestor of `HEAD`. Reusing the stale note verbatim would have produced an incorrect handoff.

### Suggested Action
When a handoff depends on branch ownership or merge reality, verify it with live git commands such as `git log`, `git branch --contains`, or `git merge-base --is-ancestor` before repeating the note. Treat handoff markdown as context, not authority.

### Metadata
- Source: error
- Related Files: context_handoff.md, context_handoff_B.md
- Tags: git, handoff, branch-state, knowledge_gap

---
## [LRN-20260313-007] correction

**Logged**: 2026-03-13T21:33:54.6971331+08:00
**Priority**: medium
**Status**: pending
**Area**: docs

### Summary
When waking multiple worker threads, stagger the wake-ups slightly instead of firing them back-to-back.

### Details
During H-thread coordination, multiple worker threads were awakened in immediate succession. User feedback clarified that future multi-thread wake-ups should be spaced out slightly. This is a coordination preference for the local thread orchestration flow and should be treated as the default behavior unless a task is explicitly urgent enough to justify simultaneous wake-ups.

### Suggested Action
In H-thread scheduling, insert a short delay between consecutive wake-ups of A/B/Test so mailbox writes and window focus automation do not overlap too tightly.

### Metadata
- Source: user_feedback
- Related Files: 绾跨▼璋冨害/H_A_H/H_A.txt, 绾跨▼璋冨害/H_B_H/H_B.txt, run-thread-work.ps1
- Tags: correction, thread-scheduling, wakeup-timing

---

## [LRN-20260313-008] correction

**Logged**: 2026-03-13T22:13:30+08:00
**Priority**: medium
**Status**: pending
**Area**: docs

### Summary
Worker-thread mailbox tasks and receipts should keep only the latest round and clear old text immediately after reading.

### Details
User clarified that worker threads should also follow a strict read-and-delete/read-and-clear mailbox discipline so task context does not grow turn after turn. The rule applies beyond H-thread receipt handling: A/B/T should clear incoming mailbox files after reading and avoid echoing old task text back in receipts.

### Suggested Action
When dispatching or updating worker tasks, explicitly remind A/B/T to clear mailbox files right after reading and to keep receipts limited to the latest round's outcome.

### Metadata
- Source: user_feedback
- Related Files: 绾跨▼璋冨害/A绾跨▼.txt, 绾跨▼璋冨害/B绾跨▼.txt, 绾跨▼璋冨害/T绾跨▼.txt, 绾跨▼璋冨害/H_A_H/H_A.txt
- Tags: correction, thread-scheduling, mailbox-hygiene

---

## [LRN-20260313-009] correction

**Logged**: 2026-03-13T22:34:17.1614917+08:00
**Priority**: medium
**Status**: pending
**Area**: docs

### Summary
Empty worker task files usually mean the worker thread already read and cleared them, not that the task content changed unexpectedly.

### Details
While coordinating H/A/B/T mailboxes, I interpreted an emptied H_A.txt as if the task content had changed and needed to be re-read before overwrite. User clarified the actual meaning: other worker threads also follow the read-then-delete/read-then-clear rule, so an empty H_A.txt is normally expected after the worker consumes it. The correction applies to my own mailbox interpretation logic, not as a new rule for A.

### Suggested Action
When inspecting H_A.txt, H_B.txt, or H_t.txt, treat an empty file as evidence the worker likely consumed the task. Do not describe that state as unexpected content drift unless there is separate evidence of task loss.

### Metadata
- Source: user_feedback
- Related Files: 绾跨▼璋冨害/H_A_H/H_A.txt, 绾跨▼璋冨害/H_B_H/H_B.txt, 绾跨▼璋冨害/H_T_H/H_t.txt
- Tags: correction, thread-scheduling, mailbox-interpretation

---
## [LRN-20260313-010] best_practice

**Logged**: 2026-03-13T23:53:14.7340394+08:00
**Priority**: medium
**Status**: pending
**Area**: tests

### Summary
Use the absolute DevEco SDK `hdc.exe` path for simulator automation instead of assuming `hdc` is on the current PowerShell PATH.

### Details
During the whiteboard simulator regression run, `hdc` commands that had worked earlier failed with `CommandNotFoundException` because the current PowerShell environment did not have `hdc` on PATH. The reliable executable was `C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe`. Switching all simulator install, start, dumpLayout, screenCap, and uiInput calls to that absolute path made the run stable again.

### Suggested Action
For future Harmony simulator smoke or regression runs in this workspace, call `C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe` explicitly unless PATH has been verified in the active shell first.

### Metadata
- Source: error
- Related Files: scripts/check-simulator-smoke-prereqs.mjs, tmp/wb_resume_layout.json
- Tags: harmony, simulator, hdc, powershell, environment

---
## [LRN-20260314-001] best_practice

**Logged**: 2026-03-14T00:36:00+08:00
**Priority**: medium
**Status**: pending
**Area**: tests

### Summary
On this Harmony simulator, `uitest dumpLayout` should be captured by receiving the generated remote file, not by redirecting stdout.

### Details
During the Round 2 whiteboard regression run, piping `hdc shell uitest dumpLayout` directly to a local `*_layout.json` file produced only a short placeholder like `DumpLayout saved to:/data/local/tmp/layout_....json`, not the actual layout tree. The reliable flow was: run `uitest dumpLayout`, parse the emitted remote path, then `hdc file recv` that path into `tmp/`. This produced the full layout JSON used for the targeted verification artifacts.

### Suggested Action
For future Harmony simulator evidence capture, treat `uitest dumpLayout` as a two-step operation: request the dump, parse the remote file path, and pull that file locally before analyzing it.

### Metadata
- Source: error
- Related Files: tmp/wb_r2_color_plus_layout.json, tmp/wb_r2_reopened_editor_layout.json
- Tags: harmony, simulator, dumpLayout, evidence-capture

---
## [LRN-20260315-001] correction

**Logged**: 2026-03-15T10:20:00+08:00
**Priority**: high
**Status**: pending
**Area**: tests

### Summary
When validating left-docked toolbar collapse/restore on the Harmony simulator, the second click must use the live collapsed-state bounds, not the pre-collapse tool coordinates.

### Details
During rebuilt/reinstalled whiteboard verification, the active left-side pen button moved downward after the first click collapsed the property column: the toolbar root changed from [54,358][603,1231] to [54,409][198,1282], and the active pen moved from [83,491][173,581] to [83,542][173,632]. Reusing the original expanded-state click point can miss the active tool and create a false "restore still broken" result. The reliable method is: capture dumpLayout after collapse, read the active tool's new bounds, then click that live center for the restore step.

### Suggested Action
For future WB-TOOLBAR-02 or similar simulator regressions, always recapture layout after the first collapse interaction and drive the second click from the collapsed state's live tool bounds before filing a blocker.

### Metadata
- Source: conversation
- Related Files: tmp/wb_left_collapsed_live.json, tmp/wb_left_restored_live.json
- Tags: harmony, simulator, toolbar, regression, live-bounds

---
## [LRN-20260316-001] best_practice

**Logged**: 2026-03-16T00:05:00+08:00
**Priority**: high
**Status**: pending
**Area**: frontend

### Summary
For Harmony ArkTS preview components backed by a stable file URI, use a preview-version key such as generatedAt/objectCount to force subtree remounts; do not place side-effect statements before the root container in build().

### Details
During simulator whiteboard verification, preview-raster.png was rewritten in place under the same file URI after each finger stroke. A PreviewThumbnail instance that keyed only on the URI kept showing the old blank PixelMap even though preview.json and the raster file had updated. Attempting to trigger a reload by inserting an if-statement before the root Stack in build() caused an ArkTS compiler failure because an @Entry component build method must have exactly one root container and cannot start with standalone statements. The reliable pattern was: fold generatedAt/objectCount into the raster key and use a keyed ForEach subtree with onAppear to remount and reload the PixelMap when preview payloads change under a stable URI.

### Suggested Action
For ArkTS components that render cacheable assets from a fixed path, treat a payload version field as part of the component identity and refresh via keyed subtree/lifecycle hooks instead of pre-root imperative code in build().

### Metadata
- Source: conversation
- Related Files: entry/src/main/ets/components/PreviewThumbnail.ets
- Tags: harmony, arkts, preview, image-cache, lifecycle

---
## [LRN-20260316-002] correction

**Logged**: 2026-03-16T00:45:00+08:00
**Priority**: high
**Status**: pending
**Area**: tests

### Summary
If the current T-thread test does not pass, preserve the already-working executable test operations as a rerun script after reporting to H, reuse that script on the next same-test request, and delete it once the test passes.

### Details
The user added a new workflow rule for repeated simulator acceptance loops. When the current validation is still failed or blocked, T should not stop at writing T_H.txt. After the feedback is written, T should convert the executable test steps that already work into a reusable script so the same scenario can be replayed quickly next time. If H later asks for the same test again, T should run that saved script first, then return the updated result. When the test finally passes, the temporary rerun script should be removed so stale scripts do not accumulate.

### Suggested Action
For repeated T-thread validation loops, save the stable executable steps into a rerun script after a failed/blocked round, mention the script path in the handoff when relevant, reuse it on the next same-test request, and delete it immediately after the scenario passes.

### Metadata
- Source: user_feedback
- Related Files: 线程调度/T线程.txt, 线程调度/T线程补充规则.md, .learnings/LEARNINGS.md
- Tags: tests, thread-scheduling, rerun-script, regression

---
## [LRN-20260316-003] best_practice

**Logged**: 2026-03-16T00:42:27.3439269+08:00
**Priority**: high
**Status**: pending
**Area**: tests

### Summary
On the Harmony simulator, `hdc shell uitest uiInput swipe` should not be assumed to drive the ArkTS gesture layer that simulator-stub preview overlays listen to.

### Details
During the Round 7 whiteboard same-session preview investigation, B added a temporary ArkTS live-ink overlay tied to `updateSimulatorFingerGesture()` / `finishSimulatorFingerGesture()`. Rebuilt and reinstalled verification still showed no immediate line at 200 ms or 700 ms after `hdc shell uitest uiInput swipe 250 620 800 670 700`, while the preview appeared only later through the preview/autosave path. That indicates this hdc-driven swipe is sufficient to change native stroke state, but is not a reliable proof that ArkTS gesture hooks fired in the same way. Simulator regressions that use hdc swipe therefore need evidence from native/debug state or preview payload timing, not just ArkTS-side touch overlays.

### Suggested Action
For simulator-stub regressions driven by `hdc uitest uiInput swipe`, verify the input path with native/debug evidence before investing in ArkTS-only gesture overlays, and treat any ArkTS overlay experiment as non-authoritative unless the same path is proven to receive those events.

### Metadata
- Source: conversation
- Related Files: entry/src/main/ets/pages/EditorWorkspace.ets, tmp/b_round7_final_fast.png, tmp/b_round7_final_wait.png
- Tags: harmony, simulator, hdc, gesture-path, verification

---
