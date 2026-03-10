# Replay Scenario Skeleton

This folder is the pre-integration skeleton for A-thread record -> replay -> compare tests.

The layout is stable.
The trace payload schema is intentionally left open.

Round 1 device capture cases are indexed in `round1-index.json`.
Those case folders are preserved and currently marked `blocked-by-device`.
They are ready to receive real trace exports later, but they intentionally do not lock the raw trace schema.

Simulator smoke status is tracked separately in `../simulator-smoke/index.json`.

Validate the skeleton with:

```bash
node ./scripts/validate-replay-scenario-layout.mjs
```

Current round1 execution status is tracked in `../../docs/device-capture-round1.md`.
