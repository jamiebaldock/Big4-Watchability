import SwiftUI

// Unlike every other tab, History deliberately shows final scores - there's
// nothing left to spoil for a game the user is intentionally browsing back
// through (see GameJson.awayScore/homeScore's doc comment).
struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @ObservedObject private var appSettings = AppSettingsStore.shared
    @ObservedObject private var weightsStore = RubricWeightsStore.shared
    @ObservedObject private var mlbWeightsStore = MlbRubricWeightsStore.shared
    @ObservedObject private var nflWeightsStore = NflRubricWeightsStore.shared
    @ObservedObject private var nhlWeightsStore = NhlRubricWeightsStore.shared
    @Environment(\.appTheme) private var theme
    @AppStorage(AppSettingsKeys.showNumericScore) private var showNumericScore = true
    @State private var selectedGameForDetail: GameJson?
    @State private var selectedHighlightsVideoId: String?
    @AppStorage(AppSettingsKeys.wifiOnlyHighlights) private var wifiOnlyHighlights = false
    @AppStorage(AppSettingsKeys.confettiEnabled) private var confettiEnabled = true
    @AppStorage(AppSettingsKeys.minTierFilterEnabled) private var minTierFilterEnabled = false
    @AppStorage(AppSettingsKeys.minTierFilter) private var minTierFilterRawValue = WatchabilityTier.skippable.rawValue
    @AppStorage(AppSettingsKeys.defaultGameDetailTab) private var defaultGameDetailTabRawValue = GameDetailTab.breakdown.rawValue

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("History")
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("League", selection: leagueSelectionBinding) {
                            Text("ALL").tag("all")
                            ForEach(LeagueGroup.allCases) { league in
                                Text(league.rawValue.uppercased()).tag(league.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .task { await viewModel.load(allLeagues: appSettings.isAllLeaguesSelected) }
                .onChange(of: viewModel.leagueGroup) { _ in
                    Task { await viewModel.load(allLeagues: appSettings.isAllLeaguesSelected) }
                }
                .onChange(of: appSettings.isAllLeaguesSelected) { _ in
                    Task { await viewModel.load(allLeagues: appSettings.isAllLeaguesSelected) }
                }
                .refreshable { await viewModel.load(allLeagues: appSettings.isAllLeaguesSelected) }
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

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.games.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.backgroundBase)
        } else if let message = viewModel.errorMessage {
            EmptyStateView(title: message, systemImage: "wifi.slash")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.backgroundBase)
        } else if viewModel.games.isEmpty {
            EmptyStateView(title: "No watchable games yet this season", systemImage: "clock.arrow.circlepath")
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

    private var displayedGames: [GameJson] {
        viewModel.games.filteredByMinTier(
            enabled: minTierFilterEnabled,
            minTier: WatchabilityTier(rawValue: minTierFilterRawValue) ?? .skippable,
            nba: { game in weightsStore.weights(for: LeagueGroup(espnLeague: game.lg)) },
            mlb: mlbWeightsStore.weights,
            nfl: nflWeightsStore.weights,
            nhl: nhlWeightsStore.weights
        )
    }

    // "ALL" plus each LeagueGroup's rawValue as the Picker's tag space -
    // reading/writing through appSettings.isAllLeaguesSelected and
    // viewModel.leagueGroup together so one segmented control drives both.
    private var leagueSelectionBinding: Binding<String> {
        Binding(
            get: { appSettings.isAllLeaguesSelected ? "all" : viewModel.leagueGroup.rawValue },
            set: { newValue in
                if newValue == "all" {
                    appSettings.isAllLeaguesSelected = true
                } else if let league = LeagueGroup(rawValue: newValue) {
                    appSettings.isAllLeaguesSelected = false
                    viewModel.leagueGroup = league
                }
            }
        )
    }
}

#Preview {
    HistoryView()
}
