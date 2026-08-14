import Foundation

// Mirrors mobile/app/.../data/NhlRubricWeights.kt - 0x-2x per-category
// multipliers, default 1x each.
struct NhlRubricWeights: Codable, Equatable {
    var margin: Double = 1.0
    var comeback: Double = 1.0
    var leadChanges: Double = 1.0
    var overtime: Double = 1.0
    var decisiveScoreLate: Double = 1.0
    var powerPlay: Double = 1.0
    var star: Double = 1.0
    var shutout: Double = 1.0
    var totalGoals: Double = 1.0
    var stakes: Double = 1.0
}

// Swift mirror of NhlRubricSettingsRepository.kt - persists as one JSON
// blob, same pattern as NflRubricWeightsStore.
@MainActor
final class NhlRubricWeightsStore: ObservableObject {
    static let shared = NhlRubricWeightsStore()

    @Published var weights: NhlRubricWeights

    private let defaults: UserDefaults
    private let key = "rubricWeights.nhl"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        weights = Self.load(defaults, key: key) ?? NhlRubricWeights()
    }

    func setWeights(_ newWeights: NhlRubricWeights) {
        weights = newWeights
        Self.save(defaults, key: key, value: newWeights)
    }

    private static func load(_ defaults: UserDefaults, key: String) -> NhlRubricWeights? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(NhlRubricWeights.self, from: data)
    }

    private static func save(_ defaults: UserDefaults, key: String, value: NhlRubricWeights) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
