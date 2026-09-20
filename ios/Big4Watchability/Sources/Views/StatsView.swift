import SwiftUI

// Swift mirror of StatsScreen.kt - season label, then one elevated card per
// stat category with its top-5 leaders (logo, name/team, value) and a
// "Show top 10"/"Show top 5" expand toggle when there are more than 5.
struct StatsView: View {
    @StateObject private var viewModel = StatsViewModel()
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
        if viewModel.isLoading && viewModel.categories.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.backgroundBase)
        } else if let message = viewModel.errorMessage {
            EmptyStateView(title: message, systemImage: "wifi.slash")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.backgroundBase)
        } else if viewModel.categories.isEmpty {
            EmptyStateView(title: "No stats available", systemImage: "chart.bar")
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
                    ForEach(viewModel.categories) { category in
                        StatCategoryCard(category: category)
                    }
                }
                .padding(16)
            }
            .background(theme.backgroundBase)
        }
    }
}

private let collapsedLeaderCount = 5

private struct StatCategoryCard: View {
    let category: StatCategory

    @Environment(\.appTheme) private var theme
    @State private var expanded = false

    private var visibleLeaders: [StatLeader] {
        expanded ? category.leaders : Array(category.leaders.prefix(collapsedLeaderCount))
    }

    private var canExpand: Bool { category.leaders.count > collapsedLeaderCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category.label)
                .font(.title3.bold())
                .foregroundStyle(theme.textPrimary)
            VStack(spacing: 0) {
                ForEach(Array(visibleLeaders.enumerated()), id: \.element.id) { index, leader in
                    StatLeaderRow(rank: index + 1, leader: leader, abbr: category.abbr)
                }
                if canExpand {
                    Button {
                        withAnimation { expanded.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(expanded ? "Show top 5" : "Show top 10")
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(AppColors.tierWorthYourTime)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .background(theme.surfaceCardElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

private struct StatLeaderRow: View {
    let rank: Int
    let leader: StatLeader
    let abbr: String

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Text("\(rank)")
                .font(.subheadline)
                .fontWeight(rank == 1 ? .bold : .regular)
                .foregroundStyle(rank == 1 ? AppColors.tierWorthYourTime : theme.textMuted)
                .frame(width: 24, alignment: .leading)
            if let logo = leader.teamLogo, let url = URL(string: logo) {
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
                Text(leader.name)
                    .font(.subheadline)
                    .foregroundStyle(theme.textPrimary)
                Text(leader.team)
                    .font(.caption2)
                    .foregroundStyle(theme.textMuted)
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(leader.value) \(abbr)")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

#Preview {
    StatsView()
}
