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

## [LRN-20260319-014] 竖向工具栏第二列不能使用 100% 宽度

### Trigger
用户再次指出竖向工具栏时，属性栏“还是一大块”，明确要求“只要两列，全部竖向排列”。

### Details
在竖向工具栏外层是 `Row(primaryColumn, secondaryColumn)` 的结构下，第二列如果继续使用 `width('100%')`，它会按外层容器宽度扩张，视觉上就会变成一整块属性卡，即使内部已经改成了竖排项也仍然不对。正确做法是给第二列显式的窄列宽度，并让内容按这条窄列排布。

### Suggested Action
以后处理竖向双列工具栏时，先单独定义 secondary column 的明确宽度，再决定内部排版；不要把双列布局里的第二列写成 `100%`。

### Metadata
- Source: user_feedback
- Related Files: entry/src/main/ets/pages/EditorWorkspace.ets
- Tags: correction, vertical-toolbar, width, ui

---

## [LRN-20260319-015] 竖向工具栏的颜色区应优先使用单列竖排

### Trigger
用户提供了参考图，明确要求“竖着排列”，箭头直接指向工具栏旁边的颜色列。

### Details
在竖向工具栏里，即使第二列整体已经是竖向布局，颜色芯片如果仍然按一行或两行横排显示，视觉上仍然和参考图不一致。用户预期的是颜色作为单独的一列，从上到下排列，和工具列并排。

### Suggested Action
以后实现竖向模式时，颜色面板默认先按单列竖排做；只有用户明确要求更多颜色同时可见时，再考虑多行横排。

### Metadata
- Source: user_feedback
- Related Files: entry/src/main/ets/pages/EditorWorkspace.ets
- Tags: correction, vertical-toolbar, colors, ui

---

## [LRN-20260319-016] 粗细预设优先使用纯图形黑色示意线

### Trigger
用户明确要求“把笔迹粗细的文字和数字描述去除，用黑色展示”，并指出横向工具栏里选中态的白色示意线不对。

### Details
粗细预设如果同时显示名称、数值和示意线，会让工具栏信息密度过高。对于这种笔记类书写工具，用户更希望直接用纯图形粗细条识别预设，并且示意线颜色保持黑色一致，不要随着选中态变成白色或跟随当前颜色。

### Suggested Action
以后处理粗细预设时，默认优先采用纯图形粗细条，除非用户明确要求显示名称或数值；示意线应保持黑色一致，选中态只通过背景和边框表达。

### Metadata
- Source: user_feedback
- Related Files: entry/src/main/ets/pages/EditorWorkspace.ets
- Tags: correction, width-presets, ui, visual-density

---

## [LRN-20260319-017] 竖向工具栏的粗细预设应使用单列窄按钮

### Trigger
用户在颜色列改成竖排后，继续指出“这三个笔迹也竖向展示”，并给出参考图说明粗细预设也应沿竖向工具栏方向收成单列。

### Details
竖向工具栏里，粗细预设如果仍然占满第二列宽度，会继续看起来像横向属性卡的残留。正确视觉应是三个窄按钮按单列堆叠，和颜色列同方向排列。

### Suggested Action
以后在竖向模式下，粗细预设默认使用固定窄宽度的单列按钮；不要让它们占满第二列。

### Metadata
- Source: user_feedback
- Related Files: entry/src/main/ets/pages/EditorWorkspace.ets
- Tags: correction, width-presets, vertical-toolbar, ui

---

## [LRN-20260319-018] 用户说“竖向展示”时，若明确提到可滑动，应实现纵向滚动容器

### Trigger
用户在粗细预设已经改成单列后，继续用截图标注“竖向展示，可以上下滑动”，说明他们要的不只是单列摆放，还要这个区域本身可纵向滑动。

### Details
对这类浮动工具栏来说，“竖向展示”可能包含两个层面：一是元素方向改成纵向；二是容器成为纵向滚动区。只做第一步会被认为还没对齐用户意图。

### Suggested Action
以后当用户在竖向工具栏场景里同时提到“上下滑动/可滑动”时，直接将对应区域实现为固定高度的纵向 `Scroll` 容器，而不是只改排列方向。

