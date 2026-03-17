## [ERR-20260311-001] hvigor-cache-workspace-missing

**Logged**: 2026-03-11T00:00:00+08:00
**Priority**: high
**Status**: pending
**Area**: config

### Summary
Hvigor failed because the cached workspace under the user profile was partially broken.

### Error
```text
ENOENT: no such file C:\Users\lasrorder\.hvigor\project_caches\bf05a3c616a7644b20dd9de65613704b32b314679bec6d21d32d4e47b72a95ea\workspace\node_modules\@ohos\hvigor\bin\hvigor.js
```

### Context
- Command attempted: `hvigorw.bat tasks --mode project -p product=simulator`
- Environment: DevEco Studio Hvigor on Windows
- Follow-up sandbox retry hit `EPERM` when Hvigor tried to recreate the same cache under `C:\Users\lasrorder\.hvigor`

### Suggested Fix
Delete the specific broken cache workspace under `.hvigor/project_caches/.../workspace` and rerun the build outside the sandbox so Hvigor can recreate its cache.

### Metadata
- Reproducible: unknown
- Related Files: .hvigor/outputs/build-logs/build.log

---

## [ERR-20260313-001] apply_patch-non-utf8-thread-file

**Logged**: 2026-03-13T00:38:06.2985536+08:00
**Priority**: medium
**Status**: pending
**Area**: docs

### Summary
`apply_patch` could not clear the thread dispatch file because the file contents were not valid UTF-8.

### Error
```text
apply_patch verification failed: Failed to read file C:\Users\lasrorder\hw\MyApplication\线程调度\H_T_H\H_t.txt: stream did not contain valid UTF-8
```

### Context
- Operation attempted: clear `线程调度\H_T_H\H_t.txt` at the start of a T-thread work run
- Expected method: `apply_patch`
- Fallback that worked: `Set-Content -LiteralPath 'C:\Users\lasrorder\hw\MyApplication\线程调度\H_T_H\H_t.txt' -Value '' -Encoding utf8`

### Suggested Fix
Treat thread handoff files as potentially non-UTF-8 and use PowerShell file APIs for read, clear, and write operations instead of `apply_patch`.

### Metadata
- Reproducible: yes
- Related Files: 线程调度\H_T_H\H_t.txt, .learnings/ERRORS.md

---

## [ERR-20260311-004] thread-wake-script-missing

**Logged**: 2026-03-11T17:50:52.0131866+08:00
**Priority**: high
**Status**: pending
**Area**: docs

### Summary
The thread-dispatch docs require `run-thread-work.ps1`, but the script is not present anywhere in the repository.

### Error
```text
The argument '.\run-thread-work.ps1' to the -File parameter does not exist. Provide the path to an existing '.ps1' file as an argument to the -File parameter.
```

### Context
- Command attempted: `powershell -ExecutionPolicy Bypass -File .\run-thread-work.ps1 -ThreadName "H" -ExecutorThreadName "A"`
- Working directory: `C:\Users\lasrorder\hw\MyApplication`
- Follow-up search under the repo found no `run-thread-work.ps1`, while `线程调度/README.md` documents it as available.

### Suggested Fix
Add the missing `run-thread-work.ps1` script to the repo or update the thread-dispatch docs to point at the real wake-up mechanism.

### Metadata
- Reproducible: yes
- Related Files: 线程调度\README.md, 线程调度\A线程.txt

---

## [ERR-20260311-002] hdc-path-assumption

**Logged**: 2026-03-11T16:18:00+08:00
**Priority**: medium
**Status**: pending
**Area**: config

### Summary
Using a hard-coded user-profile HarmonyOS SDK path for `hdc.exe` failed because this machine exposes `hdc` under the DevEco Studio SDK directory instead.

### Error
```text
& : 无法将“C:\Users\lasrorder\AppData\Local\Huawei\Sdk\openharmony\10\toolchains\hdc.exe”项识别为 cmdlet、函数、脚本文件或可运行程序的名称。
```

### Context
- Command attempted: `& 'C:\Users\lasrorder\AppData\Local\Huawei\Sdk\openharmony\10\toolchains\hdc.exe' list targets`
- Environment: Windows + DevEco Studio HarmonyOS simulator workflow
- Actual path discovered: `C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe`

### Suggested Fix
Prefer `where.exe hdc` first, or fall back to the DevEco Studio SDK toolchain path instead of assuming a user-profile SDK location.

### Metadata
- Reproducible: yes
- Related Files: .learnings/ERRORS.md

---

## [ERR-20260311-003] thread-readme-path-mismatch

**Logged**: 2026-03-11T17:50:31+08:00
**Priority**: medium
**Status**: pending
**Area**: docs

