import Foundation
import NotchShared

/// The newest Orby release on GitHub, and whether it's newer than the running build.
public struct ReleaseInfo: Equatable, Sendable {
    public var version: String
    public var page: URL

    /// GitHub's `releases/latest` response; drafts and pre-releases never come back from that endpoint.
    public static func parse(_ v: JSONValue) -> ReleaseInfo? {
        guard let tag = v["tag_name"]?.string, let page = v["html_url"]?.string.flatMap(URL.init(string:)),
            parts(tag) != nil
        else { return nil }
        return ReleaseInfo(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, page: page)
    }

    public func isNewer(than current: String) -> Bool {
        guard let mine = Self.parts(current), let theirs = Self.parts(version) else { return false }
        return mine.lexicographicallyPrecedes(theirs)
    }

    /// "v1.2.3" / "1.2" → [1, 2, 3] / [1, 2, 0]; nil for anything else (e.g. "dev").
    static func parts(_ s: String) -> [Int]? {
        let core = (s.hasPrefix("v") ? s.dropFirst() : Substring(s)).split(separator: "-").first ?? ""
        let nums = core.split(separator: ".").map { Int($0) }
        guard (1...3).contains(nums.count), nums.allSatisfy({ $0 != nil }) else { return nil }
        return (nums.compactMap { $0 } + [0, 0]).prefix(3).map { $0 }
    }
}
