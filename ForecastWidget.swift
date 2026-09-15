import WidgetKit
import CoreLocation
import SwiftUI
import Intents

struct ForecastProviderDependencies {
  var loadCurrentLocation: () async throws -> CLLocation? = { try await getCurrentLocation() }
  var resolveLocation: (Double, Double) async throws -> Location? = { try await fetchLocation(lat: $0, lon: $1) }
  var loadForecast: (Location) async throws -> [TimeStep]? = { try await fetchForecast(location: $0) }
  var loadUVForecast: (Location) async throws -> [UVTimeStep]? = { try await fetchUVForecast(location: $0) }
  var loadCrisisMessage: () async throws -> String? = { try await fetchCrisisMessage() }
}

struct ForecastProvider: IntentTimelineProvider {
  let USER_DEFAULTS_PREFIX = "forecast"
  var dependencies = ForecastProviderDependencies()
  var userDefaults: UserDefaults = .standard
  var bundle: Bundle = .main
  var now: () -> Date = { Date() }

  func placeholder(in context: Context) -> TimeStepEntry {
    return defaultEntry
  }

  func getSnapshot(for configuration: SettingsIntent, in context: Context, completion: @escaping (TimeStepEntry) -> ()) {
    completion(defaultEntry)
  }

  func getTimeline(for configuration: SettingsIntent, in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
    Task {
      completion(await makeTimeline(for: configuration))
    }
  }

  func makeTimeline(for configuration: SettingsIntent) async -> Timeline<TimeStepEntry> {
    var error: WidgetError?
    var forecast: [TimeStep]?
    var location: Location?
    var crisisMessage: String?
    let updateInterval = getSetting("weather.interval", bundle: bundle) as? Int ?? UPDATE_INTERVAL
    let settings = convertSettingsIntentToWidgetSettings(configuration, bundle: bundle)
    let oldEntries = getEntries(settings: configuration)

    if configuration.currentLocation == 0, let configuredLocation = configuration.location {
      location = convertLocationSettingToLocation(configuredLocation)
    } else if let currentLocation = try? await dependencies.loadCurrentLocation() {
      location = try? await dependencies.resolveLocation(
        currentLocation.coordinate.latitude, currentLocation.coordinate.longitude
      )
      if location == nil {
        error = .dataLoadingError
      }
    } else if let previousLocation = oldEntries?.first?.location {
      location = previousLocation
    } else {
      error = .userLocationError
    }

    if getSetting("announcements.enabled", bundle: bundle) as? Bool == true {
      crisisMessage = try? await dependencies.loadCrisisMessage()
    }

    if let location, error == nil {
      forecast = try? await dependencies.loadForecast(location)
      // Every entry needs six timesteps for the forecast views.
      if let loadedForecast = forecast, loadedForecast.count >= 6 {
        if let uvForecast = try? await dependencies.loadUVForecast(location) {
          forecast = mergeUvToForecast(forecast: loadedForecast, uvForecast: uvForecast)
        }
      } else {
        error = .dataLoadingError
      }
    }

    let updated = now()
    let policy = TimelineReloadPolicy.after(updated.addingTimeInterval(TimeInterval(updateInterval * 60)))
    if let error {
      if let lastUpdated = getUpdated(settings: configuration),
         lastUpdated.addingTimeInterval(TimeInterval(FORECAST_VALIDITY_PERIOD)) > updated,
         let oldEntries, !oldEntries.isEmpty {
        return Timeline(entries: oldEntries, policy: policy)
      }

      return Timeline(entries: [TimeStepEntry(
        date: updated,
        updated: updated,
        location: defaultLocation,
        timeSteps: [defaultTimeStep],
        crisisMessage: crisisMessage,
        error: error,
        settings: settings
      )], policy: policy)
    }

    var entries: [TimeStepEntry] = []
    if let forecast, let location {
      let entryCount = min(24, forecast.count - 5)
      for index in 0..<entryCount {
        let timeSteps = Array(forecast[index..<(index + 6)])
        let date = Date(timeIntervalSince1970: TimeInterval(forecast[index].epochtime - 60 * 60))
        entries.append(TimeStepEntry(
          date: date,
          updated: updated,
          location: location,
          timeSteps: timeSteps,
          crisisMessage: crisisMessage,
          error: nil,
          settings: settings
        ))
      }

      // Expire the last complete window, including when the server returned fewer than 30 steps.
      if let lastEntry = entries.last {
        entries.append(TimeStepEntry(
          date: lastEntry.date.addingTimeInterval(60 * 60),
          updated: updated,
          location: location,
          timeSteps: lastEntry.timeSteps,
          crisisMessage: crisisMessage,
          error: .oldDataError,
          settings: settings
        ))
      }
      saveEntries(entries, settings: configuration)
    }
    return Timeline(entries: entries, policy: policy)
  }

