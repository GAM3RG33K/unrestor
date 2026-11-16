import Testing
@testable import UnrestorDaemonCore

private let expectedHash = "00112233445566778899aabbccddeeff00112233"

private func makeExpectedBuild() throws -> UnrestorDaemonBuildIdentity {
    try #require(UnrestorDaemonBuildIdentity(
        marketingVersion: "0.2.0",
        buildVersion: "2",
        codeDirectoryHash: expectedHash
    ))
}

@Test func buildIdentityRequiresCompleteCanonicalValues() throws {
    let expectedBuild = try makeExpectedBuild()
    #expect(UnrestorDaemonBuildIdentity(
        marketingVersion: nil,
        buildVersion: "2",
        codeDirectoryHash: expectedHash
    ) == nil)
    #expect(UnrestorDaemonBuildIdentity(
        marketingVersion: "0.2.0",
        buildVersion: "   ",
        codeDirectoryHash: expectedBuild.codeDirectoryHash
    ) == nil)
    #expect(UnrestorDaemonBuildIdentity(
        marketingVersion: "0.2.0",
        buildVersion: "2",
        codeDirectoryHash: "not-a-hash"
    ) == nil)
    #expect(UnrestorDaemonBuildIdentity(
        marketingVersion: " 0.2.0 ",
        buildVersion: " 2 ",
        codeDirectoryHash: "00112233445566778899AABBCCDDEEFF00112233"
    ) == expectedBuild)
    #expect(expectedBuild.versionDescription == "0.2.0 (2)")
}

@Test func exactProtocolBuildAndReadinessAreCompatible() throws {
    let expectedBuild = try makeExpectedBuild()
    let result = UnrestorDaemonHandshakeCompatibility.evaluate(
        expectedBuild: expectedBuild,
        receivedProtocol: UnrestorDaemonProtocolVersion.current,
        receivedMarketingVersion: expectedBuild.marketingVersion,
        receivedBuildVersion: expectedBuild.buildVersion,
        receivedCodeDirectoryHash: expectedBuild.codeDirectoryHash,
        reconciliationReady: true,
        reconciliationMessage: nil
    )

    #expect(result == .compatible)
}

@Test func sameProtocolAndVersionWithDifferentSignedImageIsStale() throws {
    let expectedBuild = try makeExpectedBuild()
    let received = try #require(UnrestorDaemonBuildIdentity(
        marketingVersion: expectedBuild.marketingVersion,
        buildVersion: expectedBuild.buildVersion,
        codeDirectoryHash: "ffeeddccbbaa99887766554433221100ffeeddcc"
    ))

    let result = UnrestorDaemonHandshakeCompatibility.evaluate(
        expectedBuild: expectedBuild,
        receivedProtocol: UnrestorDaemonProtocolVersion.current,
        receivedMarketingVersion: received.marketingVersion,
        receivedBuildVersion: received.buildVersion,
        receivedCodeDirectoryHash: received.codeDirectoryHash,
        reconciliationReady: true,
        reconciliationMessage: nil
    )

    #expect(result == .staleBuild(expected: expectedBuild, received: received))
}

@Test func missingOrMalformedBuildIdentityIsLegacyOrUnidentified() throws {
    let expectedBuild = try makeExpectedBuild()
    for hash in [nil, "", "xyz"] as [String?] {
        let result = UnrestorDaemonHandshakeCompatibility.evaluate(
            expectedBuild: expectedBuild,
            receivedProtocol: UnrestorDaemonProtocolVersion.current,
            receivedMarketingVersion: expectedBuild.marketingVersion,
            receivedBuildVersion: expectedBuild.buildVersion,
            receivedCodeDirectoryHash: hash,
            reconciliationReady: true,
            reconciliationMessage: nil
        )

        #expect(result == .legacyOrUnidentified(
            receivedProtocol: UnrestorDaemonProtocolVersion.current
        ))
    }
}

@Test func incompatibleProtocolIsReportedSeparately() throws {
    let expectedBuild = try makeExpectedBuild()
    let result = UnrestorDaemonHandshakeCompatibility.evaluate(
        expectedProtocol: 2,
        expectedBuild: expectedBuild,
        receivedProtocol: 1,
        receivedMarketingVersion: expectedBuild.marketingVersion,
        receivedBuildVersion: expectedBuild.buildVersion,
        receivedCodeDirectoryHash: expectedBuild.codeDirectoryHash,
        reconciliationReady: true,
        reconciliationMessage: nil
    )

    #expect(result == .incompatibleProtocol(expected: 2, received: 1))
}

@Test func blockedReconciliationCannotLookCompatibleOrMerelyStale() throws {
    let expectedBuild = try makeExpectedBuild()
    let result = UnrestorDaemonHandshakeCompatibility.evaluate(
        expectedProtocol: 2,
        expectedBuild: expectedBuild,
        receivedProtocol: 1,
        receivedMarketingVersion: nil,
        receivedBuildVersion: nil,
        receivedCodeDirectoryHash: nil,
        reconciliationReady: false,
        reconciliationMessage: " Restore debt remains. "
    )

    #expect(result == .reconciliationBlocked("Restore debt remains."))
}

@Test func blockedReconciliationHasANonemptyFallbackMessage() throws {
    let expectedBuild = try makeExpectedBuild()
    let result = UnrestorDaemonHandshakeCompatibility.evaluate(
        expectedBuild: expectedBuild,
        receivedProtocol: UnrestorDaemonProtocolVersion.current,
        receivedMarketingVersion: expectedBuild.marketingVersion,
        receivedBuildVersion: expectedBuild.buildVersion,
        receivedCodeDirectoryHash: expectedBuild.codeDirectoryHash,
        reconciliationReady: false,
        reconciliationMessage: "  "
    )

    #expect(result == .reconciliationBlocked(
        "The daemon could not reconcile its prior sleep state."
    ))
}

@Test func protocolRemainsVersionOneForTheAdditiveMethods() {
    #expect(UnrestorDaemonProtocolVersion.current == 1)
}
