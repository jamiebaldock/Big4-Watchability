import Foundation

// Mirrors backend/src/types.ts's GameJson / LeagueGroup / GameStatus / etc.
// Keep field names (including CodingKeys) in sync with that file, the same
// way mobile/app/.../data/Game.kt does for the Android client.

enum LeagueGroup: String, Codable, CaseIterable, Identifiable {
    case nba, wnba, mlb, nfl, nhl

    var id: String { rawValue }
    var apiValue: String { rawValue }
}

enum Sport: String, Codable {
    case basketball, baseball, football, hockey
}

let sportForLeagueGroup: [LeagueGroup: Sport] = [
    .nba: .basketball,
    .wnba: .basketball,
    .mlb: .baseball,
    .nfl: .football,
    .nhl: .hockey
]

// The underlying ESPN league a game actually belongs to - distinct from
// LeagueGroup, which is the mutually-exclusive slate the client is viewing.
enum EspnLeague: String, Codable {
    case nba, wnba, summer, mlb, nfl, nhl
}

enum GameStatus: String, Codable {
    case final
    case live
    case upcoming
}

enum StarPerformance: String, Codable {
    case historic, great, good
}

struct StandoutPerformer: Codable, Identifiable, Hashable {
    var id: String { "\(name)-\(team ?? "")" }
    let name: String
    let line: String
    let team: String?
}

struct MlbRubricInputs: Codable, Hashable {
    let finalMargin: Int
    let totalRuns: Int
    let largestDeficitOvercome: Int
    let walkOff: Bool
    let extraInningsCount: Int
    let combinedHomeRuns: Int
    let maxHomeRunsByPlayer: Int
    let teamBlanked: Bool
    let noHitter: Bool
    let perfectGame: Bool
    let blownSave: Bool
    let combinedErrors: Int
}

struct NflRubricInputs: Codable, Hashable {
    let finalMargin: Int
    let largestDeficitOvercome: Int
    let leadChanges: Int
    let overtimePeriods: Int
    let decisiveScoreLate: Bool
    let combinedTurnovers: Int
    let defensiveOrSpecialTeamsTd: Bool
    let maxPassingYards: Int
    let maxRushingYards: Int
    let maxTotalTdsByPlayer: Int
    let totalPoints: Int
}

struct NhlRubricInputs: Codable, Hashable {
    let finalMargin: Int
    let totalGoals: Int
    let largestDeficitOvercome: Int
    let leadChanges: Int
    let overtimePeriods: Int
    let wentToShootout: Bool
    let decisiveScoreLate: Bool
    let combinedPowerPlayGoals: Int
    let maxGoalsByPlayer: Int
    let maxGoalieSaves: Int
    let teamShutout: Bool
}

struct GameJson: Codable, Identifiable, Hashable {
    // Composite key, matching Game.kt's Game.id - NOT eventId, which is only
    // used as the /game-detail?eventId= lookup key.
    var id: String { "\(a)@\(h)@\(utc)" }

    let eventId: String?
    let a: String
    let h: String
    let al: String?
    let hl: String?
    let stt: GameStatus
    let utc: String
    let lg: EspnLeague
    let cl: String?
    let q: Int?
    let clk: String?
    let m: Int?
    let cb: Int?
    let lc: Int?
    // Absolute final score - only ever populated by the History tab. Every
    // other tab deliberately omits these to avoid spoiling a game the viewer
    // might not have watched yet.
    let awayScore: Int?
    let homeScore: Int?
    let ot: Int
    let c5: Bool
    let lcf: Bool
    let fp: Bool
    let bz: Bool
    let st: StarPerformance?
    let sop: [StandoutPerformer]?
    let sk: Int?
    let hook: String
    let pitch: String?
    let score: Int?
    let scoreVisible: Bool
    let yt: String?
    let mlbInputs: MlbRubricInputs?
    let nflInputs: NflRubricInputs?
    let nhlInputs: NhlRubricInputs?

    enum CodingKeys: String, CodingKey {
        case eventId = "id"
        case a, h, al, hl, stt, utc, lg, cl, q, clk, m, cb, lc
        case awayScore = "as"
        case homeScore = "hs"
        case ot, c5, lcf, fp, bz, st, sop, sk, hook, pitch, score
        case scoreVisible = "score_visible"
        case yt, mlbInputs, nflInputs, nhlInputs
    }
}
