import AppKit
import SwiftUI

@main
struct ClaudeProfilesApp: App {
    @State private var store = ProfileStore()
    @State private var launcher = ProfileLauncher()
    @State private var updates = UpdateChecker()

    var body: some Scene {
        Window("Claude Profiles", id: "main") {
            RootView(store: store, launcher: launcher, updates: updates)
                .frame(minWidth: 720, minHeight: 460)
                .task { updates.checkIfDue() }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Profile…") {
                    NotificationCenter.default.post(name: .requestNewProfile, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updates.checkNow()
                    NotificationCenter.default.post(name: .requestUpdateCheck, object: nil)
                }
                Button("Open Data Folder") {
                    NSWorkspace.shared.open(Paths.appSupportRoot)
                }
            }
        }

        MenuBarExtra {
            MenuBarContent(store: store, launcher: launcher, updates: updates)
        } label: {
            Image(systemName: "person.2.crop.square.stack.fill")
        }
        .menuBarExtraStyle(.menu)
    }
}

extension Notification.Name {
    static let requestNewProfile = Notification.Name("ClaudeProfiles.requestNewProfile")
    static let requestUpdateCheck = Notification.Name("ClaudeProfiles.requestUpdateCheck")
}

private struct MenuBarContent: View {
    @Bindable var store: ProfileStore
    @Bindable var launcher: ProfileLauncher
    @Bindable var updates: UpdateChecker
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if store.profiles.isEmpty {
            Text("No profiles")
                .disabled(true)
            Divider()
        } else {
            ForEach(store.profiles) { profile in
                Menu {
                    if launcher.isRunning(profile) {
                        Button("Bring to Front") { launcher.bringToFront(profile) }
                        Button("Quit") { launcher.quit(profile) }
                    } else {
                        Button("Launch") {
                            do { _ = try launcher.launch(profile, store: store) } catch { NSLog("launch failed: \(error)") }
                        }
                    }
                } label: {
                    Label {
                        Text(launcher.isRunning(profile) ? "\(profile.name)  ●" : profile.name)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(profile.tint.color)
                    }
                }
            }
            Divider()
        }

        if case .updateAvailable(let version, let url) = updates.state {
            Button("Update available — v\(version)") {
                NSWorkspace.shared.open(url)
            }
            Divider()
        }

        Button("Open Claude Profiles…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit Claude Profiles") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
