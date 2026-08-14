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
    @AppStorage(AppSettingsKeys.wifiOnlyHighlights) private var wifiOnlyHighlights = false
    @AppStorage(AppSettingsKeys.confettiEnabled) private var confettiEnabled = true
    @State private var selectedGameForDetail: GameJson?
    @State private var selectedHighlightsVideoId: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.games.isEmpty {
                    EmptyStateView(title: "Star a game to find it here", systemImage: "star")
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
                            .swipeActions {
                                Button("Unstar", role: .destructive) {
                                    store.toggle(game)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Starred")
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
                    onWatchHighlights: { videoId in
                        selectedGameForDetail = nil
                        selectedHighlightsVideoId = videoId
                    }
                )
            }
        }
    }
}

private struct StarredRow: View {
    let game: GameJson
    let showNumericScore: Bool
    let scoreAndTier: (score: Int, tier: WatchabilityTier)?
    let confettiEnabled: Bool

    @State private var showConfetti = false

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
}

#Preview {
    StarredView()
}
