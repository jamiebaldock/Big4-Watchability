import SwiftUI

// Swift mirror of StarredScreen.kt - purely local, no network call, since
// StarredGamesStore already holds full game snapshots.
struct StarredView: View {
    @ObservedObject private var store = StarredGamesStore.shared
    @ObservedObject private var weightsStore = RubricWeightsStore.shared
    @ObservedObject private var mlbWeightsStore = MlbRubricWeightsStore.shared
    @ObservedObject private var nflWeightsStore = NflRubricWeightsStore.shared
    @ObservedObject private var nhlWeightsStore = NhlRubricWeightsStore.shared
    @Environment(\.appTheme) private var theme
    @AppStorage(AppSettingsKeys.showNumericScore) private var showNumericScore = true
    @AppStorage(AppSettingsKeys.wifiOnlyHighlights) private var wifiOnlyHighlights = false
    @AppStorage(AppSettingsKeys.confettiEnabled) private var confettiEnabled = true
    @AppStorage(AppSettingsKeys.minTierFilterEnabled) private var minTierFilterEnabled = false
    @AppStorage(AppSettingsKeys.minTierFilter) private var minTierFilterRawValue = WatchabilityTier.skippable.rawValue
    @AppStorage(AppSettingsKeys.defaultGameDetailTab) private var defaultGameDetailTabRawValue = GameDetailTab.breakdown.rawValue
    @State private var selectedGameForDetail: GameJson?
    @State private var selectedHighlightsVideoId: String?

    private var displayedGames: [GameJson] {
        store.games.filteredByMinTier(
            enabled: minTierFilterEnabled,
            minTier: WatchabilityTier(rawValue: minTierFilterRawValue) ?? .skippable,
            nba: { game in weightsStore.weights(for: LeagueGroup(espnLeague: game.lg)) },
            mlb: mlbWeightsStore.weights,
            nfl: nflWeightsStore.weights,
            nhl: nhlWeightsStore.weights
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.games.isEmpty {
                    EmptyStateView(title: "Star a game to find it here", systemImage: "star")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(theme.backgroundBase)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(displayedGames) { game in
                                GameCardView(
                                    game: game,
                                    showNumericScore: showNumericScore,
                                    scoreAndTier: game.effectiveScoreAndTier(
                                        nba: weightsStore.weights(for: LeagueGroup(espnLeague: game.lg)),
                                        mlb: mlbWeightsStore.weights,
                                        nfl: nflWeightsStore.weights,
                                        nhl: nhlWeightsStore.weights
                                    ),
                                    confettiEnabled: confettiEnabled,
                                    isStarred: true,
                                    onToggleStar: { store.toggle(game) },
                                    showDate: true,
                                    onTap: { selectedGameForDetail = game },
                                    onWatchHighlights: { selectedHighlightsVideoId = $0 }
                                )
                            }
                        }
                        .padding(16)
                    }
                    .background(theme.backgroundBase)
                }
            }
            .navigationTitle("Starred")
            .toolbarBackground(theme.backgroundBase, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .fullScreenCover(isPresented: Binding(
                get: { selectedHighlightsVideoId != nil },
                set: { if !$0 { selectedHighlightsVideoId = nil } }
            )) {
                if let videoId = selectedHighlightsVideoId {
                    HighlightsPlayerView(videoId: videoId, wifiOnlyEnabled: wifiOnlyHighlights)
                }
            }
            .sheet(item: $selectedGameForDetail) { game in
                GameDetailView(
                    game: game,
                    nbaWeights: weightsStore.weights(for: LeagueGroup(espnLeague: game.lg)),
                    wnbaWeights: weightsStore.weights(for: .wnba),
                    mlbWeights: mlbWeightsStore.weights,
                    nflWeights: nflWeightsStore.weights,
                    nhlWeights: nhlWeightsStore.weights,
                    defaultTab: GameDetailTab(rawValue: defaultGameDetailTabRawValue) ?? .breakdown,
                    onWatchHighlights: { videoId in
                        selectedGameForDetail = nil
                        selectedHighlightsVideoId = videoId
                    }
                )
            }
        }
    }
}

#Preview {
    StarredView()
}
