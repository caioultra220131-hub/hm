import fs from 'node:fs';
import path from 'node:path';

const rootDir = process.cwd();
const fixtureRoot = path.join(rootDir, 'fixtures', 'native-note');
const indexPath = path.join(fixtureRoot, 'fixture-index.json');

const failures = [];

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function assert(condition, message) {
  if (!condition) {
    failures.push(message);
  }
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function isFiniteNumber(value) {
  return typeof value === 'number' && Number.isFinite(value);
}

function ensureFileExists(relativePath) {
  const absolutePath = path.join(fixtureRoot, relativePath);
  assert(fs.existsSync(absolutePath), `Missing fixture file: ${relativePath}`);
  return absolutePath;
}

function validateBounds(bounds, label) {
  assert(isObject(bounds), `${label} must be an object`);
  if (!isObject(bounds)) {
    return;
  }
  for (const key of ['minX', 'minY', 'maxX', 'maxY']) {
    assert(isFiniteNumber(bounds[key]), `${label}.${key} must be a finite number`);
  }
  if (
    isFiniteNumber(bounds.minX) &&
    isFiniteNumber(bounds.minY) &&
    isFiniteNumber(bounds.maxX) &&
    isFiniteNumber(bounds.maxY)
  ) {
    assert(bounds.maxX >= bounds.minX, `${label}.maxX must be >= minX`);
    assert(bounds.maxY >= bounds.minY, `${label}.maxY must be >= minY`);
  }
}

function validateLegacyPoint(point, version, label) {
  assert(isObject(point), `${label} must be an object`);
  if (!isObject(point)) {
    return;
  }
  assert(isFiniteNumber(point.x), `${label}.x must be a finite number`);
  assert(isFiniteNumber(point.y), `${label}.y must be a finite number`);
  if (version === 1) {
    assert(isFiniteNumber(point.pressure), `${label}.pressure must be a finite number`);
    assert(Number.isInteger(point.timestamp), `${label}.timestamp must be an integer`);
  } else {
    assert(isFiniteNumber(point.force), `${label}.force must be a finite number`);
    assert(isFiniteNumber(point.tiltX), `${label}.tiltX must be a finite number`);
    assert(isFiniteNumber(point.tiltY), `${label}.tiltY must be a finite number`);
    assert(isFiniteNumber(point.rollAngle), `${label}.rollAngle must be a finite number`);
    assert(Number.isInteger(point.timeStamp), `${label}.timeStamp must be an integer`);
    assert(typeof point.toolType === 'string' && point.toolType.length > 0, `${label}.toolType must be a non-empty string`);
  }
}

function validateLegacyStroke(stroke, version, mode, label) {
  assert(isObject(stroke), `${label} must be an object`);
  if (!isObject(stroke)) {
    return;
  }
  if (version === 1) {
    assert(typeof stroke.id === 'string' && stroke.id.length > 0, `${label}.id must be a non-empty string`);
    assert(typeof stroke.color === 'string' && stroke.color.length > 0, `${label}.color must be a non-empty string`);
  } else {
    assert(typeof stroke.objectId === 'string' && stroke.objectId.length > 0, `${label}.objectId must be a non-empty string`);
    assert(typeof stroke.colorHex === 'string' && stroke.colorHex.length > 0, `${label}.colorHex must be a non-empty string`);
  }
  assert(typeof stroke.tool === 'string' && stroke.tool.length > 0, `${label}.tool must be a non-empty string`);
  assert(typeof stroke.shapeType === 'string' && stroke.shapeType.length > 0, `${label}.shapeType must be a non-empty string`);
  assert(Array.isArray(stroke.points) && stroke.points.length >= 2, `${label}.points must contain at least 2 points`);
  if (Array.isArray(stroke.points)) {
    stroke.points.forEach((point, index) => validateLegacyPoint(point, version, `${label}.points[${index}]`));
  }
  if (mode === 'paged') {
    assert(stroke.pageIndex === 0, `${label}.pageIndex must be 0 for paged fixtures`);
    assert(stroke.pageId === 'page-0', `${label}.pageId must be page-0 for paged fixtures`);
  }
}

function validateLegacyFixture(entry) {
  const filePath = ensureFileExists(entry.file);
  const data = readJson(filePath);
  assert(data.version === entry.version, `${entry.id} version mismatch`);
  assert(data.documentMode === entry.mode, `${entry.id} mode mismatch`);
  assert(Array.isArray(data.strokes), `${entry.id} strokes must be an array`);
  assert(Array.isArray(data.predictions), `${entry.id} predictions must be an array`);
  if (!Array.isArray(data.strokes)) {
    return;
  }

  data.strokes.forEach((stroke, index) => {
    validateLegacyStroke(stroke, entry.version, entry.mode, `${entry.id}.strokes[${index}]`);
  });

  const shapeTypes = new Set(data.strokes.map((stroke) => stroke.shapeType));
  assert(shapeTypes.has('freehand'), `${entry.id} must contain a freehand stroke`);
  assert([...shapeTypes].some((shapeType) => shapeType !== 'freehand'), `${entry.id} must contain a shape stroke`);

  const segmentGroups = new Map();
  for (const stroke of data.strokes) {
    if (typeof stroke.originStrokeId === 'string' && Number.isInteger(stroke.segmentIndex) && Number.isInteger(stroke.segmentCount)) {
      const group = segmentGroups.get(stroke.originStrokeId) ?? [];
      group.push(stroke);
      segmentGroups.set(stroke.originStrokeId, group);
    }
  }
  assert(segmentGroups.size > 0, `${entry.id} must contain segmented strokes from partial erase`);
  for (const [originStrokeId, segments] of segmentGroups.entries()) {
    const expectedCount = segments[0].segmentCount;
    assert(segments.length === expectedCount, `${entry.id} segmented group ${originStrokeId} must contain ${expectedCount} fragments`);
  }

  if (entry.mode === 'infinite') {
    const xs = data.strokes.flatMap((stroke) => Array.isArray(stroke.points) ? stroke.points.map((point) => point.x) : []);
    assert(xs.some((value) => value < 0), `${entry.id} infinite fixture must include negative world-space x values`);
    assert(xs.some((value) => value > 0), `${entry.id} infinite fixture must include positive world-space x values`);
  }
}

function validateLayout(layout, label) {
  assert(isObject(layout), `${label} must be an object`);
  if (!isObject(layout)) {
    return;
  }
  assert(layout.mode === 'paged' || layout.mode === 'infinite', `${label}.mode must be paged or infinite`);
  assert(Number.isInteger(layout.pageCount) && layout.pageCount >= 0, `${label}.pageCount must be a non-negative integer`);
  assert(Array.isArray(layout.pages), `${label}.pages must be an array`);
  if (isObject(layout.documentBounds)) {
    validateBounds(layout.documentBounds, `${label}.documentBounds`);
  }
  if (Array.isArray(layout.pages)) {
    layout.pages.forEach((page, index) => {
      assert(isObject(page), `${label}.pages[${index}] must be an object`);
      if (!isObject(page)) {
        return;
      }
      assert(typeof page.pageId === 'string' && page.pageId.length > 0, `${label}.pages[${index}].pageId must be a non-empty string`);
      assert(Number.isInteger(page.pageIndex), `${label}.pages[${index}].pageIndex must be an integer`);
      if (isObject(page.bounds)) {
        validateBounds(page.bounds, `${label}.pages[${index}].bounds`);
      }
    });
  }
}

function validatePreviewFixture(entry) {
  const filePath = ensureFileExists(entry.file);
  const data = readJson(filePath);
  assert(data.documentType === entry.documentType, `${entry.id} documentType mismatch`);
  assert(data.documentMode === entry.mode, `${entry.id} mode mismatch`);
  assert(typeof data.status === 'string' && data.status.length > 0, `${entry.id} status must be a non-empty string`);
  assert(Number.isInteger(data.previewSchemaVersion) && data.previewSchemaVersion >= 0, `${entry.id} previewSchemaVersion must be a non-negative integer`);
  assert(Number.isInteger(data.pageIndex), `${entry.id} pageIndex must be an integer`);
  assert(typeof data.targetMode === 'string' && data.targetMode.length > 0, `${entry.id} targetMode must be a non-empty string`);
  assert(Array.isArray(data.layers), `${entry.id} layers must be an array`);
  assert(Number.isInteger(data.checkpointCount) && data.checkpointCount >= 0, `${entry.id} checkpointCount must be a non-negative integer`);
  assert(Number.isInteger(data.objectCount) && data.objectCount >= 0, `${entry.id} objectCount must be a non-negative integer`);
  if (data.targetBounds !== undefined) {
    validateBounds(data.targetBounds, `${entry.id}.targetBounds`);
  }
  if (data.layout !== undefined) {
    validateLayout(data.layout, `${entry.id}.layout`);
  }

  if (entry.mode === 'paged') {
    assert(data.layout?.mode === 'paged', `${entry.id} paged fixture must use paged layout mode`);
    assert(Array.isArray(data.layout?.pages) && data.layout.pages.length >= 1, `${entry.id} paged fixture must include at least one page`);
  } else {
    assert(data.layout?.mode === 'infinite', `${entry.id} infinite fixture must use infinite layout mode`);
  }

  if (entry.scenario === 'empty-scene') {
    assert(data.objectCount === 0, `${entry.id} empty-scene preview must have objectCount=0`);
  }
  if (entry.scenario === 'page0') {
    assert(data.pageIndex === 0, `${entry.id} page0 preview must have pageIndex=0`);
    assert(data.pageId === 'page-0', `${entry.id} page0 preview must have pageId=page-0`);
  }
  if (entry.scenario === 'scene-bounds') {
    assert(isObject(data.targetBounds), `${entry.id} scene-bounds preview must include targetBounds`);
  }

  const layers = Array.isArray(data.layers) ? data.layers : [];
  if (entry.documentType === 'pdf' || entry.documentType === 'hybrid') {
    assert(layers.includes('pdf'), `${entry.id} must include pdf layer`);
    assert(layers.includes('ink'), `${entry.id} must include ink layer`);
    assert(layers.indexOf('pdf') < layers.indexOf('ink'), `${entry.id} must keep pdf below ink`);
  } else {
    assert(!layers.includes('pdf'), `${entry.id} blank fixture must not include pdf layer`);
  }
}

function validateSceneObject(object, label) {
  assert(isObject(object), `${label} must be an object`);
  if (!isObject(object)) {
    return;
  }
  for (const key of ['id', 'nodeType', 'shapeType', 'tool', 'colorHex', 'layer']) {
    assert(typeof object[key] === 'string' && object[key].length > 0, `${label}.${key} must be a non-empty string`);
  }
  assert(typeof object.selected === 'boolean', `${label}.selected must be a boolean`);
  assert(Number.isInteger(object.pointCount) && object.pointCount >= 0, `${label}.pointCount must be a non-negative integer`);
  assert(typeof object.closed === 'boolean', `${label}.closed must be a boolean`);
  validateBounds(object.bounds, `${label}.bounds`);
}

function validateSceneFixture(entry) {
  const filePath = ensureFileExists(entry.file);
  const data = readJson(filePath);
  assert(data.documentType === entry.documentType, `${entry.id} documentType mismatch`);
  assert(data.mode === entry.mode, `${entry.id} mode mismatch`);
  assert(Number.isInteger(data.version) && data.version >= 1, `${entry.id} version must be >= 1`);
  assert(typeof data.engineId === 'string' && data.engineId.length > 0, `${entry.id} engineId must be a non-empty string`);
  assert(typeof data.documentId === 'string' && data.documentId.length > 0, `${entry.id} documentId must be a non-empty string`);
  assert(typeof data.title === 'string' && data.title.length > 0, `${entry.id} title must be a non-empty string`);
  assert(Number.isInteger(data.checkpointCount) && data.checkpointCount >= 0, `${entry.id} checkpointCount must be a non-negative integer`);
  assert(Array.isArray(data.pages), `${entry.id} pages must be an array`);
  assert(Array.isArray(data.objects), `${entry.id} objects must be an array`);
  if (data.layout !== undefined) {
    validateLayout(data.layout, `${entry.id}.layout`);
  }
  if (Array.isArray(data.pages)) {
    data.pages.forEach((page, index) => {
      assert(isObject(page), `${entry.id}.pages[${index}] must be an object`);
      if (!isObject(page)) {
        return;
      }
      if (isObject(page.bounds)) {
        validateBounds(page.bounds, `${entry.id}.pages[${index}].bounds`);
      }
    });
  }
  if (Array.isArray(data.objects)) {
    data.objects.forEach((object, index) => validateSceneObject(object, `${entry.id}.objects[${index}]`));
    assert(data.objectCount === data.objects.length, `${entry.id} objectCount must equal objects.length`);
  }

  if (entry.mode === 'paged') {
    assert(Array.isArray(data.pages) && data.pages.length >= 1, `${entry.id} paged scene must include a page list`);
  } else {
    assert(data.layout?.mode === 'infinite', `${entry.id} infinite scene must use infinite layout mode`);
  }

  if (entry.scenario === 'empty-scene') {
    assert(Array.isArray(data.objects) && data.objects.length === 0, `${entry.id} empty scene must contain zero objects`);
  }
  if (entry.scenario === 'page0') {
    assert(data.objects.some((object) => object.pageIndex === 0 && object.pageId === 'page-0'), `${entry.id} page0 scene must contain page-0 anchored objects`);
  }
  if (entry.scenario === 'scene-bounds') {
    assert(isObject(data.layout?.documentBounds), `${entry.id} scene-bounds fixture must include layout.documentBounds`);
    if (entry.mode === 'infinite') {
      const xs = data.objects.flatMap((object) => [object.bounds?.minX, object.bounds?.maxX]).filter(isFiniteNumber);
      assert(xs.some((value) => value < 0), `${entry.id} infinite scene must include negative x bounds`);
      assert(xs.some((value) => value > 0), `${entry.id} infinite scene must include positive x bounds`);
    }
  }

  const layers = new Set(data.objects.map((object) => object.layer));
  if (entry.documentType === 'pdf' || entry.documentType === 'hybrid') {
    assert(layers.has('pdf'), `${entry.id} must include a pdf object`);
    assert(layers.has('ink'), `${entry.id} must include an ink object`);
  } else {
    assert(!layers.has('pdf'), `${entry.id} blank scene must not include a pdf object`);
  }
}

function validateCoverage(index) {
  const legacyVersions = new Set(index.legacyStrokes.map((entry) => entry.version));
  const legacyModes = new Set(index.legacyStrokes.map((entry) => entry.mode));
  const previewTypes = new Set(index.nativePreview.map((entry) => entry.documentType));
  const previewModes = new Set(index.nativePreview.map((entry) => entry.mode));
  const previewScenarios = new Set(index.nativePreview.map((entry) => entry.scenario));
  const sceneTypes = new Set(index.nativeScene.map((entry) => entry.documentType));
  const sceneModes = new Set(index.nativeScene.map((entry) => entry.mode));
  const sceneScenarios = new Set(index.nativeScene.map((entry) => entry.scenario));
  const acceptanceIds = new Set(index.acceptanceCriteria.map((entry) => entry.id));

  assert(legacyVersions.has(1) && legacyVersions.has(2), 'Legacy fixture set must cover versions 1 and 2');
  assert(legacyModes.has('paged') && legacyModes.has('infinite'), 'Legacy fixture set must cover paged and infinite modes');
  for (const documentType of ['blank', 'pdf', 'hybrid']) {
    assert(previewTypes.has(documentType), `Preview fixture set must cover documentType=${documentType}`);
    assert(sceneTypes.has(documentType), `Scene fixture set must cover documentType=${documentType}`);
  }
  for (const mode of ['paged', 'infinite']) {
    assert(previewModes.has(mode), `Preview fixture set must cover mode=${mode}`);
    assert(sceneModes.has(mode), `Scene fixture set must cover mode=${mode}`);
  }
  for (const scenario of ['empty-scene', 'page0', 'scene-bounds']) {
    assert(previewScenarios.has(scenario), `Preview fixture set must cover scenario=${scenario}`);
    assert(sceneScenarios.has(scenario), `Scene fixture set must cover scenario=${scenario}`);
  }
  for (const acceptanceId of [
    'reopen-no-drift',
    'surface-change-no-drift',
    'paged-page0-stable',
    'infinite-grid-stable',
    'pdf-below-ink',
    'legacy-save-upgrades-format'
  ]) {
    assert(acceptanceIds.has(acceptanceId), `Acceptance matrix must include ${acceptanceId}`);
  }
}

function main() {
  assert(fs.existsSync(indexPath), 'Missing fixture index file');
  if (!fs.existsSync(indexPath)) {
    return;
  }

  const index = readJson(indexPath);
  validateCoverage(index);
  index.legacyStrokes.forEach(validateLegacyFixture);
  index.nativePreview.forEach(validatePreviewFixture);
  index.nativeScene.forEach(validateSceneFixture);

  if (failures.length > 0) {
    console.error('Native note fixture validation failed:');
    for (const failure of failures) {
      console.error(`- ${failure}`);
    }
    process.exitCode = 1;
    return;
  }

  console.log('Native note fixture validation passed.');
  console.log(`Validated ${index.legacyStrokes.length} legacy stroke fixtures.`);
  console.log(`Validated ${index.nativePreview.length} native preview fixtures.`);
  console.log(`Validated ${index.nativeScene.length} native scene fixtures.`);
}

main();

