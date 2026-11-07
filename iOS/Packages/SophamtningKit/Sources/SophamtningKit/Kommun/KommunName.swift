/// "Avesta kommun" blir "Avesta". Namn utan ordet "kommun" lämnas som de är.
/// Samma korta namn i sökningen och på adresskorten.
public func shortKommunName(_ name: String) -> String {
    name.hasSuffix(" kommun") ? String(name.dropLast(" kommun".count)) : name
}
