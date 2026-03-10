import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const rootDir = process.cwd();
const defaultHdcPath = 'C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe';
const hapPath = path.join(rootDir, 'entry', 'build', 'default', 'outputs', 'default', 'entry-default-unsigned.hap');
const appConfigPath = path.join(rootDir, 'AppScope', 'app.json5');
const moduleConfigPath = path.join(rootDir, 'entry', 'src', 'main', 'module.json5');
const simulatorPreviewDir = path.join(rootDir, 'fixtures', 'native-note', 'simulator-preview');
const simulatorSceneDir = path.join(rootDir, 'fixtures', 'native-note', 'simulator-scene');

function exists(filePath) {
  return fs.existsSync(filePath);
}

function resolveHdcPath() {
  if (process.env.HDC_PATH && exists(process.env.HDC_PATH)) {
    return process.env.HDC_PATH;
  }
  if (exists(defaultHdcPath)) {
    return defaultHdcPath;
  }
  return '';
}

function readBundleName() {
  if (!exists(appConfigPath)) {
    return '';
  }
  return JSON.parse(fs.readFileSync(appConfigPath, 'utf8')).app?.bundleName ?? '';
}

function readJson5String(filePath, key) {
  if (!exists(filePath)) {
    return '';
  }
  const text = fs.readFileSync(filePath, 'utf8');
  const pattern = new RegExp(`"${key}"\\s*:\\s*"([^"]+)"`);
  const match = text.match(pattern);
  return match ? match[1] : '';
}

function listTargets(hdcPath) {
  if (!hdcPath) {
    return { targets: [], error: '' };
  }
  try {
    const output = execFileSync(hdcPath, ['list', 'targets'], { encoding: 'utf8' }).trim();
    if (!output || output === '[Empty]') {
      return { targets: [], error: '' };
    }
    return {
      targets: output.split(/\r?\n/).map((line) => line.trim()).filter((line) => line.length > 0),
      error: ''
    };
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    return { targets: [], error: detail };
  }
}

function countMatchingFiles(dirPath, pattern) {
  if (!exists(dirPath)) {
    return 0;
  }
  return fs.readdirSync(dirPath)
    .filter((entry) => pattern.test(entry))
    .length;
}

function reportLine(marker, name, detail) {
  console.log(`${marker} ${name}: ${detail}`);
}

function main() {
  const hdcPath = resolveHdcPath();
  const bundleName = readBundleName();
  const moduleName = readJson5String(moduleConfigPath, 'name');
  const abilityName = readJson5String(moduleConfigPath, 'mainElement');
  const targetQuery = listTargets(hdcPath);
  const targets = targetQuery.targets;
  const previewPlaceholderCount = countMatchingFiles(
    simulatorPreviewDir,
    /^preview\.x86_64\.[a-z0-9-]+\.[a-z0-9-]+\.[a-z0-9-]+\.json$/i
  );
  const scenePlaceholderCount = countMatchingFiles(
    simulatorSceneDir,
    /^scene\.x86_64\.[a-z0-9-]+\.[a-z0-9-]+\.[a-z0-9-]+\.json$/i
  );

  let hasWarning = false;

  if (hdcPath) {
    reportLine('[ok]', 'hdc', hdcPath);
  } else {
    hasWarning = true;
    reportLine('[warn]', 'hdc', 'not found');
  }

  if (exists(hapPath)) {
    reportLine('[ok]', 'hap', hapPath);
  } else {
    hasWarning = true;
    reportLine('[warn]', 'hap', 'missing');
  }

  if (targets.length > 0) {
    reportLine('[ok]', 'targets', targets.join(', '));
  } else if (targetQuery.error.length > 0) {
    hasWarning = true;
    reportLine('[warn]', 'targets', `hdc invocation failed: ${targetQuery.error}`);
  } else {
    hasWarning = true;
    reportLine('[warn]', 'targets', 'no simulator/device target visible from hdc');
  }

  if (bundleName.length > 0) {
    reportLine('[ok]', 'bundleName', bundleName);
  } else {
    hasWarning = true;
    reportLine('[warn]', 'bundleName', 'missing');
  }

  if (moduleName.length > 0) {
    reportLine('[ok]', 'moduleName', moduleName);
  } else {
    hasWarning = true;
    reportLine('[warn]', 'moduleName', 'missing');
  }

  if (abilityName.length > 0) {
    reportLine('[ok]', 'abilityName', abilityName);
  } else {
    hasWarning = true;
    reportLine('[warn]', 'abilityName', 'missing');
  }

  reportLine(
    previewPlaceholderCount > 0 ? '[ok]' : '[skip]',
    'simulator-preview placeholders',
    previewPlaceholderCount > 0 ? `${previewPlaceholderCount} file(s)` : 'skipped-no-x86-placeholder'
  );
  reportLine(
    scenePlaceholderCount > 0 ? '[ok]' : '[skip]',
    'simulator-scene placeholders',
    scenePlaceholderCount > 0 ? `${scenePlaceholderCount} file(s)` : 'skipped-no-x86-placeholder'
  );

  if (bundleName.length > 0 && moduleName.length > 0 && abilityName.length > 0) {
    reportLine(
      '[info]',
      'launch command',
      `hdc shell aa start -b ${bundleName} -m ${moduleName} -a ${abilityName} -W`
    );
  }

  if (hasWarning) {
    console.log('');
    console.log('Result: simulator smoke prerequisites have warnings.');
    process.exitCode = 1;
    return;
  }

  console.log('');
  console.log('Result: simulator smoke prerequisites passed.');
}

main();
