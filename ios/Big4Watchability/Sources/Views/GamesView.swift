import SwiftUI

struct GamesView: View {
    @StateObject private var viewModel = GamesViewModel()
    @ObservedObject private var favorites = FavoritesStore.shared
    @ObservedObject private var weightsStore = RubricWeightsStore.shared
    @ObservedObject private var mlbWeightsStore = MlbRubricWeightsStore.shared
    @ObservedObject private var starred = StarredGamesStore.shared
    @AppStorage(AppSettingsKeys.showNumericScore) private var showNumericScore = true
    @AppStorage(AppSettingsKeys.bumpFavoriteTeamGames) private var bumpFavoriteTeamGames = true

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
                    weights: weightsStore.weights(for: viewModel.leagueGroup),
                    mlbWeights: mlbWeightsStore.weights
                )
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
    let weights: RubricWeights
    let mlbWeights: MlbRubricWeights

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(game.al ?? game.a) @ \(game.hl ?? game.h)")
                    .font(.headline)
                Spacer()
                if game.scoreVisible, let score = displayScore, let tier = displayTier {
                    ScoreBadge(score: score, tier: tier, showNumber: showNumericScore)
                }
            }
            Text(game.hook)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    // NBA/WNBA/MLB get the client-side, weight-adjusted score (each sport's
    // own tier scale - MLB's 60/35/20 isn't the same as basketball's
    // 85/65/45, see MlbRubric.swift); NFL/NHL fall back to the server's
    // fixed-1x score until their rubrics are ported too.
    private var displayScore: Int? {
        switch game.lg {
        case .nba, .wnba: return game.effectiveScore(weights: weights)
        case .mlb: return game.effectiveMlbScore(weights: mlbWeights)
        default: return game.score
        }
    }

    private var displayTier: WatchabilityTier? {
        switch game.lg {
        case .nba, .wnba: return game.effectiveTier(weights: weights)
        case .mlb: return game.effectiveMlbTier(weights: mlbWeights)
        default:
            guard let score = game.score else { return nil }
            return WatchabilityTier.forScore(score)
        }
    }
}

private struct ScoreBadge: View {
    let score: Int
    let tier: WatchabilityTier
    let showNumber: Bool

    var body: some View {
        Group {
            if showNumber {
                Text("\(score)")
            } else {
                Circle().frame(width: 8, height: 8)
            }
        }
        .font(.caption.bold())
        .padding(.horizontal, showNumber ? 8 : 6)
        .padding(.vertical, 4)
        .background(tint.opacity(0.15), in: Capsule())
        .foregroundStyle(tint)
    }

    private var tint: Color {
        switch tier {
        case .instantClassic: return .red
        case .worthYourTime: return .orange
        case .solid: return .yellow
        case .skippable: return .gray
        }
    }
}

#Preview {
    GamesView()
}
