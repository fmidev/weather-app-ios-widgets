import Foundation
import SwiftUI
import Testing
import UIKit

@Suite("Widget utilities")
struct UtilsTests {
  @Test("Merges UV by timestamp while preserving forecast order, identity, and weather")
  func mergeUV() {
    let forecast = [timestep(300, uv: 9), timestep(100), timestep(200, uv: 7)]
    let uv = [UVTimeStep(epochtime: 100, uvCumulated: 0), UVTimeStep(epochtime: 300, uvCumulated: 5),
              UVTimeStep(epochtime: 400, uvCumulated: 8)]
    let merged = mergeUvToForecast(forecast: forecast, uvForecast: uv)
    var expected = forecast
    expected[0].uvCumulated = 5
    expected[1].uvCumulated = 0
    expected[2].uvCumulated = nil
    #expect(merged == expected)
    #expect(forecast.map(\.uvCumulated) == [9, nil, 7])
  }

  @Test("Uses the first matching UV value for duplicate timestamps")
  func duplicateUV() {
    let forecast = [timestep(100), timestep(100)]
    let merged = mergeUvToForecast(forecast: forecast, uvForecast: [
      UVTimeStep(epochtime: 100, uvCumulated: 2), UVTimeStep(epochtime: 100, uvCumulated: 8)
    ])
    #expect(merged.map(\.uvCumulated) == [2, 2])
    #expect(merged.map(\.id) == forecast.map(\.id))
  }

  @Test("Handles empty forecast and UV lists")
  func emptyUVLists() {
    #expect(mergeUvToForecast(forecast: [], uvForecast: [UVTimeStep(epochtime: 100, uvCumulated: 2)]).isEmpty)
    let forecast = [timestep(100, uv: 5)]
    let result = mergeUvToForecast(forecast: forecast, uvForecast: [])
    #expect(result.count == 1)
    #expect(result.first?.uvCumulated == nil)
    #expect(result.first?.id == forecast.first?.id)
  }

  @Test("Calculates Midsummer Day for every possible June 20 weekday", arguments: [
    (2020, 20), (2021, 26), (2022, 25), (2023, 24), (2024, 22), (2025, 21), (2029, 23)
  ])
  func midsummerDay(year: Int, expected: Int) {
    #expect(getMidSummerDay(year, calendar: calendar()) == expected)
  }

  @Test("Midsummer includes only Friday and Saturday in the supplied timezone", arguments: [
    ("2024-06-20T20:59:59Z", false), ("2024-06-20T21:00:00Z", true),
    ("2024-06-21T21:00:00Z", true), ("2024-06-22T20:59:59Z", true),
    ("2024-06-22T21:00:00Z", false), ("2024-07-21T12:00:00Z", false)
  ])
  func midsummerRange(instant: String, expected: Bool) throws {
    #expect(isMidSummer(date: try date(instant), calendar: calendar("Europe/Helsinki")) == expected)
  }

  @Test("Calculates Easter in March and April, including its earliest and latest dates", arguments: [
    (1818, 3, 22), (1943, 4, 25), (2000, 4, 23), (2008, 3, 23),
    (2024, 3, 31), (2025, 4, 20), (2026, 4, 5)
  ])
  func easterDate(year: Int, month: Int, day: Int) {
    let result = getEaster(year: year)
    #expect(result.month == month)
    #expect(result.day == day)
  }

  @Test("Easter includes Good Friday through Monday across the daylight saving change", arguments: [
    ("2024-03-28T21:59:59Z", false), ("2024-03-28T22:00:00Z", true),
    ("2024-03-31T01:00:00Z", true), ("2024-04-01T20:59:59Z", true),
    ("2024-04-01T21:00:00Z", false), ("2024-05-01T12:00:00Z", false)
  ])
  func easterRange(instant: String, expected: Bool) throws {
    #expect(isEaster(date: try date(instant), calendar: calendar("Europe/Helsinki")) == expected)
  }

  @Test("Removes duplicate warning type/severity pairs, retaining the first warning and original order")
  func uniqueWarnings() {
    let first = warning(.wind, .moderate, language: "first", speed: 15)
    let duplicate = warning(.wind, .moderate, language: "duplicate", speed: 25)
    let otherSeverity = warning(.wind, .severe, language: "severe")
    let otherType = warning(.rain, .moderate, language: "rain")
    let result = filterUniqueWarnings([first, otherSeverity, duplicate, otherType, duplicate])
    #expect(result.map(\.language) == ["first", "severe", "rain"])
    #expect(result.first?.wind?.speed == 15)
    #expect(result.first?.duration.startTime == first.duration.startTime)
    #expect(filterUniqueWarnings([]).isEmpty)
  }

