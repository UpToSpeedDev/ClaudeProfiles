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
    /// Tracked separately so the built-in default profile's state can be derived from
    /// `NSRunningApplication` rather than a `Process` we own.
    private(set) var externalClaudeRunning: Bool = false

    @ObservationIgnored private var processes: [UUID: Process] = [:]
    @ObservationIgnored private var externalClaude: NSRunningApplication?
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []

    init() {
        registerWorkspaceObservers()
        refreshExternalClaude()
    }

    func isRunning(_ profile: Profile) -> Bool {
        if profile.isDefault { return externalClaudeRunning }
        return runningIDs.contains(profile.id)
    }

    /// Launches a Claude instance for the profile, or activates the existing one.
    func launch(_ profile: Profile, store: ProfileStore) throws {
        if profile.isDefault {
            try launchDefault(profile, store: store)
            return
        }
        try launchIsolated(profile, store: store)
    }

    /// Bring the profile's running Claude windows to the front, if any.
    func bringToFront(_ profile: Profile) {
        if profile.isDefault {
            externalClaude?.activate(options: [.activateAllWindows])
            return
        }
        guard let pid = processes[profile.id]?.processIdentifier else { return }
        activate(pid: pid)
    }

    /// Send SIGTERM to the child Claude process. macOS will close it gracefully.
    func quit(_ profile: Profile) {
        if profile.isDefault {
            externalClaude?.terminate()
            return
        }
        guard let proc = processes[profile.id], proc.isRunning else { return }
        proc.terminate()
    }

    /// Terminate everything we spawned. Not called on app quit by default.
    func quitAll() {
        for proc in processes.values where proc.isRunning {
            proc.terminate()
        }
    }

    private func launchIsolated(_ profile: Profile, store: ProfileStore) throws {
        if let existing = processes[profile.id], existing.isRunning {
            activate(pid: existing.processIdentifier)
            return
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
    }

    private func launchDefault(_ profile: Profile, store: ProfileStore) throws {
        guard let appURL = ClaudeAppLocator.locate() else {
            throw LaunchError.claudeNotFound
        }
        if let existing = externalClaude {
            existing.activate(options: [.activateAllWindows])
            store.markLaunched(profile)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        // If only isolated-profile Claudes are running, openApplication would normally
        // re-activate one of those instead of starting a fresh instance against the
        // default data dir. Force a new instance so the default profile actually opens.
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { [weak self] _, error in
            if let error {
                NSLog("Default Claude launch failed: \(error.localizedDescription)")
            }
            Task { @MainActor in self?.refreshExternalClaude() }
        }
        store.markLaunched(profile)
    }

    private func activate(pid: pid_t) {
        guard let running = NSRunningApplication(processIdentifier: pid) else { return }
        running.activate(options: [.activateAllWindows])
    }

    private func registerWorkspaceObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        let launchObs = nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == ClaudeAppLocator.bundleID else { return }
            Task { @MainActor in self?.refreshExternalClaude() }
        }
        let termObs = nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == ClaudeAppLocator.bundleID else { return }
            Task { @MainActor in self?.refreshExternalClaude() }
        }
        workspaceObservers = [launchObs, termObs]
    }

    /// The "external" Claude is any running Claude.app instance whose pid we did not spawn.
    /// That distinguishes the user-launched (default data-dir) instance from per-profile
    /// instances we started with `--user-data-dir`.
    private func refreshExternalClaude() {
        let ourPids = Set(processes.values.map { $0.processIdentifier })
        let candidate = NSRunningApplication
            .runningApplications(withBundleIdentifier: ClaudeAppLocator.bundleID)
            .first { !ourPids.contains($0.processIdentifier) }
        externalClaude = candidate
        externalClaudeRunning = candidate != nil
    }
}
