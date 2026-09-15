import CoreLocation
import Foundation
import Testing
import WidgetKit

@Suite("Today's warnings widget provider")
struct WarningsTodayWidgetTests {
  @Test("Filters warnings by day and language, deduplicates, and sorts before caching")
  func dailyWarnings() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let intent = Self.intent()
    let today = fixture.provider.calendar.startOfDay(for: Self.now)
    let tomorrow = today.addingTimeInterval(86400)
    let bothDays = WarningDuration(startTime: today, endTime: tomorrow.addingTimeInterval(3600))
    let firstWind = Self.warning(.wind, .severe, duration: bothDays, speed: 20)
    let duplicateWind = Self.warning(.wind, .severe, duration: bothDays, speed: 30)
    fixture.provider.dependencies.loadCurrentLocation = {
      Issue.record("Configured locations must not request GPS")
      return nil
    }
    fixture.provider.dependencies.loadWarnings = { location in
      #expect(location.id == 634963)
      return [
        Self.warning(.rain, .moderate, duration: WarningDuration(startTime: tomorrow, endTime: tomorrow.addingTimeInterval(3600))),
        firstWind, duplicateWind,
        Self.warning(.thunderstorm, .extreme, duration: bothDays),
        Self.warning(.rain, .severe, duration: bothDays, language: "sv"),
        Self.warning(.rain, .severe, duration: bothDays, language: "en"),
        Self.warning(.coldWeather, .severe, duration: WarningDuration(startTime: today.addingTimeInterval(-86400), endTime: today.addingTimeInterval(-1))),
        Self.warning(.hotWeather, .severe, duration: WarningDuration(startTime: today.addingTimeInterval(3 * 86400), endTime: today.addingTimeInterval(4 * 86400))),
        Self.warning(.seaWind, .severe, duration: WarningDuration(startTime: nil, endTime: nil)),
        Self.warning(.flooding, .none, duration: bothDays)
      ]
    }