  @Test("Sorts warnings by descending severity, then descending type identifier")
  func warningOrder() {
    let input = [
      warning(.thunderstorm, .moderate, language: "moderate-thunder"),
      warning(.rain, .extreme, language: "extreme-rain"),
      warning(.wind, .severe, language: "severe-wind"),
      warning(.wind, .extreme, language: "extreme-wind"),
      warning(.seaWind, .moderate, language: "moderate-sea"),
      warning(.thunderstorm, .severe, language: "severe-thunder")
    ]
    #expect(sortWarnings(input).map(\.language) == [
      "extreme-wind", "extreme-rain", "severe-thunder", "severe-wind", "moderate-thunder", "moderate-sea"
    ])
    #expect(input.first?.language == "moderate-thunder")
  }

  @Test("Sorting omits none severity and preserves repeated warnings")
  func warningSortEdges() {
    let repeated = warning(.wind, .severe)
    let result = sortWarnings([warning(.rain, .none), repeated, repeated])
    #expect(result.count == 2)
    #expect(result.allSatisfy { $0.type == .wind && $0.severity == .severe })
    #expect(sortWarnings([]).isEmpty)
    #expect(sortWarnings([warning(.wind, .none)]).isEmpty)
  }

  @Test("Resolves severity names with a safe fallback", arguments: [
    ("Moderate", WarningSeverity.moderate), ("Severe", .severe), ("Extreme", .extreme),
    ("moderate", .none), ("Unknown", .none), ("", .none)
  ])
  func warningSeverity(value: String, expected: WarningSeverity) {
    #expect(resolveWarningSeverity(value) == expected)
  }

  @Test("Resolves all warning type names and rejects unknown values", arguments: Self.warningTypes)
  func warningType(value: String, expected: WarningType) {
    #expect(resolveWarningType(value) == expected)
  }

  @Test("Converts all intent location fields")
  func locationSetting() {
    let setting = LocationSetting(identifier: "test-location", display: "Tampere")
    setting.geoid = 634963
    setting.area = "Pirkanmaa"
    setting.lat = 61.5
    setting.lon = 23.8
    setting.timezone = "Europe/Helsinki"
    setting.iso2 = "FI"

    let result = convertLocationSettingToLocation(setting)
    #expect(result.id == 634963)
    #expect(result.name == "Tampere")
    #expect(result.area == "Pirkanmaa")
    #expect(result.lat == 61.5)
    #expect(result.lon == 23.8)
    #expect(result.timezone == "Europe/Helsinki")
    #expect(result.iso2 == "FI")
    #expect(result.country == "")
  }

  @Test("Defaults optional intent location fields")
  func missingLocationFields() {
    let setting = LocationSetting(identifier: "test-location", display: "Unknown place")
    setting.geoid = 1

    let result = convertLocationSettingToLocation(setting)
    #expect(result.id == 1)
    #expect(result.name == "Unknown place")
    #expect(result.area == "")
    #expect(result.lat == 0)
    #expect(result.lon == 0)
    #expect(result.timezone == "Europe/Helsinki")
    #expect(result.iso2 == "")
    #expect(result.country == "")
  }

  @Test("Maps intent themes to widget themes", arguments: [
    (ThemeOptions.unknown, "automatic"), (.automatic, "automatic"), (.light, "light"),
    (.dark, "dark"), (.gradient, "gradient")
  ])
  func intentThemes(theme: ThemeOptions, expected: String) throws {
    let fixture = try ConfigBundle(contents: "{}")
    defer { fixture.remove() }
    let intent = SettingsIntent()
    intent.theme = theme
    let settings = convertSettingsIntentToWidgetSettings(intent, bundle: fixture.bundle)
    #expect(settings.theme == expected)
    #expect(settings.showLogo)
  }

  @Test("Logo visibility defaults to true unless explicitly disabled", arguments: [
    ("{}", true), ("{\"layout\":{\"logo\":{\"enabled\":true}}}", true),
    ("{\"layout\":{\"logo\":{\"enabled\":false}}}", false),
    ("{\"layout\":{\"logo\":{\"enabled\":\"false\"}}}", true)
  ])
  func logoVisibility(config: String, expected: Bool) throws {
    let fixture = try ConfigBundle(contents: config)
    defer { fixture.remove() }
    #expect(convertSettingsIntentToWidgetSettings(SettingsIntent(), bundle: fixture.bundle).showLogo == expected)
  }

  @Test("Resolves SwiftUI and UIKit appearance consistently", arguments: [
    ("light", ColorScheme.light, UIUserInterfaceStyle.light),
    ("dark", .dark, .dark), ("gradient", .dark, .dark)
  ])
  func appearance(theme: String, scheme: ColorScheme, style: UIUserInterfaceStyle) {
    let settings = WidgetSettings(theme: theme, showLogo: true)
    #expect(resolveColorScheme(settings: settings) == scheme)
    #expect(resolveUserInterfaceStyle(settings: settings) == style)
  }

  @Test("Automatic and unknown themes follow system appearance", arguments: ["automatic", "unknown", ""])
  func automaticAppearance(theme: String) {
    let settings = WidgetSettings(theme: theme, showLogo: false)
    #expect(resolveColorScheme(settings: settings) == nil)
    #expect(resolveUserInterfaceStyle(settings: settings) == nil)
  }

  @Test("The background gradient runs vertically from turquoise to dark blue")
  @MainActor
  func backgroundGradient() throws {
    let image = try render(backroundGradient(), scheme: .light)
    expectPixel(try pixel(image, x: 4, y: 0), near: [2, 184, 206, 255], tolerance: 6)
    expectPixel(try pixel(image, x: 4, y: image.height - 1), near: [15, 15, 45, 255], tolerance: 2)
    expectPixel(try pixel(image, x: 1, y: image.height / 2), near: try pixel(image, x: 6, y: image.height / 2))
  }

  @Test("Fixed background themes ignore the system appearance", arguments: [
    ("light", ColorScheme.dark, UIUserInterfaceStyle.light),
    ("dark", .light, .dark), ("gradient", .light, .dark)
  ])
  @MainActor
  func fixedBackground(theme: String, systemScheme: ColorScheme, expectedStyle: UIUserInterfaceStyle) throws {
    try expectBackground(theme: theme, systemScheme: systemScheme, expectedStyle: expectedStyle)
  }

  @Test("Automatic backgrounds follow the system appearance", arguments: [
    (ColorScheme.light, UIUserInterfaceStyle.light), (.dark, .dark)
  ])
  @MainActor
  func automaticBackground(systemScheme: ColorScheme, expectedStyle: UIUserInterfaceStyle) throws {
    try expectBackground(theme: "automatic", systemScheme: systemScheme, expectedStyle: expectedStyle)
  }

  private func timestep(_ epochtime: Int, uv: Int? = nil) -> TimeStep {
    TimeStep(observation: false, epochtime: epochtime, temperature: 12.5, feelsLike: 10,
             smartSymbol: 1, windCompass8: "NW", windDirection: 315, windSpeed: 3.5, dark: 0, uvCumulated: uv)
  }

  private func warning(_ type: WarningType, _ severity: WarningSeverity, language: String = "fi", speed: Int? = nil) -> WarningTimeStep {
    WarningTimeStep(type: type, severity: severity,
                    duration: WarningDuration(startTime: Date(timeIntervalSince1970: 100), endTime: Date(timeIntervalSince1970: 200)),
                    language: language, wind: speed.map { WindWarningDetails(direction: 270, speed: $0) })
  }

  private func calendar(_ timezone: String = "UTC") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timezone)!
    return calendar
  }

  private func date(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
  }

  @MainActor
  private func render(_ gradient: LinearGradient, scheme: ColorScheme) throws -> CGImage {
    // Sample close to the endpoints: pixels represent their centers, and the first color stop is short.
    let renderer = ImageRenderer(content: Rectangle().fill(gradient).frame(width: 8, height: 512).environment(\.colorScheme, scheme))
    renderer.scale = 1
    return try #require(renderer.cgImage)
  }

  @MainActor
  private func expectBackground(theme: String, systemScheme: ColorScheme, expectedStyle: UIUserInterfaceStyle) throws {
    let bundle = Bundle(for: UtilsTestBundleMarker.self)
    let asset = try #require(UIColor(named: "WidgetBackground", in: bundle, compatibleWith: nil))
    let expected = asset.resolvedColor(with: UITraitCollection(userInterfaceStyle: expectedStyle))
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    #expect(expected.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
    let rgba = [red, green, blue, alpha].map { Int(($0 * 255).rounded()) }
    let image = try render(singleColorWidgetBackground(WidgetSettings(theme: theme, showLogo: true), bundle: bundle), scheme: systemScheme)
    for y in [0, image.height / 2, image.height - 1] {
      expectPixel(try pixel(image, x: 4, y: y), near: rgba)
    }
  }

  private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [Int] {
    let sample = try #require(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
    var rgba = [UInt8](repeating: 0, count: 4)
    try rgba.withUnsafeMutableBytes { bytes in
      let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
      let context = try #require(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                           bytesPerRow: 4, space: space,
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
      context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    return rgba.map(Int.init)
  }

  private func expectPixel(_ actual: [Int], near expected: [Int], tolerance: Int = 1, sourceLocation: SourceLocation = #_sourceLocation) {
    for (actualChannel, expectedChannel) in zip(actual, expected) {
      #expect(abs(actualChannel - expectedChannel) <= tolerance, sourceLocation: sourceLocation)
    }
  }

  private static let warningTypes: [(String, WarningType)] = [
    ("thunderstorm", .thunderstorm), ("forestFireWeather", .forestFireWeather), ("grassFireWeather", .grassFireWeather),
    ("wind", .wind), ("trafficWeather", .trafficWeather), ("rain", .rain), ("pedestrianSafety", .pedestrianSafety),
    ("hotWeather", .hotWeather), ("coldWeather", .coldWeather), ("uvNote", .uvNote), ("flooding", .flooding),
    ("seaWind", .seaWind), ("seaThunderStorm", .seaThunderStorm), ("seaWaveHeight", .seaWaveHeight),
    ("seaWaterHeightHighWater", .seaWaterHeightHighWater), ("seaWaterHeightShallowWater", .seaWaterHeightShallowWater),
    ("seaIcing", .seaIcing), ("thunderStorm", .none), ("unknown", .none), ("", .none)
  ]
}

private final class UtilsTestBundleMarker: NSObject {}
