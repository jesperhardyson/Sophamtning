import SwiftUI

/// Kärlets delar, översatta från SVG:n i Sopors `index.html` (viewBox `60 -110 360 560`). Banorna är kopierade
/// ordagrant och ritas som `Path`, med färgerna från SVG:n. De är desamma i ljust och mörkt läge.
enum BinArtwork {
    /// SVG:ns viewBox. Koordinater i delarna är i SVG:ns enheter och flyttas till vyns eget origo vid ritning.
    static let viewBox = CGRect(x: 60, y: -110, width: 360, height: 560)
    /// Gångjärnet (`.lock { transform-origin: 358px 95px }`) och kroppens vridpunkt (`.kropp { transform-origin: 240px 430px }`).
    static let hinge = CGPoint(x: 358, y: 95)
    static let bodyPivot = CGPoint(x: 240, y: 430)
    /// Markskuggans ellips (`<ellipse cx="240" cy="428" rx="115" ry="13">`), som följer temats `surface-2`.
    static let shadow = CGRect(x: 240 - 115, y: 428 - 13, width: 230, height: 26)

    /// Flyttar en punkt i SVG:ns koordinater till vyns koordinater, där viewBox börjar i (0, 0).
    static func local(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - viewBox.minX, y: point.y - viewBox.minY)
    }

    struct Part {
        let color: Color
        let path: Path

        /// En bana med `transform="translate(x y)"` och fyllnadsfärg.
        init(color: UInt32, x: Double, y: Double, d: String) {
            self.color = Color(hex: color)
            path = SVGPathParser.parse(d).applying(CGAffineTransform(translationX: x, y: y))
        }

        /// Ellipsen för hjulnavet, `transform="rotate(5.6 cx cy)"`.
        init(color: UInt32, ellipse e: (cx: Double, cy: Double, rx: Double, ry: Double, rotation: Double)) {
            self.color = Color(hex: color)
            let rect = CGRect(x: e.cx - e.rx, y: e.cy - e.ry, width: e.rx * 2, height: e.ry * 2)
            let turn = CGAffineTransform(translationX: e.cx, y: e.cy)
                .rotated(by: e.rotation * .pi / 180)
                .translatedBy(x: -e.cx, y: -e.cy)
            path = Path(ellipseIn: rect).applying(turn)
        }
    }

    /// Locket, i SVG:ns ordning (`<g id="karl-lock">`).
    static let lidParts: [Part] = [
        Part(color: 0x179E61, x: 115.98, y: 89.53, d: "M0 16.44l0 13.02c0 4.2 5.88 6.36 11.58 6.78l136.38001 9.47999c10.85998 0.66 21.23999-0.06 27.66-2.22l63.78-23.7c2.10001-0.84 3.11999-1.8 3.11999-3.72l0-16.07999-242.52 16.44z"),
        Part(color: 0x129258, x: 115.98, y: 61.27, d: "M11.22157 37.62c-6.36 1.74-11.04 3.84-11.22 6.72-0.12 2.88001 6.66 4.44 12.95999 4.92l134.27999 7.74c11.28003 0.72 22.08001-0.18001 29.70001-2.76l61.86001-22.26c3.54001-1.43999 4.56-4.25999 2.70002-5.94l-14.52002-11.4-9.60001-9.84c-1.67999-0.84-4.37997-1.14001-7.44-1.32l-14.81998-0.84-120.48001-2.64c-19.44 7.62-43.79999 19.98-55.68001 27.3-4.13998 2.93999-6.11999 7.25999-7.73999 10.32z"),
        Part(color: 0x0D7948, x: 125.62, y: 66.43, d: "M207.7431 0l-54.6 31.26c-4.55997 2.34-9.9 2.88-16.13999 2.58l-129.65999-6.78c-3.78 2.94-6.48 6.53999-7.26 9.54-0.66 2.22 2.7 3.48001 6.9 3.78l129.23999 8.1c10.98001 0.72 21.18003 0 28.62-2.34l57.36001-20.45999c1.56-0.72 1.97999-2.04 1.62-3.72-2.28-8.94-8.70001-18.78-16.08002-21.96001z"),
        Part(color: 0x128351, x: 343.02, y: 75.91, d: "M0 0l12.95999 0.54c5.34 0.3 8.04001 5.82 8.04001 13.8 0 7.38001-3 12.78-5.88003 13.56l0-13.14001c-0.23999-2.09999-1.73999-2.75999-4.38001-2.57999l-4.13998 0.36c-0.95999-4.62-3.66-9.18-6.59998-12.54z"),
        Part(color: 0x0D643D, x: 349.38, y: 76.62, d: "M7.56 0.00732c-4.62-0.24-7.20001 5.46-7.56 10.8l3.95999-0.12c2.76001-1.02 5.34 0.66 5.4 3.48001l0 12.47999c3.29999-1.02001 5.28003-6.78 5.28003-13.02 0-7.8-2.88004-13.37999-7.08002-13.62z"),
        Part(color: 0x128D57, x: 190.5, y: 40.69, d: "M11.34 0.00061c-7.61999-0.06-11.34 4.32-11.34 10.38l0 11.34c5.03999 1.5 15.06 2.34 16.44-0.3l0-6.84c0-1.74 1.13998-2.4 2.93999-2.34001l80.82002 3.72001c2.33997 0.18 3.53998 1.32 3.71997 3.24l0.78003 7.74c6.41999 1.02 15.35999 1.56 16.25998-1.26l-1.38-11.52c-0.78-6.72-5.51999-10.08-12.29999-10.38l-95.94-3.78z"),
        Part(color: 0x0D683F, x: 190.5, y: 45.9, d: "M0 7.15043l0 9.18c4.98 1.86 14.87999 2.4 16.25998 0.06l0-7.26c0-2.04 1.26002-2.64 3.90002-2.52l79.73999 3.78c2.58002 0.18 3.66001 1.38 3.9 3.42l0.78 7.8c7.02002 1.38001 15.72 1.68 16.02002-1.2l-0.78-6.96c-4.44001 0.96-10.62-0.18-14.16001-3.66-2.28-3.06-6.12002-3.96-10.13998-4.14l-43.50002-2.1c-17.34001-5.04-34.2-4.38-39.66-0.12-3.72002 5.04-9 5.34-12.36 3.72z"),
    ]

    /// Kroppen, hjulen och kanten, i SVG:ns ordning. Fraktionen ritas mellan lockets bakre läge och dessa.
    static let bodyParts: [Part] = [
        Part(color: 0x4A4F54, x: 138.36, y: 336.43, d: "M17.09999 0c-9.84 4.01999-17.09999 25.61999-17.09999 45.47998 0 22.50003 7.25999 33.84003 16.73999 35.39999 3.84 0.72003 8.10001 0.78003 10.31999 0.54004l-6.11998-81.42001-3.84001 0z"),
        Part(color: 0x31373B, x: 152.7, y: 354.31, d: "M4.86 0c-3.23999 7.91998-4.86 19.97998-4.86 30.54001 0 19.07999 5.87999 30.95996 12.17999 32.64001l-7.31999-63.18002z"),
        Part(color: 0x179E61, x: 134.64, y: 110.53, d: "M2.52 37.86l26.64 266.28001c0.71999 6.35999 5.27998 10.56 10.98 11.76001 26.04001 5.64002 70.13998 11.87995 88.20001 12.83997 5.27997 0.30005 9.95999-0.83997 13.62-3.23999l31.07998-21.29999 20.45999-74.52 20.46003-229.68001-57.96003 22.14-155.99998-6.65999 2.52 22.37999z"),
        Part(color: 0x0E824C, x: 269.16, y: 110.53, d: "M22.86002 23.16l-20.46003 299.28c-0.12 2.52002-1.07999 4.44-2.39999 5.52002 2.75998-0.36004 5.45999-1.20001 7.44-2.46002l31.07999-21.29999 20.45999-74.52 20.46002-229.68001-56.57998 23.16z"),
        Part(color: 0x4A4F54, x: 302.64, y: 339.78, d: "M23.39999 0.00714c-12.78-0.42001-23.39999 24.96002-23.39999 49.5 0 22.14001 6.72 32.64001 16.07999 34.56003 4.20001 0.89999 9.54001 1.14001 12.90002 0.83996 12-0.89999 21.72-25.01996 21.72-49.67999 0-19.32001-5.81998-30.95999-13.31997-33.65997-4.26004-1.32001-9.54001-1.62003-13.98005-1.56003z"),
        Part(color: 0x31373B, x: 317.76, y: 341.65, d: "M19.74002 0c-10.62 1.73999-19.74002 25.38001-19.74002 49.13998 0 20.46002 6 32.51999 13.56003 33.72 12.59998-0.11999 22.01999-25.20001 22.01999-49.49999 0-20.57999-6.78-33.17999-15.84-33.35999z"),
        Part(color: 0x62686C, ellipse: (cx: 338.33, cy: 382.16, rx: 9.49, ry: 25.08, rotation: 5.6)),
        Part(color: 0x107243, x: 129.06, y: 108.49, d: "M0 17.52l7.67999 22.14c1.2 3.23999 7.5 3.48 8.04001 0.41999l2.34-13.37999 122.63998 8.22 4.68002 14.64c0.96 2.82001 7.91999 2.64 8.51999-0.06l4.68-16.56 43.14001-15.72 0.9 14.81999c0.30001 3.3 6.30001 2.58 6.89999-1.01999l4.20001-23.16 5.75998-4.62 0.42001-3.24-60.05999 24.84-25.68003 1.91999-134.15997-9.23999z"),
        Part(color: 0x0D5E39, x: 291.78, y: 120.49, d: "M0.06 12.42l-0.06 7.92 38.82001-15.48 0.05999-4.86-38.82 12.42z"),
        Part(color: 0x0D5E39, x: 341.46, y: 112.09, d: "M0.36002 3.42001l-0.36002 7.44001 5.88-4.44001 1.01999-6.42001-6.53997 3.42001z"),
    ]
}

