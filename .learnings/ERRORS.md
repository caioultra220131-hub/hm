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
