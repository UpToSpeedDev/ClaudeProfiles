import Foundation
import SwiftUI

struct Profile: Identifiable, Codable, Hashable {
    enum Tint: String, Codable, CaseIterable, Identifiable {
        case blue, indigo, purple, pink, red, orange, yellow, green, mint, teal, gray
        var id: String { rawValue }

        var color: Color {
            switch self {
            case .blue: return .blue
            case .indigo: return .indigo
            case .purple: return .purple
            case .pink: return .pink
            case .red: return .red
            case .orange: return .orange
            case .yellow: return .yellow
            case .green: return .green
            case .mint: return .mint
            case .teal: return .teal
            case .gray: return .gray
            }
        }
    }

    /// Stable ID for the built-in profile that points at Claude.app's normal data directory.
    static let defaultProfileID = UUID(uuidString: "00000000-0000-0000-0000-0000000000DE")!

    let id: UUID
    var name: String
    var tint: Tint
    var dataDirectoryName: String
    var createdAt: Date
    var lastLaunchedAt: Date?
    var isDefault: Bool

    init(
        id: UUID = UUID(),
        name: String,
        tint: Tint = .blue,
        dataDirectoryName: String? = nil,
        createdAt: Date = Date(),
        lastLaunchedAt: Date? = nil,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.tint = tint
        self.dataDirectoryName = dataDirectoryName ?? id.uuidString
        self.createdAt = createdAt
        self.lastLaunchedAt = lastLaunchedAt
        self.isDefault = isDefault
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        tint = try c.decode(Tint.self, forKey: .tint)
        dataDirectoryName = try c.decode(String.self, forKey: .dataDirectoryName)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        lastLaunchedAt = try c.decodeIfPresent(Date.self, forKey: .lastLaunchedAt)
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }

    static func makeDefault() -> Profile {
        Profile(
            id: defaultProfileID,
            name: "Default",
            tint: .gray,
            dataDirectoryName: "__default__",
            createdAt: Date(),
            isDefault: true
        )
    }

    func dataDirectoryURL() -> URL {
        if isDefault {
            return Paths.defaultClaudeDataDirectory
        }
        return Paths.profilesDataRoot.appending(path: dataDirectoryName, directoryHint: .isDirectory)
    }

    func logFileURL() -> URL {
        Paths.logsRoot.appending(path: "\(dataDirectoryName).log", directoryHint: .notDirectory)
    }
}
