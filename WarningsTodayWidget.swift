import WidgetKit
import CoreLocation
import SwiftUI

struct WarningProviderDependencies {
  var loadCurrentLocation: () async throws -> CLLocation? = { try await getCurrentLocation() }
  var resolveLocation: (Double, Double) async throws -> Location? = { try await fetchLocation(lat: $0, lon: $1) }
  var loadWarnings: (Location) async throws -> [WarningTimeStep]? = { try await fetchWarnings($0) }
  var loadCrisisMessage: () async throws -> String? = { try await fetchCrisisMessage() }
}

struct WarningProvider: IntentTimelineProvider {
  let USER_DEFAULTS_PREFIX = "warnings-today"
  var dependencies = WarningProviderDependencies()
  var userDefaults: UserDefaults = .standard
  var bundle: Bundle = .main
  var now: () -> Date = { Date() }
  var calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Helsinki")!
    return calendar
  }()

  func placeholder(in context: Context) -> WarningEntry {
    return defaultWarningEntry
  }

  func getSnapshot(
    for configuration: SettingsIntent,
    in context: Context,
    completion: @escaping (WarningEntry) -> ()) {
    completion(defaultWarningEntry)
  }

  func getTimeline(
    for configuration: SettingsIntent,
    in context: Context,
    completion: @escaping (Timeline<Entry>) -> ()) {
    Task {
      completion(await makeTimeline(for: configuration))
    }
  }

  func makeTimeline(for configuration: SettingsIntent) async -> Timeline<WarningEntry> {
    var error: WidgetError?
    var warnings: [WarningTimeStep]?
    var crisisMessage: String?
    var location: Location?
    let updateInterval = getSetting("warnings.interval", bundle: bundle) as? Int ?? UPDATE_INTERVAL
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

    if let location, location.iso2 != "FI" {
      error = .locationOutsideDataArea
    }

    if getSetting("announcements.enabled", bundle: bundle) as? Bool == true {
      crisisMessage = try? await dependencies.loadCrisisMessage()
    }

    if let location, error == nil {
      warnings = try? await dependencies.loadWarnings(location)
      if warnings == nil {
        error = .dataLoadingError
      }
    }

    let updated = now()
    let policy = TimelineReloadPolicy.after(updated.addingTimeInterval(TimeInterval(updateInterval * 60)))
    if let error {
      if let lastUpdated = getUpdated(settings: configuration),
         lastUpdated.addingTimeInterval(TimeInterval(WARNING_VALIDITY_PERIOD)) > updated,
         let oldEntries, !oldEntries.isEmpty {
        return Timeline(entries: oldEntries, policy: policy)
      }
      return Timeline(entries: [WarningEntry(
        date: updated,
        updated: updated,
        location: defaultLocation,
        warnings: [],
        crisisMessage: nil,
        error: error,
        settings: settings
      )], policy: policy)
    }

    var entries: [WarningEntry] = []
    if let warnings, let location {
      // Finnish warnings and their displayed dates use Helsinki calendar days, including DST changes.
      let today = calendar.startOfDay(for: updated)
      let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
      let expiration = calendar.date(byAdding: .day, value: 2, to: today)!
      for date in [today, tomorrow] {
        let currentDayWarnings = warnings.filter { warning in
          warning.language == "fi" && warning.isValidOnDay(date, calendar: calendar)
        }
        entries.append(WarningEntry(
          date: date,
          updated: updated,
          location: location,
          warnings: sortWarnings(filterUniqueWarnings(currentDayWarnings)),
          crisisMessage: crisisMessage,
          error: nil,
          settings: settings
        ))
      }
      entries.append(WarningEntry(
        date: expiration,
        updated: updated,
        location: location,
        warnings: [],
        crisisMessage: crisisMessage,
        error: .oldDataError,
        settings: settings
      ))
      saveEntries(entries, settings: configuration)
    }
    return Timeline(entries: entries, policy: policy)
  }

  func getUserDefaultsKey(settings: SettingsIntent) -> String {
    let currentLocation = settings.currentLocation == 0 ? "false" : "true"
    let customLocation = settings.location == nil ? "nil" : settings.location!.displayString
    return "\(USER_DEFAULTS_PREFIX)-\(settings.theme.rawValue)-\(currentLocation)-\(customLocation)"
  }

  func saveEntries(_ entries: [WarningEntry], settings: SettingsIntent) {
    guard !entries.isEmpty, let data = try? JSONEncoder().encode(entries) else { return }
    let key = getUserDefaultsKey(settings: settings)
    userDefaults.set(data, forKey: key + "-entries")
    userDefaults.set(now().timeIntervalSince1970, forKey: key + "-updated")
  }

  func getEntries(settings: SettingsIntent) -> [WarningEntry]? {
    let key = getUserDefaultsKey(settings: settings)
    if let data = userDefaults.data(forKey: key + "-entries"),
       let entries = try? JSONDecoder().decode([WarningEntry].self, from: data) {
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

struct SmallWarningsTodayView : View {
  var entry: WarningProvider.Entry;

  var body: some View {
    if (entry.error != nil) {
      WarningsErrorView(error: entry.error!, size: .small)
        .modifier(TextModifier())
    } else {
      VStack {
        Text(entry.location.name).style(.boldLocation)
        Text(entry.location.area).style(.location)
        if (entry.warnings.isEmpty) {
          Spacer()
          Text("No warnings")
          Spacer()
        } else {
          Spacer()
          HStack(spacing: 15) {
            let range = 0..<min(3, entry.warnings.count)
            ForEach(range, id: \.self) { i in
              WarningIcon(warning: entry.warnings[i])
            }
          }
          Spacer()
          if (entry.crisisMessage != nil) {
            Spacer()
            Text(entry.crisisMessage!)
              .style(.crisis)
              .padding(.horizontal, 9)
              .foregroundStyle(Color("CrisisTextColor"))
              .background(Color("CrisisBackgroundColor"))
              .lineLimit(2)
              .fixedSize(horizontal: false, vertical: true)
          } else if (entry.warnings.count == 1) {
            VStack {
              Text("**\(entry.warnings[0].type.accessibilityLabel)**")
              Text(entry.warnings[0].duration.formatDuration())
            }
          } else {
            Text("Warnings (\(entry.warnings.count))")
          }
          Spacer()
        }
      }.modifier(TextModifier())
    }
  }
}

struct WarningsTodayView : View {
  var entry: WarningProvider.Entry;
  var size : ErrorViewSize
  var maxWarningRows: Int
  
  var body: some View {
    if (entry.error != nil) {
      WarningsErrorView(error: entry.error!, size: size)
        .modifier(TextModifier())
    } else {
      VStack(alignment: .leading) {
        Text(
          "**\(entry.formatLocation())** \(entry.formatArea())"
        ).style(.location)
          .padding(.top, 3)
          .frame(maxWidth: .infinity, alignment: .center)
        if (entry.warnings.isEmpty) {
          Spacer()
          Text("No warnings").frame(maxWidth: .infinity, alignment: .center)
          Spacer()
        } else {
          Spacer()
          if (maxWarningRows <= 2 && entry.warnings.count > 2) {
            WarningRow(warning: entry.warnings[0])
          } else {
            let range = 0..<min(maxWarningRows, entry.warnings.count)
            ForEach(range, id: \.self) { i in
              WarningRow(warning: entry.warnings[i])
              if (maxWarningRows > 2) {
                Spacer().frame(minHeight: 7, maxHeight: 24)
              }
            }
          }
          Spacer()
          if (entry.crisisMessage != nil) {
            CrisisMessage(message: entry.crisisMessage!)
          } else if entry.warnings.count > maxWarningRows {
            HStack {
              Spacer()
              Text("More warnings (\(entry.warnings.count - maxWarningRows))")
              Spacer()
            }
          }
        }
        if (entry.crisisMessage == nil) {
          WarningsUpdated(
            updated: entry.formatUpdated(),
            logoPosition: size == .medium ? .right : .left
          )
        }
      }.modifier(TextModifier())
    }
  }
}

struct WarningsTodayEntryView : View {
  @Environment(\.widgetFamily) var family
  @Environment(\.colorScheme) var colorScheme
  var entry: WarningProvider.Entry
  
  var body: some View {
    if (family == .systemSmall) {
      SmallWarningsTodayView(entry: entry)
        .colorScheme(resolveColorScheme(settings: entry.settings) ?? colorScheme)
    } else {
      WarningsTodayView(
        entry: entry,
        size: family == .systemMedium ? .medium : .large,
        maxWarningRows: family == .systemMedium ? 2 : 4
      )
        .colorScheme(resolveColorScheme(settings: entry.settings) ?? colorScheme)
        .padding(.horizontal, 13)
    }
  }
}

struct WarningsTodayWidget: Widget {
  let kind: String = "WarningsTodayWidget"

  var body: some WidgetConfiguration {
    IntentConfiguration(kind: kind, intent: SettingsIntent.self, provider: WarningProvider()) { entry in
      WarningsTodayEntryView(entry: entry)
        .containerBackground(
          entry.settings.theme == "gradient" ? backroundGradient() : singleColorWidgetBackground(entry.settings),
          for: .widget)
        .padding(10)
    }
    .contentMarginsDisabled()
    .configurationDisplayName("Weather warnings for today")
    .description("Weather warnings in your location. Press and hold the widget to edit settings.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

#Preview(as: .systemSmall) {
  WarningsTodayWidget()
} timeline: {
  defaultWarningEntry
}
