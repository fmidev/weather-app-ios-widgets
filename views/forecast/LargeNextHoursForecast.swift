import SwiftUI
import WidgetKit

struct LargeNextHoursForecast: View {
    var timeSteps: [TimeStep]
    var timezone: String
    var transparent = true
    var rowBackground = Color("ForecastRowBackground")
    @Environment(\.widgetRenderingMode) private var renderingMode
  
    let COLUMN_WIDTH: CGFloat = 38
    
    var body: some View {
      VStack{
        HStack{
          Image(decorative: "clock")
          Spacer()
          ForEach(1..<timeSteps.count, id: \.self) { i in
            Text(timeSteps[i].formatHours(timezone: timezone))
              .style(.time)
              .frame(width: COLUMN_WIDTH)
            if (i<timeSteps.count-1) {
              Spacer()
            }
          }
        }
        .padding(8)
        .background { forecastRowBackground }
        
        HStack{
          Image(decorative: "symbol")
          Spacer()
          ForEach(1..<timeSteps.count, id: \.self) { i in
            Image(
              String(timeSteps[i].smartSymbol),
              label: Text(timeSteps[i].getSmartSymbolTranslationKey().localized())
            ).resizable().frame(width: COLUMN_WIDTH, height: COLUMN_WIDTH)
            if (i<timeSteps.count-1) {
              Spacer()
            }
          }
        }
        .frame(height: COLUMN_WIDTH)
        .padding(.horizontal, 8)
        
        HStack{
          Image(decorative: "temperature")
          Spacer()
          ForEach(1..<timeSteps.count, id: \.self) { i in
            Text(timeSteps[i].formatTemperature(includeDegree: true))
              .style(.temperature)
              .frame(width: COLUMN_WIDTH)
            if (i<timeSteps.count-1) {
              Spacer()
            }
          }
        }
        .padding(8)
        .background { forecastRowBackground }
      }
    }

    @ViewBuilder
    private var forecastRowBackground: some View {
      // Opaque row backgrounds hide the text when iOS tints both the same color.
      if renderingMode == .fullColor && !transparent {
        rowBackground
      }
    }
}

#Preview {
  LargeNextHoursForecast(
    timeSteps: [TimeStep](repeating: defaultTimeStep, count: 5),
    timezone: "Europe/Helsinki"
  )
}
