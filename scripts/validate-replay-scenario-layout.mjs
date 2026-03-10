import fs from 'node:fs';
import path from 'node:path';

const rootDir = process.cwd();
const replayRoot = path.join(rootDir, 'fixtures', 'native-note', 'replay-scenarios', 'scenarios');
const failures = [];

function assert(condition, message) {
  if (!condition) {
    failures.push(message);
  }
}

function exists(filePath) {
  return fs.existsSync(filePath);
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function validateScenarioFolder(folderName) {
  return /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(folderName);
}

function main() {
  assert(exists(replayRoot), 'Replay scenario root is missing');
  if (!exists(replayRoot)) {
    return;
  }

  const scenarioFolders = fs.readdirSync(replayRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name);

  assert(scenarioFolders.length > 0, 'At least one replay scenario folder is required');

  for (const folderName of scenarioFolders) {
    const scenarioRoot = path.join(replayRoot, folderName);
    const casePath = path.join(scenarioRoot, 'case.json');
    const recordingsDir = path.join(scenarioRoot, 'recordings');
    const expectedDir = path.join(scenarioRoot, 'expected');
    const compareDir = path.join(scenarioRoot, 'compare');

    assert(validateScenarioFolder(folderName), `${folderName} must use lowercase kebab-case`);
    assert(exists(casePath), `${folderName}/case.json is missing`);
    assert(exists(recordingsDir), `${folderName}/recordings is missing`);
    assert(exists(expectedDir), `${folderName}/expected is missing`);
    assert(exists(compareDir), `${folderName}/compare is missing`);

    if (exists(casePath)) {
      const meta = readJson(casePath);
      assert(typeof meta.caseId === 'string' && meta.caseId.length > 0, `${folderName}/case.json caseId must be non-empty`);
      assert(typeof meta.title === 'string' && meta.title.length > 0, `${folderName}/case.json title must be non-empty`);
      assert(meta.traceCapture?.schemaLock === 'open', `${folderName}/case.json traceCapture.schemaLock must stay open at stage 1`);
      assert(typeof meta.traceCapture?.pathPattern === 'string' && meta.traceCapture.pathPattern.length > 0, `${folderName}/case.json traceCapture.pathPattern must be non-empty`);
      assert(typeof meta.expectedArtifacts?.previewSnapshot === 'string', `${folderName}/case.json expectedArtifacts.previewSnapshot is missing`);
      assert(typeof meta.expectedArtifacts?.sceneSnapshot === 'string', `${folderName}/case.json expectedArtifacts.sceneSnapshot is missing`);
      assert(typeof meta.expectedArtifacts?.debugTelemetry === 'string', `${folderName}/case.json expectedArtifacts.debugTelemetry is missing`);
    }
  }

  if (failures.length > 0) {
    console.error('Replay scenario layout validation failed:');
    for (const failure of failures) {
      console.error(`- ${failure}`);
    }
    process.exitCode = 1;
    return;
  }

  console.log('Replay scenario layout validation passed.');
  console.log(`Validated ${scenarioFolders.length} replay scenario folder(s).`);
}

main();

