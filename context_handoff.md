# Context Handoff

Date: 2026-03-08

## Current Objective

This round is only for HarmonyOS `x86_64` simulator smoke closure.

- Do not expand PDF work.
- Do not expand handwriting engine work.
- Do not add new product features.
- The head thread owns the only acceptance record.

Required smoke order:

1. `SIM-STUB-01`
2. `SIM-HOME-01`
3. `SIM-EDITOR-01`
4. `SIM-X86-01` non-blocking

Routing rules:

- Route to A: install/start failures, ABI mismatch, native module load failures, `getDebugState()` contract issues, simulator stub contract issues, `x86_64` placeholder output issues.
- Route to B: once install/start is healthy and `getDebugState()` plus stub banner/capability are correct, all page/UI/editor/preview issues default to B.
- Route to test: preflight, reproduction, regression, and result confirmation only.

## Current Verified State

- `hdc list targets`: passed
- Current simulator target: `127.0.0.1:5555`
- `entry-simulator-unsigned.hap` installs successfully on the official `x86_64` simulator.
- `aa start -b com.example.myapplication -a EntryAbility -W` succeeds.
- Package/runtime startup is currently not the blocking issue.

Current blocking symptom inside the app:

- Home page renders `Failed to open the local library.`
- Added runtime logging shows `bootstrap failed: {"code":13900002}`
- Local HarmonyOS SDK constants map `13900002` to `ERR_ENOENT`
- Interpretation: current blocker is a missing file or directory during ArkTS-side bootstrap, not install/start/stub loading

## Head Thread Role

The head thread should not continue writing product code in this round.

The head thread is responsible for:

- owning the single acceptance result in [docs/native-note-simulator-smoke-results.md](C:/Users/lasrorder/hw/MyApplication/docs/native-note-simulator-smoke-results.md)
- dispatching A, B, and test work
- updating handoff documents
- deciding route based on the first failing layer
- re-running acceptance only after A/B returns a fix

## Current Dispatch

### A Thread

Status: standby

Scope:

- `build-profile.json5`
- `entry/build-profile.json5`
- `entry/src/main/cpp/napi_bridge.cpp`
- `entry/src/main/cpp/napi_init.cpp`
- `entry/src/main/cpp/napi_runtime_simulator.cpp`
- `getDebugState()`
- simulator stub contract
- `x86_64` placeholder outputs

Current expectation:

- No new A-side action is required unless B proves the bootstrap `ENOENT` is caused by native capability/stub output or unless `SIM-X86-01` becomes actionable.

### B Thread

Status: active owner

Scope:

- `entry/src/main/ets/services/DocumentLibraryService.ets`
- `entry/src/main/ets/services/AppSettingsService.ets`
- `entry/src/main/ets/pages/Index.ets`
- `entry/src/main/ets/pages/EditorWorkspace.ets`
- `entry/src/main/ets/components/PreviewThumbnail.ets`
- `entry/src/main/ets/services/NativeNoteEngine.ets`

Primary task:

- Root-cause and fix the ArkTS bootstrap `ENOENT(13900002)` that prevents the local library from opening on simulator startup.

After that:

- rerun `SIM-HOME-01`
- rerun `SIM-EDITOR-01`
- rerun `SIM-STUB-01` only if editor entry becomes available

### Test Thread

Status: blocked on B return

Scope:

- preflight
- reproduction
- targeted regression
- final confirmation

Current expectation:

- Do not change code.
- Do not change the smoke script.
- Wait for B return, then rerun target cases and report only case/result/blocker.

## Acceptance Gate

The round is accepted only when:

- `SIM-STUB-01` is passed
- `SIM-HOME-01` is passed
- `SIM-EDITOR-01` is passed
- `SIM-X86-01` is either passed or `skipped-no-x86-placeholder`

Real-device items remain `blocked-by-device` and are out of scope for this round.
