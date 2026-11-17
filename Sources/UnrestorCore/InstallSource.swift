import Foundation

/// How this copy of Unrestor was installed. Homebrew keeps its own record of the
/// installed version, so a Homebrew install is updated through Homebrew, not by
/// replacing the app behind its back.
public enum InstallSource: Equatable, Sendable {
    case homebrew(brewPath: String)
    case direct

    /// Homebrew's two standard prefixes: Apple silicon and Intel.
    static let prefixes = ["/opt/homebrew", "/usr/local"]

    /// A Homebrew install has a Caskroom folder for the cask and a `brew`
    /// program beside it. Both are checked so a leftover folder alone does not count.
    public static func detect(fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> InstallSource {
        for prefix in prefixes
        where fileExists("\(prefix)/Caskroom/unrestor") && fileExists("\(prefix)/bin/brew") {
            return .homebrew(brewPath: "\(prefix)/bin/brew")
        }
        return .direct
    }
}

/// The script Terminal runs to update a Homebrew install. Fixed text: the brew
/// path and version are passed as arguments, never spliced into the script, and
/// nothing in it comes from the network.
///   $1 path to brew   $2 version being installed (digits and dots only)
public enum BrewUpdateScript {
    public static let cask = "GAM3RG33K/tap/unrestor"

    public static let text = """
    #!/bin/sh
    brew="$1"; version="$2"
    trap 'rm -f "$0"' EXIT
    bin="$(dirname "$brew")"

    echo "Updating Unrestor to $version with Homebrew."
    echo
    if "$brew" update && "$brew" upgrade --cask \(cask); then
        echo
        echo "Restarting the background service. It asks for your password."
        echo
        if sudo "$bin/unrestor" install; then
            echo
            echo "Done. Unrestor $version is ready."
            printf 'Press Return to close this window. '
            read -r _
            exit 0
        fi
    fi
    echo
    echo "Something went wrong. You can try again with:"
    echo "  brew update && brew upgrade --cask \(cask) && sudo unrestor install"
    printf 'Press Return to close this window. '
    read -r _
    exit 1
    """
}
