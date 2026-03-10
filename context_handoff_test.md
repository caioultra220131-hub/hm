# Context Handoff Test

Date: 2026-03-08

## Ownership

The test thread owns only:

- preflight
- reproduction
- targeted regression
- final confirmation

The test thread does not:

- edit product code
- change the smoke script
- redefine acceptance criteria

## Current Acceptance Order

Always execute in this order:

1. `SIM-STUB-01`
2. `SIM-HOME-01`
3. `SIM-EDITOR-01`
4. `SIM-X86-01`

`SIM-X86-01` is non-blocking.

If placeholder output is still missing, keep the status as `skipped-no-x86-placeholder`.

## Current Known State

- simulator target is online
- simulator HAP installs
- app starts
- current app blocker is inside the app, not in install/start

Current visible failure:

- home page shows `Failed to open the local library.`
- head-thread diagnosis points to B-owned bootstrap `ENOENT(13900002)`

## What Test Should Do Now

Status: wait for B return

Until B provides a fix:

- keep the current result record as failing/blocking
- do not expand scope
- do not spend time on A-owned hypotheses unless the head thread reroutes

## What Test Should Do After B Return

1. rerun the target case first
2. report only:
   - case id
   - reproduced or fixed
   - remaining blocker
3. if target case passes, continue with neighboring cases in the same smoke sequence
4. do not mark the full round as passed; the head thread does final sign-off

## Result Vocabulary

Only use:

- `passed`
- `failed`
- `blocked`
- `skipped-no-x86-placeholder`
