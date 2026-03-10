# Compare Template

Recommended compare order:

1. Compare replay status and sample count.
2. Compare exported scene snapshot.
3. Compare normalized preview snapshot.
4. Compare native debug telemetry.

Suggested first-pass assertions:

- scene object count stable
- page-0 anchoring stable
- infinite bounds stable
- pdf below ink
- pressure / prediction / palm counters only asserted after A-thread exposes stable telemetry baselines

