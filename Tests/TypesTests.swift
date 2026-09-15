import Foundation
import Testing

@Suite("Widget types")
struct TypesTests {
  @Test("Formats Finnish and foreign location names", arguments: [
    ("Helsinki", "Helsinki", "FI", "Suomi", "Helsinki"),
    ("Tampere", "Pirkanmaa", "FI", "Suomi", "Tampere, Pirkanmaa"),
    ("Stockholm", "Stockholm", "SE", "Sweden", "Stockholm, Sweden")
  ])
  func locationNames(name: String, area: String, iso2: String, country: String, expected: String) {
    #expect(location(name: name, area: area, iso2: iso2, country: country).formatName() == expected)
  }

  @Test("Omits an unknown country from foreign location names")
  func unknownCountry() {
    #expect(location(name: "Stockholm", area: "Stockholm County", iso2: "SE").formatName() == "Stockholm")
  }

  @Test("Rounds forecast temperatures and preserves observation decimals", arguments: [
    (false, 2.4, "2"), (false, 2.5, "3"), (false, -2.5, "-3"),
    (false, -0.4, "0"), (true, 2.5, "2.5"), (true, -2.5, "-2.5"), (true, 0.0, "0.0")
  ])
  func temperatures(observation: Bool, value: Double, expected: String) {
    let item = timestep(observation: observation, temperature: value)
    #expect(item.formatTemperature() == expected)
    #expect(item.formatTemperature(includeDegree: true) == expected + "°")
  }

  @Test("Uses feels-like temperature when requested", arguments: [false, true])
  func feelsLikeTemperature(observation: Bool) {
    let item = timestep(observation: observation, temperature: 12, feelsLike: -3.5)
    #expect(item.formatTemperature(useFeelsLike: true) == (observation ? "-3.5" : "-4"))
    #expect(item.formatTemperature(includeDegree: true, useFeelsLike: true) == (observation ? "-3.5°" : "-4°"))
  }

  @Test("Rounds forecast wind speed and preserves observation decimals", arguments: [
    (false, 4.4, "4"), (false, 4.5, "5"), (false, 0.0, "0"),
    (true, 4.5, "4.5"), (true, 0.0, "0.0")
  ])
  func windSpeed(observation: Bool, value: Double, expected: String) {
    #expect(timestep(observation: observation, windSpeed: value).formatWindSpeed() == expected)
  }

  @Test("Formats times in the requested timezone across midnight and daylight saving", arguments: [
    ("2024-01-01T22:30:00Z", "UTC", "01.01. 22:30", "22:30", "22"),
    ("2024-01-01T22:30:00Z", "Europe/Helsinki", "02.01. 00:30", "00:30", "00"),
    ("2024-07-01T22:30:00Z", "Europe/Helsinki", "02.07. 01:30", "01:30", "01"),
    ("2024-03-31T00:30:00Z", "Europe/Helsinki", "31.03. 02:30", "02:30", "02"),
    ("2024-03-31T01:30:00Z", "Europe/Helsinki", "31.03. 04:30", "04:30", "04")
  ])
  func timeFormatting(instant: String, timezone: String, dateAndTime: String, time: String, hours: String) throws {
    let item = timestep(epochtime: Int(try date(instant).timeIntervalSince1970))
    #expect(item.formatDateAndTime(timezone: timezone) == dateAndTime)
    #expect(item.formatTime(timezone: timezone) == time)
    #expect(item.formatHours(timezone: timezone) == hours)
  }

  @Test("Long date formatting includes a localized weekday and separator")
  func longDateFormatting() throws {
    let item = timestep(epochtime: Int(try date("2024-01-01T22:30:00Z").timeIntervalSince1970))
    let weekday = DateFormatter().shortWeekdaySymbols[2] // Tuesday in Helsinki.
    let capitalizedWeekday = weekday.prefix(1).uppercased() + weekday.dropFirst()
    let separator = NSLocalizedString("at", comment: "")
    #expect(item.formatDateAndTime(timezone: "Europe/Helsinki", longFormat: true) == "\(capitalizedWeekday) 02.01. \(separator) 00:30")
  }

