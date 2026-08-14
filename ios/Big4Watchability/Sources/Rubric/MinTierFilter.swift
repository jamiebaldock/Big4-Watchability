import Foundation

// Swift mirror of MinTierFilter.kt - hides games below a chosen minimum
// tier when the Settings toggle is on. A game with no revealed tier yet
// (upcoming/live, or a league without effectiveScoreAndTier data) is always
// kept, same "?: return true" fallback as the Kotlin filter.
extension WatchabilityTier {
    /// Lower is "more exciting" - matches Tier.kt's enum declaration order
    /// (INSTANT_CLASSIC=0 .. SKIPPABLE=3), used by the min-tier filter's
    /// "keep everything at or above this tier" comparison.
    var sortRank: Int {
        switch self {
        case .instantClassic: return 0
        case .worthYourTime: return 1
        case .solid: return 2
        case .skippable: return 3
        }
    }

    var displayLabel: String {
        switch self {
        case .instantClassic: return "Instant Classic"
        case .worthYourTime: return "Worth Your Time"
        case .solid: return "Solid"
        case .skippable: return "Skippable"
        }
    }
}

extension Array where Element == GameJson {
    func filteredByMinTier(
        enabled: Bool,
        minTier: WatchabilityTier,
        nba: (GameJson) -> RubricWeights,
        mlb: MlbRubricWeights,
        nfl: NflRubricWeights,
        nhl: NhlRubricWeights
    ) -> [GameJson] {
        guard enabled else { return self }
        return filter { game in
            guard let tier = game.effectiveScoreAndTier(nba: nba(game), mlb: mlb, nfl: nfl, nhl: nhl)?.tier else { return true }
            return tier.sortRank <= minTier.sortRank
        }
    }
}
