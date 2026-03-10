# Context Handoff A

Date: 2026-03-08

## Ownership

A owns only:

- native runtime
- build profile / ABI
- simulator stub contract
- `getDebugState()`
- HAP install/start path
- `x86_64` placeholder outputs

A does not own:

- ArkTS page bootstrap
- document library flow
- editor page flow
- preview display
- banner/UI wording

## Current Verified State

- `entry-simulator-unsigned.hap` installs on the official `x86_64` simulator.
- App launch succeeds with `aa start -b com.example.myapplication -a EntryAbility -W`.
- No current evidence of a fresh native-module load failure.
- Head-thread routing rule is active: if install/start is healthy and stub/debug capability is correct, later page/UI failures default to B.

## Current Status For A

Status: standby

Current known app blocker is not assigned to A.

The current blocker is:

- home/bootstrap fails inside ArkTS
- runtime log reports `bootstrap failed: {"code":13900002}`
- `13900002` maps to `ERR_ENOENT`

Unless B proves this is caused by native/stub contract output, A should not pick it up.

## A Action Items

1. Be ready to re-check `getDebugState()` and simulator stub contract only if B reports a mismatch.
2. Keep `SIM-X86-01` as a separate non-blocking task.
3. If placeholder assets are produced, notify the head thread so `SIM-X86-01` can move from `skipped-no-x86-placeholder` to a real verification.

## Escalation Back To A

Route back to A only if any of the following becomes true:

- `hdc install` fails for the simulator HAP
- app start fails
- ABI mismatch appears on the simulator HAP path
- native module load fails
- `getDebugState()` fields are missing, renamed, or semantically wrong
- stub banner/capability is wrong because native debug output is wrong
- `x86_64` placeholder output needs implementation or repair

## Acceptance Notes

A is not the owner for the current `Failed to open the local library.` blocker.

Do not take B-owned ArkTS/UI issues unless the head thread explicitly reroutes based on new evidence.
