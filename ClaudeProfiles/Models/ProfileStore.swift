import Foundation
import Observation

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
