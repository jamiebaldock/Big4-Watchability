import SwiftUI

struct GamesView: View {
    @StateObject private var viewModel = GamesViewModel()

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
            List(viewModel.games) { game in
                GameRow(game: game)
            }
            .listStyle(.plain)
        }
    }
}

private struct GameRow: View {
    let game: GameJson

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(game.al ?? game.a) @ \(game.hl ?? game.h)")
                    .font(.headline)
                Spacer()
                if game.scoreVisible, let score = game.score {
                    ScoreBadge(score: score)
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

private struct ScoreBadge: View {
    let score: Int

    var body: some View {
        Text("\(score)")
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }

    // Mirrors rubric.ts's 85/65/45 tier thresholds (see docs/nba-watchability-spec.md).
    private var tint: Color {
        switch score {
        case 85...: return .red
        case 65..<85: return .orange
        case 45..<65: return .yellow
        default: return .gray
        }
    }
}

#Preview {
    GamesView()
}
