import SwiftUI

struct StandingsView: View {
    @StateObject private var viewModel = StandingsViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Standings")
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
        if viewModel.isLoading && viewModel.groups.isEmpty {
            ProgressView()
        } else if let message = viewModel.errorMessage {
            EmptyStateView(title: message, systemImage: "wifi.slash")
        } else if viewModel.groups.isEmpty {
            EmptyStateView(title: "No standings available", systemImage: "list.number")
        } else {
            List {
                ForEach(viewModel.groups, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.teams) { team in
                            StandingsRow(team: team)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

private struct StandingsRow: View {
    let team: StandingsTeam

    var body: some View {
        HStack {
            Text(team.ab)
                .font(.subheadline.bold())
                .frame(width: 44, alignment: .leading)
            Text(team.n)
                .font(.subheadline)
            Spacer()
            Text("\(team.w)-\(team.l)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(team.gb)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

#Preview {
    StandingsView()
}
