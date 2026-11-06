import Foundation
import Testing
@testable import SophamtningKit

@Suite struct WebLinkTests {
    @Test func httpsGodkanns() throws {
        let url = try #require(URL(string: "https://sopor.hardyson.se/bidra"))
        let link = try #require(WebLink(url: url))
        #expect(link.url == url)
        #expect(link.id == url.absoluteString)
    }

    @Test func versalerIScheman() throws {
        let url = try #require(URL(string: "HTTPS://sopor.hardyson.se/bidra"))
        #expect(WebLink(url: url) != nil)
    }

    @Test(arguments: [
        "http://sopor.hardyson.se/bidra",
        "mailto:hej@example.se",
        "file:///etc/hosts",
        "javascript:alert(1)",
        "tel:+46701234567",
        "sophamtning://hem",
    ])
    func andraSchemanGerNil(_ text: String) throws {
        let url = try #require(URL(string: text))
        #expect(WebLink(url: url) == nil)
    }

    @Test func relativAdressGerNil() throws {
        let url = try #require(URL(string: "/bidra"))
        #expect(WebLink(url: url) == nil)
    }
}
