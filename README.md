# weather-app-ios-widgets

Weather app iOS widgets. Use as git submodule in the main app.

Add to new weather-app project

```
cd ios
git submodule add https://github.com/[organization]/weather-app-ios-widgets Widget
git commit -m "Added iOS widgets as a submodule"
```

If weather-app project already contains widgets clone it with command

```
git clone --recurse-submodules https://github.com/[organization]/weather-app
```

## Unit tests

Unit tests use [Swift Testing](https://developer.apple.com/xcode/swift-testing/)
and require Xcode 16 or newer with an iOS Simulator runtime (iOS 17 or newer).

Open `Tests/WidgetTests.xcodeproj`, select the `WidgetTests` scheme and an
iOS simulator, then run Product > Test (Command-U).

### Command line

With Node.js 18 or newer installed, run from this directory:

```sh
node scripts/test.mjs
```

The runner selects an available iOS 17+ simulator automatically. It prefers a
booted simulator, otherwise one with the newest installed iOS version. All
selection logic and Xcode test settings live in this repository. Paths are
resolved relative to the script, so it works from any working directory.

On macOS, missing simulators or failed tests produce a nonzero exit code and
block the push. On other platforms, the runner skips iOS tests successfully.
The first run may take longer while Xcode downloads dependencies and builds the test target.