### Metadata
- Source: user_feedback
- Related Files: entry/src/main/ets/pages/EditorWorkspace.ets
- Tags: correction, vertical-scroll, toolbar, ui

---

## [LRN-20260319-019] “整个属性栏可以上下滑动”表示第二列整体是纵向 Scroll，不是局部子区块滚动

### Trigger
用户明确纠正：“不是只要笔迹栏可以上下滑动，我要的是整个属性栏可以上下滑动，竖着！”

### Details
把某个局部区域单独做成可滚动并不能满足这种需求。用户要求的是竖向工具栏的整个第二列属性面板作为一个整体纵向滚动，里面的颜色、粗细等模块都属于同一个滚动上下文。

### Suggested Action
以后遇到“整个属性栏上下滑动”这类表达时，直接把第二列实现为 `Scroll(Column)`，不要拆成多个各自滚动的子面板。

### Metadata
- Source: user_feedback
- Related Files: entry/src/main/ets/pages/EditorWorkspace.ets
- Tags: correction, property-panel, vertical-scroll, ui

---

## [LRN-20260319-020] 用户说“太长了，缩短”且用水平标线时，优先理解为横向长度过长

### Trigger
用户在最新截图里用一条水平红线标出竖向工具栏顶部宽度，并写“太长了，缩短”。

### Details
这种标注更可能是在说横向长度/宽度过长，而不是在说整体高度过高。如果此时继续只改高度，会偏离问题本身。

### Suggested Action
以后遇到“太长了，缩短”并伴随水平标线时，先检查容器宽度、内部横向留白和按钮宽度，而不是默认理解为高度问题。

### Metadata
- Source: user_feedback
- Related Files: entry/src/main/ets/pages/EditorWorkspace.ets
- Tags: correction, ui, width, interpretation

---

## [LRN-20260319-021] 用户说“展示部分也要竖着展示”时，通常指按钮本体和示意图都改为竖向风格

### Trigger
在粗细预设已经改成竖线示意后，用户继续发图指出仍然不对。

### Details
只把内部示意线从横线改成竖线还不够；如果按钮本体仍然是横向长条，用户依然会认为它是横向展示。需要把按钮本体也收成窄竖向按钮，整体视觉才会被理解为“竖着展示”。

### Suggested Action
以后遇到“展示部分也要竖着展示”这类反馈时，检查并同时调整按钮外形、容器宽度和内部示意图，不要只改内部图形方向。

### Metadata
- Source: user_feedback
- Related Files: entry/src/main/ets/pages/EditorWorkspace.ets
- Tags: correction, width-presets, visual-direction, ui

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
## [LRN-20260319-001] correction

**Logged**: 2026-03-19T13:41:37.3190564+08:00
**Priority**: high
**Status**: pending
**Area**: ui-layout

### Summary
For this editor, the writing page must use a full-width left-anchored model, not a centered card model, otherwise rail toggles and zoom changes produce visible horizontal jumps and fake canvas margins.

### Details
I initially adjusted the page width cap and action-group placement incrementally, but the user clarified the real requirement: the writing area should default to the screen edge, stick to the rail edge when the rail is open, and remove the yellow card-like canvas background entirely. The correct fix is structural: use the writing viewport width as the base page width, anchor `x` to the left edge instead of recomputing center offsets, clamp horizontal pan as a left-anchored range, and remove outer shell/card chrome that creates artificial margins.

### Suggested Action
When a layout complaint mentions rail toggles shifting the page or zoom feeling inconsistent, check first whether the page model is centered-card based. If so, switch to a left-anchored full-width layout before making cosmetic spacing tweaks.

### Metadata
- Source: user_feedback
- Related Files: entry/src/main/ets/pages/EditorWorkspace.ets
- Tags: correction, layout, rail, zoom, editor

---

## [LRN-20260319-003] correction

**Logged**: 2026-03-19T15:52:30
**Priority**: high
**Status**: pending
**Area**: frontend

### Summary
ETS rail layout changes alone were insufficient; weak-native-shell stroke input was still stored in surface coordinates, so rail collapse and debug zoom appeared visually unchanged.

