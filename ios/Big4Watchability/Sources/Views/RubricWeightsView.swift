import SwiftUI

// Swift mirror of RubricWeightsScreen.kt - NBA/WNBA sliders only so far
// (MLB/NFL/NHL rubrics aren't ported yet, see Rubric.swift).
struct RubricWeightsView: View {
    @ObservedObject private var store = RubricWeightsStore.shared
    @State private var league: LeagueGroup = .nba

    var body: some View {
        NavigationStack {
            List {
                Picker("League", selection: $league) {
                    Text("NBA").tag(LeagueGroup.nba)
                    Text("WNBA").tag(LeagueGroup.wnba)
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

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

                Section {
                    Button("Reset to defaults", role: .destructive) {
                        store.setWeights(RubricWeights(), for: league)
                    }
                }

                Section {
                    Text("MLB, NFL, and NHL weight sliders are coming in a later build.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Rubric Weights")
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
        return VStack(alignment: .leading, spacing: 2) {
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
