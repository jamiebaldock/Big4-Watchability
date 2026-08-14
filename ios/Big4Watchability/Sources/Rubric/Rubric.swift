import Foundation

// Swift port of backend/src/rubric.ts's NBA/WNBA scoring - bracket
// boundaries and point values must stay bit-for-bit identical to that file
// (the single source of truth; see rubric.ts's own file comment on how the
// per-league brackets were calibrated off real backfilled game
// distributions). MLB/NFL/NHL each have their own rubric file server-side
// and need their own port here later - not done yet.
enum WatchabilityTier: String {
    case instantClassic = "instant_classic"
    case worthYourTime = "worth_your_time"
    case solid = "solid"
    case skippable = "skippable"

    static func forScore(_ score: Int) -> WatchabilityTier {
        if score >= 85 { return .instantClassic }
        if score >= 65 { return .worthYourTime }
        if score >= 45 { return .solid }
        return .skippable
    }
}

enum Rubric {
    static func marginPoints(_ margin: Int, isWnba: Bool) -> Int {
        let m = abs(margin)
        if isWnba {
            if m <= 4 { return 25 }
            if m <= 6 { return 20 }
            if m <= 9 { return 13 }
            if m <= 13 { return 7 }
            if m <= 17 { return 3 }
            return 0
        }
        if m <= 3 { return 25 }
        if m <= 6 { return 20 }
        if m <= 10 { return 13 }
        if m <= 15 { return 7 }
        if m <= 20 { return 3 }
        return 0
    }

    static func clutchPoints(closeInFinalTwoMin: Bool, leadChangeInFinalMin: Bool, decidedOnFinalPossession: Bool) -> Int {
        var pts = 0
        if closeInFinalTwoMin { pts += 8 }
        if leadChangeInFinalMin { pts += 6 }
        if decidedOnFinalPossession { pts += 6 }
        return pts
    }

    static func comebackPoints(_ largestDeficitOvercome: Int, isWnba: Bool) -> Int {
        if isWnba {
            if largestDeficitOvercome >= 17 { return 15 }
            if largestDeficitOvercome >= 14 { return 10 }
            if largestDeficitOvercome >= 9 { return 6 }
            return 0
        }
        if largestDeficitOvercome >= 20 { return 15 }
        if largestDeficitOvercome >= 15 { return 10 }
        if largestDeficitOvercome >= 10 { return 6 }
        return 0
    }

    private static let leadChangesForMaxPointsNba = 20
    private static let leadChangesForMaxPointsWnba = 17

    static func leadChangePoints(_ leadChanges: Int, isWnba: Bool) -> Int {
        let capThreshold = isWnba ? leadChangesForMaxPointsWnba : leadChangesForMaxPointsNba
        return min(10, (leadChanges * 10) / capThreshold)
    }

    static func overtimePoints(_ overtimePeriods: Int) -> Int {
        if overtimePeriods <= 0 { return 0 }
        return overtimePeriods >= 2 ? 10 : 7
    }

    static func starPoints(_ star: StarPerformance?) -> Int {
        switch star {
        case .historic: return 10
        case .great: return 6
        case .good: return 3
        case .none: return 0
        }
    }

    static func stakesPoints(_ stakes: Int?) -> Int {
        guard let stakes else { return 0 }
        return max(0, min(10, stakes))
    }
}

struct ScoreBreakdown {
    let margin: Int
    let clutch: Int
    let buzzerBeater: Int
    let comeback: Int
    let leadChanges: Int
    let overtime: Int
    let star: Int
    let stakes: Int

    // Weighted total - see RubricWeights.swift. No overall cap: the backend
    // rubric explicitly allows the buzzer-beater bonus to push the total
    // over 100.
    func total(weights: RubricWeights) -> Int {
        let weighted =
            Double(margin) * weights.margin +
            Double(clutch) * weights.clutch +
            Double(buzzerBeater) * weights.buzzerBeater +
            Double(comeback) * weights.comeback +
            Double(leadChanges) * weights.leadChanges +
            Double(overtime) * weights.overtime +
            Double(star) * weights.starPerformance +
            Double(stakes) * weights.stakes
        return Int(weighted.rounded())
    }
}

extension GameJson {
    var isWnbaRubric: Bool { lg == .wnba }

    var rawBreakdown: ScoreBreakdown {
        ScoreBreakdown(
            margin: Rubric.marginPoints(m ?? 0, isWnba: isWnbaRubric),
            clutch: Rubric.clutchPoints(closeInFinalTwoMin: c5, leadChangeInFinalMin: lcf, decidedOnFinalPossession: fp),
            buzzerBeater: bz ? 10 : 0,
            comeback: Rubric.comebackPoints(cb ?? 0, isWnba: isWnbaRubric),
            leadChanges: Rubric.leadChangePoints(lc ?? 0, isWnba: isWnbaRubric),
            overtime: Rubric.overtimePoints(ot),
            star: Rubric.starPoints(st),
            stakes: Rubric.stakesPoints(sk)
        )
    }

    /// Client-recomputed score using user rubric weights - only accurate for
    /// NBA/WNBA so far (MLB/NFL/NHL rubrics not ported yet), so callers
    /// should fall back to the server's fixed-1x `score` field for other
    /// leagues.
    func effectiveScore(weights: RubricWeights) -> Int {
        rawBreakdown.total(weights: weights)
    }

    func effectiveTier(weights: RubricWeights) -> WatchabilityTier {
        WatchabilityTier.forScore(effectiveScore(weights: weights))
    }
}