    let timeline = await fixture.provider.makeTimeline(for: intent)
    #expect(timeline.entries.count == 3)
    let first = try #require(timeline.entries.first)
    let second = try #require(timeline.entries.dropFirst().first)
    #expect(first.warnings.map(\.type) == [.thunderstorm, .wind])
    #expect(second.warnings.map(\.type) == [.thunderstorm, .wind, .rain])
    #expect(first.warnings.last?.wind?.speed == 20)
    #expect(first.date == today)
    #expect(second.date == tomorrow)
    #expect(first.updated == Self.now)
    #expect(first.location.id == 634963)
    #expect(first.settings.theme == "dark")
    #expect(first.settings.showLogo == false)
    #expect(first.error == nil)
    #expect(second.error == nil)
    let expired = try #require(timeline.entries.last)
    #expect(expired.date == today.addingTimeInterval(2 * 86400))
    #expect(expired.error == .oldDataError)
    #expect(expired.warnings.isEmpty)
    #expect(timeline.policy == .after(Self.now.addingTimeInterval(600)))
    let cached = try #require(fixture.provider.getEntries(settings: intent))
    #expect(cached.count == 3)
    #expect(cached.first?.warnings.map(\.type) == first.warnings.map(\.type))
    #expect(cached.last?.error == .oldDataError)
    #expect(fixture.provider.getUpdated(settings: intent) == Self.now)
  }

  @Test("Timeline dates follow Helsinki calendar days across DST and year boundaries", arguments: [
    ("2024-03-31T12:00:00Z", "2024-03-30T22:00:00Z", "2024-03-31T21:00:00Z", "2024-04-01T21:00:00Z"),
    ("2024-10-27T12:00:00Z", "2024-10-26T21:00:00Z", "2024-10-27T22:00:00Z", "2024-10-28T22:00:00Z"),
    ("2024-12-31T22:30:00Z", "2024-12-31T22:00:00Z", "2025-01-01T22:00:00Z", "2025-01-02T22:00:00Z")
  ])
  func calendarDays(now: String, today: String, tomorrow: String, expired: String) async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let instant = try date(now)
    fixture.provider.now = { instant }
    let timeline = await fixture.provider.makeTimeline(for: Self.intent())
    #expect(timeline.entries.map(\.date) == [try date(today), try date(tomorrow), try date(expired)])
    #expect(timeline.entries.last?.error == .oldDataError)
    #expect(timeline.entries.allSatisfy { $0.updated == instant })
  }

  @Test("A warning near UTC midnight is assigned to the correct Helsinki day")
  func localWarningDay() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let start = try date("2024-01-01T22:30:00Z")
    fixture.provider.dependencies.loadWarnings = { _ in
      [Self.warning(.wind, .moderate, duration: WarningDuration(startTime: start, endTime: start.addingTimeInterval(900)))]
    }
    let timeline = await fixture.provider.makeTimeline(for: Self.intent())
    #expect(timeline.entries.first?.warnings.isEmpty == true)
    #expect(timeline.entries.dropFirst().first?.warnings.map(\.type) == [.wind])
  }

  @Test("Empty warning responses are successful, not data errors")
  func noWarnings() async throws {
    let fixture = try Fixture(config: "{}")
    defer { fixture.remove() }
    let timeline = await fixture.provider.makeTimeline(for: Self.intent())
    #expect(timeline.entries.count == 3)
    #expect(timeline.entries.allSatisfy { $0.warnings.isEmpty })
    #expect(timeline.entries.dropLast().allSatisfy { $0.error == nil })
    #expect(timeline.policy == .after(Self.now.addingTimeInterval(TimeInterval(UPDATE_INTERVAL * 60))))
  }

  @Test("Uses GPS when selected or when there is no custom location", arguments: [0, 1, 2])
  func gpsLocation(mode: Int) async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let intent = Self.intent()
    if mode == 0 { intent.location = nil }
    if mode == 1 { intent.currentLocation = 1 }
    if mode == 2 { intent.currentLocation = nil }
    var resolved = false
    fixture.provider.dependencies.loadCurrentLocation = { CLLocation(latitude: 60.2, longitude: 24.9) }
    fixture.provider.dependencies.resolveLocation = { lat, lon in
      #expect(lat == 60.2)
      #expect(lon == 24.9)
      resolved = true
      return Self.location
    }
    fixture.provider.dependencies.loadWarnings = { location in
      #expect(location.id == Self.location.id)
      return []
    }
    let timeline = await fixture.provider.makeTimeline(for: intent)
    #expect(resolved)
    #expect(timeline.entries.first?.location.id == Self.location.id)
    #expect(timeline.entries.first?.error == nil)
  }

  @Test("GPS failures retain the location error instead of becoming outside-area errors", arguments: [false, true])
  func gpsFailure(throwsError: Bool) async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let intent = Self.intent()
    intent.currentLocation = 1
    fixture.provider.dependencies.loadCurrentLocation = {
      if throwsError { throw StubError.failed }
      return nil
    }
    fixture.provider.dependencies.loadWarnings = { _ in
      Issue.record("Cannot request warnings without a location")
      return nil
    }
    try expectError(await fixture.provider.makeTimeline(for: intent), .userLocationError)
    #expect(fixture.provider.getEntries(settings: intent) == nil)
  }

  @Test("Coordinate resolution failures produce a data error timeline", arguments: [false, true])
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
    fixture.provider.dependencies.loadWarnings = { _ in
      Issue.record("An unresolved location must not be force-unwrapped")
      return nil
    }
    try expectError(await fixture.provider.makeTimeline(for: intent), .dataLoadingError)
  }

  @Test("Non-Finnish locations do not request warnings", arguments: ["SE", "", "fi"])
  func outsideArea(country: String) async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let intent = Self.intent()
    intent.location?.iso2 = country
    fixture.provider.dependencies.loadWarnings = { _ in
      Issue.record("Warnings are only available for FI locations")
      return nil
    }
    try expectError(await fixture.provider.makeTimeline(for: intent), .locationOutsideDataArea)
  }

  @Test("Reuses a previous location for a fresh request even when its warnings are stale", arguments: [false, true])
  func previousLocation(throwsError: Bool) async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let intent = Self.intent()
    intent.currentLocation = 1
    fixture.provider.now = { Self.now.addingTimeInterval(-2 * 86400) }
    fixture.provider.saveEntries([Self.entry()], settings: intent)
    fixture.provider.now = { Self.now }
    fixture.provider.dependencies.loadCurrentLocation = {
      if throwsError { throw StubError.failed }
      return nil
    }
    fixture.provider.dependencies.loadWarnings = { location in
      #expect(location.id == Self.location.id)
      return []
    }
    let timeline = await fixture.provider.makeTimeline(for: intent)
    #expect(timeline.entries.count == 3)
    #expect(timeline.entries.first?.error == nil)
    #expect(fixture.provider.getUpdated(settings: intent) == Self.now)
  }

  @Test("Nil and thrown warning responses produce data error timelines", arguments: [false, true])
  func warningFailure(throwsError: Bool) async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    fixture.provider.dependencies.loadWarnings = { _ in
      if throwsError { throw StubError.failed }
      return nil
    }
    try expectError(await fixture.provider.makeTimeline(for: Self.intent()), .dataLoadingError)
  }

  @Test("Enabled announcements are included in both days and the stale entry")
  func announcements() async throws {
    let fixture = try Fixture(config: "{\"announcements\":{\"enabled\":true}}")
    defer { fixture.remove() }
    fixture.provider.dependencies.loadCrisisMessage = { "Important announcement" }
    let timeline = await fixture.provider.makeTimeline(for: Self.intent())
    #expect(timeline.entries.count == 3)
    #expect(timeline.entries.allSatisfy { $0.crisisMessage == "Important announcement" })
  }

  @Test("Missing or failed announcements do not prevent warning updates", arguments: [false, true])
  func announcementFailure(throwsError: Bool) async throws {
    let fixture = try Fixture(config: "{\"announcements\":{\"enabled\":true}}")
    defer { fixture.remove() }
    fixture.provider.dependencies.loadCrisisMessage = {
      if throwsError { throw StubError.failed }
      return nil
    }
    let timeline = await fixture.provider.makeTimeline(for: Self.intent())
    #expect(timeline.entries.first?.error == nil)
    #expect(timeline.entries.first?.crisisMessage == nil)
  }

  @Test("Disabled or missing announcement settings do not request announcements", arguments: ["{}", "{\"announcements\":{\"enabled\":false}}"])
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

  @Test("Reuses cached warnings only before the twelve-hour validity boundary", arguments: [
    (43199.0, true), (43200.0, false), (43201.0, false)
  ])
  func cacheValidity(age: Double, usable: Bool) async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let intent = Self.intent()
    let savedAt = Self.now.addingTimeInterval(-age)
    let entry = Self.entry()
    fixture.provider.now = { savedAt }
    fixture.provider.saveEntries([entry], settings: intent)
    fixture.provider.now = { Self.now }
    fixture.provider.dependencies.loadWarnings = { _ in throw StubError.failed }
    let timeline = await fixture.provider.makeTimeline(for: intent)
    if usable {
      #expect(timeline.entries.count == 1)
      #expect(timeline.entries.first?.date == entry.date)
      #expect(timeline.entries.first?.updated == entry.updated)
      #expect(timeline.entries.first?.warnings.first?.wind?.speed == 21)
      #expect(timeline.entries.first?.crisisMessage == entry.crisisMessage)
      #expect(timeline.entries.first?.error == entry.error)
    } else {
      try expectError(timeline, .dataLoadingError)
    }
    #expect(fixture.provider.getUpdated(settings: intent) == savedAt)
    #expect(timeline.policy == .after(Self.now.addingTimeInterval(600)))
  }

  @Test("Recent timestamps do not make empty or corrupt cached entries usable", arguments: ["[]", "invalid JSON"])
  func unusableCache(response: String) async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let intent = Self.intent()
    let key = fixture.provider.getUserDefaultsKey(settings: intent)
    fixture.provider.userDefaults.set(Data(response.utf8), forKey: key + "-entries")
    fixture.provider.userDefaults.set(Self.now.timeIntervalSince1970, forKey: key + "-updated")
    fixture.provider.dependencies.loadWarnings = { _ in nil }
    try expectError(await fixture.provider.makeTimeline(for: intent), .dataLoadingError)
  }

  @Test("Cached entries without an update timestamp are not reused on failure")
  func missingCacheTimestamp() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let intent = Self.intent()
    fixture.provider.saveEntries([Self.entry()], settings: intent)
    fixture.provider.userDefaults.removeObject(forKey: fixture.provider.getUserDefaultsKey(settings: intent) + "-updated")
    fixture.provider.dependencies.loadWarnings = { _ in nil }
    try expectError(await fixture.provider.makeTimeline(for: intent), .dataLoadingError)
  }

  @Test("Preserves the warnings cache key format", arguments: [
    (ThemeOptions.dark, false, "Tampere", "warnings-today-3-false-Tampere"),
    (.light, true, "Helsinki", "warnings-today-2-true-Helsinki")
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
    #expect(fixture.provider.getUserDefaultsKey(settings: intent) == "warnings-today-\(theme.rawValue)-true-nil")
  }

  @Test("Round-trips warnings, durations, wind details, and entry metadata")
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
    #expect(restored.location.id == entry.location.id)
    #expect(restored.crisisMessage == entry.crisisMessage)
    #expect(restored.error == entry.error)
    #expect(restored.settings.theme == entry.settings.theme)
    #expect(restored.settings.showLogo == entry.settings.showLogo)
    let warning = try #require(restored.warnings.first)
    #expect(warning.type == .wind)
    #expect(warning.severity == .severe)
    #expect(warning.language == "fi")
    #expect(warning.duration.startTime == entry.warnings.first?.duration.startTime)
    #expect(warning.duration.endTime == entry.warnings.first?.duration.endTime)
    #expect(warning.wind?.speed == 21)
    #expect(warning.wind?.direction == 270)
    #expect(fixture.provider.getUpdated(settings: intent) == Self.now)
    intent.theme = .light
    #expect(fixture.provider.getEntries(settings: intent) == nil)
    #expect(fixture.provider.getUpdated(settings: intent) == nil)
  }

  @Test("Failed and empty cache writes preserve saved entries and their age")
  func failedCacheWrites() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let intent = Self.intent()
    let original = Self.entry()
    fixture.provider.saveEntries([original], settings: intent)
    fixture.provider.now = { Self.now.addingTimeInterval(60) }
    fixture.provider.saveEntries([], settings: intent)
    let invalidLocation = Location(id: 1, name: "Invalid", area: "", lat: .nan, lon: 0,
                                    timezone: "Europe/Helsinki", iso2: "FI", country: nil)
    let invalid = WarningEntry(date: Self.now, updated: Self.now, location: invalidLocation,
                               warnings: [], crisisMessage: nil, error: nil, settings: original.settings)
    fixture.provider.saveEntries([invalid], settings: intent)
    #expect(fixture.provider.getEntries(settings: intent)?.first?.crisisMessage == original.crisisMessage)
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

  private enum StubError: Error { case failed }

  private func expectError(_ timeline: Timeline<WarningEntry>, _ error: WidgetError, sourceLocation: SourceLocation = #_sourceLocation) throws {
    #expect(timeline.entries.count == 1, sourceLocation: sourceLocation)
    let entry = try #require(timeline.entries.first, sourceLocation: sourceLocation)
    #expect(entry.error == error, sourceLocation: sourceLocation)
    #expect(entry.date == Self.now, sourceLocation: sourceLocation)
    #expect(entry.updated == Self.now, sourceLocation: sourceLocation)
    #expect(entry.location.id == defaultLocation.id, sourceLocation: sourceLocation)
    #expect(entry.warnings.isEmpty, sourceLocation: sourceLocation)
    #expect(entry.settings.theme == "dark", sourceLocation: sourceLocation)
    #expect(entry.settings.showLogo == false, sourceLocation: sourceLocation)
    #expect(timeline.policy == .after(Self.now.addingTimeInterval(600)), sourceLocation: sourceLocation)
  }

  private func date(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
  }

  private static let now = Date(timeIntervalSince1970: 1704110400) // January 1, 2024 at 12:00 UTC.
  private static let location = Location(id: 658225, name: "Helsinki", area: "Helsinki", lat: 60.2, lon: 24.9,
                                          timezone: "Europe/Helsinki", iso2: "FI", country: "Finland")

  private static func warning(_ type: WarningType, _ severity: WarningSeverity, duration: WarningDuration,
                              language: String = "fi", speed: Int? = nil) -> WarningTimeStep {
    WarningTimeStep(type: type, severity: severity, duration: duration, language: language,
                    wind: speed.map { WindWarningDetails(direction: 270, speed: $0) })
  }

  private static func intent() -> SettingsIntent {
    let intent = SettingsIntent()
    intent.theme = .dark
    intent.currentLocation = 0
    let setting = LocationSetting(identifier: "634963", display: "Tampere")
    setting.geoid = 634963
    setting.lat = 61.5
    setting.lon = 23.8
    setting.iso2 = "FI"
    intent.location = setting
    return intent
  }

  private static func entry() -> WarningEntry {
    WarningEntry(date: now.addingTimeInterval(-60), updated: now.addingTimeInterval(-120), location: location,
                 warnings: [warning(.wind, .severe, duration: WarningDuration(startTime: now, endTime: now.addingTimeInterval(3600)), speed: 21)],
                 crisisMessage: "Cached announcement", error: nil, settings: WidgetSettings(theme: "dark", showLogo: false))
  }

  private final class Fixture {
    let config: ConfigBundle
    let suiteName = "WarningsTodayWidgetTests-\(UUID().uuidString)"
    var provider: WarningProvider

    init(config: String = "{\"warnings\":{\"interval\":10},\"layout\":{\"logo\":{\"enabled\":false}}}") throws {
      self.config = try ConfigBundle(contents: config)
      let defaults = try #require(UserDefaults(suiteName: suiteName))
      var dependencies = WarningProviderDependencies()
      dependencies.loadCurrentLocation = { nil }
      dependencies.resolveLocation = { _, _ in nil }
      dependencies.loadWarnings = { _ in [] }
      dependencies.loadCrisisMessage = { nil }
      provider = WarningProvider(dependencies: dependencies, userDefaults: defaults, bundle: self.config.bundle,
                                 now: { WarningsTodayWidgetTests.now })
    }

    func remove() {
      provider.userDefaults.removePersistentDomain(forName: suiteName)
      config.remove()
    }
  }
}
