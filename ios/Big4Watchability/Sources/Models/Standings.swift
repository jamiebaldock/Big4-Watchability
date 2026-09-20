import Foundation

// Mirrors backend/src/types.ts's Standings*Json interfaces.

struct StandingsTeam: Codable, Identifiable, Hashable {
    let id: String
    let n: String
    let ab: String
    // Team logo URL - matches Android's StandingsTeam.logo (@SerialName("lg")).
    // Was never added here, so StandingsView never had a logo to show at all.
    let logo: String?
    let w: Int
    let l: Int
    let pct: String
    let gb: String
    let strk: String?

    enum CodingKeys: String, CodingKey {
        case id, n, ab
        case logo = "lg"
        case w, l, pct, gb, strk
    }
}

struct StandingsGroup: Codable, Hashable {
    let name: String
    let teams: [StandingsTeam]
}

struct StandingsResponse: Codable {
    let season: String
    let groups: [StandingsGroup]
}
