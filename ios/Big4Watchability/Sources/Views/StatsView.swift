import SwiftUI

struct StatsView: View {
    @StateObject private var viewModel = StatsViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Stats")
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
        if viewModel.isLoading && viewModel.categories.isEmpty {
            ProgressView()
        } else if let message = viewModel.errorMessage {
            EmptyStateView(title: message, systemImage: "wifi.slash")
        } else if viewModel.categories.isEmpty {
            EmptyStateView(title: "No stats available", systemImage: "chart.bar")
        } else {
            List {
                ForEach(viewModel.categories) { category in
                    Section(category.label) {
                        ForEach(category.leaders) { leader in
                            StatLeaderRow(leader: leader)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

private struct StatLeaderRow: View {
    let leader: StatLeader

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(leader.name)
                    .font(.subheadline.bold())
                Text(leader.team)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(leader.value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    StatsView()
}
