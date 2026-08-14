import Foundation

// Mirrors mobile/app/.../data/MlbRubricWeights.kt - 0x-2x per-category
// multipliers, default 1x each.
struct MlbRubricWeights: Codable, Equatable {
    var margin: Double = 1.0
    var walkOff: Double = 1.0
    var comeback: Double = 1.0
    var extraInnings: Double = 1.0
    var totalRuns: Double = 1.0
    var combinedHomeRuns: Double = 1.0
    var starHomeRun: Double = 1.0
    var pitchingDominance: Double = 1.0
    var blownSave: Double = 1.0
    var errors: Double = 1.0
    var stakes: Double = 1.0
}

// Swift mirror of MlbRubricSettingsRepository.kt - persists as one JSON
// blob, same pattern as RubricWeightsStore but MLB-only (separate store,
// same as Android's separate repo class per league).
@MainActor
final class MlbRubricWeightsStore: ObservableObject {
    static let shared = MlbRubricWeightsStore()

    @Published var weights: MlbRubricWeights

    private let defaults: UserDefaults
    private let key = "rubricWeights.mlb"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        weights = Self.load(defaults, key: key) ?? MlbRubricWeights()
    }

    func setWeights(_ newWeights: MlbRubricWeights) {
        weights = newWeights
        Self.save(defaults, key: key, value: newWeights)
    }

    private static func load(_ defaults: UserDefaults, key: String) -> MlbRubricWeights? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(MlbRubricWeights.self, from: data)
    }

    private static func save(_ defaults: UserDefaults, key: String, value: MlbRubricWeights) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
