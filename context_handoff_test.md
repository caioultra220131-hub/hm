# Context Handoff Test

Date: 2026-03-11

## Ownership

The test thread owns only:

- targeted regression
- confirmation after a new patch lands
- result reporting

The test thread does not:

- edit code
- redefine semantics
- use old A/B worktrees as the source of truth

## Current Source Of Truth

Test only against:

- local branch: `main`
- current accepted head: `0fbc585`

Do not test:

- `codex/feature/pdf-prep-a`
- `codex/feature/pdf-ask-prep-b`

Those worktrees are stale.

## Accepted Current Baseline

The current accepted M2 baseline on `main` is:

- `PDF` import: passed
- `HYBRID` import: passed
- active-page preview metadata: passed
- invalid PDF cleanup path: passed

The accepted preview metadata after saving page 2 is:

- `pageIndex = 1`
- `coverPageId = "page-1"`

## Important Test Rule For HYBRID Create

Do not use stale fixed coordinates for the HYBRID Create CTA.

The final accepted rerun used:

- `uitest dumpLayout` to read the real-time CTA bounds
- then clicked the CTA center from the live bounds

Reason:

- one interim HYBRID failure was a false negative caused by clicking an old Y-coordinate after the Create panel layout moved

## What Test Should Do If Work Reopens

Only rerun after a new patch lands on `main`.

When rerunning, keep the output format strict:

- case
- result
- blocker
- minimal reproduction steps

## No Current Test Action

Status: standby

The current round is already accepted. Do not reopen it unless the head thread explicitly dispatches a new regression run from `main`.
