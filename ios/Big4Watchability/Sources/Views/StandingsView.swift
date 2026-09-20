import SwiftUI

// Swift mirror of StandingsScreen.kt - season label, then one elevated card
// per division/conference group with a header row (TEAM/W/L/PCT/GB) and a
// ranked team row per team (logo, name + streak, stat columns).
struct StandingsView: View {
    @StateObject private var viewModel = StandingsViewModel()
    @Environment(\.appTheme) private var theme

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        TitleLeagueSelector(
                            selectedLeague: viewModel.leagueGroup,
                            onLeagueSelected: { viewModel.leagueGroup = $0 }
                        )
                    }
                }
                .toolbarBackground(theme.backgroundBase, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.backgroundBase)
        } else if let message = viewModel.errorMessage {
            EmptyStateView(title: message, systemImage: "wifi.slash")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.backgroundBase)
        } else if viewModel.groups.isEmpty {
            EmptyStateView(title: "No standings available", systemImage: "list.number")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.backgroundBase)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if let season = viewModel.season {
                        Text("\(season) season")
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                    }
                    ForEach(viewModel.groups, id: \.name) { group in
                        StandingsGroupSection(group: group)
                    }
                }
                .padding(16)
            }
            .background(theme.backgroundBase)
        }
    }
}

private struct StandingsGroupSection: View {
    let group: StandingsGroup

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.name)
                .font(.title3.bold())
                .foregroundStyle(theme.textPrimary)
            VStack(spacing: 0) {
                StandingsHeaderRow()
                ForEach(Array(group.teams.enumerated()), id: \.element.id) { index, team in
                    StandingsRow(rank: index + 1, team: team)
                }
            }
            .padding(.vertical, 4)
            .background(theme.surfaceCardElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

private struct StandingsHeaderRow: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 28)
            Spacer().frame(width: 32)
            Text("TEAM")
                .font(.caption2.bold())
                .foregroundStyle(theme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
            StatHeader("W")
            StatHeader("L")
            StatHeader("PCT")
            StatHeader("GB")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func StatHeader(_ label: String) -> some View {
        Text(label)
            .font(.caption2.bold())
            .foregroundStyle(theme.textMuted)
            .frame(width: 40, alignment: .trailing)
    }
}

private struct StandingsRow: View {
    let rank: Int
    let team: StandingsTeam

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Text("\(rank)")
                .font(.caption)
                .foregroundStyle(theme.textMuted)
                .frame(width: 28, alignment: .leading)
            if let logo = team.logo, let url = URL(string: logo) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .frame(width: 24, height: 24)
            } else {
                Spacer().frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(team.n)
                    .font(.subheadline)
                    .foregroundStyle(theme.textPrimary)
                if let strk = team.strk, !strk.isEmpty {
                    Text(strk)
                        .font(.caption2)
                        .foregroundStyle(theme.textMuted)
                }
            }
            .padding(.leading, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            StatValue("\(team.w)")
            StatValue("\(team.l)")
            StatValue(team.pct)
            StatValue(team.gb)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func StatValue(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(theme.textSecondary)
            .frame(width: 40, alignment: .trailing)
    }
}

#Preview {
    StandingsView()
}
