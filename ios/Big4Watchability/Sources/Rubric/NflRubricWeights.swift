import Foundation

// Mirrors mobile/app/.../data/NflRubricWeights.kt - 0x-2x per-category
// multipliers, default 1x each.
struct NflRubricWeights: Codable, Equatable {
    var margin: Double = 1.0
    var comeback: Double = 1.0
    var leadChanges: Double = 1.0
    var overtime: Double = 1.0
    var decisiveScoreLate: Double = 1.0
    var turnovers: Double = 1.0
    var defensiveOrSpecialTeamsTd: Double = 1.0
    var star: Double = 1.0
    var totalPoints: Double = 1.0
    var stakes: Double = 1.0
}

// Swift mirror of NflRubricSettingsRepository.kt - persists as one JSON
// blob, same pattern as MlbRubricWeightsStore.
@MainActor
final class NflRubricWeightsStore: ObservableObject {
    static let shared = NflRubricWeightsStore()

    @Published var weights: NflRubricWeights

    private let defaults: UserDefaults
    private let key = "rubricWeights.nfl"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        weights = Self.load(defaults, key: key) ?? NflRubricWeights()
    }

    func setWeights(_ newWeights: NflRubricWeights) {
        weights = newWeights
        Self.save(defaults, key: key, value: newWeights)
    }

    private static func load(_ defaults: UserDefaults, key: String) -> NflRubricWeights? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(NflRubricWeights.self, from: data)
    }

    private static func save(_ defaults: UserDefaults, key: String, value: NflRubricWeights) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
