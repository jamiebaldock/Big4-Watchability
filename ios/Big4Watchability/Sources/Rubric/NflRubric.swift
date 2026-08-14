import Foundation

// Swift port of backend/src/nflRubric.ts - bracket boundaries and point
// values kept bit-for-bit identical to that file. NFL has its own
// independent point scale and tier cutoffs (tierForNflScore below),
// matching MLB's precedent rather than basketball's 85/65/45.
enum NflRubric {
    static func marginPoints(_ margin: Int) -> Int {
        let m = abs(margin)
        if m <= 3 { return 25 }
        if m <= 8 { return 18 }
        if m <= 16 { return 10 }
        if m <= 24 { return 5 }
        return 0
    }

    static func comebackPoints(_ largestDeficitOvercome: Int) -> Int {
        if largestDeficitOvercome >= 14 { return 18 }
        if largestDeficitOvercome >= 10 { return 12 }
        if largestDeficitOvercome >= 7 { return 6 }
        return 0
    }

    static func leadChangePoints(_ leadChanges: Int) -> Int {
        if leadChanges >= 4 { return 12 }
        if leadChanges >= 2 { return 6 }
        if leadChanges >= 1 { return 3 }
        return 0
    }

    // Flat bonus (not tiered by OT period count like basketball) - a second
    // NFL overtime is vanishingly rare under current rules.
    static func overtimePoints(_ overtimePeriods: Int) -> Int {
        overtimePeriods >= 1 ? 12 : 0
    }

    static func decisiveScoreLatePoints(_ decisiveScoreLate: Bool) -> Int {
        decisiveScoreLate ? 15 : 0
    }

    static func turnoverPoints(_ combinedTurnovers: Int) -> Int {
        if combinedTurnovers >= 5 { return 8 }
        if combinedTurnovers >= 3 { return 4 }
        return 0
    }

    static func defensiveOrSpecialTeamsTdPoints(_ defensiveOrSpecialTeamsTd: Bool) -> Int {
        defensiveOrSpecialTeamsTd ? 10 : 0
    }

    // Takes the best-qualifying tier across three independent paths
    // (passing, rushing, or total touchdowns), not a sum.
    static func starPoints(maxPassingYards: Int, maxRushingYards: Int, maxTotalTdsByPlayer: Int) -> Int {
        if maxPassingYards >= 400 || maxRushingYards >= 175 || maxTotalTdsByPlayer >= 5 { return 15 }
        if maxPassingYards >= 350 || maxRushingYards >= 150 || maxTotalTdsByPlayer >= 4 { return 8 }
        if maxPassingYards >= 300 || maxRushingYards >= 125 { return 4 }
        return 0
    }

    static func totalPointsBonus(_ totalPoints: Int) -> Int {
        if totalPoints >= 65 { return 8 }
        if totalPoints >= 56 { return 4 }
        return 0
    }
}

struct NflScoreBreakdown {
    let margin: Int
    let comeback: Int
    let leadChanges: Int
    let overtime: Int
    let decisiveScoreLate: Int
    let turnovers: Int
    let defensiveOrSpecialTeamsTd: Int
    let star: Int
    let totalPoints: Int
    let stakes: Int

    func total(weights: NflRubricWeights) -> Int {
        let weighted =
            Double(margin) * weights.margin +
            Double(comeback) * weights.comeback +
            Double(leadChanges) * weights.leadChanges +
            Double(overtime) * weights.overtime +
            Double(decisiveScoreLate) * weights.decisiveScoreLate +
            Double(turnovers) * weights.turnovers +
            Double(defensiveOrSpecialTeamsTd) * weights.defensiveOrSpecialTeamsTd +
            Double(star) * weights.star +
            Double(totalPoints) * weights.totalPoints +
            Double(stakes) * weights.stakes
        return Int(weighted.rounded())
    }
}

// NFL's own independent scale, checked against the real 2025 sample's
// actual score distribution (stakes excluded): instant_classic at 5.9% of
// real games, worth_your_time at 18.2%, solid at 51.0%.
func tierForNflScore(_ score: Int) -> WatchabilityTier {
    if score >= 75 { return .instantClassic }
    if score >= 54 { return .worthYourTime }
    if score >= 28 { return .solid }
    return .skippable
}

extension GameJson {
    var nflBreakdown: NflScoreBreakdown? {
        guard let inputs = nflInputs else { return nil }
        return NflScoreBreakdown(
            margin: NflRubric.marginPoints(inputs.finalMargin),
            comeback: NflRubric.comebackPoints(inputs.largestDeficitOvercome),
            leadChanges: NflRubric.leadChangePoints(inputs.leadChanges),
            overtime: NflRubric.overtimePoints(inputs.overtimePeriods),
            decisiveScoreLate: NflRubric.decisiveScoreLatePoints(inputs.decisiveScoreLate),
            turnovers: NflRubric.turnoverPoints(inputs.combinedTurnovers),
            defensiveOrSpecialTeamsTd: NflRubric.defensiveOrSpecialTeamsTdPoints(inputs.defensiveOrSpecialTeamsTd),
            star: NflRubric.starPoints(
                maxPassingYards: inputs.maxPassingYards,
                maxRushingYards: inputs.maxRushingYards,
                maxTotalTdsByPlayer: inputs.maxTotalTdsByPlayer
            ),
            totalPoints: NflRubric.totalPointsBonus(inputs.totalPoints),
            stakes: Rubric.stakesPoints(sk)
        )
    }

    /// Client-recomputed NFL score using user rubric weights - nil if this
    /// game has no nflInputs (i.e. it isn't an NFL game).
    func effectiveNflScore(weights: NflRubricWeights) -> Int? {
        nflBreakdown?.total(weights: weights)
    }

    func effectiveNflTier(weights: NflRubricWeights) -> WatchabilityTier? {
        guard let score = effectiveNflScore(weights: weights) else { return nil }
        return tierForNflScore(score)
    }
}
