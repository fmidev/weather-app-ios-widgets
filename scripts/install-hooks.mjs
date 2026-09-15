import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const widgetDirectory = fileURLToPath(new URL('../', import.meta.url));
const huskyCLI = fileURLToPath(new URL('../../../node_modules/husky/lib/bin.js', import.meta.url));

try {
  // Require a repository here so Git cannot configure the parent repository instead.
  if (!existsSync(new URL('../.git', import.meta.url))) {
    throw new Error('Widget must be an initialized Git submodule or a separate Git repository.');
  }
  if (!existsSync(huskyCLI)) {
    throw new Error('Husky is missing. Run yarn install in the main weather-app directory first.');
  }

  const result = spawnSync(process.execPath, [huskyCLI, 'install'], {
    cwd: widgetDirectory,
    stdio: 'inherit',
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error('Husky installation failed.');

  const hooksPath = spawnSync('git', ['config', '--local', '--get', 'core.hooksPath'], {
    cwd: widgetDirectory,
    encoding: 'utf8',
  });
  if (hooksPath.error) throw hooksPath.error;
  if (hooksPath.status !== 0 || hooksPath.stdout.trim() !== '.husky'
      || !existsSync(new URL('../.husky/_/husky.sh', import.meta.url))) {
    throw new Error('Could not activate the Widget Git hooks.');
  }
  console.log('Widget pre-push hook installed.');
} catch (error) {
  console.error(`Widget hooks: ${error.message}`);
  process.exitCode = 1;
}
