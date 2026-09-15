import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { selectSimulator } from './select-simulator.mjs';

if (process.platform !== 'darwin') {
  console.log('Skipping widget tests: iOS Simulator requires macOS.');
  process.exit(0);
}

try {
  const result = spawnSync('xcrun', ['simctl', 'list', 'devices', 'available', '--json'], {
    encoding: 'utf8',
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(result.stderr.trim() || 'Unable to list iOS simulators. Check your Xcode installation.');
  }

  const simulator = selectSimulator(JSON.parse(result.stdout).devices, process.env.WIDGET_TEST_SIMULATOR_ID);
  console.log(`Running widget tests on ${simulator.name} (iOS ${simulator.version.join('.')}, ${simulator.udid}).`);

  const tests = spawnSync('xcodebuild', [
    'test',
    '-project', fileURLToPath(new URL('../Tests/WidgetTests.xcodeproj', import.meta.url)),
    '-scheme', 'WidgetTests',
    '-destination', `platform=iOS Simulator,id=${simulator.udid}`,
  ], { stdio: 'inherit' });
  if (tests.error) throw tests.error;
  process.exitCode = tests.status ?? 1;
} catch (error) {
  console.error(`Widget tests: ${error.message}`);
  process.exitCode = 1;
}
