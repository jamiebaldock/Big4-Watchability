import Foundation

// Swift port of mobile/app/.../data/Rubric.kt's RubricBreakdownEntry +
// rubricBreakdown/mlbRubricBreakdown/nflRubricBreakdown/nhlRubricBreakdown -
// backs the game-detail popup's "why did this score what it scored" tab.
// Reuses the exact same point functions effectiveScore/effectiveTier
// already call, just surfaced individually instead of summed, so this can
// never drift out of sync with the actual total.
struct RubricBreakdownEntry: Identifiable {
    var id: String { label }
    let label: String
    let points: Double
    let maxPoints: Double
}

extension GameJson {
    /// Empty if the outcome isn't revealed yet (same scoreVisible gate as
    /// effectiveScore). Dispatches to MLB's/NFL's/NHL's own dimensions and
    /// labels for those leagues - basketball's fields don't apply to them.
    func rubricBreakdown(
        nba: RubricWeights,
        wnba: RubricWeights,
        mlb: MlbRubricWeights,
        nfl: NflRubricWeights,
        nhl: NhlRubricWeights
    ) -> [RubricBreakdownEntry] {
        guard scoreVisible, score != nil else { return [] }
        switch lg {
        case .mlb: return mlbRubricBreakdownEntries(mlb)
        case .nfl: return nflRubricBreakdownEntries(nfl)
        case .nhl: return nhlRubricBreakdownEntries(nhl)
        case .nba, .wnba, .summer:
            let isWnba = lg == .wnba
            let weights = isWnba ? wnba : nba
            return [
                RubricBreakdownEntry(
                    label: "Margin",
                    points: Double(Rubric.marginPoints(m ?? 0, isWnba: isWnba)) * weights.margin,
                    maxPoints: 25 * weights.margin
                ),
                RubricBreakdownEntry(
                    label: "Clutch finish",
                    points: Double(Rubric.clutchPoints(closeInFinalTwoMin: c5, leadChangeInFinalMin: lcf, decidedOnFinalPossession: fp)) * weights.clutch,
                    maxPoints: 20 * weights.clutch
                ),
                RubricBreakdownEntry(
                    label: "Buzzer-beater",
                    points: Double(bz ? 10 : 0) * weights.buzzerBeater,
                    maxPoints: 10 * weights.buzzerBeater
                ),
                RubricBreakdownEntry(
                    label: "Comeback",
                    points: Double(Rubric.comebackPoints(cb ?? 0, isWnba: isWnba)) * weights.comeback,
                    maxPoints: 15 * weights.comeback
                ),
                RubricBreakdownEntry(
                    label: "Lead changes",
                    points: Double(Rubric.leadChangePoints(lc ?? 0, isWnba: isWnba)) * weights.leadChanges,
                    maxPoints: 10 * weights.leadChanges
                ),
                RubricBreakdownEntry(
                    label: "Overtime",
                    points: Double(Rubric.overtimePoints(ot)) * weights.overtime,
                    maxPoints: 10 * weights.overtime
                ),
                RubricBreakdownEntry(
                    label: "Star performance",
                    points: Double(Rubric.starPoints(st)) * weights.starPerformance,
                    maxPoints: 10 * weights.starPerformance
                ),
                RubricBreakdownEntry(
                    label: "Stakes",
                    points: Double(Rubric.stakesPoints(sk)) * weights.stakes,
                    maxPoints: 10 * weights.stakes
                )
            ]
        }
    }

    private func mlbRubricBreakdownEntries(_ weights: MlbRubricWeights) -> [RubricBreakdownEntry] {
        guard let inputs = mlbInputs else { return [] }
        return [
            RubricBreakdownEntry(label: "Margin", points: Double(MlbRubric.marginPoints(inputs.finalMargin)) * weights.margin, maxPoints: 20 * weights.margin),
            RubricBreakdownEntry(label: "Walk-off", points: Double(MlbRubric.walkOffPoints(inputs.walkOff)) * weights.walkOff, maxPoints: 25 * weights.walkOff),
            RubricBreakdownEntry(label: "Comeback", points: Double(MlbRubric.comebackPoints(inputs.largestDeficitOvercome)) * weights.comeback, maxPoints: 18 * weights.comeback),
            RubricBreakdownEntry(label: "Extra innings", points: Double(MlbRubric.extraInningsPoints(inputs.extraInningsCount)) * weights.extraInnings, maxPoints: 10 * weights.extraInnings),
            RubricBreakdownEntry(label: "Total runs", points: Double(MlbRubric.totalRunsPoints(inputs.totalRuns)) * weights.totalRuns, maxPoints: 10 * weights.totalRuns),
            RubricBreakdownEntry(label: "Combined home runs", points: Double(MlbRubric.combinedHomeRunsPoints(inputs.combinedHomeRuns)) * weights.combinedHomeRuns, maxPoints: 6 * weights.combinedHomeRuns),
            RubricBreakdownEntry(label: "Star home run", points: Double(MlbRubric.starHomeRunPoints(inputs.maxHomeRunsByPlayer)) * weights.starHomeRun, maxPoints: 12 * weights.starHomeRun),
            RubricBreakdownEntry(
                label: "Pitching dominance",
                points: Double(MlbRubric.pitchingDominancePoints(teamBlanked: inputs.teamBlanked, noHitter: inputs.noHitter, perfectGame: inputs.perfectGame)) * weights.pitchingDominance,
                maxPoints: 30 * weights.pitchingDominance
            ),
            RubricBreakdownEntry(label: "Blown save", points: Double(MlbRubric.blownSavePoints(inputs.blownSave)) * weights.blownSave, maxPoints: 6 * weights.blownSave),
            RubricBreakdownEntry(label: "Errors", points: Double(MlbRubric.errorsPoints(inputs.combinedErrors)) * weights.errors, maxPoints: 4 * weights.errors),
            RubricBreakdownEntry(label: "Stakes", points: Double(Rubric.stakesPoints(sk)) * weights.stakes, maxPoints: 10 * weights.stakes)
        ]
    }

