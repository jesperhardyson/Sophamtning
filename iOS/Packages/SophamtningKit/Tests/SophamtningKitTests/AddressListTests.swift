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
