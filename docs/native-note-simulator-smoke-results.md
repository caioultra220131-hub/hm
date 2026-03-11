# Native Note Simulator Smoke Results

Date: 2026-03-08

## Summary

- `hdc list targets`: passed (`127.0.0.1:5555`)
- `hdc install -r entry-simulator-unsigned.hap`: passed
- `aa start -b com.example.myapplication -a EntryAbility -W`: passed
- `SIM-STUB-01`: passed
- `SIM-HOME-01`: passed
- `SIM-EDITOR-01`: passed
- `SIM-X86-01`: passed

## Current Head-Thread Conclusion

This round is accepted.

The simulator install/start path, home bootstrap, editor entry, simulator stub banner/capability, source toggle, save path, and back/reopen loop all completed successfully on the HarmonyOS `x86_64` simulator.

Remaining work is now product polish, not smoke unblocking. The next small iteration is `zh-CN` content conversion for visible UI copy and seeded demo content.

## Case Results

| Case | Status | Notes | Owner |
| --- | --- | --- | --- |
| `SIM-STUB-01` | `passed` | Editor opens on `pages/EditorWorkspace`; `runtimeProfile=simulator-stub` is visible; placeholder surface and stub banner render; trace actions remain disabled with unsupported messaging. | Head |
| `SIM-HOME-01` | `passed` | Fresh install + cold start lands on `pages/Index`; local library opens; seeded folders, tags, and documents are visible. | Head |
| `SIM-EDITOR-01` | `passed` | From home, document open succeeds; `Preview` and `Source` both render; `Save` path is exercised; `Back to library` returns to home; reopen succeeds. | Head |
| `SIM-X86-01` | `passed` | Combined acceptance: simulator UI shows placeholder surface, and A thread confirmed stable `x86_64` placeholder outputs for `requestPreviewRender` and `exportSceneSnapshot`. | Head + A |

## Next Dispatch

### To B Thread

Primary work order: none for this round. The second `zh-CN` pass has been accepted.

- follow-up work, if any, should move to a separate polish task or a future i18n/resource pass
- do not reopen simulator smoke unless behavior regresses

### To Test Thread

Current regression baseline is closed.

- keep `fresh install` as the required validation mode for future seeded-content localization checks
- no further action in this round unless a new patch lands

### To A Thread

Stay standby.

- no product-copy work
- re-engage only if the Chinese pass exposes native/stub/capability regressions

## Evidence

- layout capture files under [tmp](/C:/Users/lasrorder/hw/MyApplication/tmp)
- `myapp-acceptance-home.json`: seeded content visible on `pages/Index`
- `myapp-acceptance-editor.json`: editor opened on `pages/EditorWorkspace`
- `myapp-acceptance-trace.json`: trace controls present and disabled
- `myapp-acceptance-source.json`: `TextArea` rendered for source editing
- `myapp-acceptance-back.json`: returned to `pages/Index`
- `myapp-acceptance-reopen.json`: reopen path returns to `pages/EditorWorkspace`
- `reg-zh-home-fresh.json`: fresh install confirms home shell copy and seeded folders/tags are now Chinese
- `reg-zh-editor.json`: editor shell copy is mostly Chinese, but seeded demo title and several toolbar/tool labels still remain English
- `reg-zh-home-final.json`: fresh install confirms seeded demo titles, summaries, folder/tag labels, and home actions are Chinese
- `reg-zh-editor-final.json`: editor confirms Chinese toolbar/tool labels, Chinese document title, Chinese stub banner, and unchanged `runtimeProfile=simulator-stub`

## Post-Smoke Zh-CN Status

Core simulator smoke remains accepted after the Chinese patch build and fresh install.

The `zh-CN` pass is accepted for the current simulator scope:

- home shell copy is Chinese
- seeded folders, tags, document titles, and seeded markdown summaries are Chinese on fresh install
- editor shell copy such as back/save/preview/source/stub banner is Chinese
- editor toolbar and tool labels are Chinese
- technical/debug values intentionally remain raw where appropriate, such as `runtimeProfile=simulator-stub`, `OpenGL ES`, `Markdown`, `PDF`, and trace/debug state fields

Head-thread release decision:

- simulator smoke: accepted
- Chinese-content pass: accepted

## Release Gate

This round is accepted.

Accepted state:

- `SIM-STUB-01 = passed`
- `SIM-HOME-01 = passed`
- `SIM-EDITOR-01 = passed`
- `SIM-X86-01 = passed`

## Post-Smoke Follow-Up Status

The original simulator smoke acceptance remains valid.

Follow-up work after that acceptance now has two separate outcomes:

- A-thread `getDebugState()` contract alignment: accepted
- post-smoke editor layout refinement: accepted