  @Test("Uses the current timezone when none is specified")
  func defaultTimezone() throws {
    let calendar = Calendar.current
    let instant = try #require(calendar.date(from: DateComponents(year: 2024, month: 1, day: 2, hour: 14, minute: 35)))
    let item = timestep(epochtime: Int(instant.timeIntervalSince1970))
    #expect(item.formatDateAndTime() == "02.01. 14:35")
    #expect(item.formatTime() == "14:35")
    #expect(item.formatHours() == "14")
  }

  @Test("Selects weather icons at thresholds and in priority order", arguments: [
    (9.9, 20.0, 1, "basic"), (10.0, 35.0, 37, "windy"),
    (10.0, -15.0, 37, "windy"), (0.0, 29.9, 1, "basic"),
    (0.0, 30.0, 37, "hot"), (0.0, -9.9, 1, "basic"),
    (0.0, -10.0, 37, "winter"), (0.0, 10.0, 36, "basic"),
    (0.0, 10.0, 37, "raining"), (0.0, 10.0, 38, "raining"),
    (0.0, 10.0, 39, "raining"), (0.0, 10.0, 40, "basic")
  ])
  func weatherIcons(wind: Double, temperature: Double, symbol: Int, expected: String) throws {
    let fixture = try ConfigBundle(contents: "{}")
    defer { fixture.remove() }
    #expect(timestep(temperature: temperature, windSpeed: wind, symbol: symbol).getFeelsLikeIcon(bundle: fixture.bundle) == expected)
  }

  @Test("Finnish holiday icons take priority over the weather", arguments: [
    ("2024-02-14", "valentine"), ("2024-03-08", "womensday"),
    ("2024-05-01", "vappu"), ("2024-06-21", "midsummer"), ("2024-06-22", "midsummer"),
    ("2020-06-19", "midsummer"), ("2020-06-20", "midsummer"),
    ("2021-06-25", "midsummer"), ("2021-06-26", "midsummer"),
    ("2024-03-29", "easter"), ("2024-03-30", "easter"), ("2024-03-31", "easter"), ("2024-04-01", "easter"),
    ("2024-12-06", "independence"), ("2024-12-24", "xmas"), ("2024-12-25", "xmas"),
    ("2024-12-26", "xmas"), ("2024-12-31", "newyear")
  ])
  func holidayIcons(day: String, expected: String) throws {
    let fixture = try ConfigBundle(contents: "{\"location\":{\"default\":{\"country\":\"FI\"}}}")
    defer { fixture.remove() }
    let instant = try date(day + "T12:00:00Z")
    #expect(timestep(windSpeed: 20).getFeelsLikeIcon(date: instant, calendar: Self.calendar, bundle: fixture.bundle) == expected)
  }

  @Test("Holiday ranges exclude their neighboring days", arguments: [
    "2024-03-28", "2024-04-02", "2024-06-20", "2024-06-23", "2024-12-23", "2024-12-27"
  ])
  func outsideHolidays(day: String) throws {
    let fixture = try ConfigBundle(contents: "{\"location\":{\"default\":{\"country\":\"FI\"}}}")
    defer { fixture.remove() }
    #expect(timestep().getFeelsLikeIcon(date: try date(day + "T12:00:00Z"), calendar: Self.calendar, bundle: fixture.bundle) == "basic")
  }

  @Test("Finnish holidays are disabled for other countries")
  func foreignHoliday() throws {
    let fixture = try ConfigBundle(contents: "{\"location\":{\"default\":{\"country\":\"SE\"}}}")
    defer { fixture.remove() }
    #expect(timestep(windSpeed: 20).getFeelsLikeIcon(date: try date("2024-12-25T12:00:00Z"), calendar: Self.calendar, bundle: fixture.bundle) == "windy")
  }

  @Test("Maps day and night symbols to translation keys", arguments: [
    (1, "symbol-1"), (99, "symbol-99"), (100, "symbol-0"), (101, "symbol-1"), (139, "symbol-39")
  ])
  func symbolKeys(symbol: Int, expected: String) {
    #expect(timestep(symbol: symbol).getSmartSymbolTranslationKey() == expected)
  }

