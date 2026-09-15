import Foundation
import Testing

@Suite("Widget configuration")
struct ConfigTests {
  @Test("Reads string settings using dotted paths", arguments: [
    ("title", "Weather"),
    ("location.default.name", "Tampere"),
    ("location.default.timezone", "Europe/Helsinki")
  ])
  func stringSettings(path: String, expected: String) throws {
    let fixture = try ConfigBundle(contents: Self.config)
    defer { fixture.remove() }

    #expect(getSetting(path, bundle: fixture.bundle) as? String == expected)
  }

  @Test("Preserves JSON value types")
  func settingTypes() throws {
    let fixture = try ConfigBundle(contents: Self.config)
    defer { fixture.remove() }

    #expect(getSetting("location.default.id", bundle: fixture.bundle) as? Int == 634963)
    #expect(getSetting("location.default.lat", bundle: fixture.bundle) as? Double == 61.4991)
    #expect(getSetting("enabled", bundle: fixture.bundle) as? Bool == true)
    #expect(getSetting("disabled", bundle: fixture.bundle) as? Bool == false)
    #expect(getSetting("zero", bundle: fixture.bundle) as? Int == 0)
    #expect(getSetting("empty", bundle: fixture.bundle) as? String == "")
    #expect(getSetting("languages", bundle: fixture.bundle) as? [String] == ["fi", "sv", "en"])
    let logo = try #require(getSetting("layout.logo", bundle: fixture.bundle) as? [String: Bool])
    #expect(logo == ["enabled": true])
  }

  @Test("Returns JSON null for missing paths and explicit null", arguments: [
    "missing", "location.missing.name", "title.child", "nullable"
  ])
  func missingSettings(path: String) throws {
    let fixture = try ConfigBundle(contents: Self.config)
    defer { fixture.remove() }

    #expect(getSetting(path, bundle: fixture.bundle) is NSNull)
  }

  @Test("Returns JSON null for malformed JSON", arguments: ["", "{invalid json"])
  func malformedSettings(contents: String) throws {
    let fixture = try ConfigBundle(contents: contents)
    defer { fixture.remove() }

    #expect(getSetting("location.default.name", bundle: fixture.bundle) is NSNull)
  }

  @Test("Maps all configured location fields")
  func configuredLocation() throws {
    let fixture = try ConfigBundle(contents: Self.config)
    defer { fixture.remove() }

    let location = getDefaultLocation(bundle: fixture.bundle)

    #expect(location.id == 634963)
    #expect(location.name == "Tampere")
    #expect(location.area == "Pirkanmaa")
    #expect(location.lat == 61.4991)
    #expect(location.lon == 23.7871)
    #expect(location.timezone == "Europe/Helsinki")
    #expect(location.iso2 == "FI")
    #expect(location.country == nil)
  }

  @Test("Uses fallbacks when the configuration resource is missing")
  func missingResource() throws {
    let fixture = try ConfigBundle(contents: nil)
    defer { fixture.remove() }

    #expect(fixture.bundle.url(forResource: "widgetConfig", withExtension: "json") == nil)
    #expect(getSetting("enabled", bundle: fixture.bundle) == nil)
    expectDefaultLocation(getDefaultLocation(bundle: fixture.bundle))
  }

  @Test("Uses fallbacks when the configuration resource cannot be read")
  func unreadableResource() throws {
    let fixture = try ConfigBundle(contents: nil, unreadable: true)
    defer { fixture.remove() }

    // A directory is discoverable as a resource, but cannot be read as a JSON file.
    let url = try #require(fixture.bundle.url(forResource: "widgetConfig", withExtension: "json"))
    #expect(throws: (any Error).self) { try String(contentsOf: url) }
    #expect(getSetting("enabled", bundle: fixture.bundle) == nil)
    expectDefaultLocation(getDefaultLocation(bundle: fixture.bundle))
  }

  private func expectDefaultLocation(_ location: Location, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(location.id == defaultLocation.id, sourceLocation: sourceLocation)
    #expect(location.name == defaultLocation.name, sourceLocation: sourceLocation)
    #expect(location.area == defaultLocation.area, sourceLocation: sourceLocation)
    #expect(location.lat == defaultLocation.lat, sourceLocation: sourceLocation)
    #expect(location.lon == defaultLocation.lon, sourceLocation: sourceLocation)
    #expect(location.timezone == defaultLocation.timezone, sourceLocation: sourceLocation)
    #expect(location.iso2 == defaultLocation.iso2, sourceLocation: sourceLocation)
    #expect(location.country == defaultLocation.country, sourceLocation: sourceLocation)
  }

  private static let config = """
    {
      "title": "Weather",
      "enabled": true,
      "disabled": false,
      "zero": 0,
      "empty": "",
      "nullable": null,
      "languages": ["fi", "sv", "en"],
      "layout": {"logo": {"enabled": true}},
      "location": {
        "default": {
          "id": 634963,
          "name": "Tampere",
          "area": "Pirkanmaa",
          "lat": 61.4991,
          "lon": 23.7871,
          "timezone": "Europe/Helsinki",
          "country": "FI"
        }
      }
    }
    """
}
