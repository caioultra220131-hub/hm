# Context Handoff A

Date: 2026-03-11

## Ownership

A owns only:

- native runtime
- simulator stub contract
- `readPdfPageCount(pdfPath)` helper
- page-aware open/session semantics
- preview/scene/debug native payload semantics
- build/runtime issues on simulator

A does not own:

- ArkTS home/create flow
- document package bootstrap
- editor page switching UI
- preview metadata persistence

## Current Status

Status: standby

The accepted source of truth is now local `main@0fbc585`.

The old A worktree branch:

- `codex/feature/pdf-prep-a`

is still parked at `e82869b` and should be treated as stale.

## Accepted Native State

The current accepted `main` already includes:

- `readPdfPageCount(pdfPath: string): string`
- page-aware runtime for paged imported docs
- `PDF` and `HYBRID` imported docs entering the real paged session path through explicit `pages[] + activePageId`
- stable preview/scene/debug outputs for the accepted M2 flow

## Important Semantic Reminder

Do not misroute imported `HYBRID` docs to A based on the compat fallback in native code.

Current intended semantics are:

- imported `HYBRID` docs persist real `pages[]`
- those imported pages currently use `pageKind = "pdf"` for M2 phase 1
- `documentType = hybrid -> pdf-fragment` in native compat logic is only a fallback path when no valid real `pages[]` are provided
- `pdf-fragment` support still exists, but it is not the current persisted shape of imported M2 `HYBRID` docs

## Route Back To A Only If

- `readPdfPageCount()` regresses
- page-aware open/session logic regresses for paged imported docs
- preview/scene/debug payloads diverge from accepted M2 semantics
- simulator stub/native capability output regresses
- a future task intentionally expands true `pdf-fragment` imported-page semantics

## No Current A Action

Do not pick up new work here unless the head thread explicitly reopens A-owned native scope based on new evidence from `main`.
