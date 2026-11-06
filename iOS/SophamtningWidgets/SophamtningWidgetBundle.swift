import SwiftUI
import WidgetKit

struct PlatshallareEntry: TimelineEntry {
    let date: Date
}

struct PlatshallareProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlatshallareEntry {
        PlatshallareEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (PlatshallareEntry) -> Void) {
        completion(PlatshallareEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<PlatshallareEntry>) -> Void) {
        completion(Timeline(entries: [PlatshallareEntry(date: .now)], policy: .never))
    }
}

struct PlatshallareWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "se.hardyson.sophamtning.platshallare", provider: PlatshallareProvider()) { _ in
            Text("Sophämtning")
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Sophämtning")
        .description("Platshållare tills widgeten byggs.")
    }
}

@main
struct SophamtningWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlatshallareWidget()
    }
}
