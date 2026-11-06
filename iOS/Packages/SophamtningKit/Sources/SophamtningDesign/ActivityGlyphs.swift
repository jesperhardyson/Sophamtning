import SwiftUI

/// Appens märke i en vit ruta, för Live Activityns låsskärm. Bilden är 36 pt i 3x och aldrig större än rutan,
/// eftersom systemet annars kan vägra starta aktiviteten. Märket i full storlek får inte användas där.
public struct ActivityAppIcon: View {
    public init() {}

    public var body: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Color.white)
            .frame(width: 44, height: 44)
            .overlay {
                Image("activity-symbol", bundle: .module)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color(red: 0x15 / 255, green: 0x7A / 255, blue: 0x46 / 255))
                    .frame(width: 36, height: 36)
            }
            .accessibilityHidden(true)
    }
}

/// Soptunnan i Dynamic Island. En vektorbild, ritad i den storlek presentationen ger.
public struct BinGlyph: View {
    let size: CGFloat

    public init(size: CGFloat = 20) {
        self.size = size
    }

    public var body: some View {
        Image("trash-2", bundle: .module)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
