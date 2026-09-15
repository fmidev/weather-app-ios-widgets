import assert from 'node:assert/strict';
import { test } from 'node:test';
import { selectSimulator } from '../scripts/select-simulator.mjs';

const device = (udid, state = 'Shutdown', isAvailable = true) => ({
  udid, name: `Simulator ${udid}`, state, isAvailable,
});

test('prefers a booted iOS simulator over a newer shutdown simulator', () => {
  const simulator = selectSimulator({
    'com.apple.CoreSimulator.SimRuntime.iOS-18-5': [device('booted', 'Booted')],
    'com.apple.CoreSimulator.SimRuntime.iOS-26-5': [device('newer')],
  });
  assert.equal(simulator.udid, 'booted');
});

test('compares runtime versions numerically when no simulator is booted', () => {
  const simulator = selectSimulator({
    'com.apple.CoreSimulator.SimRuntime.iOS-18-9': [device('older')],
    'com.apple.CoreSimulator.SimRuntime.iOS-18-10': [device('newer')],
  });
  assert.equal(simulator.udid, 'newer');
});

test('ignores other platforms, old iOS versions, and unavailable devices', () => {
  const simulator = selectSimulator({
    'com.apple.CoreSimulator.SimRuntime.watchOS-26-5': [device('watch', 'Booted')],
    'com.apple.CoreSimulator.SimRuntime.tvOS-26-5': [device('tv', 'Booted')],
    'com.apple.CoreSimulator.SimRuntime.iOS-16-4': [device('old', 'Booted')],
    'com.apple.CoreSimulator.SimRuntime.iOS-26-5': [device('unavailable', 'Booted', false)],
    'com.apple.CoreSimulator.SimRuntime.iOS-17-0': [device('supported')],
  });
  assert.equal(simulator.udid, 'supported');
});

test('allows an explicit simulator ID to override the automatic selection', () => {
  const simulator = selectSimulator({
    'com.apple.CoreSimulator.SimRuntime.iOS-26-5': [device('booted', 'Booted'), device('requested')],
  }, 'requested');
  assert.equal(simulator.udid, 'requested');
});

test('fails clearly when an explicit simulator is unavailable', () => {
  assert.throws(() => selectSimulator({}, 'missing'), /Simulator missing is not available/);
});

test('fails clearly when there are no compatible simulators', () => {
  assert.throws(() => selectSimulator({}), /No available iOS 17\+ simulator/);
});

test('selects the same device regardless of device listing order', () => {
  const runtime = 'com.apple.CoreSimulator.SimRuntime.iOS-26-5';
  const first = selectSimulator({ [runtime]: [device('b'), device('a')] });
  const second = selectSimulator({ [runtime]: [device('a'), device('b')] });
  assert.equal(first.udid, second.udid);
});
