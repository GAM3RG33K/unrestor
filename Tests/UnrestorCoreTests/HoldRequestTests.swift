import Foundation
import Testing
@testable import UnrestorCore

private func tempStore() -> HoldRequestStore {
    HoldRequestStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("unrestor-tests-\(UUID().uuidString)", isDirectory: true))
}

@Test func idsAreFilenameSafe() {
    #expect(HoldRequest.isValidID("run-123.abc_X"))
    for bad in ["", ".hidden", "../x", "a/b", "a b", String(repeating: "a", count: 65)] {
        #expect(!HoldRequest.isValidID(bad), "\(bad)")
    }
}

@Test func writeListRemoveRoundTrips() throws {
    let store = tempStore()
    let request = HoldRequest(id: "one", label: "build", pid: 42,
                              createdAt: Date(timeIntervalSince1970: 1_000))
    try store.write(request)
    #expect(store.list() == [request])
    store.remove(id: "one")
    #expect(store.list().isEmpty)
}

@Test func refusesUnsafeIDs() {
    #expect(throws: HoldRequestStore.StoreError.invalidID("../evil")) {
        try tempStore().write(HoldRequest(id: "../evil", label: "x"))
    }
}

@Test func skipsCorruptAndMismatchedFiles() throws {
    let store = tempStore()
    try store.write(HoldRequest(id: "good", label: "ok"))
    try Data("{nope".utf8).write(to: store.directory.appendingPathComponent("bad.json"))
    let renamed = store.directory.appendingPathComponent("other.json")
    try FileManager.default.copyItem(
        at: store.directory.appendingPathComponent("good.json"), to: renamed)
    #expect(store.list().map(\.id) == ["good"])
}

@Test func activeRequestsDropExpiredAndDeadProcesses() throws {
    let store = tempStore()
    let now = Date(timeIntervalSince1970: 10_000)
    try store.write(HoldRequest(id: "live", label: "a", pid: 1))
    try store.write(HoldRequest(id: "dead", label: "b", pid: 2))
    try store.write(HoldRequest(id: "expired", label: "c", expiresAt: now))
    try store.write(HoldRequest(id: "manual", label: "d", expiresAt: now.addingTimeInterval(60)))
    let active = store.activeRequests(now: now, isProcessAlive: { $0 == 1 })
    #expect(Set(active.map(\.id)) == ["live", "manual"])
    #expect(Set(store.list().map(\.id)) == ["live", "manual"])   // finished ones deleted
}

@Test func currentProcessIsAliveAndImpossiblePidIsNot() {
    #expect(ProcessLiveness.isAlive(getpid()))
    #expect(!ProcessLiveness.isAlive(0))
    #expect(!ProcessLiveness.isAlive(-5))
}
