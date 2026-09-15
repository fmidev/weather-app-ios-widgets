import Foundation
import Testing

@Suite("Widget network")
struct NetworkTests {
  @Test("Uses supported location languages and Finnish as fallback", arguments: [
    ("fi_FI", "fi"), ("sv_SE", "sv"), ("en_US", "en"), ("de_DE", "fi"), ("und", "fi")
  ])
  func languageCode(identifier: String, expected: String) {
    #expect(getLanguageCode(locale: Locale(identifier: identifier)) == expected)
  }

  @Test("Builds the location request and maps the first result")
  func location() async throws {
    let fixture = try ConfigBundle(contents: Self.config)
    defer { fixture.remove() }

    let result = try await fetchLocation(
      lat: 61.5, lon: 23.8, bundle: fixture.bundle, locale: Locale(identifier: "sv_SE")
    ) { url in
      try expectRequest(url, path: "/location", query: [
        "param": "geoid,name,region,latitude,longitude,region,country,iso2,localtz",
        "latlon": "61.5,23.8", "lang": "sv", "format": "json", "who": "mobileweather-widget-ios"
      ])
      return Data("""
        [
          {"geoid":634963,"name":"Tampere","region":"Pirkanmaa","latitude":1,"longitude":2,
           "localtz":"Europe/Helsinki","iso2":"FI","country":"Finland"},
          {"geoid":658225,"name":"Helsinki"}
        ]
        """.utf8)
    }

    let location = try #require(result)
    #expect(location.id == 634963)
    #expect(location.name == "Tampere")
    #expect(location.area == "Pirkanmaa")
    // Coordinates come from the request, not the nearest location in the response.
    #expect(location.lat == 61.5)
    #expect(location.lon == 23.8)
    #expect(location.timezone == "Europe/Helsinki")
    #expect(location.iso2 == "FI")
    #expect(location.country == "Finland")
  }

  @Test("Defaults missing location fields", arguments: ["[]", "[{}]"])
  func missingLocationFields(response: String) async throws {
    let fixture = try ConfigBundle(contents: Self.config)
    defer { fixture.remove() }

    let result = try await fetchLocation(lat: 61.5, lon: 23.8, bundle: fixture.bundle) { _ in
      Data(response.utf8)
    }
    let location = try #require(result)
    #expect(location.id == 0)
    #expect(location.name == "")
    #expect(location.area == "")
    #expect(location.lat == 61.5)
    #expect(location.lon == 23.8)
    #expect(location.timezone == "")
    #expect(location.iso2 == "")
    #expect(location.country == "")
  }

  @Test("Builds the forecast request and preserves all fields and timestep order")
  func forecast() async throws {
    let fixture = try ConfigBundle(contents: Self.config)
    defer { fixture.remove() }

    let result = try await fetchForecast(location: Self.location, bundle: fixture.bundle) { url in
      try expectRequest(url, path: "/weather", query: [
        "param": "epochtime,temperature,feelslike,smartsymbol,windcompass8,winddirection,windspeedms,dark",
        "timesteps": "30", "format": "json", "latlon": "61.5,23.8", "who": "mobileweather-widget-ios"
      ])
      return Data("""
        [
          {"epochtime":1700000000,"temperature":-2.5,"feelslike":-6.2,"smartsymbol":121,
           "windcompass8":"NW","winddirection":315,"windspeedms":4.5,"dark":1},
          {"epochtime":1700003600,"temperature":0.5,"feelslike":-1,"smartsymbol":1,
           "windcompass8":"N","winddirection":0,"windspeedms":0,"dark":0}
        ]
        """.utf8)
    }

    let items = try #require(result)
    #expect(items.map(\.epochtime) == [1700000000, 1700003600])
    let first = try #require(items.first)
    #expect(first.observation == false)
    #expect(first.temperature == -2.5)
    #expect(first.feelsLike == -6.2)
    #expect(first.smartSymbol == 121)
    #expect(first.windCompass8 == "NW")
    #expect(first.windDirection == 315)
    #expect(first.windSpeed == 4.5)
    #expect(first.dark == 1)
    #expect(first.uvCumulated == nil)
    #expect(items.last?.temperature == 0.5)
    #expect(items.last?.dark == 0)
  }

