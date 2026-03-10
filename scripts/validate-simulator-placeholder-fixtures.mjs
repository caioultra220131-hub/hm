import fs from 'node:fs';
import path from 'node:path';

const rootDir = process.cwd();
const previewRoot = path.join(rootDir, 'fixtures', 'native-note', 'simulator-preview');
const sceneRoot = path.join(rootDir, 'fixtures', 'native-note', 'simulator-scene');
const previewPattern = /^preview\.x86_64\.[a-z0-9-]+\.[a-z0-9-]+\.[a-z0-9-]+\.json$/i;
const scenePattern = /^scene\.x86_64\.[a-z0-9-]+\.[a-z0-9-]+\.[a-z0-9-]+\.json$/i;
const failures = [];

function exists(filePath) {
  return fs.existsSync(filePath);
}

function validateFiles(rootPath, pattern, label) {
  if (!exists(rootPath)) {
    return [];
  }
  return fs.readdirSync(rootPath)
    .filter((entry) => entry.toLowerCase().endsWith('.json'))
    .map((entry) => {
      if (!pattern.test(entry)) {
        failures.push(`${label}/${entry} does not match the expected x86_64 naming rule`);
      }
      const absolutePath = path.join(rootPath, entry);
      try {
        JSON.parse(fs.readFileSync(absolutePath, 'utf8'));
      } catch (error) {
        failures.push(`${label}/${entry} is not valid JSON: ${error instanceof Error ? error.message : String(error)}`);
      }
      return entry;
    });
}

function main() {
  const previewFiles = validateFiles(previewRoot, previewPattern, 'simulator-preview');
  const sceneFiles = validateFiles(sceneRoot, scenePattern, 'simulator-scene');
  const totalFiles = previewFiles.length + sceneFiles.length;

  if (totalFiles === 0) {
    console.log('No simulator x86_64 placeholder fixtures found.');
    console.log('Result: skipped-no-x86-placeholder');
    return;
  }

  if (failures.length > 0) {
    console.error('Simulator placeholder fixture validation failed:');
    for (const failure of failures) {
      console.error(`- ${failure}`);
    }
    process.exitCode = 1;
    return;
  }

  console.log(`Validated ${previewFiles.length} simulator preview fixture(s).`);
  console.log(`Validated ${sceneFiles.length} simulator scene fixture(s).`);
}

main();
