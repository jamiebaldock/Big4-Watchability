import SwiftUI

struct GamesView: View {
    @StateObject private var viewModel = GamesViewModel()
    @ObservedObject private var favorites = FavoritesStore.shared
    @ObservedObject private var weightsStore = RubricWeightsStore.shared
    @ObservedObject private var mlbWeightsStore = MlbRubricWeightsStore.shared
    @ObservedObject private var nflWeightsStore = NflRubricWeightsStore.shared
    @ObservedObject private var nhlWeightsStore = NhlRubricWeightsStore.shared
    @ObservedObject private var starred = StarredGamesStore.shared
    @AppStorage(AppSettingsKeys.showNumericScore) private var showNumericScore = true
    @AppStorage(AppSettingsKeys.bumpFavoriteTeamGames) private var bumpFavoriteTeamGames = true
    @AppStorage(AppSettingsKeys.wifiOnlyHighlights) private var wifiOnlyHighlights = false
    @State private var selectedHighlightsVideoId: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Games")
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
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.games.isEmpty {
            ProgressView()
        } else if let message = viewModel.errorMessage {
            EmptyStateView(title: message, systemImage: "wifi.slash")
        } else if viewModel.games.isEmpty {
            EmptyStateView(title: "No games today", systemImage: "sportscourt")
        } else {
            List(orderedGames) { game in
                GameRow(
                    game: game,
                    showNumericScore: showNumericScore,
                    scoreAndTier: game.effectiveScoreAndTier(
                        nba: weightsStore.weights(for: viewModel.leagueGroup),
                        mlb: mlbWeightsStore.weights,
                        nfl: nflWeightsStore.weights,
                        nhl: nhlWeightsStore.weights
                    )
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if let videoId = game.yt {
                        selectedHighlightsVideoId = videoId
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        starred.toggle(game)
                    } label: {
                        Label(starred.isStarred(game) ? "Unstar" : "Star", systemImage: starred.isStarred(game) ? "star.slash" : "star.fill")
                    }
                    .tint(.yellow)
                }
            }
            .listStyle(.plain)
        }
    }

    // Mirrors GameListViewModel.kt's favorite-team bump: favorited teams'
    // games float to the top, stable order otherwise preserved.
    private var orderedGames: [GameJson] {
        guard bumpFavoriteTeamGames else { return viewModel.games }
        let favoriteNames = Set(
            favorites.teams
                .filter { $0.leagueGroup == viewModel.leagueGroup }
                .map { $0.team.name }
        )
        guard !favoriteNames.isEmpty else { return viewModel.games }
        let (favored, rest) = viewModel.games.reduce(into: ([GameJson](), [GameJson]())) { result, game in
            if favoriteNames.contains(game.a) || favoriteNames.contains(game.h) {
                result.0.append(game)
            } else {
                result.1.append(game)
            }
        }
        return favored + rest
    }
}

private struct GameRow: View {
    let game: GameJson
    let showNumericScore: Bool
    let scoreAndTier: (score: Int, tier: WatchabilityTier)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(game.al ?? game.a) @ \(game.hl ?? game.h)")
                    .font(.headline)
                if game.yt != nil {
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
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
    GamesView()
}
