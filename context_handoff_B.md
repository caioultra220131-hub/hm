# Context Handoff B

Date: 2026-03-08

## Ownership

B owns only:

- ArkTS bootstrap
- document library flow
- home page
- editor page
- preview consumption/display
- simulator-stub UI behavior after native capability is already correct

Primary files:

- [DocumentLibraryService.ets](C:/Users/lasrorder/hw/MyApplication/entry/src/main/ets/services/DocumentLibraryService.ets)
- [AppSettingsService.ets](C:/Users/lasrorder/hw/MyApplication/entry/src/main/ets/services/AppSettingsService.ets)
- [Index.ets](C:/Users/lasrorder/hw/MyApplication/entry/src/main/ets/pages/Index.ets)
- [EditorWorkspace.ets](C:/Users/lasrorder/hw/MyApplication/entry/src/main/ets/pages/EditorWorkspace.ets)
- [PreviewThumbnail.ets](C:/Users/lasrorder/hw/MyApplication/entry/src/main/ets/components/PreviewThumbnail.ets)
- [NativeNoteEngine.ets](C:/Users/lasrorder/hw/MyApplication/entry/src/main/ets/services/NativeNoteEngine.ets)

## Current Head-Thread Diagnosis

This is the current active B-owned blocker:

- simulator install/start is already healthy
- app reaches `pages/Index`
- home page shows `Failed to open the local library.`
- runtime log shows `bootstrap failed: {"code":13900002}`
- HarmonyOS SDK constant mapping identifies `13900002` as `ERR_ENOENT`

Therefore the current working diagnosis is:

- ArkTS bootstrap is touching a missing file or directory
- current first-failure layer is B, not A

## Immediate B Tasks

1. Root-cause the exact file operation that throws `ENOENT(13900002)` during bootstrap.
2. Prioritize these paths:
   - `DocumentLibraryService.initialize()`
   - `DocumentLibraryService.seedDefaults()`
   - `DocumentLibraryService.createDocument()`
   - `AppSettingsService.getSettings()`
   - `AppSettingsService.writeEnvelope()`
   - any directory creation or JSON write/read around app bootstrap
3. Fix the ArkTS-side bootstrap failure without changing public native API surface.
4. After the fix, hand back:
   - root cause
   - changed files
   - exact regression cases to rerun
   - any remaining known risk

## Routing Rule Reminder

Do not bounce this back to A just because the failure happens early.

If the following are already true, the issue stays with B by default:

- app installs
- app starts
- `getDebugState()` is correct
- stub banner/capability contract is correct

Only reroute if B proves the ArkTS failure is downstream of wrong native/stub output.

## Expected Regression After B Return

The head thread and test thread will rerun:

1. `SIM-STUB-01`
2. `SIM-HOME-01`
3. `SIM-EDITOR-01`

`SIM-X86-01` remains non-blocking.

## Notes

There is already a provisional workspace patch in B-owned files from earlier local diagnosis. B should treat the current workspace state as input, review it, and decide whether to keep, revise, or supersede it.
