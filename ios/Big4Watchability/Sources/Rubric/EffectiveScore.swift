import Foundation

// Single choke point for "what score/tier should this game show," now that
// all 5 leagues have a ported rubric - every screen that displays a score
// (GamesView, HistoryView, ...) should go through this rather than
// re-deriving the per-league switch itself.
extension GameJson {
    func effectiveScoreAndTier(
        nba: RubricWeights,
        mlb: MlbRubricWeights,
        nfl: NflRubricWeights,
        nhl: NhlRubricWeights
    ) -> (score: Int, tier: WatchabilityTier)? {
        switch lg {
        case .nba, .wnba:
            let score = effectiveScore(weights: nba)
            return (score, effectiveTier(weights: nba))
        case .mlb:
            guard let score = effectiveMlbScore(weights: mlb), let tier = effectiveMlbTier(weights: mlb) else { return nil }
            return (score, tier)
        case .nfl:
            guard let score = effectiveNflScore(weights: nfl), let tier = effectiveNflTier(weights: nfl) else { return nil }
            return (score, tier)
        case .nhl:
            guard let score = effectiveNhlScore(weights: nhl), let tier = effectiveNhlTier(weights: nhl) else { return nil }
            return (score, tier)
        case .summer:
            guard let score else { return nil }
            return (score, WatchabilityTier.forScore(score))
        }
    }
}
