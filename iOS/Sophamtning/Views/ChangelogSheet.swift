import SophamtningDesign
import SophamtningKit
import SwiftUI

/// Arket Nyheter, från raden Version i inställningarna. Innehållet kommer från `CHANGELOG.md`, som följer med appen, så
/// sidan fungerar utan nät och stämmer med versionen som är installerad.
struct ChangelogSheet: View {
    let onClose: () -> Void

    private let versions: [Changelog.Version] = {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return Changelog.parse(text)
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if versions.isEmpty {
                            MessageCard(style: .neutral, icon: "info.circle", title: "Inga nyheter att visa", message: "Nyheterna följer med nästa version av appen.")
                                .padding(.top, 16)
                        }
                        ForEach(versions) { version in
                            versionView(version)
                        }
                    }
                    .padding(.horizontal, PageMargin.horizontal)
                    .padding(.bottom, 32)
                }
                .hardTopEdgeWhenScrolled()
            }
            .navigationTitle("Nyheter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Systemets stängknapp i glas, som i de andra arken.
                    Button("Stäng", systemImage: "xmark", role: .close) { onClose() }
                }
            }
        }
    }

    private func versionView(_ version: Changelog.Version) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(version.title)
                .font(.ui(24, weight: .heavy, relativeTo: .title2))
                .foregroundStyle(Color.Theme.text)
                .padding(.top, 28)
                .padding(.bottom, 14)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(version.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.ui(16, weight: .heavy, relativeTo: .headline))
                            .foregroundStyle(Color.Theme.text2)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(section.items, id: \.self) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("•")
                                    .accessibilityHidden(true)
                                Text(item)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.ui(17, weight: .semibold, relativeTo: .body))
                            .foregroundStyle(Color.Theme.text)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.Theme.border))
        }
    }
}
