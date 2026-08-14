import Foundation

// Mirrors mobile/app/.../data/RubricWeights.kt (NBA/WNBA shape) - 0x-2x
// per-category multipliers, default 1x each.
struct RubricWeights: Codable, Equatable {
    var margin: Double = 1.0
    var clutch: Double = 1.0
    var buzzerBeater: Double = 1.0
    var comeback: Double = 1.0
    var leadChanges: Double = 1.0
    var overtime: Double = 1.0
    var starPerformance: Double = 1.0
    var stakes: Double = 1.0

    static let range: ClosedRange<Double> = 0...2
}

// Swift mirror of RubricSettingsRepository.kt - persists as one JSON blob
// per league group, same pattern as FavoritesStore. NBA and WNBA share the
// same weight shape and key prefix distinguishes them; MLB/NFL/NHL will get
// their own weight shapes (and their own store) once those rubrics are
// ported.
@MainActor
final class RubricWeightsStore: ObservableObject {
    static let shared = RubricWeightsStore()

    @Published var nba: RubricWeights
    @Published var wnba: RubricWeights

    private let defaults: UserDefaults
    private let nbaKey = "rubricWeights.nba"
    private let wnbaKey = "rubricWeights.wnba"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        nba = Self.load(defaults, key: nbaKey) ?? RubricWeights()
        wnba = Self.load(defaults, key: wnbaKey) ?? RubricWeights()
    }

    func weights(for league: LeagueGroup) -> RubricWeights {
        league == .wnba ? wnba : nba
    }

    func setWeights(_ weights: RubricWeights, for league: LeagueGroup) {
        if league == .wnba {
            wnba = weights
            Self.save(defaults, key: wnbaKey, value: weights)
        } else {
            nba = weights
            Self.save(defaults, key: nbaKey, value: weights)
        }
    }

    private static func load(_ defaults: UserDefaults, key: String) -> RubricWeights? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(RubricWeights.self, from: data)
    }

    private static func save(_ defaults: UserDefaults, key: String, value: RubricWeights) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
