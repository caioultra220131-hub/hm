import fs from 'node:fs';
import path from 'node:path';

const rootDir = process.cwd();
const logPath = path.join(rootDir, '.hvigor', 'outputs', 'build-logs', 'build.log');
const expectedOutput = path.join(rootDir, 'entry', 'build', 'default', 'outputs', 'default', 'entry-default-unsigned.hap');

const checks = [];

function pushCheck(name, ok, detail) {
  checks.push({ name, ok, detail });
}

function exists(filePath) {
  return fs.existsSync(filePath);
}

function analyzeBuildLog() {
  if (!exists(logPath)) {
    return { status: 'missing-log', detail: 'build log not found' };
  }

  const text = fs.readFileSync(logPath, 'utf8');
  const lines = text.split(/\r?\n/);
  let lastStatus = 'unknown';
  let lastStatusLine = '';
  let lastTask = '';
  let envWarning = '';

  for (const line of lines) {
    if (line.includes('Executing task ')) {
      lastTask = line.trim();
    }
    if (line.includes('BUILD SUCCESSFUL')) {
      lastStatus = 'success';
      lastStatusLine = line.trim();
    } else if (line.includes('BUILD FAILED')) {
      lastStatus = 'failed';
      lastStatusLine = line.trim();
    }
    if (line.includes("Invalid value of 'DEVECO_SDK_HOME'")) {
      envWarning = "Invalid value of 'DEVECO_SDK_HOME' detected in build log";
    }
  }

  return {
    status: lastStatus,
    detail: lastStatusLine || 'no BUILD SUCCESSFUL / BUILD FAILED marker found',
    lastTask,
    envWarning
  };
}

function main() {
  const requiredFiles = [
    'hvigorfile.ts',
    'entry/hvigorfile.ts',
    'build-profile.json5',
    'entry/build-profile.json5',
    'oh-package.json5',
    'entry/oh-package.json5'
  ];

  for (const relativePath of requiredFiles) {
    const absolutePath = path.join(rootDir, relativePath);
    pushCheck(relativePath, exists(absolutePath), exists(absolutePath) ? 'present' : 'missing');
  }

  const devecoSdkHome = process.env.DEVECO_SDK_HOME ?? '';
  const javaHome = process.env.JAVA_HOME ?? '';
  pushCheck('env.DEVECO_SDK_HOME', devecoSdkHome.length > 0 && exists(devecoSdkHome), devecoSdkHome.length > 0 ? devecoSdkHome : 'unset');
  pushCheck('env.JAVA_HOME', javaHome.length > 0 && exists(javaHome), javaHome.length > 0 ? javaHome : 'unset');
  pushCheck('expected hap output', exists(expectedOutput), exists(expectedOutput) ? expectedOutput : 'not generated yet');

  const log = analyzeBuildLog();
  pushCheck('build log', log.status !== 'missing-log', log.detail);
  if (log.lastTask) {
    pushCheck('last executed task', true, log.lastTask);
  }
  if (log.envWarning) {
    pushCheck('build log env warning', false, log.envWarning);
  }

  const failed = checks.filter((entry) => !entry.ok);
  console.log('assembleHap smoke prerequisite report');
  for (const check of checks) {
    const marker = check.ok ? '[ok]' : '[warn]';
    console.log(`${marker} ${check.name}: ${check.detail}`);
  }

  if (failed.length > 0) {
    console.log('');
    console.log('Result: prerequisite warnings present. Resolve warnings before handing to B-thread integration.');
    process.exitCode = 1;
    return;
  }

  console.log('');
  console.log('Result: prerequisite check passed. Environment is ready for assembleHap smoke verification.');
}

main();