### Details
User reported that rail collapse and debug zoom still showed the same blank-right-area behavior after multiple ETS-side fixes. The correct root cause was in native input handling inside entry/src/main/cpp/napi_init.cpp: render had started projecting points as page-space, but touch input still entered the pipeline as surface-space. The fix is to normalize input samples to page coordinates before selection, erasing, stroke capture, and commit logic.

### Suggested Action
When paged rendering depends on viewport size, verify input, storage, and render all use the same coordinate space before adjusting shell layout further.

### Metadata
- Source: user_feedback
- Related Files: entry/src/main/cpp/napi_init.cpp, entry/src/main/ets/pages/EditorWorkspace.ets
- Tags: harmonyos, native-shell, coordinate-space, rail, zoom
- See Also: LRN-20260319-002

---
## [LRN-20260319-004] correction

**Logged**: 2026-03-19T16:14:47.8679776+08:00
**Priority**: high
**Status**: pending
**Area**: frontend

### Summary
On the Harmony x86_64 simulator, rail-collapse and debug-zoom regressions may be caused by the `simulator-stub` preview layer reusing a stale `PreviewThumbnail` size, even when the outer writing page has already resized correctly.

### Details
After the user reported that the problem still existed, layout dumps showed the outer writing viewport and page shell expanding from 2074 to 2560 when the rail collapsed, but the inner preview subtree stayed at 2074. The runtime was `simulator-stub` (`stubReason=x86_64-simulator-uses-weak-native-shell`), so native surface fixes could not explain the on-screen result. The actual issue was that `previewThumbnailRenderKey()` only depended on snapshot freshness, not the rendered page width/height, so `PreviewThumbnail` was reused across rail and zoom changes and visually looked like it only moved instead of resizing.

### Suggested Action
For simulator-stub editor rendering, include the current rendered width and height in preview component keys or otherwise force the preview layer to rebuild when viewport size or page scale changes.

### Metadata
- Source: user_feedback
- Related Files: entry/src/main/ets/pages/EditorWorkspace.ets, entry/src/main/ets/components/PreviewThumbnail.ets
- Tags: correction, simulator-stub, preview, rail, zoom
- See Also: LRN-20260319-003, LRN-20260316-003

---

## [LRN-20260319-005] best_practice

**Logged**: 2026-03-19T00:00:00+08:00
**Priority**: medium
**Status**: pending
**Area**: frontend

### Summary
ArkTS ??? UI Builder ????? `Stack` ?? `Blank()`?????? `Array.from` ??????

### Details
??? `EditorWorkspace.ets` ???????????ArkTS ????????`Blank` ????? `Row/Column/Flex` ??? `Array.from({ length }, ...)` ? ArkTS ????? `arkts-no-inferred-generic-params` ? `arkts-no-any-unknown`?????????? `Stack` ??? `Column(){}` ????????????????? `for` ???? `number[]`?

### Suggested Action
??? ArkTS Builder ???? `Column(){}`/`Row(){}` ???????????????????????????

### Metadata
- Source: error
- Related Files: entry/src/main/ets/pages/EditorWorkspace.ets
- Tags: arkts, ui-builder, compile, custom-color

---

## [LRN-20260319-006] correction

**Logged**: 2026-03-19T17:35:00+08:00
**Priority**: high
**Status**: pending
**Area**: frontend

### Summary
For this editor, the custom color entry must use a continuous visible picker, not a stepped matrix or chip-based approximation.

### Details
I first replaced the broken custom-color popup with a stable but discrete selector made of recent chips, a tone matrix, and hue stops. The user clarified that this was still the wrong interaction model: they wanted the Huawei-style continuous HSB picker they had shown in the screenshot, or a ready-made official component. The correct fix path here is to integrate the official `painting_color_selector` component rather than iterating further on a homegrown stepped picker.

### Suggested Action
When the user references a concrete picker interaction like continuous hue/saturation/value dragging, do not substitute a discrete approximation even if it is visually cleaner or faster to ship. Prefer an existing official component when one is available and matches the required interaction model.

