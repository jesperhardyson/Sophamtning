import Foundation

extension String {
    /// `nil` när texten är tom.
    var nilIfEmpty: String? { isEmpty ? nil : self }

    /// Texten utan mellanslag och radbrytningar runt omkring, eller `nil` när inget återstår. Källans texter visas så.
    var trimmedNonEmpty: String? { trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
}
