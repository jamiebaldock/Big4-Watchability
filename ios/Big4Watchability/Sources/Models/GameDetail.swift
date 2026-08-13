import Foundation

// Mirrors backend/src/types.ts's GameDetailResponseJson and friends - backs
// the on-demand game-detail popup for a tapped finished tile.

struct TopPerformer: Codable, Identifiable, Hashable {
    var id: String { "\(name)-\(team)" }
    let name: String
    let team: String
    let line: String
}

struct HeadToHeadGame: Codable, Identifiable, Hashable {
    let eventId: String
    var id: String { eventId }
    let utc: String
    let away: String
    let home: String
    let awayScore: Int
    let homeScore: Int
}

struct TeamStandingsContext: Codable, Hashable {
    let rank: Int?
    let record: String?
    let groupName: String?
}

struct GameDetailResponse: Codable {
    let topPerformers: [TopPerformer]
    let headToHead: [HeadToHeadGame]
    let awayStandings: TeamStandingsContext
    let homeStandings: TeamStandingsContext
}
