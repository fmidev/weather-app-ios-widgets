// Keep this aligned with IPHONEOS_DEPLOYMENT_TARGET in WidgetTests.xcodeproj.
const minimumIOSVersion = 17;

export const selectSimulator = (devices, preferredId) => {
  const candidates = Object.entries(devices).flatMap(([runtime, simulators]) => {
    const match = /^com\.apple\.CoreSimulator\.SimRuntime\.iOS-(\d+(?:-\d+)*)$/.exec(runtime);
    if (!match) return [];

    const version = match[1].split('-').map(Number);
    if (version[0] < minimumIOSVersion) return [];

    return simulators
      .filter((simulator) => simulator.isAvailable)
      .map((simulator) => ({ ...simulator, version }));
  });

  if (preferredId) {
    const simulator = candidates.find(({ udid }) => udid === preferredId);
    if (!simulator) {
      throw new Error(`Simulator ${preferredId} is not available with iOS ${minimumIOSVersion} or newer.`);
    }
    return simulator;
  }

  candidates.sort((left, right) => {
    const booted = Number(right.state === 'Booted') - Number(left.state === 'Booted');
    if (booted) return booted;

    for (let index = 0; index < Math.max(left.version.length, right.version.length); index += 1) {
      const difference = (right.version[index] ?? 0) - (left.version[index] ?? 0);
      if (difference) return difference;
    }

    return left.udid.localeCompare(right.udid);
  });

  if (!candidates.length) {
    throw new Error(`No available iOS ${minimumIOSVersion}+ simulator. Install an iOS runtime and create a simulator in Xcode.`);
  }

  return candidates[0];
};
