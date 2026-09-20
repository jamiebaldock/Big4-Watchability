import Foundation

// Mirrors Android's DayGames (mobile/app/.../data/Game.kt) - one calendar
// date's slate, as returned by /schedule's per-day grouping.
struct DayGames: Codable, Identifiable, Hashable {
    let date: String
    var games: [GameJson]
    var id: String { date }
}
