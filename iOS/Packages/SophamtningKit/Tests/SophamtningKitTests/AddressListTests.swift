import Testing
import Foundation
import SophamtningKit

private func address(_ id: String, primary: Bool = false, added: TimeInterval) -> SavedAddress {
    var value = SavedAddress.fixture(key: AddressKey(source: "orebro", id: id), isPrimary: primary)
    value.addedAt = Date(timeIntervalSince1970: added)
    return value
}

@Test func forstaAdressenBlirHuvudadress() {
    let list = AddressList.add(address("a", added: 1), to: [])
    #expect(list.map(\.key.id) == ["a"])
    #expect(list[0].isPrimary)
}

@Test func nastaAdressBlirInteHuvudadress() {
    let list = AddressList.add(address("b", primary: true, added: 2), to: AddressList.add(address("a", added: 1), to: []))
    #expect(list.map(\.key.id) == ["a", "b"])
    #expect(list.map(\.isPrimary) == [true, false])
}

@Test func enAdressSomRedanFinnsLaggsInteTillIgen() {
    let first = AddressList.add(address("a", added: 1), to: [])
    let list = AddressList.add(address("a", added: 5), to: first)
    #expect(list == first)
}

@Test func borttagenHuvudadressGerAldstaKvarvarande() {
    let list = [address("a", primary: true, added: 30), address("b", added: 20), address("c", added: 10)]
    let result = AddressList.remove(list[0].key, from: list)
    #expect(result.map(\.key.id) == ["b", "c"])
    #expect(result.map(\.isPrimary) == [false, true])
}

@Test func borttagningAvEnVanligAdressBehallerHuvudadressen() {
    let list = [address("a", primary: true, added: 30), address("b", added: 20)]
    let result = AddressList.remove(list[1].key, from: list)
    #expect(result.map(\.key.id) == ["a"])
    #expect(result[0].isPrimary)
}

@Test func endastEnHuvudadress() {
    let list = [address("a", primary: true, added: 1), address("b", added: 2), address("c", added: 3)]
    let result = AddressList.setPrimary(list[2].key, in: list)
    #expect(result.map(\.isPrimary) == [false, false, true])
    #expect(result.filter(\.isPrimary).count == 1)
}

@Test func okandNyckelAndrarInteHuvudadressen() {
    let list = [address("a", primary: true, added: 1), address("b", added: 2)]
    #expect(AddressList.setPrimary(AddressKey(source: "x", id: "y"), in: list) == list)
}

@Test func borttagningAvSistaAdressenGerTomLista() {
    let list = [address("a", primary: true, added: 1)]
    #expect(AddressList.remove(list[0].key, from: list).isEmpty)
}

@Test func listaUtanHuvudadressFarAldstaSomHuvudadress() {
    let list = AddressList.add(address("c", added: 3), to: [address("a", added: 2), address("b", added: 1)])
    #expect(list.filter(\.isPrimary).map(\.key.id) == ["b"])
}

@Test func namnetTrimmasOchKravsInteVaraTomt() {
    #expect(AddressList.validName("  Stugan ") == "Stugan")
    #expect(AddressList.validName("") == nil)
    #expect(AddressList.validName("   \n ") == nil)
}

@Test func namnetArHogst60Tecken() {
    #expect(AddressList.validName(String(repeating: "å", count: 60)) != nil)
    #expect(AddressList.validName(String(repeating: "å", count: 61)) == nil)
}

@Test func nyttNamnAndrarBaraDenAdressen() {
    let list = [address("a", primary: true, added: 1), address("b", added: 2)]
    let result = AddressList.rename(list[1].key, to: " Stugan ", in: list)
    #expect(result.map(\.displayName) == [list[0].displayName, "Stugan"])
    #expect(result.map(\.isPrimary) == [true, false])
}

@Test func ogiltigtNamnEllerOkandNyckelAndrarInget() {
    let list = [address("a", primary: true, added: 1)]
    #expect(AddressList.rename(list[0].key, to: "  ", in: list) == list)
    #expect(AddressList.rename(AddressKey(source: "x", id: "y"), to: "Stugan", in: list) == list)
}
