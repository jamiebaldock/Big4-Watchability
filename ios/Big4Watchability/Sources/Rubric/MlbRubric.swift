import Foundation

// Swift port of backend/src/mlbRubric.ts - bracket boundaries and point
// values kept bit-for-bit identical to that file. MLB has its own
// independent point scale and tier cutoffs (tierForMlbScore below), NOT
// normalized to basketball's 85/65/45 (James's explicit call - see that
// file's own comment).
enum MlbRubric {
    // Real qualification rates (2,478-game 2025 sample): m=1 in 29.3% of
    // games, m<=2 in 46.3%, m<=3 in 59.0%, m>=8 (blowout) in 9.4%.
    static func marginPoints(_ margin: Int) -> Int {
        let m = abs(margin)
        if m == 1 { return 20 }
        if m == 2 { return 15 }
        if m <= 5 { return 9 }
        if m <= 7 { return 4 }
        return 0
    }

    static func walkOffPoints(_ walkOff: Bool) -> Int {
        walkOff ? 25 : 0
    }

    static func comebackPoints(_ largestDeficitOvercome: Int) -> Int {
        if largestDeficitOvercome >= 6 { return 18 }
        if largestDeficitOvercome >= 4 { return 12 }
        if largestDeficitOvercome >= 2 { return 6 }
        return 0
    }

    static func extraInningsPoints(_ extraInningsCount: Int) -> Int {
        if extraInningsCount >= 2 { return 10 }
        if extraInningsCount >= 1 { return 5 }
        return 0
    }

    static func totalRunsPoints(_ totalRuns: Int) -> Int {
        if totalRuns >= 18 { return 10 }
        if totalRuns >= 15 { return 6 }
        if totalRuns >= 10 { return 3 }
        return 0
    }

    static func combinedHomeRunsPoints(_ combinedHomeRuns: Int) -> Int {
        if combinedHomeRuns >= 5 { return 6 }
        if combinedHomeRuns >= 3 { return 3 }
        return 0
    }

    static func starHomeRunPoints(_ maxHomeRunsByPlayer: Int) -> Int {
        if maxHomeRunsByPlayer >= 3 { return 12 }
        if maxHomeRunsByPlayer >= 2 { return 5 }
        return 0
    }

    // Each tier implies the one below it - takes the highest bracket that
    // applies, not a sum.
    static func pitchingDominancePoints(teamBlanked: Bool, noHitter: Bool, perfectGame: Bool) -> Int {
        if perfectGame { return 30 }
        if noHitter { return 20 }
        if teamBlanked { return 8 }
        return 0
    }

    static func blownSavePoints(_ blownSave: Bool) -> Int {
        blownSave ? 6 : 0
    }

    static func errorsPoints(_ combinedErrors: Int) -> Int {
        combinedErrors >= 3 ? 4 : 0
    }
}

struct MlbScoreBreakdown {
    let margin: Int
    let walkOff: Int
    let comeback: Int
    let extraInnings: Int
    let totalRuns: Int
    let combinedHomeRuns: Int
    let starHomeRun: Int
    let pitchingDominance: Int
    let blownSave: Int
    let errors: Int
    let stakes: Int

    func total(weights: MlbRubricWeights) -> Int {
        let weighted =
            Double(margin) * weights.margin +
            Double(walkOff) * weights.walkOff +
            Double(comeback) * weights.comeback +
            Double(extraInnings) * weights.extraInnings +
            Double(totalRuns) * weights.totalRuns +
            Double(combinedHomeRuns) * weights.combinedHomeRuns +
            Double(starHomeRun) * weights.starHomeRun +
            Double(pitchingDominance) * weights.pitchingDominance +
            Double(blownSave) * weights.blownSave +
            Double(errors) * weights.errors +
            Double(stakes) * weights.stakes
        return Int(weighted.rounded())
    }
}

// MLB's own independent scale, checked against the real 2025 sample's
// actual score distribution (stakes excluded): instant_classic at 4.9% of
// real games, worth_your_time at 19.4%, solid at 51.1%.
func tierForMlbScore(_ score: Int) -> WatchabilityTier {
    if score >= 60 { return .instantClassic }
    if score >= 35 { return .worthYourTime }
    if score >= 20 { return .solid }
    return .skippable
}

extension GameJson {
    var mlbBreakdown: MlbScoreBreakdown? {
        guard let inputs = mlbInputs else { return nil }
        return MlbScoreBreakdown(
            margin: MlbRubric.marginPoints(inputs.finalMargin),
            walkOff: MlbRubric.walkOffPoints(inputs.walkOff),
            comeback: MlbRubric.comebackPoints(inputs.largestDeficitOvercome),
            extraInnings: MlbRubric.extraInningsPoints(inputs.extraInningsCount),
            totalRuns: MlbRubric.totalRunsPoints(inputs.totalRuns),
            combinedHomeRuns: MlbRubric.combinedHomeRunsPoints(inputs.combinedHomeRuns),
            starHomeRun: MlbRubric.starHomeRunPoints(inputs.maxHomeRunsByPlayer),
            pitchingDominance: MlbRubric.pitchingDominancePoints(
                teamBlanked: inputs.teamBlanked,
                noHitter: inputs.noHitter,
                perfectGame: inputs.perfectGame
            ),
            blownSave: MlbRubric.blownSavePoints(inputs.blownSave),
            errors: MlbRubric.errorsPoints(inputs.combinedErrors),
            stakes: Rubric.stakesPoints(sk)
        )
    }

    /// Client-recomputed MLB score using user rubric weights - nil if this
    /// game has no mlbInputs (i.e. it isn't an MLB game), matching the
    /// backend's own guard.
    func effectiveMlbScore(weights: MlbRubricWeights) -> Int? {
        mlbBreakdown?.total(weights: weights)
    }

    func effectiveMlbTier(weights: MlbRubricWeights) -> WatchabilityTier? {
        guard let score = effectiveMlbScore(weights: weights) else { return nil }
        return tierForMlbScore(score)
    }
}
