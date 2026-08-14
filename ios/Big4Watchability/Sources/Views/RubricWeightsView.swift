import SwiftUI

// Swift mirror of RubricWeightsScreen.kt - all 5 leagues now have sliders,
// each sport's own weight shape (see Rubric.swift/MlbRubric.swift/
// NflRubric.swift/NhlRubric.swift).
struct RubricWeightsView: View {
    @ObservedObject private var store = RubricWeightsStore.shared
    @ObservedObject private var mlbStore = MlbRubricWeightsStore.shared
    @ObservedObject private var nflStore = NflRubricWeightsStore.shared
    @ObservedObject private var nhlStore = NhlRubricWeightsStore.shared
    @State private var league: LeagueGroup = .nba

    var body: some View {
        NavigationStack {
            List {
                Picker("League", selection: $league) {
                    Text("NBA").tag(LeagueGroup.nba)
                    Text("WNBA").tag(LeagueGroup.wnba)
                    Text("MLB").tag(LeagueGroup.mlb)
                    Text("NFL").tag(LeagueGroup.nfl)
                    Text("NHL").tag(LeagueGroup.nhl)
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                switch league {
                case .mlb: mlbSliders
                case .nfl: nflSliders
                case .nhl: nhlSliders
                default: basketballSliders
                }

                Section {
                    Button("Reset to defaults", role: .destructive) {
                        switch league {
                        case .mlb: mlbStore.setWeights(MlbRubricWeights())
                        case .nfl: nflStore.setWeights(NflRubricWeights())
                        case .nhl: nhlStore.setWeights(NhlRubricWeights())
                        default: store.setWeights(RubricWeights(), for: league)
                        }
                    }
                }
            }
            .navigationTitle("Rubric Weights")
        }
    }

    @ViewBuilder
    private var basketballSliders: some View {
        Section {
            weightSlider("Margin", keyPath: \.margin)
            weightSlider("Clutch", keyPath: \.clutch)
            weightSlider("Buzzer beater", keyPath: \.buzzerBeater)
            weightSlider("Comeback", keyPath: \.comeback)
            weightSlider("Lead changes", keyPath: \.leadChanges)
            weightSlider("Overtime", keyPath: \.overtime)
            weightSlider("Star performance", keyPath: \.starPerformance)
            weightSlider("Stakes", keyPath: \.stakes)
        } footer: {
            Text("Each category's contribution to the watchability score, from 0x (ignored) to 2x (doubled). Defaults to 1x.")
        }
    }

    @ViewBuilder
    private var mlbSliders: some View {
        Section {
            mlbWeightSlider("Margin", keyPath: \.margin)
            mlbWeightSlider("Walk-off", keyPath: \.walkOff)
            mlbWeightSlider("Comeback", keyPath: \.comeback)
            mlbWeightSlider("Extra innings", keyPath: \.extraInnings)
            mlbWeightSlider("Total runs", keyPath: \.totalRuns)
            mlbWeightSlider("Combined home runs", keyPath: \.combinedHomeRuns)
            mlbWeightSlider("Star home run", keyPath: \.starHomeRun)
            mlbWeightSlider("Pitching dominance", keyPath: \.pitchingDominance)
            mlbWeightSlider("Blown save", keyPath: \.blownSave)
            mlbWeightSlider("Errors", keyPath: \.errors)
            mlbWeightSlider("Stakes", keyPath: \.stakes)
        } footer: {
            Text("MLB has its own independent point scale and tier cutoffs, not normalized to basketball's.")
        }
    }

    @ViewBuilder
    private var nflSliders: some View {
        Section {
            nflWeightSlider("Margin", keyPath: \.margin)
            nflWeightSlider("Comeback", keyPath: \.comeback)
            nflWeightSlider("Lead changes", keyPath: \.leadChanges)
            nflWeightSlider("Overtime", keyPath: \.overtime)
            nflWeightSlider("Decisive late score", keyPath: \.decisiveScoreLate)
            nflWeightSlider("Turnovers", keyPath: \.turnovers)
            nflWeightSlider("Defensive/ST touchdown", keyPath: \.defensiveOrSpecialTeamsTd)
            nflWeightSlider("Star performance", keyPath: \.star)
            nflWeightSlider("Total points", keyPath: \.totalPoints)
            nflWeightSlider("Stakes", keyPath: \.stakes)
        } footer: {
            Text("NFL has its own independent point scale and tier cutoffs, not normalized to basketball's.")
        }
    }

    @ViewBuilder
    private var nhlSliders: some View {
        Section {
            nhlWeightSlider("Margin", keyPath: \.margin)
            nhlWeightSlider("Comeback", keyPath: \.comeback)
            nhlWeightSlider("Lead changes", keyPath: \.leadChanges)
            nhlWeightSlider("Overtime", keyPath: \.overtime)
            nhlWeightSlider("Decisive late score", keyPath: \.decisiveScoreLate)
            nhlWeightSlider("Power play goals", keyPath: \.powerPlay)
            nhlWeightSlider("Star performance", keyPath: \.star)
            nhlWeightSlider("Shutout", keyPath: \.shutout)
            nhlWeightSlider("Total goals", keyPath: \.totalGoals)
            nhlWeightSlider("Stakes", keyPath: \.stakes)
        } footer: {
            Text("NHL has its own independent point scale and tier cutoffs, not normalized to basketball's.")
        }
    }

    private func weightSlider(_ label: String, keyPath: WritableKeyPath<RubricWeights, Double>) -> some View {
        let binding = Binding<Double>(
            get: { store.weights(for: league)[keyPath: keyPath] },
            set: { newValue in
                var weights = store.weights(for: league)
                weights[keyPath: keyPath] = newValue
                store.setWeights(weights, for: league)
            }
        )
        return sliderRow(label, binding: binding)
    }

    private func mlbWeightSlider(_ label: String, keyPath: WritableKeyPath<MlbRubricWeights, Double>) -> some View {
        let binding = Binding<Double>(
            get: { mlbStore.weights[keyPath: keyPath] },
            set: { newValue in
                var weights = mlbStore.weights
                weights[keyPath: keyPath] = newValue
                mlbStore.setWeights(weights)
            }
        )
        return sliderRow(label, binding: binding)
    }

    private func nflWeightSlider(_ label: String, keyPath: WritableKeyPath<NflRubricWeights, Double>) -> some View {
        let binding = Binding<Double>(
            get: { nflStore.weights[keyPath: keyPath] },
            set: { newValue in
                var weights = nflStore.weights
                weights[keyPath: keyPath] = newValue
                nflStore.setWeights(weights)
            }
        )
        return sliderRow(label, binding: binding)
    }

    private func nhlWeightSlider(_ label: String, keyPath: WritableKeyPath<NhlRubricWeights, Double>) -> some View {
        let binding = Binding<Double>(
            get: { nhlStore.weights[keyPath: keyPath] },
            set: { newValue in
                var weights = nhlStore.weights
                weights[keyPath: keyPath] = newValue
                nhlStore.setWeights(weights)
            }
        )
        return sliderRow(label, binding: binding)
    }

    private func sliderRow(_ label: String, binding: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%.1fx", binding.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: binding, in: RubricWeights.range, step: 0.1)
        }
    }
}

#Preview {
    RubricWeightsView()
}
