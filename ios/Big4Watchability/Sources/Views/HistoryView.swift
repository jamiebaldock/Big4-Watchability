import SwiftUI

// Unlike every other tab, History deliberately shows final scores - there's
// nothing left to spoil for a game the user is intentionally browsing back
// through (see GameJson.awayScore/homeScore's doc comment).
struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @ObservedObject private var weightsStore = RubricWeightsStore.shared
    @ObservedObject private var mlbWeightsStore = MlbRubricWeightsStore.shared
    @ObservedObject private var nflWeightsStore = NflRubricWeightsStore.shared
    @ObservedObject private var nhlWeightsStore = NhlRubricWeightsStore.shared
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
                        Picker("League", selection: $viewModel.leagueGroup) {
                            ForEach(LeagueGroup.allCases) { league in
                                Text(league.rawValue.uppercased()).tag(league)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .task { await viewModel.load() }
                .onChange(of: viewModel.leagueGroup) { _ in
                    Task { await viewModel.load() }
                }
                .refreshable { await viewModel.load() }
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
                        nbaWeights: weightsStore.weights(for: viewModel.leagueGroup),
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
        } else if let message = viewModel.errorMessage {
            EmptyStateView(title: message, systemImage: "wifi.slash")
        } else if viewModel.games.isEmpty {
            EmptyStateView(title: "No watchable games yet this season", systemImage: "clock.arrow.circlepath")
        } else {
            List(displayedGames) { game in
                HistoryRow(
                    game: game,
                    showNumericScore: showNumericScore,
                    scoreAndTier: game.effectiveScoreAndTier(
                        nba: weightsStore.weights(for: viewModel.leagueGroup),
                        mlb: mlbWeightsStore.weights,
                        nfl: nflWeightsStore.weights,
                        nhl: nhlWeightsStore.weights
                    ),
                    confettiEnabled: confettiEnabled
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if game.hasBreakdown {
                        selectedGameForDetail = game
                    } else if let videoId = game.yt {
                        selectedHighlightsVideoId = videoId
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private var displayedGames: [GameJson] {
        viewModel.games.filteredByMinTier(
            enabled: minTierFilterEnabled,
            minTier: WatchabilityTier(rawValue: minTierFilterRawValue) ?? .skippable,
            nba: { _ in weightsStore.weights(for: viewModel.leagueGroup) },
            mlb: mlbWeightsStore.weights,
            nfl: nflWeightsStore.weights,
            nhl: nhlWeightsStore.weights
        )
    }
}

private struct HistoryRow: View {
    let game: GameJson
    let showNumericScore: Bool
    let scoreAndTier: (score: Int, tier: WatchabilityTier)?
    let confettiEnabled: Bool

    @State private var showConfetti = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(matchupText)
                    .font(.headline)
                Spacer()
                if let scoreAndTier {
                    ScoreBadge(score: scoreAndTier.score, tier: scoreAndTier.tier, showNumber: showNumericScore)
                }
            }
            Text(game.hook)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
        .overlay {
            if showConfetti {
                GeometryReader { proxy in
                    ConfettiBurst(onFinished: { showConfetti = false })
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .allowsHitTesting(false)
            }
        }
        .task(id: "\(game.id)-\(scoreAndTier?.tier.rawValue ?? "")-\(game.stt.rawValue)") {
            guard let scoreAndTier, scoreAndTier.tier == .instantClassic, game.stt == .final else { return }
            guard InstantClassicCelebrationTracker.markIfFirstTime(game.id) else { return }
            if confettiEnabled {
                showConfetti = true
                fireInstantClassicHaptic()
            }
        }
    }

    private var matchupText: String {
        let away = game.al ?? game.a
        let home = game.hl ?? game.h
        if let awayScore = game.awayScore, let homeScore = game.homeScore {
            return "\(away) \(awayScore) @ \(home) \(homeScore)"
        }
        return "\(away) @ \(home)"
    }
}

#Preview {
    HistoryView()
}
