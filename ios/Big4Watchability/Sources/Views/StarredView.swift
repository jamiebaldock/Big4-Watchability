import SwiftUI

// Swift mirror of StarredScreen.kt - purely local, no network call, since
// StarredGamesStore already holds full game snapshots.
struct StarredView: View {
    @ObservedObject private var store = StarredGamesStore.shared
    @ObservedObject private var weightsStore = RubricWeightsStore.shared
    @ObservedObject private var mlbWeightsStore = MlbRubricWeightsStore.shared
    @ObservedObject private var nflWeightsStore = NflRubricWeightsStore.shared
    @ObservedObject private var nhlWeightsStore = NhlRubricWeightsStore.shared
    @AppStorage(AppSettingsKeys.showNumericScore) private var showNumericScore = true

    var body: some View {
        NavigationStack {
            if store.games.isEmpty {
                EmptyStateView(title: "Star a game to find it here", systemImage: "star")
                    .navigationTitle("Starred")
            } else {
                List {
                    ForEach(store.games) { game in
                        StarredRow(
                            game: game,
                            showNumericScore: showNumericScore,
                            scoreAndTier: game.effectiveScoreAndTier(
                                nba: weightsStore.weights(for: LeagueGroup(espnLeague: game.lg)),
                                mlb: mlbWeightsStore.weights,
                                nfl: nflWeightsStore.weights,
                                nhl: nhlWeightsStore.weights
                            )
                        )
                        .swipeActions {
                            Button("Unstar", role: .destructive) {
                                store.toggle(game)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .navigationTitle("Starred")
            }
        }
    }
}

private struct StarredRow: View {
    let game: GameJson
    let showNumericScore: Bool
    let scoreAndTier: (score: Int, tier: WatchabilityTier)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(game.al ?? game.a) @ \(game.hl ?? game.h)")
                    .font(.headline)
                Spacer()
                if game.scoreVisible, let scoreAndTier {
                    ScoreBadge(score: scoreAndTier.score, tier: scoreAndTier.tier, showNumber: showNumericScore)
                }
            }
            Text(game.hook)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    StarredView()
}
