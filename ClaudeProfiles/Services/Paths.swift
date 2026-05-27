import Foundation

enum Paths {
    static let supportDirectoryName = "ClaudeProfiles"

    static var appSupportRoot: URL {
        let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = (base ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support"))
            .appending(path: supportDirectoryName, directoryHint: .isDirectory)
        ensureDirectory(root)
        return root
    }

    static var profilesJSONURL: URL {
        appSupportRoot.appending(path: "profiles.json", directoryHint: .notDirectory)
    }

    static var profilesDataRoot: URL {
        let url = appSupportRoot.appending(path: "data", directoryHint: .isDirectory)
        ensureDirectory(url)
        return url
    }

    static var logsRoot: URL {
        let url = appSupportRoot.appending(path: "logs", directoryHint: .isDirectory)
        ensureDirectory(url)
        return url
    }

    private static func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
