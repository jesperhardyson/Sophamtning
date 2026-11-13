import SophamtningDesign
import SwiftUI
import WidgetKit

@main
struct SophamtningWidgetBundle: WidgetBundle {
    init() {
        // En gång per process, så att Nunito och Fredoka finns när vyerna ritas.
        Fonts.register()
    }

    var body: some Widget {
        NextPickupWidget()
        PickupLiveActivity()
        PlaceOutControl()
    }
}
