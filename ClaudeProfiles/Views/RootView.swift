import SwiftUI

struct RootView: View {
    @Bindable var store: ProfileStore
    @Bindable var launcher: ProfileLauncher
    @Bindable var updates: UpdateChecker

    @State private var selection: Profile.ID?
    @State private var showingNewSheet = false
    @State private var pendingDelete: Profile?
    @State private var pendingDeleteSize: Int64? = nil
    @State private var pendingMakeDefault: Profile?
    @State private var makeDefaultError: String?
    @State private var showUpdateResultAlert = false
    @State private var manualCheckPending = false

    private var claudeInstalled: Bool { ClaudeAppLocator.locate() != nil }

    var body: some View {
        VStack(spacing: 0) {
            UpdateBanner(updates: updates)
            content
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestUpdateCheck)) { _ in
            manualCheckPending = true
            // If the state is already terminal (e.g. cached), surface it immediately.
            presentManualResultIfReady()
        }
        .onChange(of: updates.state) { _, _ in
            presentManualResultIfReady()
        }
        .alert(updateAlertTitle, isPresented: $showUpdateResultAlert) {
            if case .updateAvailable(_, let url) = updates.state {
                Button("Open Release Page") { NSWorkspace.shared.open(url) }
                Button("Later", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(updateAlertMessage)
        }
    }

    private func presentManualResultIfReady() {
        guard manualCheckPending else { return }
        switch updates.state {
        case .checking, .idle:
            return
        case .upToDate, .updateAvailable, .failed:
            manualCheckPending = false
            showUpdateResultAlert = true
        }
    }

    private var content: some View {
        NavigationSplitView {
            ProfileListView(
                store: store,
                launcher: launcher,
                selection: $selection,
                onAdd: { showingNewSheet = true },
                onDelete: { profile in beginDelete(profile) },
                onMakeDefault: { profile in beginMakeDefault(profile) }
            )
            .frame(minWidth: 220)
        } detail: {
            if let selectedID = selection, let profile = store.profiles.first(where: { $0.id == selectedID }) {
                ProfileDetailView(
                    profile: profile,
                    store: store,
                    launcher: launcher,
                    onDelete: { beginDelete(profile) },
                    onMakeDefault: { beginMakeDefault(profile) }
                )
            } else if store.profiles.isEmpty {
                EmptyStateView(claudeInstalled: claudeInstalled) {
                    showingNewSheet = true
                }
            } else {
                Text("Select a profile")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Claude Profiles")
        .sheet(isPresented: $showingNewSheet) {
            NewProfileSheet { name, tint in
                let profile = store.add(name: name, tint: tint)
                selection = profile.id
            }
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: deleteBinding,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { profile in
            Button("Move Data to Trash", role: .destructive) {
                if launcher.isRunning(profile) { launcher.quit(profile) }
                store.delete(profile, removeData: true)
                if selection == profile.id { selection = nil }
                pendingDelete = nil
            }
            Button("Keep Data", role: .destructive) {
                if launcher.isRunning(profile) { launcher.quit(profile) }
                store.delete(profile, removeData: false)
                if selection == profile.id { selection = nil }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: { _ in
            Text(deleteMessage)
        }
        .confirmationDialog(
            makeDefaultTitle,
            isPresented: makeDefaultBinding,
            titleVisibility: .visible,
            presenting: pendingMakeDefault
        ) { profile in
            if runningForSwap(profile).isEmpty {
                Button("Make Default") { performMakeDefault(profile) }
            } else {
                Button("Quit Claude & Make Default") { performMakeDefault(profile) }
            }
            Button("Cancel", role: .cancel) { pendingMakeDefault = nil }
        } message: { profile in
            Text(makeDefaultMessage(for: profile))
        }
        .alert(
            "Couldn't Make Default",
            isPresented: Binding(get: { makeDefaultError != nil }, set: { if !$0 { makeDefaultError = nil } })
        ) {
            Button("OK", role: .cancel) { makeDefaultError = nil }
        } message: {
            Text(makeDefaultError ?? "")
        }
    }

    private var updateAlertTitle: String {
        switch updates.state {
        case .updateAvailable: return "Update available"
        case .upToDate: return "You're up to date"
        case .failed: return "Update check failed"
        case .checking, .idle: return ""
        }
    }

    private var updateAlertMessage: String {
        switch updates.state {
        case .updateAvailable(let v, _):
            return "Claude Profiles v\(v) is available. You're running v\(updates.currentVersion)."
        case .upToDate(let v):
            return "Running the latest version (v\(v))."
        case .failed(let msg):
            return msg
        case .checking, .idle:
            return ""
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var deleteTitle: String {
        "Delete \"\(pendingDelete?.name ?? "")\"?"
    }

    private var deleteMessage: String {
        let sizeString = pendingDeleteSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "the"
        return "The profile will be removed from the launcher. Its data directory contains \(sizeString) of cookies, sessions, and caches. Move that data to the Trash, or keep it on disk?"
    }

    private func beginDelete(_ profile: Profile) {
        guard !profile.isDefault else { return }
        pendingDeleteSize = nil
        pendingDelete = profile
        let url = profile.dataDirectoryURL()
        Task.detached(priority: .utility) {
            let size = DirectorySize.bytes(at: url)
            await MainActor.run {
                if pendingDelete?.id == profile.id {
                    pendingDeleteSize = size
                }
            }
        }
    }

    // MARK: - Make Default

    private var makeDefaultBinding: Binding<Bool> {
        Binding(get: { pendingMakeDefault != nil }, set: { if !$0 { pendingMakeDefault = nil } })
    }

    private var makeDefaultTitle: String {
        "Make \"\(pendingMakeDefault?.name ?? "")\" the default?"
    }

    /// The current default plus the target, limited to whichever are running — these must be
    /// quit before their data directories can be swapped.
    private func runningForSwap(_ target: Profile) -> [Profile] {
        let current = store.profiles.first { $0.isDefault }
        return [current, target].compactMap { $0 }.filter { launcher.isRunning($0) }
    }

    private func makeDefaultMessage(for profile: Profile) -> String {
        let base = "Launching plain Claude will open \"\(profile.name)\". Its data and the current default's "
            + "data directories are swapped on disk."
        let running = runningForSwap(profile)
        guard !running.isEmpty else { return base }
        let names = running.map { "\"\($0.name)\"" }.joined(separator: " and ")
        return base + " Claude is running for \(names) and must be quit first."
    }

    private func beginMakeDefault(_ profile: Profile) {
        guard !profile.isDefault else { return }
        pendingMakeDefault = profile
    }

    private func performMakeDefault(_ profile: Profile) {
        pendingMakeDefault = nil
        let running = runningForSwap(profile)
        Task { @MainActor in
            for p in running { launcher.quit(p) }
            // Wait for the instances to actually exit (the launcher flips isRunning via its
            // workspace termination observer) before moving any files.
            if !running.isEmpty {
                var waited = 0.0
                while waited < 15.0 {
                    if running.allSatisfy({ !launcher.isRunning($0) }) { break }
                    try? await Task.sleep(for: .milliseconds(400))
                    waited += 0.4
                }
                if running.contains(where: { launcher.isRunning($0) }) {
                    makeDefaultError = "Claude is still running. Quit it (check for an unsaved-changes prompt) and try again."
                    return
                }
            }
            do {
                try store.setDefault(profile)
                selection = profile.id
            } catch {
                makeDefaultError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

private struct UpdateBanner: View {
    @Bindable var updates: UpdateChecker

    var body: some View {
        if case .updateAvailable(let version, let url) = updates.state {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.tint)
                Text("Claude Profiles v\(version) is available.")
                    .font(.callout)
                Spacer()
                Button("View Release") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.tint.opacity(0.12))
            .overlay(alignment: .bottom) {
                Divider()
            }
        }
    }
}
