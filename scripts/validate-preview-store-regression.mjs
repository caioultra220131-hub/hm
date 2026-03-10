import fs from 'node:fs';
import path from 'node:path';

const rootDir = process.cwd();
const packRoot = path.join(rootDir, 'fixtures', 'native-note', 'preview-store-regression');
const indexPath = path.join(packRoot, 'index.json');

const failures = [];

function assert(condition, message) {
  if (!condition) {
    failures.push(message);
  }
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function exists(filePath) {
  return fs.existsSync(filePath);
}

function ensureScenarioShape(scenario, label) {
  assert(typeof scenario.id === 'string' && scenario.id.length > 0, `${label}.id must be a non-empty string`);
  assert(typeof scenario.folder === 'string' && scenario.folder.length > 0, `${label}.folder must be a non-empty string`);
  assert(['missing', 'corrupt', 'legacy', 'rich'].includes(scenario.state), `${label}.state must be missing/corrupt/legacy/rich`);
  assert(['blank', 'pdf', 'hybrid'].includes(scenario.documentType), `${label}.documentType must be blank/pdf/hybrid`);
  assert(['paged', 'infinite'].includes(scenario.documentMode), `${label}.documentMode must be paged/infinite`);
  assert(['fallback', 'ready', 'error'].includes(scenario.expectedPreviewStatus), `${label}.expectedPreviewStatus must be fallback/ready/error`);
  assert(['vector-fallback', 'raster', 'summary-fallback'].includes(scenario.expectedCardPath), `${label}.expectedCardPath must be vector-fallback/raster/summary-fallback`);
  assert(typeof scenario.searchUsesPreviewSummary === 'boolean', `${label}.searchUsesPreviewSummary must be boolean`);
}

function validateStoredPreview(filePath, scenario, label) {
  try {
    const payload = readJson(filePath);
    if (scenario.state === 'legacy') {
      assert(typeof payload.previewSchemaVersion === 'number', `${label} legacy preview must include previewSchemaVersion`);
      assert(typeof payload.targetMode === 'string' && payload.targetMode.length > 0, `${label} legacy preview must include targetMode`);
      assert(payload.pageContract === undefined, `${label} legacy preview should not include new pageContract`);
    }
    if (scenario.state === 'rich') {
      assert(typeof payload.schemaVersion === 'number', `${label} rich preview must include schemaVersion`);
      assert(typeof payload.previewStatus === 'string', `${label} rich preview must include previewStatus`);
      assert(payload.pageContract && typeof payload.pageContract === 'object', `${label} rich preview must include pageContract`);
      assert(payload.raster && typeof payload.raster === 'object', `${label} rich preview must include raster`);
      assert(typeof payload.raster?.uri === 'string' && payload.raster.uri.length > 0, `${label} rich preview raster must include uri`);
    }
  } catch (error) {
    failures.push(`${label} preview.json must be valid JSON: ${error.message}`);
  }
}

function main() {
  assert(exists(indexPath), 'preview-store-regression/index.json is missing');
  if (!exists(indexPath)) {
    return;
  }

  const index = readJson(indexPath);
  assert(Array.isArray(index.scenarios) && index.scenarios.length >= 4, 'preview-store-regression/index.json must list scenarios');
  if (!Array.isArray(index.scenarios)) {
    return;
  }

  for (const [scenarioIndex, scenario] of index.scenarios.entries()) {
    const label = `scenarios[${scenarioIndex}]`;
    ensureScenarioShape(scenario, label);

    const folderPath = path.join(packRoot, scenario.folder);
    const scenarioPath = path.join(folderPath, 'scenario.json');
    const previewPath = path.join(folderPath, 'preview.json');

    assert(exists(folderPath), `${label} folder is missing: ${scenario.folder}`);
    assert(exists(scenarioPath), `${label} scenario.json is missing`);
    if (exists(scenarioPath)) {
      const scenarioMeta = readJson(scenarioPath);
      assert(scenarioMeta.id === scenario.id, `${label} scenario.json id mismatch`);
      assert(typeof scenarioMeta.previewSummary === 'string' && scenarioMeta.previewSummary.length > 0, `${label} scenario.json previewSummary must be non-empty`);
    }

    if (scenario.state === 'missing') {
      assert(!exists(previewPath), `${label} missing state must not contain preview.json`);
      continue;
    }

    assert(exists(previewPath), `${label} preview.json is missing`);
    if (!exists(previewPath)) {
      continue;
    }

    if (scenario.state === 'corrupt') {
      try {
        readJson(previewPath);
        failures.push(`${label} corrupt state must not be valid JSON`);
      } catch (_) {
        // expected
      }
      continue;
    }

    validateStoredPreview(previewPath, scenario, label);
  }

  if (failures.length > 0) {
    console.error('Preview store regression validation failed:');
    for (const failure of failures) {
      console.error(`- ${failure}`);
    }
    process.exitCode = 1;
    return;
  }

  console.log('Preview store regression validation passed.');
  console.log(`Validated ${index.scenarios.length} preview store scenarios.`);
}

main();

