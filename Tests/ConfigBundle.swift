import Foundation
import Testing

struct ConfigBundle {
  let bundle: Bundle
  private let url: URL

  init(contents: String?, unreadable: Bool = false) throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ConfigTests-\(UUID().uuidString).bundle", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    do {
      let info: [String: String] = [
        "CFBundleIdentifier": "org.weather-app.ConfigTests.\(UUID().uuidString)",
        "CFBundlePackageType": "BNDL"
      ]
      let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
      try data.write(to: url.appendingPathComponent("Info.plist"))
      let resourceURL = url.appendingPathComponent("widgetConfig.json")
      if unreadable {
        try FileManager.default.createDirectory(at: resourceURL, withIntermediateDirectories: false)
      } else if let contents {
        try contents.write(to: resourceURL, atomically: true, encoding: .utf8)
      }
      self.bundle = try #require(Bundle(url: url))
      self.url = url
    } catch {
      try? FileManager.default.removeItem(at: url)
      throw error
    }
  }

  func remove() {
    try? FileManager.default.removeItem(at: url)
  }
}