  @Test("Defaults missing forecast fields")
  func missingForecastFields() async throws {
    let fixture = try ConfigBundle(contents: Self.config)
    defer { fixture.remove() }

    let result = try await fetchForecast(location: Self.location, bundle: fixture.bundle) { _ in Data("[{}]".utf8) }
    let items = try #require(result)
    let item = try #require(items.first)
    #expect(item.observation == false)
    #expect(item.epochtime == 0)
    #expect(item.temperature == 0)
    #expect(item.feelsLike == 0)
    #expect(item.smartSymbol == 0)
    #expect(item.windCompass8 == "")
    #expect(item.windDirection == 0)
    #expect(item.windSpeed == 0)
    #expect(item.dark == 0)
  }

  @Test("Builds the UV request and maps UV timesteps")
  func uvForecast() async throws {
    let fixture = try ConfigBundle(contents: Self.config)
    defer { fixture.remove() }

    let result = try await fetchUVForecast(location: Self.location, bundle: fixture.bundle) { url in
      try expectRequest(url, path: "/weather", query: [
        "param": "epochtime,uvcumulated", "producer": "uv", "timesteps": "30",
        "format": "json", "latlon": "61.5,23.8", "who": "mobileweather-widget-ios"
      ])
      return Data("""
        [{"epochtime":1700000000,"uvcumulated":3},{"epochtime":1700003600,"uvcumulated":0},{}]
        """.utf8)
    }

    let items = try #require(result)
    #expect(items.map(\.epochtime) == [1700000000, 1700003600, 0])
    #expect(items.map(\.uvCumulated) == [3, 0, 0])
  }

  @Test("Builds the warnings request and maps dates, severity, and wind", arguments: ["wind", "seaWind"])
  func warnings(type: String) async throws {
    let fixture = try ConfigBundle(contents: Self.config)
    defer { fixture.remove() }

    let result = try await fetchWarnings(Self.location, bundle: fixture.bundle) { url in
      try expectRequest(url, path: "/warnings", query: [
        "latlon": "61.5,23.8", "country": "fi", "who": "mobileweather-widget-ios"
      ])
      return Data("""
        {"data":{"warnings":[{
          "type":"\(type)","severity":"Severe","language":"fi",
          "duration":{"startTime":"2024-01-01T02:00:00.000+0200","endTime":"2024-01-01T05:00:00.000+0200"},
          "physical":{"windIntensity":21,"windDirection":270}
        }]}}
        """.utf8)
    }

    let items = try #require(result)
    #expect(items.count == 1)
    let warning = try #require(items.first)
    #expect(warning.type == (type == "wind" ? .wind : .seaWind))
    #expect(warning.severity == .severe)
    #expect(warning.language == "fi")
    #expect(warning.duration.startTime == Date(timeIntervalSince1970: 1704067200))
    #expect(warning.duration.endTime == Date(timeIntervalSince1970: 1704078000))
    #expect(warning.wind?.speed == 21)
    #expect(warning.wind?.direction == 270)
  }

  @Test("Keeps wind warnings without complete numeric wind details", arguments: [
    "{}", "{\"windIntensity\":21}", "{\"windDirection\":270}",
    "{\"windIntensity\":\"21\",\"windDirection\":270}",
    "{\"windIntensity\":21,\"windDirection\":\"270\"}"
  ])
  func incompleteWind(physical: String) async throws {
    let fixture = try ConfigBundle(contents: Self.config)
    defer { fixture.remove() }

    let result = try await fetchWarnings(Self.location, bundle: fixture.bundle) { _ in
      Data("{\"data\":{\"warnings\":[{\"type\":\"wind\",\"physical\":\(physical)}]}}".utf8)
    }
    let items = try #require(result)
    #expect(items.count == 1)
    #expect(items.first?.type == .wind)
    #expect(items.first?.wind == nil)
  }

