import SophamtningDesign
import SophamtningKit
import SwiftUI

// Delar som kommunfrågan, adressökningen och områdesvalet delar.

enum AddRoute: Hashable {
    case kommun
    case search(source: String?)
    /// `place` är platsen som områdena hämtades för. Utan plats finns inte "Hitta område med senaste tömningen".
    case areas(title: String, place: String?, hits: [SearchHit])
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
            case .areas(let title, let place, let hits): AreaPickerView(model: model, title: title, place: place, hits: hits, onSaved: onSaved)
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
    /// Fältet får fokus när skärmen visas, så att tangentbordet syns utan tryck.
    @FocusState private var focused: Bool

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
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.Theme.text2)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .padding(.trailing, -12)
                .accessibilityLabel("Rensa")
            }
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 48)
        .background(Color.Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.Theme.border))
        .task {
            // I ett ark tar fokus emot först när övergången är klar.
            try? await Task.sleep(for: .milliseconds(350))
            focused = true
        }
    }
}

/// Lägger innehållet på en rad, men under varandra med tillgänglighetsstorlekar på text, så att ingen text
/// bryts mitt i ett ord eller trängs ihop.
struct AdaptiveStack<Content: View>: View {
    var spacing: CGFloat = 12
    var verticalSpacing: CGFloat?
    var alignment: VerticalAlignment = .center
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: verticalSpacing ?? spacing))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
        layout { content }
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

/// Sparar adressen och anropar `onSaved` om det gick. Går det inte visar vyn sitt eget fel, så modellens
/// lagringsfel rensas för att inte dyka upp en gång till på hemskärmen.
@MainActor
func save(_ hit: SearchHit, in model: AppModel, onSaved: () -> Void) -> Bool {
    model.clearStorageError()
    guard model.add(hit) else {
        model.clearStorageError()
        return false
    }
    onSaved()
    return true
}

let saveFailedMessage = "Adressen kunde inte sparas. Försök igen."


/// Källans namn för ett id, annars id:t med stor bokstav.
func sourceName(_ id: String, in sources: [Source]?) -> String {
    if let name = sources?.first(where: { $0.id == id })?.name { return name }
    return id.prefix(1).uppercased() + id.dropFirst()
}

func capitalizedFirst(_ text: String) -> String {
    text.prefix(1).uppercased() + text.dropFirst()
}

/// En träff som valts, med ett id som skiljer träffar från olika källor åt.
struct HitSelection: Identifiable {
    let hit: SearchHit
    var id: String { "\(hit.source)/\(hit.id)" }
}

let tipLink = WebLink(url: URL(string: "https://sopor.hardyson.se/bidra")!)!

/// Adressen och platsen på var sin rad. Adressen i radens vanliga stil, och platsen en storlek mindre med en liten
/// platsikon. VoiceOver läser båda som en text, utan mittpunkt: "Storgatan 12, Krylbo, Avesta kommun".
struct AddressLinesView: View {
    let lines: HomeContent.AddressLines
    /// Adressens storlek. Platsen är två punkter mindre.
    let size: CGFloat
    let addressStyle: TextStyleChoice
    var addressColor: Color = Color.Theme.text2
    var placeColor: Color = Color.Theme.text2

    /// Textstilen som storleken följer med Dynamic Type, för adressen och för platsen en storlek ner.
    enum TextStyleChoice {
        case body, subheadline

        var address: Font.TextStyle { self == .body ? .body : .subheadline }
        var place: Font.TextStyle { self == .body ? .callout : .footnote }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !lines.address.isEmpty {
                Text(lines.address)
                    .font(.ui(size, weight: .semibold, relativeTo: addressStyle.address))
                    .foregroundStyle(addressColor)
            }
            if !lines.place.isEmpty {
                Label {
                    Text(lines.place)
                        .font(.ui(size - 2, weight: .semibold, relativeTo: addressStyle.place))
                } icon: {
                    Image(systemName: "mappin")
                        .font(.system(addressStyle.place, weight: .semibold))
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                .labelStyle(PlaceLabelStyle())
                .foregroundStyle(placeColor)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.accessibilityLabel)
    }
}

/// Ikonen tätt intill texten, på första radens baslinje.
private struct PlaceLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}
