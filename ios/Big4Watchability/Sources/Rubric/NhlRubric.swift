import Foundation

// Swift port of backend/src/nhlRubric.ts - bracket boundaries and point
// values kept bit-for-bit identical to that file. NHL has its own
// independent point scale and tier cutoffs (tierForNhlScore below), same
// precedent as MLB/NFL rather than basketball's 85/65/45.
enum NhlRubric {
    static func marginPoints(_ margin: Int) -> Int {
        let m = abs(margin)
        if m <= 1 { return 20 }
        if m <= 2 { return 14 }
        if m <= 3 { return 8 }
        if m <= 4 { return 4 }
        return 0
    }

    static func comebackPoints(_ largestDeficitOvercome: Int) -> Int {
        if largestDeficitOvercome >= 3 { return 18 }
        if largestDeficitOvercome >= 2 { return 12 }
        if largestDeficitOvercome >= 1 { return 6 }
        return 0
    }

    static func leadChangePoints(_ leadChanges: Int) -> Int {
        if leadChanges >= 3 { return 12 }
        if leadChanges >= 2 { return 6 }
        if leadChanges >= 1 { return 3 }
        return 0
    }

    // A real 3-on-3 overtime winner is treated as more dramatic than a
    // shootout finish (hockey's own two-tier "extra time" structure).
    static func overtimePoints(overtimePeriods: Int, wentToShootout: Bool) -> Int {
        if overtimePeriods < 1 { return 0 }
        return wentToShootout ? 8 : 15
    }

    static func decisiveScoreLatePoints(_ decisiveScoreLate: Bool) -> Int {
        decisiveScoreLate ? 15 : 0
    }

    static func powerPlayPoints(_ combinedPowerPlayGoals: Int) -> Int {
        if combinedPowerPlayGoals >= 3 { return 8 }
        if combinedPowerPlayGoals >= 2 { return 4 }
        return 0
    }

    // Takes the best-qualifying tier across two independent paths (a
    // skater's hat trick, or a goalie's big save total), not a sum. A
    // skater's 2-goal game is deliberately excluded (50.1% of real games -
    // too common on its own to signal a standout performance).
    static func starPoints(maxGoalsByPlayer: Int, maxGoalieSaves: Int) -> Int {
        if maxGoalsByPlayer >= 3 || maxGoalieSaves >= 40 { return 15 }
        if maxGoalieSaves >= 35 { return 8 }
        if maxGoalieSaves >= 30 { return 4 }
        return 0
    }

    static func shutoutPoints(_ teamShutout: Bool) -> Int {
        teamShutout ? 12 : 0
    }

    static func totalGoalsBonus(_ totalGoals: Int) -> Int {
        if totalGoals >= 9 { return 8 }
        if totalGoals >= 7 { return 4 }
        return 0
    }
}

struct NhlScoreBreakdown {
    let margin: Int
    let comeback: Int
    let leadChanges: Int
    let overtime: Int
    let decisiveScoreLate: Int
    let powerPlay: Int
    let star: Int
    let shutout: Int
    let totalGoals: Int
    let stakes: Int

    func total(weights: NhlRubricWeights) -> Int {
        let weighted =
            Double(margin) * weights.margin +
            Double(comeback) * weights.comeback +
            Double(leadChanges) * weights.leadChanges +
            Double(overtime) * weights.overtime +
            Double(decisiveScoreLate) * weights.decisiveScoreLate +
            Double(powerPlay) * weights.powerPlay +
            Double(star) * weights.star +
            Double(shutout) * weights.shutout +
            Double(totalGoals) * weights.totalGoals +
            Double(stakes) * weights.stakes
        return Int(weighted.rounded())
    }
}

// NHL's own independent scale, checked against the real 2025-26 sample's
// actual score distribution (stakes excluded): instant_classic at 4.0% of
// real games, worth_your_time at 16.2%, solid at 53.7%.
func tierForNhlScore(_ score: Int) -> WatchabilityTier {
    if score >= 78 { return .instantClassic }
    if score >= 56 { return .worthYourTime }
    if score >= 29 { return .solid }
    return .skippable
}

extension GameJson {
    var nhlBreakdown: NhlScoreBreakdown? {
        guard let inputs = nhlInputs else { return nil }
        return NhlScoreBreakdown(
            margin: NhlRubric.marginPoints(inputs.finalMargin),
            comeback: NhlRubric.comebackPoints(inputs.largestDeficitOvercome),
            leadChanges: NhlRubric.leadChangePoints(inputs.leadChanges),
            overtime: NhlRubric.overtimePoints(overtimePeriods: inputs.overtimePeriods, wentToShootout: inputs.wentToShootout),
            decisiveScoreLate: NhlRubric.decisiveScoreLatePoints(inputs.decisiveScoreLate),
            powerPlay: NhlRubric.powerPlayPoints(inputs.combinedPowerPlayGoals),
            star: NhlRubric.starPoints(maxGoalsByPlayer: inputs.maxGoalsByPlayer, maxGoalieSaves: inputs.maxGoalieSaves),
            shutout: NhlRubric.shutoutPoints(inputs.teamShutout),
            totalGoals: NhlRubric.totalGoalsBonus(inputs.totalGoals),
            stakes: Rubric.stakesPoints(sk)
        )
    }

    /// Client-recomputed NHL score using user rubric weights - nil if this
    /// game has no nhlInputs (i.e. it isn't an NHL game).
    func effectiveNhlScore(weights: NhlRubricWeights) -> Int? {
        nhlBreakdown?.total(weights: weights)
    }

    func effectiveNhlTier(weights: NhlRubricWeights) -> WatchabilityTier? {
        guard let score = effectiveNhlScore(weights: weights) else { return nil }
        return tierForNhlScore(score)
    }
}
