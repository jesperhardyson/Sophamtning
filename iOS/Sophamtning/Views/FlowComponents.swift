import SophamtningDesign
import SophamtningKit
import SwiftUI

// Delar som kommunfrågan, adressökningen och områdesvalet delar.

enum AddRoute: Hashable {
    case kommun
    case search(source: String?)
    case areas(title: String, hits: [SearchHit])
}

/// Adressflödet i ett ark. Efter en sparad adress anropas `onSaved`, som stänger arket.
struct AddFlowView: View {
    let model: AppModel
    let root: AddRoute
    let onClose: () -> Void
    let onSaved: () -> Void

    var body: some View {
        NavigationStack {
            destination(root, isRoot: true)
                .navigationDestination(for: AddRoute.self) { destination($0, isRoot: false) }
        }
    }

    @ViewBuilder
    private func destination(_ route: AddRoute, isRoot: Bool) -> some View {
        Group {
            switch route {
            case .kommun: KommunCheckView(model: model)
            case .search(let source): SearchView(model: model, presetSource: source, onSaved: onSaved)
            case .areas(let title, let hits): AreaPickerView(model: model, title: title, hits: hits, onSaved: onSaved)
            }
        }
        .toolbar {
            if isRoot {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onClose) { Image(systemName: "xmark") }
                        .accessibilityLabel("Stäng")
                }
            }
        }
    }
}

struct FlowSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(.body))
                .foregroundStyle(Color.Theme.text)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .font(.ui(18, weight: .semibold, relativeTo: .body))
                .foregroundStyle(Color.Theme.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.Theme.text2)
                }
                .accessibilityLabel("Rensa")
            }
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 48)
        .background(Color.Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.Theme.border))
    }
}

/// Primärknapp, 52 hög och helt rund. Används både för knappar och navigeringslänkar.
struct PrimaryButtonLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.ui(17, weight: .heavy, relativeTo: .headline))
            .foregroundStyle(Color.Theme.onPrimary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .background(Color.Theme.primary, in: Capsule())
    }
}

/// Vit lista med avgränsare, som träffarna och områdena.
struct ResultList<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.Theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct ResultDivider: View {
    var body: some View { Rectangle().fill(Color.Theme.border).frame(height: 1) }
}

/// Sparar adressen och anropar `onSaved` om det gick. Går det inte är lagringsfelet satt i modellen.
@MainActor
func save(_ hit: SearchHit, in model: AppModel, onSaved: () -> Void) -> Bool {
    model.clearStorageError()
    guard model.add(hit) else { return false }
    onSaved()
    return true
}

/// Källans namn för ett id, annars id:t med stor bokstav.
func sourceName(_ id: String, in sources: [Source]?) -> String {
    if let name = sources?.first(where: { $0.id == id })?.name { return name }
    return id.prefix(1).uppercased() + id.dropFirst()
}

func capitalizedFirst(_ text: String) -> String {
    text.prefix(1).uppercased() + text.dropFirst()
}

/// "Avesta kommun" blir "Avesta". Namn utan ordet "kommun" lämnas som de är.
func shortKommunName(_ name: String) -> String {
    name.hasSuffix(" kommun") ? String(name.dropLast(" kommun".count)) : name
}

/// En träff som valts, med ett id som skiljer träffar från olika källor åt.
struct HitSelection: Identifiable {
    let hit: SearchHit
    var id: String { "\(hit.source)/\(hit.id)" }
}

let tipURL = URL(string: "https://sopor.hardyson.se/bidra")!
