import AppKit
import Foundation
import Observation

enum LaunchError: LocalizedError {
    case claudeNotFound
    case executableMissing(URL)
    case spawnFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            return "Claude.app is not installed. Install it from claude.ai/download."
        case .executableMissing(let url):
            return "Claude executable not found at \(url.path)."
        case .spawnFailed(let underlying):
            return "Failed to launch Claude: \(underlying.localizedDescription)"
        }
    }
}

@MainActor
@Observable
final class ProfileLauncher {
    private(set) var runningIDs: Set<UUID> = []
    private var processes: [UUID: Process] = [:]

    func isRunning(_ profile: Profile) -> Bool {
        runningIDs.contains(profile.id)
    }

    /// Launches a Claude instance for the profile, or activates the existing one.
    @discardableResult
    func launch(_ profile: Profile, store: ProfileStore) throws -> pid_t {
        if let existing = processes[profile.id], existing.isRunning {
            activate(pid: existing.processIdentifier)
            return existing.processIdentifier
        }

        guard let appURL = ClaudeAppLocator.locate() else {
            throw LaunchError.claudeNotFound
        }
        let exec = ClaudeAppLocator.innerExecutable(in: appURL)
        guard FileManager.default.isExecutableFile(atPath: exec.path) else {
            throw LaunchError.executableMissing(exec)
        }

        let dataDir = profile.dataDirectoryURL()
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = exec
        proc.arguments = ["--user-data-dir=\(dataDir.path)"]
        proc.qualityOfService = .userInitiated

        // Per-launch log; truncate on each launch.
        let logURL = profile.logFileURL()
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            proc.standardOutput = handle
            proc.standardError = handle
        }

        proc.terminationHandler = { [weak self] terminated in
            let pid = terminated.processIdentifier
            Task { @MainActor in
                guard let self else { return }
                if let entry = self.processes.first(where: { $0.value.processIdentifier == pid }) {
                    self.processes.removeValue(forKey: entry.key)
                    self.runningIDs.remove(entry.key)
                }
            }
        }

        do {
            try proc.run()
        } catch {
            throw LaunchError.spawnFailed(underlying: error)
        }

        processes[profile.id] = proc
        runningIDs.insert(profile.id)
        store.markLaunched(profile)
        return proc.processIdentifier
    }

    /// Bring the profile's running Claude windows to the front, if any.
    func bringToFront(_ profile: Profile) {
        guard let pid = processes[profile.id]?.processIdentifier else { return }
        activate(pid: pid)
    }

    /// Send SIGTERM to the child Claude process. macOS will close it gracefully.
    func quit(_ profile: Profile) {
        guard let proc = processes[profile.id], proc.isRunning else { return }
        proc.terminate()
    }

    /// Terminate everything we spawned. Not called on app quit by default.
    func quitAll() {
        for proc in processes.values where proc.isRunning {
            proc.terminate()
        }
    }

    private func activate(pid: pid_t) {
        guard let running = NSRunningApplication(processIdentifier: pid) else { return }
        running.activate(options: [.activateAllWindows])
    }
}
