import SwiftUI

struct RootView: View {
    @Bindable var store: ProfileStore
    @Bindable var launcher: ProfileLauncher

    @State private var selection: Profile.ID?
    @State private var showingNewSheet = false
    @State private var pendingDelete: Profile?
    @State private var pendingDeleteSize: Int64? = nil

    private var claudeInstalled: Bool { ClaudeAppLocator.locate() != nil }

    var body: some View {
        NavigationSplitView {
            ProfileListView(
                store: store,
                launcher: launcher,
                selection: $selection,
                onAdd: { showingNewSheet = true },
                onDelete: { profile in beginDelete(profile) }
            )
            .frame(minWidth: 220)
        } detail: {
            if let selectedID = selection, let profile = store.profiles.first(where: { $0.id == selectedID }) {
                ProfileDetailView(
                    profile: profile,
                    store: store,
                    launcher: launcher,
                    onDelete: { beginDelete(profile) }
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
}
