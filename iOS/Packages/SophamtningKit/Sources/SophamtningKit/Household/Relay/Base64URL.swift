import Foundation

/// base64url utan utfyllnad, som i brevlådans protokoll.
extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    /// `nil` för allt som inte är base64url utan utfyllnad.
    init?(base64URL text: String) {
        guard text.utf8.allSatisfy({ byte in
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "_"): true
            default: false
            }
        }) else { return nil }
        var padded = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        padded += String(repeating: "=", count: (4 - padded.count % 4) % 4)
        self.init(base64Encoded: padded)
    }
}