  @Test("Handles non-wind warnings, unknown values, and invalid dates")
  func warningDefaults() async throws {
    let fixture = try ConfigBundle(contents: Self.config)
    defer { fixture.remove() }

    let result = try await fetchWarnings(Self.location, bundle: fixture.bundle) { _ in
      Data("""
        {"data":{"warnings":[
          {"type":"rain","severity":"Moderate","language":"sv","physical":{"windIntensity":21,"windDirection":270}},
          {"type":"unknown","severity":"unknown","duration":{"startTime":"invalid","endTime":"invalid"}}
        ]}}
        """.utf8)
    }
    let items = try #require(result)
    #expect(items.count == 2)
    let rain = try #require(items.first)
    #expect(rain.type == .rain)
    #expect(rain.severity == .moderate)
    #expect(rain.language == "sv")
    #expect(rain.wind == nil)
    #expect(rain.duration.startTime == nil)
    #expect(rain.duration.endTime == nil)
    let unknown = try #require(items.last)
    #expect(unknown.type == .none)
    #expect(unknown.severity == .none)
    #expect(unknown.language == "")
    #expect(unknown.duration.startTime == nil)
    #expect(unknown.duration.endTime == nil)
  }

  @Test("Selects the first crisis announcement in the supported or fallback language", arguments: [
    ("fi_FI", "fi"), ("sv_SE", "sv"), ("en_US", "en"), ("de_DE", "en"), ("und", "en")
  ])
  func crisisMessage(identifier: String, language: String) async throws {
    let fixture = try ConfigBundle(contents: Self.config)
    defer { fixture.remove() }

    let message = try await fetchCrisisMessage(bundle: fixture.bundle, locale: Locale(identifier: identifier)) { url in
      try expectRequest(url, path: "/announcements/\(language)", query: [:])
      return Data("""
        [{"type":"Info","content":"Other"},{"type":"Crisis","content":"First crisis"},
         {"type":"Crisis","content":"Second crisis"}]
        """.utf8)
    }
    #expect(message == "First crisis")
  }

  @Test("Returns nil without a crisis announcement", arguments: ["[]", "[{}]", "[{\"type\":\"crisis\",\"content\":\"Wrong case\"}]"])
  func noCrisis(response: String) async throws {
    let fixture = try ConfigBundle(contents: Self.config)
    defer { fixture.remove() }

    let message = try await fetchCrisisMessage(bundle: fixture.bundle) { _ in Data(response.utf8) }
    #expect(message == nil)
  }

  @Test("Defaults missing crisis content to an empty string")
  func missingCrisisContent() async throws {
    let fixture = try ConfigBundle(contents: Self.config)
    defer { fixture.remove() }

    let message = try await fetchCrisisMessage(bundle: fixture.bundle) { _ in Data("[{\"type\":\"Crisis\"}]".utf8) }
    #expect(message == "")
  }

  @Test("Does not request optional endpoints without a valid URL", arguments: ["{}", "{\"warnings\":{\"apiUrl\":false},\"announcements\":{\"api\":{\"fi\":42}}}"])
  func missingOptionalURLs(config: String) async throws {
    let fixture = try ConfigBundle(contents: config)
    defer { fixture.remove() }
    let unexpectedRequest: (String) async throws -> Data = { _ in
      Issue.record("An unconfigured endpoint must not make a request")
      throw StubError.failed
    }

    let warnings = try await fetchWarnings(Self.location, bundle: fixture.bundle, loadData: unexpectedRequest)
    let crisis = try await fetchCrisisMessage(
      bundle: fixture.bundle, locale: Locale(identifier: "fi_FI"), loadData: unexpectedRequest
    )
    #expect(warnings == nil)
    #expect(crisis == nil)
  }

