import Foundation

// Storage wrapper around TeamJson - the API's TeamJson has no leagueGroup
// field (it's always fetched within a leagueGroup-scoped request), but a
// persisted favorite needs to remember which league it came from, same as
// Kotlin's Team.leagueGroup client-only addition.
struct FavoriteTeam: Codable, Identifiable, Hashable {
    var id: String { team.id }
    let team: TeamJson
    let leagueGroup: LeagueGroup
}
