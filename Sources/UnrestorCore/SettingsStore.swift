import Foundation

/// Settings shared by the menu-bar app and the command-line tool, kept in one
/// small JSON file in your own Application Support folder.
public struct SettingsStore: Sendable {
    public let url: URL

    public init(url: URL = SettingsStore.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Unrestor", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    /// Missing or unreadable settings fall back to the defaults.
    public func load() -> Settings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    public func save(_ settings: Settings) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(settings) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