### Summary
The H-thread dispatch guide points to a root `README.md`, but the actual wake-up instructions live under `线程调度/README.md`.

### Error
```text
Get-Content : 找不到路径“C:\Users\lasrorder\hw\MyApplication\README.md”，因为该路径不存在。
```

### Context
- Command attempted: `Get-Content -Path 'C:\Users\lasrorder\hw\MyApplication\README.md'`
- Source instruction file: `线程调度/H线程调度流程说明.txt`
- Actual file discovered: `线程调度/README.md`

### Suggested Fix
Update `线程调度/H线程调度流程说明.txt` to reference `线程调度/README.md`, or add a root-level pointer document to avoid dispatch setup confusion.

### Metadata
- Reproducible: yes
- Related Files: 线程调度/H线程调度流程说明.txt, 线程调度/README.md

---

## [ERR-20260311-004] thread-wake-script-missing

**Logged**: 2026-03-11T18:00:00+08:00
**Priority**: high
**Status**: resolved
**Area**: docs

### Summary
The thread-dispatch docs require `run-thread-work.ps1`, but no such script exists anywhere in the repository.

### Error
```text
Get-Content : 找不到路径“C:\Users\lasrorder\hw\MyApplication\run-thread-work.ps1”，因为该路径不存在。
```

### Context
- Command attempted: `Get-Content -Raw 'C:\Users\lasrorder\hw\MyApplication\run-thread-work.ps1'`
- Follow-up searches for `run-thread-work.ps1`, `run-thread-work*`, and `*.ps1` under the workspace returned no results
- Dispatch docs still instruct operators to execute `powershell -ExecutionPolicy Bypass -File .\run-thread-work.ps1 ...`

### Suggested Fix
Either add the missing `run-thread-work.ps1` script at the documented location or update the dispatch documentation to reference the real automation entrypoint.

### Metadata
- Reproducible: yes
- Related Files: 线程调度/README.md, 线程调度/H线程调度流程说明.txt

---

## [ERR-20260313-001] hvigor-cache-rebuild-permission

**Logged**: 2026-03-13T00:56:33.0379906+08:00
**Priority**: medium
**Status**: pending
**Area**: build

### Summary
After deleting a broken Hvigor project cache, the simulator build failed inside the sandbox because Hvigor needed to recreate files under `C:\Users\lasrorder\.hvigor`.

### Error
```text
ENOENT: no such file C:\Users\lasrorder\.hvigor\project_caches\6f96e0621eb9065e01aa58bc2afabbed4ea46cc5c4a319e529a6e6b62b638d46\workspace\node_modules\@ohos\hvigor\bin\hvigor.js
EPERM: operation not permitted, mkdir 'C:\Users\lasrorder\.hvigor\project_caches\6f96e0621eb9065e01aa58bc2afabbed4ea46cc5c4a319e529a6e6b62b638d46\workspace\node_modules\@ohos'
```

### Context
- Command attempted: `hvigorw.bat assembleApp --mode project -p product=simulator --info`
- First failure pointed to a missing external Hvigor cache workspace.
- Deleting that cache path fixed the stale state, but the follow-up build still needed non-sandbox write access to recreate `C:\Users\lasrorder\.hvigor\project_caches\...`.
- Re-running the same build command outside the sandbox succeeded immediately.

### Suggested Fix
When Hvigor reports missing files under `C:\Users\lasrorder\.hvigor\project_caches\...`, clear the specific broken cache directory and rerun `assembleApp` with permission to write the external Hvigor cache.

### Metadata
- Reproducible: yes
- Related Files: .hvigor/outputs/build-logs/build.log

---
## [ERR-20260313-001] git-worktree-remove

**Logged**: 2026-03-13T01:20:00+08:00
**Priority**: medium
**Status**: pending
**Area**: config

### Summary
Windows ��ɾ���� worktree ʱ��`git worktree remove --force` ������·��ʧ�ܡ�

### Error
```
error: failed to delete 'C:/Users/lasrorder/hw/MyApplication/.worktrees/editor-embedded-ui-b': Filename too long
```

### Context
- Command attempted: `git worktree remove --force '.worktrees\\editor-embedded-ui-b'`
- Worktree contained many nested tmp/build artifacts from B/Test runs
- Environment: Windows PowerShell workspace on NTFS

### Suggested Fix
����֧�ֳ�·������ʽĿ¼ɾ����ʽ�Ƴ�����Ŀ¼����ִ�� `git worktree prune --expire now` ���� git ע�ᡣ

### Metadata
- Reproducible: yes
- Related Files: .worktrees/editor-embedded-ui-b

---

## [ERR-20260313-002] harmony-uitest-embed-placement-drag

**Logged**: 2026-03-13T13:48:00+08:00
**Priority**: medium
**Status**: pending
**Area**: tests