### Metadata
- Source: user_feedback
- Related Files: entry/src/main/ets/pages/EditorWorkspace.ets, market_components/painting_color_selector/painting_color_selector
- Tags: correction, color-picker, component-integration, ux

---
## [LRN-20260319-007] implementation

**Logged**: 2026-03-19T20:05:00+08:00
**Priority**: medium
**Status**: pending
**Area**: frontend

### Summary
The Huawei `painting_color_selector` component must stay mounted during color sampling; hide it visually instead of unmounting it.

### Details
The component stores its snapshot pixel map on the component instance and updates sampled colors through `@Monitor('touchX','touchY')`. If the host closes or unmounts the dialog when entering sampling mode, the component instance is destroyed and live sampling stops. The correct approach is to keep the dialog session alive, move the panel off-screen or make it invisible during sampling, and let the full-screen sampling overlay own touch input until release.

### Suggested Action
When integrating host-side color sampling UX around this component, keep `showCustomColorDialog` true, toggle a separate sampling mode flag, and only hide the visible panel. Do not unmount the `ColorSelector` instance until sampling is complete.

### Metadata
- Source: implementation
- Related Files: entry/src/main/ets/pages/EditorWorkspace.ets, market_components/painting_color_selector/painting_color_selector/src/main/ets/comp/ColorSelector.ets
- Tags: color-picker, sampling, component-lifecycle, arkui

---
## [LRN-20260319-008] correction

**Logged**: 2026-03-19T21:55:00+08:00
**Priority**: high
**Status**: pending
**Area**: frontend

### Summary
When compacting the floating toolbar, reducing internal density is not enough; the horizontal shell width and the primary-row button count must both shrink.

### Details
The user corrected that they wanted the toolbar narrower, not shorter. I had previously compressed labels and vertical spacing while leaving the horizontal shell at a width still dictated by the primary row (drag handle + tool buttons + more + finger). That produced a visually wide card even though controls were denser. The correct fix path is to reduce the horizontal outer width and reflow the primary row so it contains fewer buttons per row.

### Suggested Action
For horizontal toolbar compaction, measure the widest row first, then change outer width constants and row composition together. Do not treat text removal or vertical compression as a substitute for actual width reduction.

### Metadata
- Source: user_feedback
- Related Files: entry/src/main/ets/pages/EditorWorkspace.ets
- Tags: correction, toolbar, width, layout

---
## [LRN-20260319-009] correction

**Logged**: 2026-03-19T22:05:00+08:00
**Priority**: high
**Status**: pending
**Area**: frontend

### Summary
For the horizontal editor toolbar, the user wants an exact two-row structure, not a denser multi-row layout.

### Details
After shrinking widths, I still introduced a third row by splitting extra tools and width presets into separate lines. The user corrected that the horizontal layout requirement is structural: one row for tools and one row for properties, no more. The correct implementation is to collapse horizontal expanded state into exactly two rows even if that means removing some low-priority controls from the horizontal surface.

### Suggested Action
When the user specifies a row count for a compact layout, treat that as a hard structural requirement. Remove or defer secondary controls instead of preserving them through additional rows.

### Metadata
- Source: user_feedback
- Related Files: entry/src/main/ets/pages/EditorWorkspace.ets
- Tags: correction, toolbar, horizontal-layout, ux

---
## [LRN-20260319-010] correction

**Logged**: 2026-03-19T22:18:00+08:00
**Priority**: high
**Status**: pending
**Area**: frontend

### Summary
For the horizontal editor toolbar, preserve horizontal scrolling and tool reachability before optimizing size.

### Details
I over-focused on shrinking the floating toolbar shell and removed horizontal scrolling, which made several tools unreachable and broke the intended interaction. The user clarified that the target was to reduce the vertical height of the two-row horizontal layout, not to cut width at the expense of access. The correct fix is to keep the toolbar and property rows horizontally scrollable and only trim button size, spacing, and vertical padding.

### Suggested Action
When compacting a horizontally scrollable toolbar, treat scrollability and full tool access as non-negotiable. Reduce row height only after confirming all tools and properties remain reachable.

### Metadata
- Source: user_feedback
- Related Files: entry/src/main/ets/pages/EditorWorkspace.ets
- Tags: correction, toolbar, scrolling, accessibility

