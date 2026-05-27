import SwiftUI

struct EmptyStateView: View {
    let claudeInstalled: Bool
    let createProfile: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: claudeInstalled ? "person.2.crop.square.stack" : "questionmark.app.dashed")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text(claudeInstalled ? "No Profiles Yet" : "Claude.app Not Found")
                .font(.title2.weight(.semibold))
            Text(claudeInstalled
                 ? "Create a profile to run Claude with an isolated account. Each profile keeps its own cookies, sessions, and extensions."
                 : "Install Claude from claude.ai/download and reopen this app.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if claudeInstalled {
                Button {
                    createProfile()
                } label: {
                    Label("Create First Profile", systemImage: "plus")
                        .padding(.horizontal, 6)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    NSWorkspace.shared.open(ClaudeAppLocator.downloadURL)
                } label: {
                    Label("Open claude.ai/download", systemImage: "arrow.up.right.square")
                        .padding(.horizontal, 6)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
