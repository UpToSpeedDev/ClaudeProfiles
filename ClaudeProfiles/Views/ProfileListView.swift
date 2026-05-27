import SwiftUI

struct ProfileListView: View {
    let store: ProfileStore
    let launcher: ProfileLauncher
    @Binding var selection: Profile.ID?
    let onAdd: () -> Void
    let onDelete: (Profile) -> Void

    var body: some View {
        List(selection: $selection) {
            ForEach(store.profiles) { profile in
                ProfileRow(profile: profile, isRunning: launcher.isRunning(profile))
                    .tag(profile.id)
                    .contextMenu {
                        Button("Rename") { renameDialog(for: profile) }
                        Menu("Color") {
                            ForEach(Profile.Tint.allCases) { tint in
                                Button {
                                    store.setTint(profile, to: tint)
                                } label: {
                                    Label(tint.rawValue.capitalized, systemImage: profile.tint == tint ? "checkmark" : "")
                                }
                            }
                        }
                        Divider()
                        Button("Reveal Data in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([profile.dataDirectoryURL()])
                        }
                        Button("Reveal Log in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([profile.logFileURL()])
                        }
                        Divider()
                        Button("Delete…", role: .destructive) { onDelete(profile) }
                    }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onAdd()
                } label: {
                    Label("New Profile", systemImage: "plus")
                }
                .help("New Profile (⌘N)")
            }
        }
    }

    private func renameDialog(for profile: Profile) {
        let alert = NSAlert()
        alert.messageText = "Rename Profile"
        alert.informativeText = "Enter a new name for \"\(profile.name)\"."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = profile.name
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.rename(profile, to: field.stringValue)
        }
    }
}

private struct ProfileRow: View {
    let profile: Profile
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(profile.tint.color)
                .frame(width: 12, height: 12)
            Text(profile.name)
                .lineLimit(1)
            Spacer()
            if isRunning {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                    .help("Running")
            }
        }
    }
}
