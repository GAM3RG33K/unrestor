import Foundation

public enum LaunchDaemonPlist {
    /// The launchd job the installer writes. Root-owned, so the allowed user id
    /// and the program path cannot be changed without root.
    public static func render(daemonPath: String, allowedUID: UInt32) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(DaemonProtocol.label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(xmlEscape(daemonPath))</string>
                <string>--allowed-uid</string>
                <string>\(allowedUID)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
        </dict>
        </plist>

        """
    }

    static func xmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
