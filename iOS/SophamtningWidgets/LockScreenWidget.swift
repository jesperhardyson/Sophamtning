import SophamtningKit
import SwiftUI
import WidgetKit

/// Widgetarna på låsskärmen: raden ovanför klockan, rektangeln och cirkeln. I systemets färger, utan egen bakgrund.
struct LockScreenWidget: View {
    let family: WidgetFamily
    let content: LockScreenContent

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(content.inline)
        case .accessoryCircular:
            circle
        default:
            rectangle
        }
    }

    private var rectangle: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(content.title)
                .font(.headline)
                .widgetAccentable()
            if !content.date.isEmpty {
                Text(content.date)
                    .font(.subheadline)
            }
            HStack(spacing: 4) {
                if content.placedOut {
                    Image(systemName: "checkmark.circle.fill")
                }
                Text(content.line)
            }
            .font(.subheadline)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var circle: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                if content.placedOut {
                    Image(systemName: "checkmark")
                        .font(.title2.weight(.bold))
                } else if let days = content.days {
                    Image(systemName: "trash")
                        .font(.caption2)
                    Text(days)
                        .font(.title3.weight(.bold))
                        .minimumScaleFactor(0.6)
                    Text("dgr")
                        .font(.caption2)
                } else {
                    Image(systemName: "trash")
                        .font(.title3)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.inline)
    }
}