    private func nflRubricBreakdownEntries(_ weights: NflRubricWeights) -> [RubricBreakdownEntry] {
        guard let inputs = nflInputs else { return [] }
        return [
            RubricBreakdownEntry(label: "Margin", points: Double(NflRubric.marginPoints(inputs.finalMargin)) * weights.margin, maxPoints: 25 * weights.margin),
            RubricBreakdownEntry(label: "Comeback", points: Double(NflRubric.comebackPoints(inputs.largestDeficitOvercome)) * weights.comeback, maxPoints: 18 * weights.comeback),
            RubricBreakdownEntry(label: "Lead changes", points: Double(NflRubric.leadChangePoints(inputs.leadChanges)) * weights.leadChanges, maxPoints: 12 * weights.leadChanges),
            RubricBreakdownEntry(label: "Overtime", points: Double(NflRubric.overtimePoints(inputs.overtimePeriods)) * weights.overtime, maxPoints: 12 * weights.overtime),
            RubricBreakdownEntry(
                label: "Decisive late score",
                points: Double(NflRubric.decisiveScoreLatePoints(inputs.decisiveScoreLate)) * weights.decisiveScoreLate,
                maxPoints: 15 * weights.decisiveScoreLate
            ),
            RubricBreakdownEntry(label: "Turnovers", points: Double(NflRubric.turnoverPoints(inputs.combinedTurnovers)) * weights.turnovers, maxPoints: 8 * weights.turnovers),
            RubricBreakdownEntry(
                label: "Defensive/special-teams TD",
                points: Double(NflRubric.defensiveOrSpecialTeamsTdPoints(inputs.defensiveOrSpecialTeamsTd)) * weights.defensiveOrSpecialTeamsTd,
                maxPoints: 10 * weights.defensiveOrSpecialTeamsTd
            ),
            RubricBreakdownEntry(
                label: "Star performance",
                points: Double(NflRubric.starPoints(maxPassingYards: inputs.maxPassingYards, maxRushingYards: inputs.maxRushingYards, maxTotalTdsByPlayer: inputs.maxTotalTdsByPlayer)) * weights.star,
                maxPoints: 15 * weights.star
            ),
            RubricBreakdownEntry(label: "Total points", points: Double(NflRubric.totalPointsBonus(inputs.totalPoints)) * weights.totalPoints, maxPoints: 8 * weights.totalPoints),
            RubricBreakdownEntry(label: "Stakes", points: Double(Rubric.stakesPoints(sk)) * weights.stakes, maxPoints: 10 * weights.stakes)
        ]
    }

    private func nhlRubricBreakdownEntries(_ weights: NhlRubricWeights) -> [RubricBreakdownEntry] {
        guard let inputs = nhlInputs else { return [] }
        return [
            RubricBreakdownEntry(label: "Margin", points: Double(NhlRubric.marginPoints(inputs.finalMargin)) * weights.margin, maxPoints: 20 * weights.margin),
            RubricBreakdownEntry(label: "Comeback", points: Double(NhlRubric.comebackPoints(inputs.largestDeficitOvercome)) * weights.comeback, maxPoints: 18 * weights.comeback),
            RubricBreakdownEntry(label: "Lead changes", points: Double(NhlRubric.leadChangePoints(inputs.leadChanges)) * weights.leadChanges, maxPoints: 12 * weights.leadChanges),
            RubricBreakdownEntry(
                label: "Overtime",
                points: Double(NhlRubric.overtimePoints(overtimePeriods: inputs.overtimePeriods, wentToShootout: inputs.wentToShootout)) * weights.overtime,
                maxPoints: 15 * weights.overtime
            ),
            RubricBreakdownEntry(
                label: "Decisive late goal",
                points: Double(NhlRubric.decisiveScoreLatePoints(inputs.decisiveScoreLate)) * weights.decisiveScoreLate,
                maxPoints: 15 * weights.decisiveScoreLate
            ),
            RubricBreakdownEntry(label: "Power play goals", points: Double(NhlRubric.powerPlayPoints(inputs.combinedPowerPlayGoals)) * weights.powerPlay, maxPoints: 8 * weights.powerPlay),
            RubricBreakdownEntry(
                label: "Star performance",
                points: Double(NhlRubric.starPoints(maxGoalsByPlayer: inputs.maxGoalsByPlayer, maxGoalieSaves: inputs.maxGoalieSaves)) * weights.star,
                maxPoints: 15 * weights.star
            ),
            RubricBreakdownEntry(label: "Shutout", points: Double(NhlRubric.shutoutPoints(inputs.teamShutout)) * weights.shutout, maxPoints: 12 * weights.shutout),
            RubricBreakdownEntry(label: "Total goals", points: Double(NhlRubric.totalGoalsBonus(inputs.totalGoals)) * weights.totalGoals, maxPoints: 8 * weights.totalGoals),
            RubricBreakdownEntry(label: "Stakes", points: Double(Rubric.stakesPoints(sk)) * weights.stakes, maxPoints: 10 * weights.stakes)
        ]
    }
}
