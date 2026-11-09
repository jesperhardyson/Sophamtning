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
    /// Raden som står öppen. Bara en åt gången.
    @Binding var openRow: AddressKey?
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmingRemoval = false
    @State private var notificationsDenied = false

    /// Valen i snabbmenyn och bland VoiceOver-åtgärderna. En enda källa för båda.
    private typealias Choice = AddressAction

    private var address: SavedAddress? { model.addresses.first { $0.key == key } }

    var body: some View {
        SwipeToDeleteRow(id: key, openRow: $openRow, onDelete: { confirmingRemoval = true }) {
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
            Button("Öppna Inställningar") { openNotificationSettings() }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Du har stängt av notiser för Sophämtning i iOS.")
        }
    }

    /// Valen i ordning, samma som i adressvyn. Live Activity gäller bara huvudadressen.
    private func choices(_ address: SavedAddress) -> [Choice] {
        AddressAction.choices(isPrimary: address.isPrimary)
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
                    Label(HomeContent.reminderTitle, systemImage: "bell.badge")
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

/// En rad som går att svepa åt vänster, som i Påminnelser: en röd kapsel med **Ta bort** kommer fram till höger, och ett
/// fullt svep eller ett tryck på kapseln anropar `onDelete`. Svepet börjar bara efter en tydligt vågrät rörelse, så att
/// scrollning, dra för att uppdatera och tryck på raden fungerar som vanligt.
struct SwipeToDeleteRow<ID: Hashable, Content: View>: View {
    let id: ID
    @Binding var openRow: ID?
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Fingrets förskjutning.
    @State private var offset: CGFloat = 0
    /// Språnget förbi gränsen för fullt svep. Ett eget tillstånd med egen `.offset`, så att nästa rörelse med fingret
    /// inte avbryter fjädern.
    @State private var jumpOffset: CGFloat = 0
    /// Om raden har hoppat förbi gränsen. Ändras i samma fjäder som språnget, så att ikonen och texten följer med.
    @State private var jumped = false
    @State private var start: CGFloat = 0
    @State private var dragging = false
    @State private var width: CGFloat = 0
    /// Ikonens och textens bredd i full storlek.
    @State private var labelWidth: CGFloat = 0

    private var isFullSwipe: Bool { width > 0 && SwipeReveal.isFullSwipe(offset: offset, width: width) }

    /// Den del av förskjutningen som följer fingret, dämpad förbi gränsen för fullt svep.
    private var trackedOffset: CGFloat {
        width > 0 ? SwipeReveal.trackedOffset(offset, width: width) : offset
    }

    /// Ett tryck på raden stänger den öppna raden, den här eller en annan, i stället för att öppna adressen.
    private var tapCloses: Bool {
        SwipeReveal.tapCloses(offset: offset, dragging: dragging, anotherRowOpen: openRow != nil && openRow != id)
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
            .offset(x: trackedOffset)
            .offset(x: jumpOffset)
            .background(alignment: .trailing) { deleteButton }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            .gesture(SwipePan(isOpen: offset < 0, onChange: { changed($0) }, onEnd: { ended($0) }, onCancel: { cancelled() }))
            // En lätt vibration när gränsen passeras, åt båda hållen, men bara medan fingret drar.
            .sensoryFeedback(.impact(weight: .light), trigger: isFullSwipe) { _, _ in dragging }
            .onChange(of: openRow) { _, row in
                // En annan rad öppnades, eller hemskärmen scrollades.
                if row != id, !dragging { settle(at: 0) }
            }
            .anchorPreference(key: SwipeRowBounds.self, value: .bounds) { [$0] }
    }

    /// Kapseln som i Påminnelser. Den är en egen vy som animerar språnget för sig, så att fingret inte avbryter fjädern.
    private var deleteButton: some View {
        SwipeDeleteCapsule(
            trackedOffset: trackedOffset,
            jump: jumpOffset,
            width: width,
            content: jumped ? .leading : .center,
            progress: SwipeReveal.revealProgress(offset: offset),
            isShown: offset < 0,
            reduceMotion: reduceMotion,
            labelWidth: $labelWidth,
            onDelete: { onDelete() }
        )
    }

    private func changed(_ translation: CGFloat) {
        if !dragging {
            dragging = true
            start = offset
            openRow = id
        }
        offset = SwipeReveal.offset(start: start, translation: translation, width: width)
        if isFullSwipe != jumped {
            // Språnget till full bredd och tillbaka fjädrar för sig. Fingret följs utan animation.
            let full = isFullSwipe
            withAnimation(SwipeReveal.jump(reduceMotion: reduceMotion)) {
                jumped = full
                jumpOffset = SwipeReveal.jumpOffset(isFullSwipe: full, width: width)
            }
        }
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

    /// Ett avbrutet svep tar aldrig bort och bekräftar aldrig. Raden stängs bara.
    private func cancelled() {
        dragging = false
        if openRow == id { openRow = nil }
        settle(at: 0)
    }

    private func settle(at target: CGFloat) {
        withAnimation(SwipeReveal.settle(reduceMotion: reduceMotion)) {
            offset = target
            jumpOffset = 0
            jumped = false
        }
    }
}

/// Kapseln som i Påminnelser: 34 pt hög, mitt för raden, med papperskorgen och texten bredvid varandra i systemets
/// typsnitt. Den fyller ytan bredvid raden. Ikonen och texten står i mitten, och vid kanten mot raden förbi gränsen för
/// fullt svep. Den tonas och skalas in med svepet, och med Reducera rörelse tonas den bara in.
///
/// Bredden räknas av `trackedOffset + jump`. Bara `jump` animeras, så att en ny rörelse med fingret, som ändrar
/// `trackedOffset` utan animation, inte avbryter språngets fjäder.
// `@preconcurrency`: SwiftUI läser `animatableData` på huvudtråden, som vyn i övrigt.
private struct SwipeDeleteCapsule: View, @preconcurrency Animatable {
    let trackedOffset: CGFloat
    var jump: CGFloat
    let width: CGFloat
    let content: SwipeReveal.ContentPosition
    let progress: CGFloat
    let isShown: Bool
    let reduceMotion: Bool
    @Binding var labelWidth: CGFloat
    let onDelete: () -> Void

    var animatableData: CGFloat {
        get { jump }
        set { jump = newValue }
    }

    var body: some View {
        let layout = SwipeReveal.buttonLayout(offset: trackedOffset + jump, width: width)
        Button(action: { onDelete() }) {
            HStack(spacing: 6) {
                Image(systemName: "trash.fill")
                    .accessibilityHidden(true)
                Text("Ta bort")
            }
            .font(.footnote)
            // Växer inte längre än till andra tillgänglighetsstorleken. Med stor text krymps ikonen och texten
            // tillsammans, så att de ryms i kapseln utan att kapas.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { labelWidth = $0 }
            .scaleEffect(SwipeReveal.labelScale(width: labelWidth))
            .frame(width: min(labelWidth, SwipeReveal.labelMaxWidth))
            .foregroundStyle(.white)
            .padding(.horizontal, SwipeReveal.contentPadding)
            .frame(width: layout.width, height: SwipeReveal.buttonHeight, alignment: content == .leading ? .leading : .center)
            .background(Color.Theme.destructive, in: Capsule())
            // Tryckytan är hela den synliga kapseln, och minst 44 pt hög.
            .frame(height: SwipeReveal.tapHeight)
            .contentShape(Rectangle())
        }
        .scaleEffect(reduceMotion ? 1 : progress)
        .opacity(isShown ? progress : 0)
        .frame(maxHeight: .infinity)
        // VoiceOver når borttagningen med en åtgärd på raden. Knappen läses bara när raden står öppen.
        .accessibilityHidden(!isShown)
        .accessibilityIdentifier("svep-ta-bort")
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
