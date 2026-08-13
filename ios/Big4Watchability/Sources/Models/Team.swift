import Foundation

// Mirrors backend/src/types.ts's Team/Player/Roster*Json interfaces - backs
// the favorite-teams/players search screens.

struct TeamJson: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let logo: String?
}

struct PlayerJson: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let headshot: String?
}

struct RosterResponse: Codable {
    let players: [PlayerJson]
}

struct TeamsResponse: Codable {
    let teams: [TeamJson]
}
