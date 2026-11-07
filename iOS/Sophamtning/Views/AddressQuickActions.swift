import SophamtningDesign
import SophamtningKit
import SwiftUI
import UIKit

// MARK: Gemensamma dialoger

extension View {
    /// Dialogen för att byta namn, samma i adressvyn och på hemskärmen.
    func renameAddressAlert(isPresented: Binding<Bool>, name: Binding<String>, onSave: @escaping () -> Void) -> some View {
        alert("Byt namn", isPresented: isPresented) {
            TextField("Namn", text: name)
            Button("Spara", action: onSave)
                .disabled(AddressList.validName(name.wrappedValue) == nil)
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Namnet får vara högst \(AddressList.maxNameLength) tecken.")
        }
    }

    /// Bekräftelsen före borttagning, samma i adressvyn och på hemskärmen.
    func removeAddressConfirmation(isPresented: Binding<Bool>, onRemove: @escaping () -> Void) -> some View {
        confirmationDialog("Ta bort adressen?", isPresented: isPresented, titleVisibility: .visible) {
            Button("Ta bort", role: .destructive, action: onRemove)
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Adressen, det sparade schemat och dess påminnelser tas bort från telefonen.")
        }
    }
}

// MARK: Snabbval på hemskärmen

/// En adress på hemskärmen med svep och snabbmeny. Svep åt vänster visar **Ta bort**, och ett långt tryck öppnar
/// systemets snabbmeny med samma val som menyn i adressvyn, plus påminnelserna. VoiceOver får samma val som åtgärder.
/// Allt går via `AppModel`, med samma regler som i adressvyn, så inget slås på utan användarens val.
struct AddressQuickActions<Content: View>: View {
    let model: AppModel
    let key: AddressKey
    let cornerRadius: CGFloat
    /// Huvudkortet har en rund knapp bakom sig, och raderna en knapp lika hög som raden.
    let buttonShape: SwipeReveal.ButtonShape
    /// Raden som står öppen. Bara en åt gången.
    @Binding var openRow: AddressKey?
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmingRemoval = false
    @State private var notificationsDenied = false

    /// Valen i snabbmenyn och bland VoiceOver-åtgärderna. En enda källa för båda.
    private enum Choice: Hashable {
        case rename, makePrimary, notifications, liveActivity, remove
    }

    private var address: SavedAddress? { model.addresses.first { $0.key == key } }

