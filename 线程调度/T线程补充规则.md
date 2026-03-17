# T Thread Supplemental Rules

## Retest Script Rule
- If the current test does not pass, write the H feedback first, then save the already-working executable test operations as a reusable rerun script for that scenario.
- When H later asks for the same test again, run that saved script first and then return the updated test result.
- If the same scenario finally passes, delete the temporary rerun script immediately so stale retry scripts do not accumulate.

## Expected Practice
- Keep the rerun script focused on the exact scenario that failed or blocked.
- Prefer storing the script in a temporary or clearly test-scoped location so it is easy to remove after the pass.
- If the script path matters for the next round, include it in `T_H.txt`.
