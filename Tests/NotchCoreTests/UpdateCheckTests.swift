import Foundation
import Testing

@testable import NotchCore
@testable import NotchShared

@Suite struct UpdateCheckTests {
    @Test func parsesGitHubLatestRelease() throws {
        let json = #"{"tag_name": "v0.2.0", "html_url": "https://github.com/ALIFKHIJANAH/orby/releases/tag/v0.2.0", "draft": false}"#
        let r = try #require(ReleaseInfo.parse(try JSONValue.decode(Data(json.utf8))))
        #expect(r.version == "0.2.0")
        #expect(r.page.absoluteString.hasSuffix("/v0.2.0"))
    }

    @Test func rejectsTagsThatAreNotVersions() throws {
        let json = #"{"tag_name": "nightly", "html_url": "https://example.com"}"#
        #expect(ReleaseInfo.parse(try JSONValue.decode(Data(json.utf8))) == nil)
    }

    @Test func comparesVersionsNumerically() {
        let r = { (v: String) in ReleaseInfo(version: v, page: URL(string: "https://example.com")!) }
        #expect(r("0.1.10").isNewer(than: "0.1.9"))
        #expect(r("0.2").isNewer(than: "0.1.2"))
        #expect(r("1.0.0").isNewer(than: "0.9.9"))
        #expect(!r("0.1.2").isNewer(than: "0.1.2"))
        #expect(!r("0.1.2").isNewer(than: "v0.1.2"))
        #expect(!r("0.1.1").isNewer(than: "0.1.2"))
        #expect(!r("0.2.0").isNewer(than: "dev"))
    }
}
