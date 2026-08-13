import Foundation

// Mirrors backend/src/types.ts's Stat*Json interfaces.

struct StatLeader: Codable, Identifiable, Hashable {
    var id: String { "\(name)-\(team)" }
    let name: String
    let team: String
    let teamLogo: String?
    let value: String
}

struct StatCategory: Codable, Identifiable, Hashable {
    var id: String { key }
    let key: String
    let label: String
    let abbr: String
    let leaders: [StatLeader]
}

struct StatsResponse: Codable {
    let season: String
    let categories: [StatCategory]
}
