import Foundation
import Testing
@testable import UnrestorDaemonCore

@Test func onlyDirectApplicationsChildrenMayManageBackgroundServices() {
    #expect(BackgroundServiceEligibility.mayManageBackgroundServices(
        bundleURL: URL(fileURLWithPath: "/Applications/Unrestor.app"),
        bundleIdentifier: "app.unrestor"
    ))
    #expect(BackgroundServiceEligibility.mayManageBackgroundServices(
        bundleURL: URL(fileURLWithPath: "/Applications/Unrestor Dev.app"),
        bundleIdentifier: "app.unrestor.dev"
    ))
    #expect(!BackgroundServiceEligibility.mayManageBackgroundServices(
        bundleURL: URL(fileURLWithPath: "/tmp/Unrestor.app"),
        bundleIdentifier: "app.unrestor"
    ))
    #expect(!BackgroundServiceEligibility.mayManageBackgroundServices(
        bundleURL: URL(fileURLWithPath: "/Applications/Tools/Unrestor.app"),
        bundleIdentifier: "app.unrestor"
    ))
}

@Test func lookalikeIdentifiersAndNonAppBundlesAreRejected() {
    #expect(!BackgroundServiceEligibility.mayManageBackgroundServices(
        bundleURL: URL(fileURLWithPath: "/Applications/Unrestor.app"),
        bundleIdentifier: "app.unrestor.evil"
    ))
    #expect(!BackgroundServiceEligibility.mayManageBackgroundServices(
        bundleURL: URL(fileURLWithPath: "/Applications/Unrestor"),
        bundleIdentifier: "app.unrestor"
    ))
}

@Test func serviceManagementRequiresTheLiveExpectedSigningIdentity() {
    let productionURL = URL(fileURLWithPath: "/Applications/Unrestor.app")
    let production = RuntimeSigningIdentity(
        identifier: "app.unrestor",
        teamIdentifier: BackgroundServiceEligibility.expectedTeamIdentifier
    )
    #expect(BackgroundServiceEligibility.mayManageBackgroundServices(
        bundleURL: productionURL,
        bundleIdentifier: production.identifier,
        signingIdentity: production
    ))

    for identity in [
        RuntimeSigningIdentity(
            identifier: "app.unrestor.dev",
            teamIdentifier: BackgroundServiceEligibility.expectedTeamIdentifier
        ),
        RuntimeSigningIdentity(
            identifier: "app.unrestor",
            teamIdentifier: "ATTACKERTEAM"
        ),
    ] {
        #expect(!BackgroundServiceEligibility.mayManageBackgroundServices(
            bundleURL: productionURL,
            bundleIdentifier: "app.unrestor",
            signingIdentity: identity
        ))
    }
}