extension Color {
    /// En fast färg (sRGB) från ett hexvärde, utan hänsyn till ljust eller mörkt läge.
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

/// Tolkar SVG:ns banor (`d="…"`) till `Path`. Stöder M, L, H, V, C, S och Z, med gemener för relativa värden,
/// vilket är allt kärlets banor använder. Okända kommandon ger en tom bana, så att testerna fångar dem.
enum SVGPathParser {
    static func parse(_ d: String) -> Path {
        var scanner = Scanner(d)
        var path = Path()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?
        var command: Character = "M"
        var first = true

        func point(_ relative: Bool, _ x: Double, _ y: Double) -> CGPoint {
            relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while true {
            scanner.skipSeparators()
            if scanner.atEnd { break }
            if let letter = scanner.peekCommand() {
                command = letter
                scanner.advance()
                if letter == "z" || letter == "Z" {
                    path.closeSubpath()
                    current = start
                    lastControl = nil
                    continue
                }
            } else if first {
                return Path()
            }
            first = false
            let relative = command.isLowercase
            switch command {
            case "M", "m":
                guard let x = scanner.number(), let y = scanner.number() else { return Path() }
                current = point(relative, x, y)
                start = current
                path.move(to: current)
                lastControl = nil
                // Fler talpar efter M är implicita L.
                command = relative ? "l" : "L"
            case "L", "l":
                guard let x = scanner.number(), let y = scanner.number() else { return Path() }
                current = point(relative, x, y)
                path.addLine(to: current)
                lastControl = nil
            case "H", "h":
                guard let x = scanner.number() else { return Path() }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                lastControl = nil
            case "V", "v":
                guard let y = scanner.number() else { return Path() }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                lastControl = nil
            case "C", "c":
                guard let a = scanner.number(), let b = scanner.number(), let c = scanner.number(),
                      let e = scanner.number(), let f = scanner.number(), let g = scanner.number() else { return Path() }
                let c1 = point(relative, a, b), c2 = point(relative, c, e), end = point(relative, f, g)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
                lastControl = c2
            case "S", "s":
                guard let c = scanner.number(), let e = scanner.number(), let f = scanner.number(), let g = scanner.number() else { return Path() }
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let c2 = point(relative, c, e), end = point(relative, f, g)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
                lastControl = c2
            default:
                return Path()
            }
        }
        return path
    }

    /// Läser tecken för tecken: kommandobokstäver och tal som `.5`, `-.5`, `1-.5` och `1.5.3`.
    private struct Scanner {
        private let chars: [Character]
        private var index = 0

        init(_ string: String) { chars = Array(string) }

        var atEnd: Bool { index >= chars.count }

        mutating func skipSeparators() {
            while index < chars.count, chars[index] == " " || chars[index] == "," || chars[index] == "\n" || chars[index] == "\t" { index += 1 }
        }

        func peekCommand() -> Character? {
            guard index < chars.count, chars[index].isLetter else { return nil }
            return chars[index]
        }

        mutating func advance() { index += 1 }

        mutating func number() -> Double? {
            skipSeparators()
            let begin = index
            if index < chars.count, chars[index] == "-" || chars[index] == "+" { index += 1 }
            var sawDot = false
            var sawDigit = false
            while index < chars.count {
                let c = chars[index]
                if c.isASCII, c.isNumber { sawDigit = true; index += 1 }
                else if c == ".", !sawDot { sawDot = true; index += 1 }
                else { break }
            }
            guard sawDigit else { index = begin; return nil }
            return Double(String(chars[begin..<index]))
        }
    }
}
