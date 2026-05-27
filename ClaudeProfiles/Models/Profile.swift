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

    let id: UUID
    var name: String
    var tint: Tint
    var dataDirectoryName: String
    var createdAt: Date
    var lastLaunchedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        tint: Tint = .blue,
        dataDirectoryName: String? = nil,
        createdAt: Date = Date(),
        lastLaunchedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.tint = tint
        self.dataDirectoryName = dataDirectoryName ?? id.uuidString
        self.createdAt = createdAt
        self.lastLaunchedAt = lastLaunchedAt
    }

    func dataDirectoryURL() -> URL {
        Paths.profilesDataRoot.appending(path: dataDirectoryName, directoryHint: .isDirectory)
    }

    func logFileURL() -> URL {
        Paths.logsRoot.appending(path: "\(dataDirectoryName).log", directoryHint: .notDirectory)
    }
}
