import Foundation

// Swift mirror of mobile/app/.../data/FavoritesRepository.kt - UserDefaults
// standing in for Jetpack DataStore, same "one JSON-encoded list under one
// key" pattern (full snapshots persisted, not just ids, so favorites render
// without a re-fetch).
@MainActor
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    @Published private(set) var teams: [FavoriteTeam] = []
    @Published private(set) var players: [FavoritePlayer] = []

    private let defaults: UserDefaults
    private let teamsKey = "favorites.teams"
    private let playersKey = "favorites.players"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        teams = Self.load(defaults, key: teamsKey) ?? []
        players = Self.load(defaults, key: playersKey) ?? []
    }

    func isFavorite(team: TeamJson) -> Bool {
        teams.contains { $0.team.id == team.id }
    }

    func toggle(team: TeamJson, leagueGroup: LeagueGroup) {
        if let index = teams.firstIndex(where: { $0.team.id == team.id }) {
            teams.remove(at: index)
        } else {
            teams.append(FavoriteTeam(team: team, leagueGroup: leagueGroup))
        }
        Self.save(defaults, key: teamsKey, value: teams)
    }

    func isFavorite(player: PlayerJson, team: String) -> Bool {
        players.contains { $0.name == player.name && $0.team == team }
    }

    func toggle(player: PlayerJson, team: String, leagueGroup: LeagueGroup) {
        if let index = players.firstIndex(where: { $0.name == player.name && $0.team == team }) {
            players.remove(at: index)
        } else {
            players.append(FavoritePlayer(name: player.name, team: team, leagueGroup: leagueGroup, headshot: player.headshot))
        }
        Self.save(defaults, key: playersKey, value: players)
    }

    private static func load<T: Decodable>(_ defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ defaults: UserDefaults, key: String, value: T) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