  func getUserDefaultsKey(settings: SettingsIntent) -> String {
    let currentLocation = settings.currentLocation == 0 ? "false" : "true"
    let customLocation = settings.location == nil ? "nil" : settings.location!.displayString
    return "\(USER_DEFAULTS_PREFIX)-\(settings.theme.rawValue)-\(currentLocation)-\(customLocation)"
  }

  func saveEntries(_ entries: [TimeStepEntry], settings: SettingsIntent) {
    guard !entries.isEmpty, let data = try? JSONEncoder().encode(entries) else { return }
    let key = getUserDefaultsKey(settings: settings)
    userDefaults.set(data, forKey: key + "-entries")
    userDefaults.set(now().timeIntervalSince1970, forKey: key + "-updated")
  }

  func getEntries(settings: SettingsIntent) -> [TimeStepEntry]? {
    let key = getUserDefaultsKey(settings: settings)
    if let data = userDefaults.data(forKey: key + "-entries"),
       let entries = try? JSONDecoder().decode([TimeStepEntry].self, from: data) {
      return entries
    }
    return nil
  }

  func getUpdated(settings: SettingsIntent) -> Date? {
    let key = getUserDefaultsKey(settings: settings)
    guard let timestamp = userDefaults.object(forKey: key + "-updated") as? Double else { return nil }
    return Date(timeIntervalSince1970: timestamp)
  }
}

struct ErrorView : View {
  var entry: ForecastProvider.Entry
     
  var body: some View {
    VStack {
      Spacer()
      switch entry.error {
        case .userLocationError:
          Text("Could not get location information").style(.errorTitle).multilineTextAlignment(.center)
        case .dataLoadingError:
          Text("Error loading forecast data").style(.errorTitle).multilineTextAlignment(.center)
        case .oldDataError:
          Text("Weather data is too old").style(.errorTitle).multilineTextAlignment(.center)
        default:
          Text("Unknown error").style(.errorTitle).multilineTextAlignment(.center)
      }
      Spacer()
    }.modifier(TextModifier())
  }
}

struct SmallWidgetView : View {
  var entry: ForecastProvider.Entry

  var body: some View {
    if (entry.error != nil) {
      ForecastErrorView(error: entry.error!, size: .small)
    } else {
      VStack(spacing: 0) {
        Text(entry.location.name).style(.boldLocation)
        Text(entry.location.area).style(.location)
        Spacer()
        NextHourForecast(timeStep: entry.timeSteps[0])
        Spacer()
        if (entry.crisisMessage != nil) {
          HStack{
            Text(entry.crisisMessage!)
              .style(.crisis)
              .foregroundStyle(Color("CrisisTextColor"))
              .lineLimit(2)
              .fixedSize(horizontal: false, vertical: true)
          }.padding(.horizontal, 9).background(Color("CrisisBackgroundColor"))
        } else {
          if (entry.settings.showLogo) {
            Image(decorative: "FMI").resizable().frame(width: 50, height: 24)
          }
        }
      }.padding(.horizontal, 5).modifier(TextModifier())
    }
  }
}

