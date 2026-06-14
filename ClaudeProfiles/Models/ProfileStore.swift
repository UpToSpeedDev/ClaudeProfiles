import Foundation
import Observation
import SwiftUI

enum DefaultSwapError: LocalizedError {
    case moveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .moveFailed(let underlying):
            return "Couldn't swap the data directories: \(underlying.localizedDescription)"
        }
    }
}

@MainActor
@Observable
final class ProfileStore {
    private(set) var profiles: [Profile] = []

    init() {
        load()
        ensureDefaultProfile()
    }

    private func ensureDefaultProfile() {
        if !profiles.contains(where: { $0.isDefault }) {
            profiles.insert(Profile.makeDefault(), at: 0)
            save()
        }
    }

    func add(name: String, tint: Profile.Tint) -> Profile {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? defaultName() : trimmed
        let profile = Profile(name: finalName, tint: tint)
        try? FileManager.default.createDirectory(at: profile.dataDirectoryURL(), withIntermediateDirectories: true)
        profiles.append(profile)
        save()
        return profile
    }

    /// Reorders profiles in the sidebar. The new order is persisted as the array order.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        profiles.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func update(_ profile: Profile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        save()
    }

    func rename(_ profile: Profile, to newName: String) {
        var copy = profile
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.name = trimmed.isEmpty ? profile.name : trimmed
        update(copy)
    }

    func setTint(_ profile: Profile, to tint: Profile.Tint) {
        var copy = profile
        copy.tint = tint
        update(copy)
    }

    /// Transfers the Default role to `target` by physically swapping its data directory with the
    /// native Claude data directory, so launching plain Claude.app opens `target`'s data. The
    /// previous default's data is preserved in `target`'s former isolated slot. Only the
    /// `isDefault` badge moves; names stay with their data.
    ///
    /// Contract: the caller must ensure both the current default's and `target`'s Claude
    /// instances are quit first — moving a data directory out from under a live Claude corrupts it.
    func setDefault(_ target: Profile) throws {
        guard !target.isDefault else { return }
        guard let curIdx = profiles.firstIndex(where: { $0.isDefault }),
              let tgtIdx = profiles.firstIndex(where: { $0.id == target.id }) else { return }

        var current = profiles[curIdx]
        var newDefault = profiles[tgtIdx]

        let fm = FileManager.default
        let nativeDir = Paths.defaultClaudeDataDirectory            // holds current's data (N)
        let targetDir = newDefault.dataDirectoryURL()               // …/data/<tgtOldName> holds T
        try? fm.createDirectory(at: nativeDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

        // Same-volume renames (atomic, O(1)). Temp lives under profilesDataRoot.
        let tmp = Paths.profilesDataRoot.appending(path: ".swap-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try fm.moveItem(at: nativeDir, to: tmp)                 // native → tmp (= N)
            do {
                try fm.moveItem(at: targetDir, to: nativeDir)      // target → native (native = T)
            } catch {
                try? fm.moveItem(at: tmp, to: nativeDir)           // rollback: native = N
                throw DefaultSwapError.moveFailed(error)
            }
            do {
                try fm.moveItem(at: tmp, to: targetDir)            // tmp → target slot (targetDir = N)
            } catch {
                try? fm.moveItem(at: nativeDir, to: targetDir)     // rollback: targetDir = T
                try? fm.moveItem(at: tmp, to: nativeDir)           //           native = N
                throw DefaultSwapError.moveFailed(error)
            }
        } catch let error as DefaultSwapError {
            throw error
        } catch {
            throw DefaultSwapError.moveFailed(error)
        }

        // Swap the two directory-name strings + the badge. ("__default__" ⇄ <tgtOldName>.)
        let curOldName = current.dataDirectoryName                  // "__default__"
        current.isDefault = false
        current.dataDirectoryName = newDefault.dataDirectoryName    // → …/data/<tgtOldName> (= N)
        newDefault.isDefault = true
        newDefault.dataDirectoryName = curOldName                   // "__default__" (ignored while default)

        profiles[curIdx] = current
        profiles[tgtIdx] = newDefault
        save()
    }

    func markLaunched(_ profile: Profile, at date: Date = Date()) {
        var copy = profile
        copy.lastLaunchedAt = date
        update(copy)
    }

    /// Removes the profile. If `removeData` is true, the on-disk data directory is moved to Trash.
    /// The built-in default profile cannot be deleted.
    func delete(_ profile: Profile, removeData: Bool) {
        guard !profile.isDefault else { return }
        profiles.removeAll { $0.id == profile.id }
        save()
        if removeData {
            let url = profile.dataDirectoryURL()
            var resultingURL: NSURL?
            try? FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        }
    }

    private func defaultName() -> String {
        let n = profiles.count + 1
        return "Profile \(n)"
    }

    private func load() {
        let url = Paths.profilesJSONURL
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Profile].self, from: data) {
            profiles = decoded
        }
    }

    private func save() {
        let url = Paths.profilesJSONURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(profiles) else { return }
        let tmp = url.deletingLastPathComponent().appending(path: ".profiles.json.tmp", directoryHint: .notDirectory)
        do {
            try data.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            try? data.write(to: url, options: .atomic)
        }
    }
}
