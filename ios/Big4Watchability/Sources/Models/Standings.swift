import Foundation

// Mirrors backend/src/types.ts's Standings*Json interfaces.

struct StandingsTeam: Codable, Identifiable, Hashable {
    let id: String
    let n: String
    let ab: String
    let lg: String?
    let w: Int
    let l: Int
    let pct: String
    let gb: String
    let strk: String?
}

struct StandingsGroup: Codable, Hashable {
    let name: String
    let teams: [StandingsTeam]
}

struct StandingsResponse: Codable {
    let season: String
    let groups: [StandingsGroup]
}