    var body: some View {
        SwipeToDeleteRow(id: key, cornerRadius: cornerRadius, buttonShape: buttonShape, openRow: $openRow, onDelete: { confirmingRemoval = true }) {
            content()
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .contextMenu { if let address { menu(address) } }
                .accessibilityActions { if let address { actions(address) } }
        }
        .renameAddressAlert(isPresented: $renaming, name: $newName) {
            model.clearStorageError()
            model.rename(key, to: newName)
        }
        .removeAddressConfirmation(isPresented: $confirmingRemoval) {
            model.clearStorageError()
            // Stängs före borttagningen, så att läget inte följer med till nästa adress.
            openRow = nil
            withAnimation(Motion.transition(reduceMotion: reduceMotion)) { model.remove(key) }
        }
        .onChange(of: confirmingRemoval) { _, shown in
            // Avbryt, eller ett tryck utanför: raden glider tillbaka.
            if !shown, openRow == key { openRow = nil }
        }
        // Snabbmenyn stängs när ett val görs, så nekad behörighet visas här i stället för i en rad som inte syns.
        .alert("Notiser är avstängda", isPresented: $notificationsDenied) {
            Button("Öppna Inställningar") {
                guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
                Task { await UIApplication.shared.open(url) }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Du har stängt av notiser för Sophämtning i iOS.")
        }
    }

    /// Valen i ordning, samma som i adressvyn. Live Activity gäller bara huvudadressen.
    private func choices(_ address: SavedAddress) -> [Choice] {
        var choices: [Choice] = [.rename]
        if !address.isPrimary { choices.append(.makePrimary) }
        choices.append(.notifications)
        if address.isPrimary { choices.append(.liveActivity) }
        choices.append(.remove)
        return choices
    }

    /// Samma ordning, texter och ikoner som i adressvyn.
    @ViewBuilder
    private func menu(_ address: SavedAddress) -> some View {
        ForEach(choices(address), id: \.self) { choice in
            switch choice {
            case .rename:
                Button { perform(.rename, address) } label: { Label("Byt namn", systemImage: "pencil") }
            case .makePrimary:
                Button { perform(.makePrimary, address) } label: { Label("Gör till huvudadress", systemImage: "house") }
            case .notifications:
                // Closures i stället för metodreferenser: Swift 6.3 i Xcode 26.6 kraschar på omvandlingen av en metod till `set:`.
                Toggle(isOn: Binding(get: { model.remindersOn(for: address) }, set: { setNotifications($0) })) {
                    Label("Notis kvällen före", systemImage: "bell.badge")
                }
            case .liveActivity:
                // Avstängda i iOS visas överst på hemskärmen, och fel på hemkortet.
                Toggle(isOn: Binding(get: { model.settings.liveActivityOn }, set: { setLiveActivity($0) })) {
                    Label("Live Activity", systemImage: "iphone.radiowaves.left.and.right")
                    Text("Starten aviseras med ljud.")
                }
            case .remove:
                Button(role: .destructive) { perform(.remove, address) } label: { Label("Ta bort", systemImage: "trash") }
            }
        }
    }

    /// Samma val som snabbmenyn, som VoiceOver-åtgärder. Reglagen blir åtgärder som säger vad de gör.
    @ViewBuilder
    private func actions(_ address: SavedAddress) -> some View {
        ForEach(choices(address), id: \.self) { choice in
            Button(actionName(choice, address)) { perform(choice, address) }
        }
    }

    private func actionName(_ choice: Choice, _ address: SavedAddress) -> String {
        switch choice {
        case .rename: "Byt namn"
        case .makePrimary: "Gör till huvudadress"
        case .notifications: model.remindersOn(for: address) ? "Stäng av notis kvällen före" : "Slå på notis kvällen före"
        case .liveActivity: model.settings.liveActivityOn ? "Stäng av Live Activity" : "Slå på Live Activity"
        case .remove: "Ta bort"
        }
    }

    // MARK: Val

    private func perform(_ choice: Choice, _ address: SavedAddress) {
        switch choice {
        case .rename:
            newName = address.displayName
            renaming = true
        case .makePrimary:
            model.clearStorageError()
            model.setPrimary(key)
        case .notifications:
            setNotifications(!model.remindersOn(for: address))
        case .liveActivity:
            setLiveActivity(!model.settings.liveActivityOn)
        case .remove:
            confirmingRemoval = true
        }
    }

    private func setNotifications(_ on: Bool) {
        model.clearStorageError()
        Task {
            // Frågan om tillstånd ställs av modellen, bara när valet slås på. Ett lagringsfel visas överst på hemskärmen.
            if await model.setNotifications(on, for: key) == .denied { notificationsDenied = true }
        }
    }

    private func setLiveActivity(_ on: Bool) {
        model.clearStorageError()
        model.setLiveActivity(on)
    }
}

// MARK: Svep

/// En rad som går att svepa åt vänster, som i Mail: knappen **Ta bort** kommer fram till höger, och ett fullt svep
/// eller ett tryck på knappen anropar `onDelete`. Svepet börjar bara efter en tydligt vågrät rörelse, så att scrollning,
/// dra för att uppdatera och tryck på raden fungerar som vanligt.
struct SwipeToDeleteRow<ID: Hashable, Content: View>: View {
    let id: ID
    /// Den höga knappens hörn följer radens.
    let cornerRadius: CGFloat
    /// En rund knapp mitt för raden, eller en knapp lika hög som raden.
    let buttonShape: SwipeReveal.ButtonShape
    @Binding var openRow: ID?
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var start: CGFloat = 0
    @State private var dragging = false
    @State private var width: CGFloat = 0

    private var isFullSwipe: Bool { width > 0 && SwipeReveal.isFullSwipe(offset: offset, width: width, shape: buttonShape) }

    /// Ett tryck på raden stänger den öppna raden, den här eller en annan, i stället för att öppna adressen.
    private var tapCloses: Bool {
        if offset < 0 { return !dragging }
        return openRow != nil && openRow != id
    }

    var body: some View {
        content()
            .overlay {
                if tapCloses {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { openRow = nil }
                        .accessibilityHidden(true)
                }
            }
            .offset(x: offset)
            .background(alignment: .trailing) { deleteButton }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            .gesture(SwipePan(isOpen: offset < 0, onChange: { changed($0) }, onEnd: { ended($0) }, onCancel: { cancelled() }))
            .sensoryFeedback(.impact(weight: .light), trigger: isFullSwipe) { _, full in full }
            .onChange(of: openRow) { _, row in
                // En annan rad öppnades, eller hemskärmen scrollades.
                if row != id, !dragging { settle(at: 0) }
            }
            .anchorPreference(key: SwipeRowBounds.self, value: .bounds) { [$0] }
    }

    private var deleteButton: some View {
        let revealed = max(0, -offset - SwipeReveal.gap)
        return Button(action: onDelete) {
            switch buttonShape {
            case .fullHeight: fullHeightLabel
            case .round: roundLabel
            }
        }
        // Den runda knappen sitter vid raden när den har kommit fram helt, och följer raden vid ett längre svep.
        .frame(width: revealed, alignment: revealed < buttonShape.buttonWidth ? .trailing : .leading)
        .frame(maxHeight: .infinity)
        .opacity(offset < 0 ? 1 : 0)
        // VoiceOver når borttagningen med en åtgärd på raden. Knappen läses bara när raden står öppen.
        .accessibilityHidden(offset >= 0)
        .accessibilityIdentifier("svep-ta-bort")
    }

