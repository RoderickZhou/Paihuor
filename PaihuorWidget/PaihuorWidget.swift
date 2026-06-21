import SwiftUI
import WidgetKit

struct PaihuorWidgetEntry: TimelineEntry {
    let date: Date
}

struct PaihuorWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PaihuorWidgetEntry {
        PaihuorWidgetEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (PaihuorWidgetEntry) -> Void) {
        completion(PaihuorWidgetEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PaihuorWidgetEntry>) -> Void) {
        completion(Timeline(entries: [PaihuorWidgetEntry(date: Date())], policy: .never))
    }
}

struct PaihuorWidgetView: View {
    let entry: PaihuorWidgetEntry

    var body: some View {
        Link(destination: URL(string: "paihuor://record")!) {
            ZStack {
                Color(red: 0.298, green: 0.686, blue: 0.314)

                VStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 42, weight: .bold))
                    Text("派活儿")
                        .font(.headline)
                }
                .foregroundStyle(.white)
            }
        }
    }
}

@main
struct PaihuorWidgetBundle: WidgetBundle {
    var body: some Widget {
        PaihuorQuickRecordWidget()
    }
}

struct PaihuorQuickRecordWidget: Widget {
    let kind = "PaihuorQuickRecord"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PaihuorWidgetProvider()) { entry in
            PaihuorWidgetView(entry: entry)
                .paiWidgetBackground()
        }
        .configurationDisplayName("派活儿")
        .description("点一下，马上新建一条派活。")
        .supportedFamilies([.systemSmall])
    }
}

private extension View {
    @ViewBuilder
    func paiWidgetBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(.fill.tertiary, for: .widget)
        } else {
            self
        }
    }
}