### Summary
On the Harmony x86_64 simulator, `hdc shell uitest uiInput drag` can drive surface finger-writing and overflow pan, but it did not reliably trigger the text-tool embed placement overlay into the composer modal after placement was armed.

### Error
```text
Observed behavior: after the `����ͼ��` button switched to `ȡ������` and the trace message changed to �����ڵ�ǰҳ�ϳ�ͼ�Ŀ�����, repeated `uiInput drag` gestures on the active page kept the UI in armed state instead of opening the composer modal.
```

### Context
- Commands attempted: multiple `hdc shell uitest uiInput drag <x1> <y1> <x2> <y2> 700` gestures on the active page after arming embed placement from the text tool.
- Environment: `runtimeProfile=simulator-stub` on the Harmony x86_64 simulator (`127.0.0.1:5555`).
- Same session confirmed that `uiInput drag` still updated finger counters/strokes and that overflow free-pan worked under simulator zoom, so the limitation appears specific to the embed placement gesture path.

### Suggested Fix
When validating the embed composer on simulator, do not assume `uiInput drag` can drive every PanGesture-based overlay the same way it drives surface pan. Prefer a second verification path, such as direct tap/selection automation on the overlay, or treat this as a simulator automation gap and verify the composer path separately.

### Metadata
- Reproducible: yes
- Related Files: entry/src/main/ets/pages/EditorWorkspace.ets, .worktrees/simulator-finger-pan-validation-a/tmp/t_a_fix_insert_arm_actual.jpeg

---## [ERR-20260313-003] hvigor-worktree-cache-rerun

**Logged**: 2026-03-13T14:16:12.1647221+08:00
**Priority**: medium
**Status**: pending
**Area**: config

### Summary
在独立 worktree 中二次执行 `assembleApp` 时，Hvigor 可能命中损坏的外部 project cache，导致复跑失败，即使前一次构建已经成功。

### Error
```text
ERROR: 00308003 Operation Error
Error Message: ENOENT: no such file C:\Users\lasrorder\.hvigor\project_caches\a70d15d4daf7838e259339491f07bc55fcb270e720c867ae7668204fb44abf38\workspace\node_modules\@ohos\hvigor\bin\hvigor.js
* Try the following:
  > delete C:\Users\lasrorder\.hvigor\project_caches\a70d15d4daf7838e259339491f07bc55fcb270e720c867ae7668204fb44abf38\workspace and retry.
```

### Context
- Command attempted: `hvigorw.bat assembleApp -p product=simulator -p buildMode=release -i`
- Environment: `C:\Users\lasrorder\hw\MyApplication\.worktrees\finger-coordinate-alignment-a`
- The first simulator release build in the same worktree completed successfully.
- The failure only appeared on a follow-up rerun used to capture the final log tail.

### Suggested Fix
如果第一次构建已经成功，不要为了截取尾日志立刻重复执行 `assembleApp`。若必须复跑并出现该错误，先清理对应的 `C:\Users\lasrorder\.hvigor\project_caches\...\workspace` 缓存，再重新构建。

### Metadata
- Reproducible: yes
- Related Files: C:\Users\lasrorder\.hvigor\project_caches\a70d15d4daf7838e259339491f07bc55fcb270e720c867ae7668204fb44abf38\workspace

---## [ERR-20260313-004] harmony-layout-dump-not-strict-json

**Logged**: 2026-03-13T15:05:00+08:00
**Priority**: low
**Status**: pending
**Area**: tests

### Summary
Harmony UI layout dump files named `*_layout.json` may not be strict JSON and can fail `ConvertFrom-Json`.

### Error
```text
ConvertFrom-Json : The supplied object is invalid. Expected ':' or '}'.
```

### Context
- Operation attempted: parse `tmp/*_layout.json` artifacts from simulator validation with PowerShell `ConvertFrom-Json`
- The dump file still contained useful OCR/text content, but the serialized structure was not valid enough for strict JSON parsing
- Regex extraction against the raw file worked and was sufficient to recover fields like `runtimeProfile`, `surface`, `page=`, `objects=`, and zoom text

### Suggested Fix
Treat Harmony `*_layout.json` artifacts as semi-structured text first. If strict JSON parsing fails, fall back to raw-text regex extraction instead of retrying `ConvertFrom-Json`.

### Metadata
- Reproducible: yes
- Related Files: .worktrees/page-scale-stability-b/tmp/t_b_scale_zoom_before_switch_layout.json

---## [ERR-20260313-005] apply-patch-nonutf8-thread-file

**Logged**: 2026-03-13T20:52:25+08:00
**Priority**: low
**Status**: pending
**Area**: docs

### Summary
`apply_patch` could not update the thread handoff file because `H_t.txt` was not valid UTF-8.

