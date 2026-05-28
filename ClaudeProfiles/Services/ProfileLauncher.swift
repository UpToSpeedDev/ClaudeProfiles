import AppKit
import Darwin
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
    /// Pids for profile instances we discovered by scanning running Claudes (e.g. orphans
    /// from a previous app session). Kept separate so we know we don't own a `Process`.
    @ObservationIgnored private var adoptedPids: [UUID: pid_t] = [:]
    @ObservationIgnored private var externalClaude: NSRunningApplication?
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private weak var store: ProfileStore?

    init() {
        registerWorkspaceObservers()
    }

    /// Called by the App once the store is available so the launcher can classify
    /// running Claudes by matching `--user-data-dir=` against known profile paths.
    func bind(store: ProfileStore) {
        self.store = store
        rescanRunningClaudes()
    }

    func isRunning(_ profile: Profile) -> Bool {
        if profile.isDefault { return externalClaudeRunning }
        if let proc = processes[profile.id], proc.isRunning { return true }
        return adoptedPids[profile.id] != nil
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
        if let pid = runningPid(for: profile) { activate(pid: pid) }
    }

    /// Send SIGTERM to the profile's Claude process. macOS will close it gracefully.
    func quit(_ profile: Profile) {
        if profile.isDefault {
            externalClaude?.terminate()
            return
        }
        if let proc = processes[profile.id], proc.isRunning {
            proc.terminate()
            return
        }
        if let pid = adoptedPids[profile.id],
           let app = NSRunningApplication(processIdentifier: pid) {
            app.terminate()
        }
    }

    /// Terminate everything we spawned. Not called on app quit by default.
    func quitAll() {
        for proc in processes.values where proc.isRunning {
            proc.terminate()
        }
    }

    private func runningPid(for profile: Profile) -> pid_t? {
        if let proc = processes[profile.id], proc.isRunning {
            return proc.processIdentifier
        }
        return adoptedPids[profile.id]
    }

    private func launchIsolated(_ profile: Profile, store: ProfileStore) throws {
        if let pid = runningPid(for: profile) {
            activate(pid: pid)
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
                }
                self.rescanRunningClaudes()
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
            Task { @MainActor in self?.rescanRunningClaudes() }
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
            Task { @MainActor in self?.rescanRunningClaudes() }
        }
        let termObs = nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == ClaudeAppLocator.bundleID else { return }
            Task { @MainActor in self?.rescanRunningClaudes() }
        }
        workspaceObservers = [launchObs, termObs]
    }

    /// Walk every running Claude.app, read its launch arguments, and route each instance:
    /// - matches a known profile's `--user-data-dir` ⇒ that profile is running (adopt the pid).
    /// - no `--user-data-dir`, or pointed at Claude's default data dir ⇒ this is the "external"
    ///   default Claude.
    /// - anything else (e.g. a deleted profile) is ignored.
    private func rescanRunningClaudes() {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: ClaudeAppLocator.bundleID)
        let defaultDir = Paths.defaultClaudeDataDirectory.standardizedFileURL.path
        let profilesByDir: [String: UUID] = Dictionary(
            (store?.profiles ?? [])
                .filter { !$0.isDefault }
                .map { ($0.dataDirectoryURL().standardizedFileURL.path, $0.id) },
            uniquingKeysWith: { first, _ in first }
        )

        var newAdopted: [UUID: pid_t] = [:]
        var externalCandidate: NSRunningApplication?

        for app in apps {
            let pid = app.processIdentifier

            // Already owned via a Process we spawned — no need to inspect argv.
            if processes.contains(where: { $0.value.processIdentifier == pid }) {
                continue
            }

            let args = Self.processArguments(pid: pid) ?? []
            let dataDir = Self.userDataDir(in: args)?.standardizedFileURL.path

            if let dataDir, let profileID = profilesByDir[dataDir] {
                newAdopted[profileID] = pid
            } else if dataDir == nil || dataDir == defaultDir {
                if externalCandidate == nil { externalCandidate = app }
            }
        }

        adoptedPids = newAdopted
        externalClaude = externalCandidate
        externalClaudeRunning = externalCandidate != nil

        let spawnedRunning = processes.compactMap { $0.value.isRunning ? $0.key : nil }
        runningIDs = Set(spawnedRunning).union(newAdopted.keys)
    }

    /// Read another process's argv via `sysctl(KERN_PROCARGS2)`. Returns nil if the
    /// process is gone or we don't have permission.
    private static func processArguments(pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        let probe = mib.withUnsafeMutableBufferPointer {
            sysctl($0.baseAddress, UInt32($0.count), nil, &size, nil, 0)
        }
        if probe != 0 || size <= MemoryLayout<Int32>.size { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        let read = mib.withUnsafeMutableBufferPointer { mibPtr in
            buffer.withUnsafeMutableBufferPointer { bufPtr in
                sysctl(mibPtr.baseAddress, UInt32(mibPtr.count), bufPtr.baseAddress, &size, nil, 0)
            }
        }
        if read != 0 { return nil }

        // Layout: [Int32 argc][exec path NUL-terminated][NUL padding][argv[0]\0]...[argv[argc-1]\0][envp...]
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var idx = MemoryLayout<Int32>.size
        while idx < buffer.count && buffer[idx] != 0 { idx += 1 }      // skip exec path
        while idx < buffer.count && buffer[idx] == 0 { idx += 1 }      // skip NUL padding

        var args: [String] = []
        var collected: Int32 = 0
        while collected < argc && idx < buffer.count {
            var end = idx
            while end < buffer.count && buffer[end] != 0 { end += 1 }
            if let s = String(bytes: buffer[idx..<end], encoding: .utf8) {
                args.append(s)
            }
            idx = end + 1
            collected += 1
        }
        return args
    }

    private static func userDataDir(in args: [String]) -> URL? {
        let key = "--user-data-dir"
        for arg in args where arg.hasPrefix("\(key)=") {
            return URL(fileURLWithPath: String(arg.dropFirst(key.count + 1)))
        }
        for (i, arg) in args.enumerated() where arg == key && i + 1 < args.count {
            return URL(fileURLWithPath: args[i + 1])
        }
        return nil
    }
}