struct MediumWidgetView : View {
  var entry: ForecastProvider.Entry

  var body: some View {
    if (entry.error != nil) {
      ForecastErrorView(error: entry.error!, size: .medium)
    } else {
      VStack {
        if (entry.crisisMessage == nil) {
          HStack {
            Text(
              "**\(entry.formatLocation())** \(entry.formatArea())"
            ).style(.location)
            Spacer()
            if (entry.settings.showLogo) {
              Image(decorative: "FMI").resizable().frame(width: 56, height: 27)
            }
          }.padding(.horizontal, 10)
        }
        Spacer()
        ForecastRow(location: entry.location, timeSteps: entry.timeSteps)
        Spacer()
        if (entry.crisisMessage != nil) {
          CrisisMessage(message: entry.crisisMessage!)
          Spacer()
        }
      }.padding(.horizontal, 8).modifier(TextModifier())
    }
  }
}

struct LargeWidgetView : View {
  var entry: ForecastProvider.Entry
  @Environment(\.colorScheme) var colorScheme

  var body: some View {
    GeometryReader { geometry in
      if (entry.error != nil) {
        ForecastErrorView(error: entry.error!, size: .large)
      } else {
        VStack {
          Text(
            "**\(entry.formatLocation())** \(entry.formatArea())"
          ).style(.location)
          Text("at \(entry.timeSteps[0].formatTime(timezone: entry.location.timezone))")
            .style(.largeTime)
          NextHourForecast(timeStep: entry.timeSteps[0], large: geometry.size.height >= 320)
          if (colorScheme == .dark) {
            Divider().background(.white)
          }
          LargeNextHoursForecast(
            timeSteps: entry.timeSteps,
            timezone: entry.location.timezone,
            transparent: entry.settings.theme == "gradient"
          )
          if (entry.crisisMessage != nil) {
            Spacer()
            CrisisMessage(message: entry.crisisMessage!)
            Spacer()
          } else {
            Spacer()
            HStack {
              Image(decorative: "FMI").resizable().frame(width: 56, height: 27)
              Spacer()
              Text("Updated at **\(entry.formatUpdated())**").style(.updatedTime)
              Spacer()
              Spacer().frame(width: 56, height: 27)
            }
          }
        }.padding(.horizontal, 8).modifier(TextModifier())
      }
    }
  }
}

struct ForecastWidgetEntryView : View {
  @Environment(\.widgetFamily) var family
  @Environment(\.colorScheme) var colorScheme

  var entry: ForecastProvider.Entry
  
  var body: some View {
    if (family == .systemLarge) {
      LargeWidgetView(entry: entry)
        .colorScheme(resolveColorScheme(settings: entry.settings) ?? colorScheme)
    } else if (family == .systemMedium) {
      MediumWidgetView(entry: entry)
        .colorScheme(resolveColorScheme(settings: entry.settings) ?? colorScheme)
    } else {
      SmallWidgetView(entry: entry)
        .colorScheme(resolveColorScheme(settings: entry.settings) ?? colorScheme)
    }
  }
}

struct ForecastWidget: Widget {
  let kind: String = "ForecastWidget"
    
  var body: some WidgetConfiguration {
    IntentConfiguration(
      kind: kind, intent: SettingsIntent.self, provider: ForecastProvider()
    ) { entry in
        ForecastWidgetEntryView(entry: entry)
          .containerBackground(
            entry.settings.theme == "gradient" ? backroundGradient() : singleColorWidgetBackground(entry.settings),
            for: .widget
          ).padding(8)
      }
      .contentMarginsDisabled()
      .configurationDisplayName("Forecast")
      .description(
        "Displays the forecast for the next hour or the coming hours. Press and hold the widget to edit settings."
      ).supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

#Preview(as: .systemSmall) {
    ForecastWidget()
} timeline: {
    defaultEntry
}
