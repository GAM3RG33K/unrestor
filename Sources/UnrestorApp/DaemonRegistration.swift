import Foundation
import ServiceManagement
import UnrestorDaemonCore

enum DaemonRegistrationFailure: LocalizedError {
    case ineligibleLocation
    case missingBundleIdentifier
    case invalidSigningIdentity(String)

    var errorDescription: String? {
        switch self {
        case .ineligibleLocation:
            "Move Unrestor.app to /Applications, then open it again."
        case .missingBundleIdentifier:
            "The app bundle identifier is missing."
        case .invalidSigningIdentity(let message):
            "Unrestor's signature could not be verified: \(message)"
        }
    }
}

/// The only place that constructs an `SMAppService`. Do not add a status query:
/// Background Task Management treats even a read as contact from this app copy
/// and can repoint its persistent record away from the installed app.
enum DaemonRegistration {
    static func register() throws {
        try service().register()
    }

    /// Replaces a daemon left over from an older build.
    static func refresh() async throws {
        let service = try service()
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            service.unregister { error in
                if let error, (error as NSError).code != Int(kSMErrorJobNotFound) {
                    c.resume(throwing: error)
                } else {
                    c.resume()
                }
            }
        }
        try service.register()
    }

    static func isApprovalNeeded(_ error: Error) -> Bool {
        (error as NSError).code == Int(kSMErrorLaunchDeniedByUser)
    }

    @MainActor
    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func service() throws -> SMAppService {
        let identity: RuntimeSigningIdentity
        do {
            identity = try RuntimeSigningIdentity.validatedCurrent()
        } catch {
            throw DaemonRegistrationFailure.invalidSigningIdentity(error.localizedDescription)
        }
        let bundleIdentifier = Bundle.main.bundleIdentifier
        guard BackgroundServiceEligibility.mayManageBackgroundServices(
            bundleURL: Bundle.main.bundleURL,
            bundleIdentifier: bundleIdentifier,
            signingIdentity: identity
        ) else {
            throw DaemonRegistrationFailure.ineligibleLocation
        }
        guard let bundleIdentifier else { throw DaemonRegistrationFailure.missingBundleIdentifier }
        // The matching plist is embedded at Contents/Library/LaunchDaemons.
        return SMAppService.daemon(plistName: bundleIdentifier + ".daemon.plist")
    }
}