### Error
```text
apply_patch verification failed: Failed to read file to update C:\Users\lasrorder\hw\MyApplication\�̵߳���\H_T_H\H_t.txt: stream did not contain valid UTF-8
```

### Context
- Operation attempted: clear `�̵߳���/H_T_H/H_t.txt` immediately after reading it per thread workflow
- The file content was readable via PowerShell `Get-Content`, but `apply_patch` rejected it because the underlying stream was not valid UTF-8
- Fallback used: PowerShell `Clear-Content` to preserve the thread workflow instead of blocking on encoding conversion

### Suggested Fix
For thread mailbox files that may be GBK/ANSI encoded, use PowerShell file primitives (`Get-Content`, `Clear-Content`, `Set-Content`) instead of `apply_patch`, or normalize the mailbox files to UTF-8 before patch-based edits.

### Metadata
- Reproducible: yes
- Related Files: C:\Users\lasrorder\hw\MyApplication\�̵߳���\H_T_H\H_t.txt

---
## [ERR-20260313-006] apply-patch-non-utf8-thread-files

**Logged**: 2026-03-13T20:53:38.8371570+08:00
**Priority**: medium
**Status**: pending
**Area**: docs

### Summary
`apply_patch` cannot update non-UTF-8 thread mailbox files in this workspace.

### Error
```text
apply_patch verification failed: Failed to read file to update C:\Users\lasrorder\hw\MyApplication\...\H_B_H\H_B.txt: stream did not contain valid UTF-8
```

### Context
- Operation attempted: clear the B thread mailbox and write a handoff receipt
- PowerShell could read the mailbox content, but `apply_patch` rejected the file before patching because the stream was not valid UTF-8
- Safe fallback was to rewrite the mailbox files with PowerShell/.NET and normalize the final output to BOM-free UTF-8 or zero-byte empty content

### Suggested Fix
Before editing thread mailbox files, assume legacy or non-UTF-8 encoding is possible. If `apply_patch` fails on encoding, switch to an explicit PowerShell/.NET rewrite path and normalize the rewritten files.

### Metadata
- Reproducible: yes
- Related Files: H_B_H/H_B.txt, H_B_H/B_H.txt

---## [ERR-20260313-007] apply-patch-thread-mailbox-context-mismatch

**Logged**: 2026-03-13T23:15:00+08:00
**Priority**: low
**Status**: pending
**Area**: docs

### Summary
`apply_patch` can miss thread mailbox files even when PowerShell just read them successfully, so direct overwrite is the more reliable fallback for mailbox coordination.

### Error
```text
apply_patch verification failed: Failed to find expected lines in C:\Users\lasrorder\hw\MyApplication\线程调度\H_T_H\T_H.txt
```

### Context
- Operation attempted: clear `T_H.txt` and write the next-round B task in `H_B.txt`
- PowerShell `Get-Content -Raw` immediately before the patch returned the current mailbox content
- `apply_patch` still failed to match the expected lines, likely because mailbox text/line endings changed outside the patcher's exact context expectations
- Safe fallback was to use `Set-Content` for mailbox-only files so thread coordination would not stall

### Suggested Fix
For thread mailbox `.txt` files, prefer direct `Set-Content`/`Clear-Content` style overwrites once content has been read and accepted, rather than relying on context-sensitive patch hunks.

### Metadata
- Reproducible: intermittent
- Related Files: C:\Users\lasrorder\hw\MyApplication\线程调度\H_T_H\T_H.txt, C:\Users\lasrorder\hw\MyApplication\线程调度\H_B_H\H_B.txt

---
## [ERR-20260315-002] hdc-command-unavailable

**Logged**: 2026-03-15T22:44:00+08:00
**Priority**: medium
**Status**: pending
**Area**: config

### Summary
Attempted to verify simulator connectivity for manual uiInput reproduction, but `hdc` is not available in the current shell environment.

### Error
```text
Get-Command : 无法将“hdc”项识别为 cmdlet、函数、脚本文件或可运行程序的名称。
hdc : 无法将“hdc”项识别为 cmdlet、函数、脚本文件或可运行程序的名称。
```

### Context
- Operation attempted: confirm simulator connectivity before trying a real `uiInput` blank-note finger-write repro
- Native/runtime build verification still succeeded via `hvigorw.bat -p product=simulator assembleApp`
- This blocks only the manual device/simulator repro path from this shell session

### Suggested Fix
Expose `hdc` on PATH for Codex shell sessions, or provide the absolute `hdc.exe` path in AGENTS/tooling docs so simulator validation can be invoked directly.

### Metadata
- Reproducible: yes
- Related Files: C:\Users\lasrorder\hw\MyApplication\AGENTS.md

---