---
## [LRN-20260319-011] correction

**Logged**: 2026-03-19T22:32:00+08:00
**Priority**: high
**Status**: pending
**Area**: frontend

### Summary
For this toolbar, width adjustment controls must not remain permanently visible in the property row.

### Details
The user clarified that the property row should not always contain a width slider. Instead, the normal state should show width presets, and only a second tap on the currently selected preset should enter a dedicated adjustment sub-state inside the same property row. They also explicitly wanted the width value text rendered in black for readability.

### Suggested Action
Model preset selection and preset adjustment as two separate UI states. Keep the property row compact by default and only swap in the slider when the user explicitly re-enters width adjustment for the selected preset.

### Metadata
- Source: user_feedback
- Related Files: entry/src/main/ets/pages/EditorWorkspace.ets
- Tags: correction, width-control, toolbar, readability

---
## [LRN-20260319-012] correction

**Logged**: 2026-03-19T22:44:00+08:00
**Priority**: high
**Status**: pending
**Area**: frontend

### Summary
The vertical toolbar layout must not use a large fixed-height property card; it should remain a true two-column vertical arrangement.

### Details
After earlier fixes, the horizontal toolbar behavior was closer, but the user showed that the left-docked vertical mode still rendered the property area as a large fixed-height block beside the tool column. They explicitly wanted only two columns, both vertically arranged. The correct fix is to remove the tall property card structure, keep the secondary column segmented, and use width-adjust substate only when re-tapping the selected width preset.

### Suggested Action
For docked vertical editor toolbars, keep the primary tool column and secondary property column visually independent and vertically segmented. Avoid fixed-height scroll cards unless overflow is proven necessary.

### Metadata
- Source: user_feedback
- Related Files: entry/src/main/ets/pages/EditorWorkspace.ets
- Tags: correction, vertical-toolbar, layout, width-adjustment

---
## [LRN-20260319-013] correction

**Logged**: 2026-03-19T22:52:00+08:00
**Priority**: high
**Status**: pending
**Area**: frontend

### Summary
For the left-docked editor toolbar, the property column must be visually narrow even when its content is functionally correct.

### Details
After fixing the vertical property column behavior, the user screenshot still showed the secondary column reading as a large panel because color chips stayed on one row and width presets used long label buttons. The correct direction is to compress the visual width of the secondary column: split colors into multiple rows, convert width presets to compact buttons, and remove auxiliary hint text from the vertical property column.

### Suggested Action
When the user asks for a strict two-column vertical toolbar, optimize visual narrowness, not just interaction logic. Prefer short labels and multi-row chip groups over long horizontal runs inside the secondary column.

### Metadata
- Source: user_feedback
- Related Files: entry/src/main/ets/pages/EditorWorkspace.ets
- Tags: correction, vertical-toolbar, compactness, ui

---
- [2026-03-19] LRN-20260319-022: �ڸ���������������ģʽ��û�˵������չʾ��ʱ��ͨ��ָ�ؼ�����ҲҪխ������/���У������ǽ����Ѷ������Ƭ����ѵ�����Ҫͬʱ����ܿ��ȡ��ڶ�����С����ǯ�ơ��Լ��ؼ������Ŀ��߱ȡ�
- [2026-03-19] LRN-20260319-023: ʹ�� painting_color_selector ʱ������ͼ��������� await getComponentSnapshot(... waitUntilRenderFinished: true) ���л���ɫģʽ���󻭲��ϻ�������Կ�������������������Ӧ�ȴ�����ɫģʽ������壬���첽ȡ���գ����� touchX/touchY ������ readPixelsSync ����Լ 16ms ������

- [2026-03-19] �û�ָ���������ȡ��ɫ�󣬻��ǻῨ�������������Ŀ���ɫ�ڼ������ɫ�����Ϊ��͸�����ǲ����ģ�͸������Կ���ͣ���ڽ������ﲢ�̵����������¿������������޸�ʱӦ����ɫģʽ����ȫ��������壬�������Ƴ� market ���������� pixelMap/getComponentSnapshot/readPixelsSync ·����ֻ����������ȡɫ�߼���
