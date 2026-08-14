import Foundation

// Mirrors mobile/app/.../data/Team.kt's FavoritePlayer - a snapshot (not just
// an id) so favorites render without needing a re-fetch, same reasoning as
// FavoritesRepository.kt on Android.
struct FavoritePlayer: Codable, Identifiable, Hashable {
    var id: String { "\(name)-\(team)" }
    let name: String
    let team: String
    let leagueGroup: LeagueGroup?
    let headshot: String?
}