  @Test("Splits entry location and area without repeating matching names", arguments: [
    ("Helsinki", "Helsinki", "Helsinki", ""), ("Tampere", "Pirkanmaa", "Tampere, ", "Pirkanmaa")
  ])
  func entryNames(name: String, area: String, expectedName: String, expectedArea: String) {
    let place = location(name: name, area: area)
    let forecast = forecastEntry(location: place)
    let warnings = warningEntry(location: place)
    #expect(forecast.formatLocation() == expectedName)
    #expect(forecast.formatArea() == expectedArea)
    #expect(warnings.formatLocation() == expectedName)
    #expect(warnings.formatArea() == expectedArea)
  }

  @Test("Entry update times use the location timezone and their respective separators", arguments: [
    ("UTC", "22.30", "22:30"), ("Europe/Helsinki", "00.30", "00:30"), ("America/New_York", "17.30", "17:30")
  ])
  func updatedTimes(timezone: String, forecastTime: String, warningTime: String) throws {
    let updated = try date("2024-01-01T22:30:00Z")
    let place = location(timezone: timezone)
    #expect(forecastEntry(location: place, updated: updated).formatUpdated() == forecastTime)
    #expect(warningEntry(location: place, updated: updated).formatUpdated() == warningTime)
  }

  @Test("Warning dates use the Helsinki day even for a foreign location")
  func warningDate() throws {
    let instant = try date("2024-01-01T22:30:00Z")
    let weekday = DateFormatter().weekdaySymbols[2]
    let capitalizedWeekday = weekday.prefix(1).uppercased() + weekday.dropFirst()
    #expect(warningEntry(location: location(timezone: "America/New_York"), date: instant).formatDate() == "\(capitalizedWeekday) 02.01.")
  }

  @Test("Warning severities preserve their identifiers and descriptions", arguments: [
    (WarningSeverity.none, 0, "none"), (.moderate, 1, "moderate"), (.severe, 2, "severe"), (.extreme, 3, "extreme")
  ])
  func severityValues(severity: WarningSeverity, raw: Int, description: String) {
    #expect(severity.rawValue == raw)
    #expect(severity.description == description)
  }

  @Test("Warning types preserve identifiers, descriptions, and accessibility labels", arguments: Self.warningTypes)
  func warningTypes(type: WarningType, raw: Int, description: String, label: String) {
    #expect(type.rawValue == raw)
    #expect(type.description == description)
    #expect(type.accessibilityLabel == NSLocalizedString(label, comment: ""))
  }

  @Test("Formats warning duration in Helsinki time", arguments: [
    ("2024-01-01T08:00:00Z", "2024-01-01T12:30:00Z", "10:00 - 14:30"),
    ("2024-01-01T08:00:00Z", "2024-01-02T12:30:00Z", "01.01. 10:00 - 02.01. 14:30"),
    ("2024-01-01T21:00:00Z", "2024-01-01T23:00:00Z", "01.01. 23:00 - 02.01. 01:00"),
    ("2024-07-01T08:00:00Z", "2024-07-01T12:30:00Z", "11:00 - 15:30")
  ])
  func durationFormatting(start: String, end: String, expected: String) throws {
    let duration = WarningDuration(startTime: try date(start), endTime: try date(end))
    #expect(duration.formatDuration() == expected)
  }

  @Test("Missing duration endpoints produce no text and no valid days", arguments: [
    (true, false), (false, true), (true, true)
  ])
  func missingDuration(missingStart: Bool, missingEnd: Bool) throws {
    let instant = try date("2024-01-01T12:00:00Z")
    let duration = WarningDuration(startTime: missingStart ? nil : instant, endTime: missingEnd ? nil : instant)
    #expect(duration.formatDuration() == "")
    #expect(WarningTimeStep(type: .rain, severity: .moderate, duration: duration, language: "fi").isValidOnDay(instant) == false)
  }

  @Test("Warning validity includes the full first and last day")
  func validDays() throws {
    let calendar = Calendar.current
    let start = try #require(calendar.date(from: DateComponents(year: 2024, month: 1, day: 2, hour: 12)))
    let end = try #require(calendar.date(from: DateComponents(year: 2024, month: 1, day: 4, hour: 12)))
    let firstMidnight = calendar.startOfDay(for: start)
    let followingMidnight = try #require(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)))
    let warning = WarningTimeStep(type: .rain, severity: .moderate, duration: WarningDuration(startTime: start, endTime: end), language: "fi")
    #expect(warning.isValidOnDay(firstMidnight.addingTimeInterval(-1)) == false)
    #expect(warning.isValidOnDay(firstMidnight))
    #expect(warning.isValidOnDay(start.addingTimeInterval(24 * 60 * 60)))
    #expect(warning.isValidOnDay(followingMidnight.addingTimeInterval(-1)))
    #expect(warning.isValidOnDay(followingMidnight) == false)
  }

