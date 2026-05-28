import SwiftUI

struct ProfileDetailView: View {
    let profile: Profile
    let store: ProfileStore
    let launcher: ProfileLauncher
    let onDelete: () -> Void

    @State private var diskUsage: Int64? = nil
    @State private var lastError: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                actions

                if let lastError {
                    Label(lastError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                Divider()

                infoGrid

                Divider()

                dataSection
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: profile.id) {
            await recomputeDiskUsage()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(profile.tint.color)
                .frame(width: 28, height: 28)
            Text(profile.name)
                .font(.largeTitle.weight(.semibold))
            if launcher.isRunning(profile) {
                Label("Running", systemImage: "circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
                    .font(.callout)
                    .padding(.leading, 8)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 10) {
            if launcher.isRunning(profile) {
                Button {
                    launcher.bringToFront(profile)
                } label: {
                    Label("Bring to Front", systemImage: "arrow.up.left.and.arrow.down.right")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    launcher.quit(profile)
                } label: {
                    Label("Quit", systemImage: "stop.fill")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .controlSize(.large)
            } else {
                Button {
                    launch()
                } label: {
                    Label("Launch Claude", systemImage: "play.fill")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("l", modifiers: [.command])
            }

            Spacer()

            if !profile.isDefault {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Profile", systemImage: "trash")
                }
            }
        }
    }

    private var infoGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledRow(label: "Created", value: profile.createdAt.formatted(date: .abbreviated, time: .shortened))
            LabeledRow(
                label: "Last launched",
                value: profile.lastLaunchedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
            )
            LabeledRow(
                label: "Disk usage",
                value: diskUsage.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—"
            )
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Data Directory")
                .font(.headline)
            Text(profile.dataDirectoryURL().path)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([profile.dataDirectoryURL()])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                if !profile.isDefault {
                    Button {
                        NSWorkspace.shared.open(profile.logFileURL())
                    } label: {
                        Label("Open Log", systemImage: "doc.text")
                    }
                }
                Button {
                    Task { await recomputeDiskUsage() }
                } label: {
                    Label("Recalculate Size", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private func launch() {
        do {
            _ = try launcher.launch(profile, store: store)
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func recomputeDiskUsage() async {
        let url = profile.dataDirectoryURL()
        let bytes = await Task.detached(priority: .utility) {
            DirectorySize.bytes(at: url)
        }.value
        diskUsage = bytes
    }
}

private struct LabeledRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: 120, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

enum DirectorySize {
    static func bytes(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            let size = Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
            total += size
        }
        return total
    }
}
