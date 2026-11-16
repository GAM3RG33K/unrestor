import Foundation
import Testing
@testable import UnrestorCore

@Test func settingsRoundTripAndFallBackToDefaults() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("unrestor-settings-\(UUID().uuidString)/settings.json")
    let store = SettingsStore(url: url)
    #expect(store.load() == Settings())             // missing file
    var settings = Settings()
    settings.batteryFloor = 35
    settings.onlyWhileConnectedToPower = true
    store.save(settings)
    #expect(store.load() == settings)
    try Data("not json".utf8).write(to: url)
    #expect(store.load() == Settings())             // corrupt file
}
