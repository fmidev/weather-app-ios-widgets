import CoreLocation
import Foundation
import Testing
import WidgetKit

@Suite("Forecast widget provider")
struct ForecastWidgetTests {
  @Test("Builds 24 six-hour windows and a final stale entry, then caches the timeline")
  func fullTimeline() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let intent = Self.intent()
    let forecast = Self.forecast()
    fixture.provider.dependencies.loadForecast = { location in
      #expect(location.id == 634963)
      return forecast
    }
    fixture.provider.dependencies.loadCurrentLocation = {
      Issue.record("A configured location must not request GPS")
      return nil
    }

    let timeline = await fixture.provider.makeTimeline(for: intent)
    #expect(timeline.entries.count == 25)
    for (index, entry) in timeline.entries.prefix(24).enumerated() {
      #expect(entry.date == Self.now.addingTimeInterval(TimeInterval(index * 3600)))
      #expect(entry.updated == Self.now)
      #expect(entry.location.id == 634963)
      #expect(entry.timeSteps == Array(forecast[index..<(index + 6)]))
      #expect(entry.error == nil)
      #expect(entry.settings.theme == "dark")
      #expect(entry.settings.showLogo == false)
    }
    let last = try #require(timeline.entries.last)
    #expect(last.error == .oldDataError)
    #expect(last.date == Self.now.addingTimeInterval(24 * 3600))
    #expect(last.timeSteps == Array(forecast[23..<29]))
    #expect(timeline.policy == .after(Self.now.addingTimeInterval(10 * 60)))
    let saved = try #require(fixture.provider.getEntries(settings: intent))
    #expect(saved.count == timeline.entries.count)
    #expect(saved.first?.timeSteps == timeline.entries.first?.timeSteps)
    #expect(saved.last?.error == .oldDataError)
    #expect(fixture.provider.getUpdated(settings: intent) == Self.now)
  }

  @Test("Handles shorter responses with complete windows and caps longer responses", arguments: [
    (6, 2), (7, 3), (28, 24), (29, 25), (30, 25), (40, 25)
  ])
  func forecastLengths(count: Int, expectedEntries: Int) async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    fixture.provider.dependencies.loadForecast = { _ in Self.forecast(count: count) }

    let timeline = await fixture.provider.makeTimeline(for: Self.intent())
    #expect(timeline.entries.count == expectedEntries)
    #expect(timeline.entries.allSatisfy { $0.timeSteps.count == 6 })
    #expect(timeline.entries.dropLast().allSatisfy { $0.error == nil })
    #expect(timeline.entries.last?.error == .oldDataError)
    #expect(timeline.entries.last?.date == Self.now.addingTimeInterval(TimeInterval((expectedEntries - 1) * 3600)))
  }

  @Test("Uses the default refresh interval when no interval is configured")
  func defaultInterval() async throws {
    let fixture = try Fixture(config: "{}")
    defer { fixture.remove() }
    let timeline = await fixture.provider.makeTimeline(for: Self.intent())
    #expect(timeline.policy == .after(Self.now.addingTimeInterval(TimeInterval(UPDATE_INTERVAL * 60))))
  }

  @Test("Resolves GPS coordinates when current location is selected", arguments: [true, false])
  func gpsLocation(explicitSelection: Bool) async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let intent = Self.intent()
    intent.currentLocation = explicitSelection ? 1 : nil
    var resolved = false
    fixture.provider.dependencies.loadCurrentLocation = { CLLocation(latitude: 60.2, longitude: 24.9) }
    fixture.provider.dependencies.resolveLocation = { lat, lon in
      #expect(lat == 60.2)
      #expect(lon == 24.9)
      resolved = true
      return Self.location
    }
    fixture.provider.dependencies.loadForecast = { location in
      #expect(location.name == Self.location.name)
      return Self.forecast()
    }
    let timeline = await fixture.provider.makeTimeline(for: intent)
    #expect(resolved)
    #expect(timeline.entries.first?.location.id == Self.location.id)
    #expect(timeline.entries.first?.error == nil)
  }

  @Test("Falls back to GPS when the custom location is absent")
  func missingCustomLocation() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let intent = Self.intent()
    intent.location = nil
    fixture.provider.dependencies.loadCurrentLocation = { CLLocation(latitude: 60, longitude: 24) }
    fixture.provider.dependencies.resolveLocation = { _, _ in Self.location }
    let timeline = await fixture.provider.makeTimeline(for: intent)
    #expect(timeline.entries.first?.location.id == Self.location.id)
    #expect(timeline.entries.first?.error == nil)
  }

  @Test("Uses the previous location to load fresh data when GPS is unavailable", arguments: [false, true])
  func previousLocation(throwsError: Bool) async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let intent = Self.intent()
    intent.currentLocation = 1
    fixture.provider.saveEntries([Self.entry()], settings: intent)
    // The previous location remains useful even after the cached weather has expired.
    fixture.provider.userDefaults.set(Self.now.addingTimeInterval(-2 * 86400).timeIntervalSince1970,
                                      forKey: fixture.provider.getUserDefaultsKey(settings: intent) + "-updated")
    fixture.provider.dependencies.loadCurrentLocation = {
      if throwsError { throw StubError.failed }
      return nil
    }
    fixture.provider.dependencies.loadForecast = { location in
      #expect(location.id == Self.location.id)
      return Self.forecast()
    }
    let timeline = await fixture.provider.makeTimeline(for: intent)
    #expect(timeline.entries.count == 25)
    #expect(timeline.entries.first?.error == nil)
    #expect(fixture.provider.getUpdated(settings: intent) == Self.now)
  }

  @Test("Returns a location error timeline if GPS fails and no cache exists", arguments: [false, true])
  func locationFailure(throwsError: Bool) async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let intent = Self.intent()
    intent.currentLocation = 1
    fixture.provider.dependencies.loadCurrentLocation = {
      if throwsError { throw StubError.failed }
      return nil
    }
    fixture.provider.dependencies.loadForecast = { _ in
      Issue.record("A forecast request needs a location")
      return nil
    }
    let timeline = await fixture.provider.makeTimeline(for: intent)
    try expectError(timeline, .userLocationError)
    #expect(fixture.provider.getEntries(settings: intent) == nil)
  }

  @Test("Returns a data error timeline if coordinates cannot be resolved", arguments: [false, true])
  func resolutionFailure(throwsError: Bool) async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let intent = Self.intent()
    intent.currentLocation = 1
    fixture.provider.dependencies.loadCurrentLocation = { CLLocation(latitude: 60, longitude: 24) }
    fixture.provider.dependencies.resolveLocation = { _, _ in
      if throwsError { throw StubError.failed }
      return nil
    }
    fixture.provider.dependencies.loadForecast = { _ in
      Issue.record("An unresolved location must not be force-unwrapped")
      return nil
    }
    try expectError(await fixture.provider.makeTimeline(for: intent), .dataLoadingError)
  }

  @Test("Treats nil, failed, empty, and incomplete forecast responses as data errors", arguments: [
    Failure.nilResult, .throwsError, .empty, .incomplete
  ])
  func forecastFailure(failure: Failure) async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    fixture.provider.dependencies.loadForecast = { _ in
      switch failure {
        case .nilResult: return nil
        case .throwsError: throw StubError.failed
        case .empty: return []
        case .incomplete: return Self.forecast(count: 5)
      }
    }
    fixture.provider.dependencies.loadUVForecast = { _ in
      Issue.record("UV should not be loaded without a usable forecast")
      return nil
    }
    try expectError(await fixture.provider.makeTimeline(for: Self.intent()), .dataLoadingError)
  }

  @Test("Merges UV data before building timeline windows")
  func uvData() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let forecast = Self.forecast()
    fixture.provider.dependencies.loadForecast = { _ in forecast }
    fixture.provider.dependencies.loadUVForecast = { location in
      #expect(location.id == 634963)
      return [UVTimeStep(epochtime: forecast[0].epochtime, uvCumulated: 3)]
    }
    let timeline = await fixture.provider.makeTimeline(for: Self.intent())
    let first = try #require(timeline.entries.first)
    #expect(first.timeSteps[0].uvCumulated == 3)
    #expect(first.timeSteps[1].uvCumulated == nil)
    #expect(first.timeSteps[0].temperature == forecast[0].temperature)
  }

  @Test("UV failures do not prevent a valid weather timeline")
  func uvFailure() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    fixture.provider.dependencies.loadUVForecast = { _ in throw StubError.failed }
    let timeline = await fixture.provider.makeTimeline(for: Self.intent())
    #expect(timeline.entries.count == 25)
    #expect(timeline.entries.first?.error == nil)
  }

  @Test("Enabled announcements are included in successful and error entries", arguments: [false, true])
  func announcements(forecastFails: Bool) async throws {
    let fixture = try Fixture(config: "{\"announcements\":{\"enabled\":true}}")
    defer { fixture.remove() }
    fixture.provider.dependencies.loadCrisisMessage = { "Important announcement" }
    fixture.provider.dependencies.loadForecast = { _ in forecastFails ? nil : Self.forecast() }
    let timeline = await fixture.provider.makeTimeline(for: Self.intent())
    #expect(!timeline.entries.isEmpty)
    #expect(timeline.entries.allSatisfy { $0.crisisMessage == "Important announcement" })
    #expect(timeline.entries.first?.error == (forecastFails ? .dataLoadingError : nil))
  }

  @Test("Announcement failures are optional")
  func announcementFailure() async throws {
    let fixture = try Fixture(config: "{\"announcements\":{\"enabled\":true}}")
    defer { fixture.remove() }
    fixture.provider.dependencies.loadCrisisMessage = { throw StubError.failed }
    let timeline = await fixture.provider.makeTimeline(for: Self.intent())
    #expect(timeline.entries.first?.error == nil)
    #expect(timeline.entries.first?.crisisMessage == nil)
  }

  @Test("Disabled or missing announcement settings do not make a request", arguments: [
    "{}", "{\"announcements\":{\"enabled\":false}}"
  ])
  func disabledAnnouncements(config: String) async throws {
    let fixture = try Fixture(config: config)
    defer { fixture.remove() }
    fixture.provider.dependencies.loadCrisisMessage = {
      Issue.record("Disabled announcements must not be requested")
      return nil
    }
    let timeline = await fixture.provider.makeTimeline(for: Self.intent())
    #expect(timeline.entries.first?.crisisMessage == nil)
  }

  @Test("Reuses a recent cached timeline on failure without refreshing its saved timestamp")
  func recentCache() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let intent = Self.intent()
    let cached = Self.entry()
    let savedAt = Self.now.addingTimeInterval(-TimeInterval(FORECAST_VALIDITY_PERIOD) + 1)
    fixture.provider.now = { savedAt }
    fixture.provider.saveEntries([cached], settings: intent)
    fixture.provider.now = { Self.now }
    fixture.provider.dependencies.loadForecast = { _ in nil }
    let timeline = await fixture.provider.makeTimeline(for: intent)
    #expect(timeline.entries.count == 1)
    #expect(timeline.entries.first?.timeSteps == cached.timeSteps)
    #expect(timeline.entries.first?.updated == cached.updated)
    #expect(timeline.entries.first?.error == cached.error)
    #expect(fixture.provider.getUpdated(settings: intent) == savedAt)
    #expect(timeline.policy == .after(Self.now.addingTimeInterval(600)))
  }

  @Test("Rejects cached weather at or beyond the validity limit", arguments: [0.0, 1.0])
  func staleCache(extraAge: Double) async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let intent = Self.intent()
    let savedAt = Self.now.addingTimeInterval(-TimeInterval(FORECAST_VALIDITY_PERIOD) - extraAge)
    fixture.provider.now = { savedAt }
    fixture.provider.saveEntries([Self.entry()], settings: intent)
    fixture.provider.now = { Self.now }
    fixture.provider.dependencies.loadForecast = { _ in nil }
    try expectError(await fixture.provider.makeTimeline(for: intent), .dataLoadingError)
    #expect(fixture.provider.getUpdated(settings: intent) == savedAt)
  }

  @Test("A recent timestamp alone does not make an empty or corrupt cache usable", arguments: ["[]", "invalid JSON"])
  func invalidCache(response: String) async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let intent = Self.intent()
    let key = fixture.provider.getUserDefaultsKey(settings: intent)
    fixture.provider.userDefaults.set(Data(response.utf8), forKey: key + "-entries")
    fixture.provider.userDefaults.set(Self.now.timeIntervalSince1970, forKey: key + "-updated")
    fixture.provider.dependencies.loadForecast = { _ in nil }
    try expectError(await fixture.provider.makeTimeline(for: intent), .dataLoadingError)
  }

  @Test("Preserves the existing cache key format", arguments: [
    (ThemeOptions.dark, false, "Tampere", "forecast-3-false-Tampere"),
    (.light, true, "Helsinki", "forecast-2-true-Helsinki")
  ])
  func cacheKeys(theme: ThemeOptions, currentLocation: Bool, name: String, expected: String) throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let intent = Self.intent()
    intent.theme = theme
    intent.currentLocation = NSNumber(value: currentLocation)
    intent.location = LocationSetting(identifier: "location", display: name)
    #expect(fixture.provider.getUserDefaultsKey(settings: intent) == expected)
    intent.currentLocation = nil
    intent.location = nil
    #expect(fixture.provider.getUserDefaultsKey(settings: intent) == "forecast-\(theme.rawValue)-true-nil")
  }

  @Test("Round-trips cached entries and isolates different widget settings")
  func cachePersistence() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let intent = Self.intent()
    let entry = Self.entry()
    fixture.provider.saveEntries([entry], settings: intent)
    let entries = try #require(fixture.provider.getEntries(settings: intent))
    let restored = try #require(entries.first)
    #expect(entries.count == 1)
    #expect(restored.date == entry.date)
    #expect(restored.updated == entry.updated)
    #expect(restored.timeSteps == entry.timeSteps)
    #expect(restored.location.name == entry.location.name)
    #expect(restored.crisisMessage == entry.crisisMessage)
    #expect(restored.error == entry.error)
    #expect(restored.settings.theme == entry.settings.theme)
    #expect(restored.settings.showLogo == entry.settings.showLogo)
    #expect(fixture.provider.getUpdated(settings: intent) == Self.now)
    intent.theme = .light
    #expect(fixture.provider.getEntries(settings: intent) == nil)
    #expect(fixture.provider.getUpdated(settings: intent) == nil)
  }

  @Test("Empty or unencodable entries do not overwrite a valid cache or its timestamp")
  func failedCacheWrites() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let intent = Self.intent()
    let original = Self.entry()
    fixture.provider.saveEntries([original], settings: intent)
    fixture.provider.now = { Self.now.addingTimeInterval(60) }
    fixture.provider.saveEntries([], settings: intent)
    var steps = Self.forecast(count: 6)
    steps[0] = TimeStep(observation: false, epochtime: 0, temperature: .nan, feelsLike: 0,
                        smartSymbol: 1, windCompass8: "N", windDirection: 0, windSpeed: 0, dark: 0)
    let invalid = TimeStepEntry(date: Self.now, updated: Self.now, location: Self.location,
                                timeSteps: steps, crisisMessage: nil, error: nil, settings: original.settings)
    fixture.provider.saveEntries([invalid], settings: intent)
    #expect(fixture.provider.getEntries(settings: intent)?.first?.timeSteps == original.timeSteps)
    #expect(fixture.provider.getUpdated(settings: intent) == Self.now)
  }

  @Test("Missing and corrupt cache values return nil")
  func missingCache() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let intent = Self.intent()
    #expect(fixture.provider.getEntries(settings: intent) == nil)
    #expect(fixture.provider.getUpdated(settings: intent) == nil)
    let key = fixture.provider.getUserDefaultsKey(settings: intent)
    fixture.provider.userDefaults.set(Data("broken".utf8), forKey: key + "-entries")
    fixture.provider.userDefaults.set("broken", forKey: key + "-updated")
    #expect(fixture.provider.getEntries(settings: intent) == nil)
    #expect(fixture.provider.getUpdated(settings: intent) == nil)
  }

  enum Failure {
    case nilResult, throwsError, empty, incomplete
  }

  private enum StubError: Error {
    case failed
  }

  private func expectError(_ timeline: Timeline<TimeStepEntry>, _ error: WidgetError, sourceLocation: SourceLocation = #_sourceLocation) throws {
    #expect(timeline.entries.count == 1, sourceLocation: sourceLocation)
    let entry = try #require(timeline.entries.first, sourceLocation: sourceLocation)
    #expect(entry.error == error, sourceLocation: sourceLocation)
    #expect(entry.date == Self.now, sourceLocation: sourceLocation)
    #expect(entry.updated == Self.now, sourceLocation: sourceLocation)
    #expect(entry.location.id == defaultLocation.id, sourceLocation: sourceLocation)
    #expect(entry.timeSteps.count == 1, sourceLocation: sourceLocation)
    #expect(timeline.policy == .after(Self.now.addingTimeInterval(600)), sourceLocation: sourceLocation)
  }

  private static let now = Date(timeIntervalSince1970: 1704067200)
  private static let location = Location(id: 658225, name: "Helsinki", area: "Helsinki", lat: 60.2, lon: 24.9,
                                          timezone: "Europe/Helsinki", iso2: "FI", country: "Finland")

  private static func forecast(count: Int = 30) -> [TimeStep] {
    (0..<count).map { index in
      TimeStep(observation: false, epochtime: Int(now.timeIntervalSince1970) + (index + 1) * 3600,
               temperature: Double(index), feelsLike: Double(index - 2), smartSymbol: 1,
               windCompass8: "N", windDirection: 0, windSpeed: 2, dark: 0)
    }
  }

  private static func intent() -> SettingsIntent {
    let intent = SettingsIntent()
    intent.theme = .dark
    intent.currentLocation = 0
    let setting = LocationSetting(identifier: "634963", display: "Tampere")
    setting.geoid = 634963
    setting.lat = 61.5
    setting.lon = 23.8
    intent.location = setting
    return intent
  }

  private static func entry() -> TimeStepEntry {
    TimeStepEntry(date: now.addingTimeInterval(-60), updated: now.addingTimeInterval(-120), location: location,
                  timeSteps: forecast(count: 6), crisisMessage: "Cached announcement", error: .oldDataError,
                  settings: WidgetSettings(theme: "dark", showLogo: false))
  }

  private final class Fixture {
    let config: ConfigBundle
    let suiteName = "ForecastWidgetTests-\(UUID().uuidString)"
    var provider: ForecastProvider

    init(config: String = "{\"weather\":{\"interval\":10},\"layout\":{\"logo\":{\"enabled\":false}}}") throws {
      self.config = try ConfigBundle(contents: config)
      let defaults = try #require(UserDefaults(suiteName: suiteName))
      var dependencies = ForecastProviderDependencies()
      dependencies.loadCurrentLocation = { nil }
      dependencies.resolveLocation = { _, _ in nil }
      dependencies.loadForecast = { _ in ForecastWidgetTests.forecast() }
      dependencies.loadUVForecast = { _ in nil }
      dependencies.loadCrisisMessage = { nil }
      provider = ForecastProvider(dependencies: dependencies, userDefaults: defaults, bundle: self.config.bundle,
                                  now: { ForecastWidgetTests.now })
    }

    func remove() {
      provider.userDefaults.removePersistentDomain(forName: suiteName)
      config.remove()
    }
  }
}
