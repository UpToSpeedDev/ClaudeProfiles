import AppKit
import Foundation

enum ClaudeAppLocator {
    static let bundleID = "com.anthropic.claudefordesktop"
    static let downloadURL = URL(string: "https://claude.ai/download")!

    /// Returns the URL of Claude.app if installed.
    static func locate() -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url
        }
        let fallback = URL(fileURLWithPath: "/Applications/Claude.app")
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }

    /// Inner executable used to spawn isolated instances.
    static func innerExecutable(in appURL: URL) -> URL {
        appURL.appending(path: "Contents/MacOS/Claude", directoryHint: .notDirectory)
    }
}
