# Native Note Fixtures

This folder contains compatibility fixtures for note packages that use:

- legacy `strokes.json` payloads that need migration coverage
- native preview payload snapshots
- native scene snapshot exports
- stored `preview.json` regression packs for homepage fallback checks
- replay scenario skeletons for future record -> replay -> compare work
- simulator smoke case index and optional x86_64 placeholder fixture slots

The fixtures are intentionally static and self-contained so they can be:

- copied into manual acceptance packages
- diffed during migration work
- validated by the lightweight smoke script at `scripts/validate-native-note-fixtures.mjs`

Run the validator from the workspace root:

```bash
node ./scripts/validate-native-note-fixtures.mjs
```

The validator checks:

- minimal shape correctness
- coverage of the required document types and modes
- coverage of the required acceptance scenarios

Additional validators:

```bash
node ./scripts/validate-preview-store-regression.mjs
node ./scripts/validate-replay-scenario-layout.mjs
node ./scripts/check-assemble-hap-smoke-prereqs.mjs
node ./scripts/check-simulator-smoke-prereqs.mjs
node ./scripts/validate-simulator-placeholder-fixtures.mjs
```
