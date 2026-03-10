# Preview Store Regression Pack

This pack models `preview.json` states as they are stored under a document package.

It is for B-thread integration and homepage regression only.

Covered cases:

- `missing`: no `preview.json`
- `corrupt`: invalid `preview.json`
- `legacy-summary-only`: old stored preview shape
- `richer-payload`: full stored preview snapshot with raster/vector fields

Validate the pack with:

```bash
node ./scripts/validate-preview-store-regression.mjs
```