  @Test("Propagates transport failures", arguments: Endpoint.allCases)
  func transportFailure(endpoint: Endpoint) async throws {
    let fixture = try ConfigBundle(contents: Self.config)
    defer { fixture.remove() }

    await #expect(throws: StubError.failed) {
      _ = try await fetch(endpoint, bundle: fixture.bundle) { _ in throw StubError.failed }
    }
  }

  @Test("Returns nil for malformed JSON", arguments: Endpoint.allCases)
  func malformedJSON(endpoint: Endpoint) async throws {
    let fixture = try ConfigBundle(contents: Self.config)
    defer { fixture.remove() }

    let result = try await fetch(endpoint, bundle: fixture.bundle) { _ in Data("{invalid json".utf8) }
    #expect(result == nil)
  }

  @Test("Rejects unexpected response containers", arguments: [Endpoint.forecast, .uv, .warnings, .crisis], ["{}", "null"])
  func invalidContainer(endpoint: Endpoint, response: String) async throws {
    let fixture = try ConfigBundle(contents: Self.config)
    defer { fixture.remove() }

    let result = try await fetch(endpoint, bundle: fixture.bundle) { _ in Data(response.utf8) }
    #expect(result == nil)
  }

  @Test("Returns empty arrays for empty forecast and warning lists", arguments: [Endpoint.forecast, .uv, .warnings])
  func emptyLists(endpoint: Endpoint) async throws {
    let fixture = try ConfigBundle(contents: Self.config)
    defer { fixture.remove() }

    let response = endpoint == .warnings ? "{\"data\":{\"warnings\":[]}}" : "[]"
    let result = try await fetch(endpoint, bundle: fixture.bundle) { _ in Data(response.utf8) }
    let items = try #require(result as? [Any])
    #expect(items.isEmpty)
  }

  enum Endpoint: CaseIterable {
    case location, forecast, uv, warnings, crisis
  }

  private enum StubError: Error {
    case failed
  }

  private func fetch(_ endpoint: Endpoint, bundle: Bundle, loadData: (String) async throws -> Data) async throws -> Any? {
    switch endpoint {
      case .location:
        return try await fetchLocation(lat: 61.5, lon: 23.8, bundle: bundle, loadData: loadData)
      case .forecast:
        return try await fetchForecast(location: Self.location, bundle: bundle, loadData: loadData)
      case .uv:
        return try await fetchUVForecast(location: Self.location, bundle: bundle, loadData: loadData)
      case .warnings:
        return try await fetchWarnings(Self.location, bundle: bundle, loadData: loadData)
      case .crisis:
        return try await fetchCrisisMessage(bundle: bundle, loadData: loadData)
    }
  }

  private func expectRequest(_ url: String, path: String, query: [String: String], sourceLocation: SourceLocation = #_sourceLocation) throws {
    let components = try #require(URLComponents(string: url), sourceLocation: sourceLocation)
    #expect(components.scheme == "https", sourceLocation: sourceLocation)
    #expect(components.host == "weather.example", sourceLocation: sourceLocation)
    #expect(components.path == path, sourceLocation: sourceLocation)
    let queryItems = components.queryItems ?? []
    #expect(queryItems.count == query.count, sourceLocation: sourceLocation)
    for (name, value) in query {
      #expect(queryItems.filter { $0.name == name }.map(\.value) == [value], sourceLocation: sourceLocation)
    }
  }

  private static let location = Location(
    id: 634963, name: "Tampere", area: "Pirkanmaa", lat: 61.5, lon: 23.8,
    timezone: "Europe/Helsinki", iso2: "FI", country: "Finland"
  )

  private static let config = """
    {
      "location":{"apiUrl":"https://weather.example/location"},
      "weather":{"apiUrl":"https://weather.example/weather"},
      "warnings":{"apiUrl":"https://weather.example/warnings"},
      "announcements":{"api":{
        "fi":"https://weather.example/announcements/fi",
        "sv":"https://weather.example/announcements/sv",
        "en":"https://weather.example/announcements/en"
      }}
    }
    """
}
