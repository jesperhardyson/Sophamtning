/// Vad det betyder att uppkopplingen för signaler stängdes.
public enum RelayClose {
    /// Om servern stängde för att jag inte längre är med, eller för att hushållet har avslutats. Då hämtar appen direkt, och
    /// serverns svar avgör. När nätet försvinner räcker det att koppla upp igen.
    /// - Parameters:
    ///   - closeCode: varför uppkopplingen stängdes. 4403 är borttagen och 4410 avslutat.
    ///   - status: svaret när uppkopplingen öppnades, eller `nil` utan svar.
    public static func mayHaveLostHousehold(closeCode: Int, status: Int?) -> Bool {
        closeCode == 4403 || closeCode == 4410 || status == 403 || status == 410
    }
}