    /// Knappen på raderna: lika hög som raden, med radens hörn.
    private var fullHeightLabel: some View {
        VStack(spacing: 4) {
            Image(systemName: "trash")
                .font(.system(.title3, weight: .semibold))
                .accessibilityHidden(true)
            Text("Ta bort")
                .font(.ui(15, weight: .heavy, relativeTo: .footnote))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.Theme.destructive, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Knappen bakom huvudkortet: en rund knapp mitt för kortet, med texten under. Den tonas och skalas in med svepet,
    /// och fjädrar med raden. Med Reducera rörelse tonas den bara in.
    private var roundLabel: some View {
        let progress = SwipeReveal.revealProgress(offset: offset, shape: buttonShape)
        return VStack(spacing: 6) {
            Image(systemName: "trash")
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: buttonShape.buttonWidth, height: buttonShape.buttonWidth)
                .background(Color.Theme.destructive, in: Circle())
                .accessibilityHidden(true)
            Text("Ta bort")
                .font(.ui(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(Color.Theme.text)
                // Knappen är 56 pt bred i alla textstorlekar. Texten bryts efter "Ta" när den inte ryms på en rad, och
                // växer inte längre än till tredje tillgänglighetsstorleken, så att "bort" ryms i bredden.
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .frame(width: buttonShape.buttonWidth)
        .contentShape(Rectangle())
        .scaleEffect(reduceMotion ? 1 : 0.5 + 0.5 * progress)
        .opacity(progress)
    }

    private func changed(_ translation: CGFloat) {
        if !dragging {
            dragging = true
            start = offset
            openRow = id
        }
        offset = SwipeReveal.offset(start: start, translation: translation, width: width)
    }

    private func ended(_ velocity: CGFloat) {
        dragging = false
        switch SwipeReveal.outcome(offset: offset, velocity: velocity, width: width, shape: buttonShape) {
        case .delete:
            // Raden står öppen medan bekräftelsen visas, och glider tillbaka vid Avbryt.
            openRow = id
            settle(at: -buttonShape.openWidth)
            onDelete()
        case .open:
            openRow = id
            settle(at: -buttonShape.openWidth)
        case .closed:
            if openRow == id { openRow = nil }
            settle(at: 0)
        }
    }

    /// Ett avbrutet svep tar aldrig bort och bekräftar aldrig. Raden stängs bara.
    private func cancelled() {
        dragging = false
        if openRow == id { openRow = nil }
        settle(at: 0)
    }

    private func settle(at target: CGFloat) {
        withAnimation(SwipeReveal.settle(reduceMotion: reduceMotion)) { offset = target }
    }
}

/// Var raderna med svep ligger, så att ett tryck utanför dem kan stänga den öppna raden.
struct SwipeRowBounds: PreferenceKey {
    static var defaultValue: [Anchor<CGRect>] { [] }

    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Ett tryck utanför raderna stänger den öppna raden och gör inget annat, som i Mail. Raderna sköter själva tryck
    /// på sig, och scrollning stänger raden via `onScrollPhaseChange`.
    func closesOpenSwipeRow<ID: Hashable>(_ openRow: Binding<ID?>) -> some View {
        overlayPreferenceValue(SwipeRowBounds.self) { anchors in
            if openRow.wrappedValue != nil {
                GeometryReader { proxy in
                    Color.clear
                        .contentShape(OutsideRows(rows: anchors.map { proxy[$0] }))
                        .onTapGesture { openRow.wrappedValue = nil }
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

/// Ytan utanför raderna.
private struct OutsideRows: Shape {
    let rows: [CGRect]

    func path(in rect: CGRect) -> Path {
        rows.reduce(Path(rect)) { $0.subtracting(Path($1)) }
    }
}

/// Panoreringen bakom svepet. En UIKit-gest, eftersom den måste kunna avstå innan scrollvyn tar över: den börjar bara
/// när rörelsen är tydligt vågrät, och scrollvyn väntar till dess. Annars får scrollvyn rörelsen direkt.
private struct SwipePan: UIGestureRecognizerRepresentable {
    let isOpen: Bool
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat) -> Void
    let onCancel: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.isOpen = isOpen
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChange(recognizer.translation(in: recognizer.view).x)
        case .ended:
            onEnd(recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed:
            onCancel()
        default:
            break
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isOpen = false

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let movement = pan.translation(in: pan.view)
            return SwipeReveal.begins(movement: CGSize(width: movement.x, height: movement.y), isOpen: isOpen)
        }

        /// Scrollvyns panorering väntar tills svepet har avstått, så att en vågrät rörelse aldrig också scrollar.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}
