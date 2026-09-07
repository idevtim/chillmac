import Foundation
import Security

/// Authenticates the two ends of the app ↔ helper XPC channel.
///
/// The helper runs as root and writes to the SMC, so an unauthenticated listener lets any
/// process on the machine drive the fans and flip the SoC into test mode. Both sides pin the
/// other to a code signing requirement instead.
enum XPCSecurity {

    /// Signing identifier of the main app, which is the helper's only legitimate client.
    static let appIdentifier = "com.idevtim.ChillMac"
    /// Signing identifier of the privileged helper.
    static let helperIdentifier = "com.idevtim.ChillMac.Helper"

    /// Team the shipped binaries are signed with. Not a secret — it is printed by
    /// `codesign -d` on any copy of the app. This is the floor, not the source of truth:
    /// `ownTeamIdentifier` overrides it whenever the running binary can report its own team,
    /// so re-signing under a different identity does not need a code change. Its job is to
    /// guarantee the daemon always has *something* enforceable, because a helper that cannot
    /// authenticate callers has only two options and both are bad: serve everyone, or serve
    /// no one and take fan control down with it.
    private static let shippedTeamIdentifier = "UA2RJP3TSL"

    /// What this process can enforce against its XPC peer.
    enum Policy {
        /// Peers must satisfy this requirement string.
        case require(String)
        /// Development build: peers are ad-hoc signed and cannot be authenticated at all.
        case cannotVerify
    }

    /// Team identifier this process was signed with. Nil for unsigned or ad-hoc signed
    /// builds, which is what `CODE_SIGN_IDENTITY: "-"` produces for local development.
    static let ownTeamIdentifier: String? = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }

        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }()

    /// Requirement matching `identifier`, signed by the expected team, on a chain anchored
    /// to Apple. Anchoring matters: without it the team OU is just a string that an ad-hoc
    /// signature could claim for itself.
    static func policy(forIdentifier identifier: String) -> Policy {
        #if DEBUG
        // Development builds are ad-hoc signed and have no team, so no requirement can
        // describe them. Installing one here would lock the debug app out of its own helper.
        return .cannotVerify
        #else
        let team = ownTeamIdentifier ?? shippedTeamIdentifier
        let text = "identifier \"\(identifier)\" and anchor apple generic "
            + "and certificate leaf[subject.OU] = \"\(team)\""

        // Both setCodeSigningRequirement and setConnectionCodeSigningRequirement raise an
        // Objective-C exception on a malformed string, and Swift cannot catch those. Parse
        // it here first so a bad requirement degrades instead of crashing the daemon.
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else {
            NSLog("XPCSecurity: refusing to install malformed requirement: %@", text)
            return .cannotVerify
        }
        return .require(text)
        #endif
    }
}
