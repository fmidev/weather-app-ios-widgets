import SwiftUI
import Testing
import WidgetKit

@Suite("Large forecast rows")
struct LargeNextHoursForecastTests {
  @Test("Row backgrounds only appear in full color with an opaque theme", arguments: [
    (WidgetRenderingMode.fullColor, false, 255), (.fullColor, true, 0),
    (.accented, false, 0), (.accented, true, 0),
    (.vibrant, false, 0), (.vibrant, true, 0)
  ], [ColorScheme.light, .dark])
  @MainActor
  func rowBackgrounds(configuration: (WidgetRenderingMode, Bool, Int), scheme: ColorScheme) throws {
    let (mode, transparent, expectedAlpha) = configuration
    let view = LargeNextHoursForecast(
      timeSteps: [TimeStep](repeating: defaultTimeStep, count: 6),
      timezone: "Europe/Helsinki",
      transparent: transparent,
      rowBackground: .red
    )
    .frame(width: 340)
    .environment(\.widgetRenderingMode, mode)
    .environment(\.colorScheme, scheme)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    let image = try #require(renderer.cgImage)

    // Sample the padding of both rows, away from text and icons.
    #expect(try alpha(image, x: 1, y: 1) == expectedAlpha)
    #expect(try alpha(image, x: 1, y: image.height - 2) == expectedAlpha)

    // Removing a background must preserve the hours and temperatures themselves.
    for row in [0..<(image.height / 3), (image.height * 2 / 3)..<image.height] {
      var hasContent = false
      for y in row {
        for x in (image.width - 45)..<(image.width - 8) {
          if try alpha(image, x: x, y: y) > 0 {
            hasContent = true
            break
          }
        }
        if hasContent { break }
      }
      #expect(hasContent)
    }
  }

  private func alpha(_ image: CGImage, x: Int, y: Int) throws -> Int {
    let sample = try #require(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
    var rgba = [UInt8](repeating: 0, count: 4)
    try rgba.withUnsafeMutableBytes { bytes in
      let context = try #require(CGContext(
        data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
      ))
      context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    return Int(rgba[3])
  }
}
