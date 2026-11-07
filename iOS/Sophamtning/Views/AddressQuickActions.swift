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
/// systemets snabbmeny med samma val som menyn i adressvyn, plus påminnelserna. Allt går via `AppModel`, med samma
/// regler som i adressvyn, så inget slås på utan användarens val.
struct AddressQuickActions<Content: View>: View {
    let model: AppModel
    let key: AddressKey
    let cornerRadius: CGFloat
    /// Raden som står öppen. Bara en åt gången.
    @Binding var openRow: AddressKey?
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmingRemoval = false
    @State private var notificationsDenied = false
    /// Snabbvalen för VoiceOver, där systemets snabbmeny inte är en åtgärd på kortet.
    @State private var choosing = false
    /// Det som väljs bland snabbvalen öppnas först när de har stängts.
    @State private var afterChoice: Choice?

    private enum Choice { case rename, remove }

    private var address: SavedAddress? { model.addresses.first { $0.key == key } }

    var body: some View {
        SwipeToDeleteRow(id: key, cornerRadius: cornerRadius, openRow: $openRow, onDelete: { confirmingRemoval = true }) {
            content()
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .contextMenu { if let address { menu(address) } }
                .accessibilityAction(named: "Ta bort") { confirmingRemoval = true }
                .accessibilityAction(named: "Snabbval") { choosing = true }
        }
        .renameAddressAlert(isPresented: $renaming, name: $newName) {
            model.clearStorageError()
            model.rename(key, to: newName)
        }
        .removeAddressConfirmation(isPresented: $confirmingRemoval) {
            model.clearStorageError()
            withAnimation(Motion.transition(reduceMotion: reduceMotion)) { model.remove(key) }
        }
        .onChange(of: confirmingRemoval) { _, shown in
            // Avbryt, eller ett tryck utanför: raden glider tillbaka.
            if !shown, openRow == key { openRow = nil }
        }
        .confirmationDialog("Snabbval", isPresented: $choosing, titleVisibility: .visible) {
            if let address { choices(address) }
        }
        .onChange(of: choosing) { _, shown in
            guard !shown, let choice = afterChoice else { return }
            afterChoice = nil
            switch choice {
            case .rename: renaming = true
            case .remove: confirmingRemoval = true
            }
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

    /// Samma ordning, texter och ikoner som i adressvyn.
    @ViewBuilder
    private func menu(_ address: SavedAddress) -> some View {
        Button { startRename(address) } label: { Label("Byt namn", systemImage: "pencil") }
        if !address.isPrimary {
            Button { makePrimary() } label: { Label("Gör till huvudadress", systemImage: "house") }
        }
        // Closures i stället för metodreferenser: Swift 6.3 i Xcode 26.6 kraschar på omvandlingen av en metod till `set:`.
        Toggle(isOn: Binding(get: { model.remindersOn(for: address) }, set: { setNotifications($0) })) {
            Label("Notis kvällen före", systemImage: "bell.badge")
        }
        // Live Activity gäller bara huvudadressen. Avstängda i iOS visas överst på hemskärmen, och fel på hemkortet.
        if address.isPrimary {
            Toggle(isOn: Binding(get: { model.settings.liveActivityOn }, set: { setLiveActivity($0) })) {
                Label("Live Activity", systemImage: "iphone.radiowaves.left.and.right")
            }
        }
        Button(role: .destructive) { confirmingRemoval = true } label: { Label("Ta bort", systemImage: "trash") }
    }

    /// Samma val som snabbmenyn, i samma ordning. Reglagen blir knappar som säger vad de gör.
    @ViewBuilder
    private func choices(_ address: SavedAddress) -> some View {
        Button("Byt namn") { newName = address.displayName; afterChoice = .rename }
        if !address.isPrimary {
            Button("Gör till huvudadress") { makePrimary() }
        }
        let notificationsOn = model.remindersOn(for: address)
        Button(notificationsOn ? "Stäng av notis kvällen före" : "Slå på notis kvällen före") { setNotifications(!notificationsOn) }
        if address.isPrimary {
            let liveActivityOn = model.settings.liveActivityOn
            Button(liveActivityOn ? "Stäng av Live Activity" : "Slå på Live Activity") { setLiveActivity(!liveActivityOn) }
        }
        Button("Ta bort", role: .destructive) { afterChoice = .remove }
        Button("Avbryt", role: .cancel) {}
    }

    // MARK: Val

    private func startRename(_ address: SavedAddress) {
        newName = address.displayName
        renaming = true
    }

    private func makePrimary() {
        model.clearStorageError()
        model.setPrimary(key)
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

/// En rad som går att svepa åt vänster, som i Mail: en röd knapp **Ta bort** kommer fram till höger, och ett fullt svep
/// eller ett tryck på knappen anropar `onDelete`. Svepet börjar bara efter en tydligt vågrät rörelse, så att scrollning,
/// dra för att uppdatera och tryck på raden fungerar som vanligt.
struct SwipeToDeleteRow<ID: Hashable, Content: View>: View {
    let id: ID
    /// Knappens hörn följer radens.
    let cornerRadius: CGFloat
    @Binding var openRow: ID?
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var start: CGFloat = 0
    @State private var dragging = false
    @State private var width: CGFloat = 0

    private var isFullSwipe: Bool { width > 0 && SwipeReveal.isFullSwipe(offset: offset, width: width) }

    var body: some View {
        content()
            // Ett tryck på en öppen rad stänger den, i stället för att öppna adressen.
            .overlay {
                if offset < 0, !dragging {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { openRow = nil }
                        .accessibilityHidden(true)
                }
            }
            .offset(x: offset)
            .background(alignment: .trailing) { deleteButton }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            .gesture(SwipePan(isOpen: offset < 0, onChange: { changed($0) }, onEnd: { ended($0) }))
            .sensoryFeedback(.impact(weight: .light), trigger: isFullSwipe) { _, full in full }
            .onChange(of: openRow) { _, row in
                // En annan rad öppnades, eller hemskärmen scrollades.
                if row != id, !dragging { settle(at: 0) }
            }
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            VStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(.system(.title3, weight: .semibold))
                Text("Ta bort")
                    .font(.ui(15, weight: .heavy, relativeTo: .footnote))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.red, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .frame(width: max(0, -offset - SwipeReveal.gap))
        .opacity(offset < 0 ? 1 : 0)
        // VoiceOver når borttagningen med en åtgärd på raden. Knappen läses bara när raden står öppen.
        .accessibilityHidden(offset >= 0)
        .accessibilityIdentifier("svep-ta-bort")
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
        switch SwipeReveal.outcome(offset: offset, velocity: velocity, width: width) {
        case .delete:
            // Raden står öppen medan bekräftelsen visas, och glider tillbaka vid Avbryt.
            openRow = id
            settle(at: -SwipeReveal.openWidth)
            onDelete()
        case .open:
            openRow = id
            settle(at: -SwipeReveal.openWidth)
        case .closed:
            if openRow == id { openRow = nil }
            settle(at: 0)
        }
    }

    private func settle(at target: CGFloat) {
        withAnimation(SwipeReveal.settle(reduceMotion: reduceMotion)) { offset = target }
    }
}

/// Panoreringen bakom svepet. En UIKit-gest, eftersom den måste kunna avstå innan scrollvyn tar över: den börjar bara
/// när rörelsen är tydligt vågrät, och scrollvyn väntar till dess. Annars får scrollvyn rörelsen direkt.
private struct SwipePan: UIGestureRecognizerRepresentable {
    let isOpen: Bool
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat) -> Void

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
            onEnd(0)
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
