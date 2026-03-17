# Context Handoff A

Date: 2026-03-13

## Ownership

A owns only:

- native runtime
- simulator stub contract
- `readPdfPageCount(pdfPath)` helper
- page-aware open/session semantics
- preview/scene/debug native payload semantics
- simulator build/runtime capability and validation-path issues
- finger telemetry / simulator-side coordinate mapping

A does not own:

- ArkTS home/create flow
- document package bootstrap
- editor page switching UI
- preview metadata persistence
- rail / toolbar / autosave UI polish

## Current Status

Status: standby

The current A-side accepted baseline is not on local `main`.

Use:

- `codex/bugfix/finger-coordinate-alignment-a` @ `3b67c9dd1ab6b5ae49e8d5f1e64a3cd18f27f19c`

Layered on:

- `codex/bugfix/simulator-finger-pan-validation-a` @ `89228da25e26e7a7896a6a8c62a0b64d50518c92`

Current local `main@4d500af` does not contain this A-owned chain.

## Accepted A-Side State

The accepted A-side chain already includes:

- existing accepted native/runtime semantics for paged documents
- stable simulator ready state for validation
- usable finger telemetry / synthetic stroke validation path on simulator
- simulator-only zoom/reset helpers needed for overflow / free-pan verification
- unified simulator canvas frame mapping so finger hit-test, guide dots, placeholder objects, and visible scene content use the same coordinate basis

## Route Back To A Only If

- `readPdfPageCount()` regresses
- page-aware open/session native semantics regress
- preview/scene/debug native payload semantics drift again
- simulator stub capability / ready state / finger telemetry path regresses
- finger writing lands away from the visible page/content rect again
- viewport or zoom changes break the unified simulator coordinate mapping
- a future task intentionally expands true `pdf-fragment` imported-page semantics

## Residual Notes

- Current reality: the accepted A-owned chain is still on feature branches and has not been merged back to `main`
- `hvigor` can emit external cache `ENOENT` noise in isolated worktrees; treat that as tool/cache noise unless reproduced as a real code-level runtime regression