  @Test("Warning validity uses the supplied calendar and includes the final fractional second", arguments: [
    (-0.5, false), (0.0, true), (86399.5, true), (86400.0, false)
  ])
  func validDaysWithCalendar(offset: Double, expected: Bool) throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Europe/Helsinki"))
    let midnight = try date("2024-01-01T22:00:00Z")
    let duration = WarningDuration(startTime: midnight.addingTimeInterval(3600), endTime: midnight.addingTimeInterval(7200))
    let warning = WarningTimeStep(type: .rain, severity: .moderate, duration: duration, language: "fi")
    #expect(warning.isValidOnDay(midnight.addingTimeInterval(offset), calendar: calendar) == expected)
  }

  private func location(name: String = "Helsinki", area: String = "Helsinki", iso2: String = "FI", country: String? = nil, timezone: String = "Europe/Helsinki") -> Location {
    Location(id: 658225, name: name, area: area, lat: 60.17, lon: 24.94, timezone: timezone, iso2: iso2, country: country)
  }

  private func timestep(observation: Bool = false, temperature: Double = 10, feelsLike: Double = 10, windSpeed: Double = 0, symbol: Int = 1, epochtime: Int = 0) -> TimeStep {
    TimeStep(observation: observation, epochtime: epochtime, temperature: temperature, feelsLike: feelsLike,
             smartSymbol: symbol, windCompass8: "N", windDirection: 0, windSpeed: windSpeed, dark: 0)
  }

  private func forecastEntry(location: Location, updated: Date = Date(timeIntervalSince1970: 0)) -> TimeStepEntry {
    TimeStepEntry(date: Date(timeIntervalSince1970: 0), updated: updated, location: location, timeSteps: [],
                  crisisMessage: nil, error: nil, settings: WidgetSettings(theme: "automatic", showLogo: true))
  }

  private func warningEntry(location: Location, date: Date = Date(timeIntervalSince1970: 0), updated: Date = Date(timeIntervalSince1970: 0)) -> WarningEntry {
    WarningEntry(date: date, updated: updated, location: location, warnings: [], crisisMessage: nil,
                 error: nil, settings: WidgetSettings(theme: "automatic", showLogo: true))
  }

  private func date(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
  }

  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  private static let warningTypes: [(WarningType, Int, String, String)] = [
    (.none, 0, "none", "No warnings"),
    (.seaIcing, 1, "seaIcing", "Ice accretion warning"),
    (.seaWaterHeightShallowWater, 2, "seaWaterHeightShallowWater", "Warning for low sea level"),
    (.seaWaterHeightHighWater, 3, "seaWaterHeightHighWater", "Warning for high sea level"),
    (.seaWaveHeight, 4, "seaWaveHeight", "Wave height warning"),
    (.seaThunderStorm, 5, "seaThunderStorm", "Thunderstorm wind gusts for sea areas"),
    (.seaWind, 6, "seaWind", "Wind warning for sea areas"),
    (.flooding, 7, "flooding", "Flood warning"),
    (.uvNote, 8, "uvNote", "UV advisory"),
    (.coldWeather, 9, "coldWeather", "Cold warning"),
    (.hotWeather, 10, "hotWeather", "Heat wave warning"),
    (.pedestrianSafety, 11, "pedestrianSafety", "Pedestrian weather warning"),
    (.rain, 12, "rain", "Heavy rain warning"),
    (.trafficWeather, 13, "trafficWeather", "Traffic weather warning"),
    (.wind, 14, "wind", "Wind warning for land areas"),
    (.grassFireWeather, 15, "grassFireWeather", "Grass fire warning"),
    (.forestFireWeather, 16, "forestFireWeather", "Forest fire warning"),
    (.thunderstorm, 17, "thunderStorm", "Severe thunderstorm warning")
  ]
}
