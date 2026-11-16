import Foundation

public enum UnrestorLinks {
    public static let repository = "GAM3RG33K/unrestor"
    public static let latestReleaseAPI =
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    public static let releasesPage = URL(string: "https://github.com/\(repository)/releases")!
}

/// A published release the updater could install.
public struct ReleaseInfo: Equatable, Sendable {
    public let version: AppVersion
    public let dmgURL: URL
    public let checksumURL: URL
    public let dmgSize: Int?
    public let pageURL: URL
}

/// Reads GitHub's "latest release" JSON. Pure: no network.
public enum ReleaseFeed {
    private struct Payload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
            let size: Int?
        }
        let tag_name: String
        let html_url: String
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]
    }

    /// Nil for anything that is not a usable final release: a bad tag, a draft
    /// or pre-release, or a missing DMG or checksum.
    public static func parse(_ data: Data) -> ReleaseInfo? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.draft != true, payload.prerelease != true,
              let version = AppVersion(payload.tag_name),
              let page = URL(string: payload.html_url)
        else { return nil }
        let dmgName = "Unrestor-\(version).dmg"
        guard let dmg = payload.assets.first(where: { $0.name == dmgName }),
              let sum = payload.assets.first(where: { $0.name == dmgName + ".sha256" }),
              let dmgURL = URL(string: dmg.browser_download_url),
              let sumURL = URL(string: sum.browser_download_url),
              UpdateURLPolicy.isAllowed(dmgURL), UpdateURLPolicy.isAllowed(sumURL)
        else { return nil }
        return ReleaseInfo(version: version, dmgURL: dmgURL, checksumURL: sumURL,
                           dmgSize: dmg.size, pageURL: page)
    }

    /// "<64 hex>  filename" or a bare hash, as `shasum` prints it.
    public static func parseChecksum(_ text: String) -> String? {
        guard let first = text.split(whereSeparator: \.isWhitespace).first else { return nil }
        let hash = first.lowercased()
        guard hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else { return nil }
        return hash
    }
}

/// Downloads may come only from GitHub, over HTTPS.
public enum UpdateURLPolicy {
    public static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host == "api.github.com"
            || host.hasSuffix(".githubusercontent.com")
    }
}
