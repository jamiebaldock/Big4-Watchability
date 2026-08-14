import SwiftUI

// Unlike every other tab, History deliberately shows final scores - there's
// nothing left to spoil for a game the user is intentionally browsing back
// through (see GameJson.awayScore/homeScore's doc comment).
struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()

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
            List(viewModel.games) { game in
                HistoryRow(game: game)
            }
            .listStyle(.plain)
        }
    }
}

private struct HistoryRow: View {
    let game: GameJson

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(matchupText)
                    .font(.headline)
                Spacer()
                if let score = game.score {
                    Text("\(score)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            Text(game.hook)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
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
