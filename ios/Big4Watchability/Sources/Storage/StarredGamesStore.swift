import Foundation

// Swift mirror of mobile/app/.../data/StarredGamesRepository.kt - full Game
// snapshots (not just ids) persisted as one JSON list, same reasoning as
// FavoritesStore: renders without a re-fetch, and there's no "look up an
// arbitrary game by id" endpoint to re-fetch from anyway.
@MainActor
final class StarredGamesStore: ObservableObject {
    static let shared = StarredGamesStore()

    @Published private(set) var games: [GameJson] = []

    private let defaults: UserDefaults
    private let key = "starred.games"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        games = Self.load(defaults, key: key) ?? []
    }

    func isStarred(_ game: GameJson) -> Bool {
        games.contains { $0.id == game.id }
    }

    func toggle(_ game: GameJson) {
        if let index = games.firstIndex(where: { $0.id == game.id }) {
            games.remove(at: index)
        } else {
            games.append(game)
        }
        Self.save(defaults, key: key, value: games)
    }

    private static func load(_ defaults: UserDefaults, key: String) -> [GameJson]? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([GameJson].self, from: data)
    }

    private static func save(_ defaults: UserDefaults, key: String, value: [GameJson]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
