# Context Handoff B

Date: 2026-03-11

## Ownership

B owns only:

- ArkTS import/create flow
- document package creation and persistence
- home page create panel
- editor page switching/save/back/reopen integration
- preview metadata persistence on the ArkTS side

Primary files remain:

- [DocumentLibraryService.ets](C:/Users/lasrorder/hw/MyApplication/entry/src/main/ets/services/DocumentLibraryService.ets)
- [Index.ets](C:/Users/lasrorder/hw/MyApplication/entry/src/main/ets/pages/Index.ets)
- [EditorWorkspace.ets](C:/Users/lasrorder/hw/MyApplication/entry/src/main/ets/pages/EditorWorkspace.ets)
- [NativeNoteEngine.ets](C:/Users/lasrorder/hw/MyApplication/entry/src/main/ets/services/NativeNoteEngine.ets)
- [PdfImportService.ets](C:/Users/lasrorder/hw/MyApplication/entry/src/main/ets/services/PdfImportService.ets)
- [PreviewAdapterService.ets](C:/Users/lasrorder/hw/MyApplication/entry/src/main/ets/services/PreviewAdapterService.ets)

## Current Status

Status: standby

The accepted source of truth is local `main@0fbc585`.

The old B worktree branch:

- `codex/feature/pdf-ask-prep-b`

is still parked at `e82869b` and should not be used as the active baseline anymore.

## Accepted B-Side State

The current accepted `main` already includes:

- single-entry `Select PDF & Create` flow for imported `PDF` and `HYBRID`
- imported package creation under `attachments/` and `pages/`
- `attachments[] + pages[] + activePageId + coverPage`
- imported `PDF/HYBRID` forced to paged mode
- editor reopen landing back on the saved active page
- home preview metadata following the active page in the accepted flow
- invalid PDF failure cleanup without leaving bad rows or half-written packages

## Important Semantic Reminder

Imported `HYBRID` docs are intentionally persisted as imported full-page PDF-backed pages in M2 phase 1.

That means:

- shared `pageKind` enum still includes `blank | pdf | pdf-fragment`
- imported `HYBRID` pages currently land as `pageKind = "pdf"`
- do not reinterpret that as a blocker unless a future coordinated contract migration deliberately changes imported `HYBRID` semantics

## Resolved False Negative

One HYBRID failure during this round was not a product bug.

It was caused by stale test click coordinates after the Create panel layout shifted.

Final accepted behavior:

- live `dumpLayout` was used to read the actual CTA bounds
- clicking the real CTA center entered the picker
- final `HYBRID` import/save/back/reopen path passed

## Remaining Non-Blocking Follow-Up

There is one B-owned hardening item left if this area is reopened:

- `refreshPreview()` can still preserve stale stored preview `pageIndex/pageId` when no fresh native preview payload is merged
- this did not fail in the accepted end-to-end M2 flow
- if reopened, focus on [DocumentLibraryService.ets](C:/Users/lasrorder/hw/MyApplication/entry/src/main/ets/services/DocumentLibraryService.ets) and [PreviewAdapterService.ets](C:/Users/lasrorder/hw/MyApplication/entry/src/main/ets/services/PreviewAdapterService.ets)

## Route Back To B Only If

- a new regression is reproduced on `main` in import/create/editor/home preview flow
- the preview hardening item is explicitly reopened as follow-up work

Otherwise B stays closed for this round.