### Accepted A-Thread Contract Patch

The native `getDebugState()` contract is now aligned across both `device-native` and `simulator-stub`.

- `device-native` now explicitly returns `previewRenderSupported`, `sceneExportSupported`, and `stubReason`
- `simulator-stub` now explicitly returns `previewRenderSupported`, `sceneExportSupported`, and `stubReason`
- ArkTS compatibility parsing remains unchanged, so this is a contract completion patch rather than an API break

Head-thread decision: A may return to standby after this patch.

### Accepted Layout Refinement

The latest layout build satisfies the visual target on fresh install:

- writing surface is again the first visual focus
- the toolbar is reduced toward a compact floating strip
- the right side is reduced toward a narrow page rail rather than a second workspace
- the first `Save` bounce regression is fixed
- trace long-press opens the panel again
- `Start Trace`, `Stop Trace`, and `Replay Last Trace` remain disabled in simulator stub mode
- a single tap on editor `Back` now returns to in-app `pages/Index`
- reopening the same document from home returns to `pages/EditorWorkspace`

Head-thread decision: mark the layout refinement as accepted.

### Current Ownership

- A thread: standby
- B thread: closed for this round
- test thread: closed for this round

## Post-Acceptance Hardening

The follow-up hardening pass is also accepted.

### Accepted A-Thread Native Consolidation

The native/stub layer was further consolidated without changing public API names or ArkTS call sites.

- `napi_runtime_simulator.cpp` and `napi_init.cpp` now share canonical helpers for preview, scene, and capability field emission
- `getDebugState`, `requestPreviewRender`, and `exportSceneSnapshot` schemas are pinned more explicitly in `NativeNoteEngine.test.ets`
- the simulator placeholder schema and device-native schema now share a more stable contract surface
- this cleanup does not touch `EditorWorkspace.ets`, `Index.ets`, or `DocumentLibraryService.ets`

Operational note from A thread:

- if hvigor fails under `.hvigor/project_caches/.../workspace`, delete that specific cache workspace first and rerun the build
- if `hvigor daemon: Current process status is busy` appears, retry before treating it as a native regression

### Accepted B-Thread ArkTS Cleanup

The ArkTS/UI layer was cleaned up after the feature pass without reopening the accepted simulator flows.

- `EditorWorkspace.ets` now centralizes visible editor copy under `EDITOR_WORKSPACE_COPY`
- `Index.ets` now centralizes visible home copy under `INDEX_COPY`
- `DocumentLibraryService.ets` continues seeded/demo copy under `SEEDED_DOCUMENTS` and `DOCUMENT_LIBRARY_COPY`
- temporary copy maps and ad-hoc builder-local text fragments were removed in favor of explicit constants
- the accepted `save`, `back`, `reopen`, and trace-long-press behavior remains intact

### Final Test Baseline

The frozen end-to-end regression baseline for this round is:

1. assemble latest simulator HAP
2. uninstall old app
3. install fresh
4. cold start into `pages/Index`
5. verify seeded Chinese home content
6. open a document into `pages/EditorWorkspace`
7. save and remain in `pages/EditorWorkspace`
8. single-tap back to in-app `pages/Index`
9. reopen the same document into `pages/EditorWorkspace`
10. long-press the canvas to open the trace panel
11. verify `Start Trace`, `Stop Trace`, and `Replay Last Trace` stay disabled

Head-thread final decision:

- simulator smoke: accepted
- Chinese-content pass: accepted
- layout refinement: accepted
- native/schema hardening: accepted
- ArkTS/UI cleanup: accepted

## M2 PDF/HYBRID Paged Import Pass

Date: 2026-03-11

This follow-up pass is accepted.

Scope covered in this round:

- imported `PDF` paged document creation
- imported `HYBRID` paged document creation
- page-aware open/save/back/reopen on imported paged docs
- preview metadata following the current active page
- invalid PDF import failure cleanup

Accepted results:

- `M2-PDF-IMPORT-01 = passed`
- `M2-HYBRID-IMPORT-01 = passed`
- `M2-ACTIVE-PREVIEW-01 = passed`
- `M2-INVALID-PDF-01 = passed`

Head-thread notes:

- `PDF` import now creates a real paged package, opens into the editor, saves on page 2, returns home, and reopens on page 2.
- `HYBRID` import now follows the same paged flow and also reopens on page 2 after save/back.
- home preview metadata now stays aligned with the active page; accepted value after saving page 2 is `pageIndex = 1` and `coverPageId = "page-1"`.
- invalid/non-PDF input is rejected without leaving a bad document row or half-written package.
- one interim HYBRID failure was caused by stale test click coordinates after the Create panel layout moved; live layout verification confirmed the CTA itself was functional, and the final rerun passed.
