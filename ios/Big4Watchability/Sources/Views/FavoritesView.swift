import SwiftUI

// Restyled to match Android's dark theme/logos (FavoriteTeamsPage/
// FavoritePlayersPage in FavoritesScreen.kt) - kept as one scrollable list
// with sections rather than porting Android's full swipeable multi-page
// pager (which also has its own "games from your favorited teams" page
// this app doesn't have at all) - that's new functionality, not a style
// pass, and worth scoping separately if wanted.
struct FavoritesView: View {
    @StateObject private var viewModel = FavoritesViewModel()
    @ObservedObject private var favorites = FavoritesStore.shared
    @Environment(\.appTheme) private var theme
    @AppStorage(AppSettingsKeys.playerHaterMode) private var playerHaterMode = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if !favorites.teams.isEmpty {
                        FavoritesSection(title: "Favorite Teams") {
                            ForEach(favorites.teams) { favorite in
                                FavoriteTeamRow(
                                    favorite: favorite,
                                    onRemove: { favorites.toggle(team: favorite.team, leagueGroup: favorite.leagueGroup) }
                                )
                            }
                        }
                    }

                    if !favorites.players.isEmpty {
                        FavoritesSection(title: "Favorite Players") {
                            ForEach(favorites.players) { favorite in
                                FavoritePlayerRow(
                                    favorite: favorite,
                                    playerHaterMode: playerHaterMode,
                                    isHated: favorites.isHated(name: favorite.name),
                                    onToggleHated: {
                                        guard let leagueGroup = favorite.leagueGroup else { return }
                                        let player = PlayerJson(id: favorite.name, name: favorite.name, headshot: favorite.headshot)
                                        favorites.toggleHated(player: player, team: favorite.team, leagueGroup: leagueGroup)
                                    },
                                    onRemove: {
                                        guard let leagueGroup = favorite.leagueGroup else { return }
                                        let player = PlayerJson(id: favorite.name, name: favorite.name, headshot: favorite.headshot)
                                        favorites.toggle(player: player, team: favorite.team, leagueGroup: leagueGroup)
                                    }
                                )
                            }
                        }
                    }

                    // Player Hater Mode easter egg - only reachable while the
                    // toggle (SecretScreenView) is on, same "never appears
                    // while the mode is off" rule as FavoritesScreen.kt's 5th
                    // page.
                    if playerHaterMode, !favorites.hatedPlayers.isEmpty {
                        FavoritesSection(title: "👎 Players") {
                            ForEach(favorites.hatedPlayers) { player in
                                HatedPlayerRow(player: player, onRemove: { favorites.removeHated(player) })
                            }
                        }
                    }

                    FavoritesSection(title: "Add Teams (\(viewModel.leagueGroup.displayName))") {
                        if viewModel.isLoadingTeams {
                            ProgressView().padding(.vertical, 8)
                        } else {
                            ForEach(viewModel.browsableTeams) { team in
                                BrowsableTeamRow(
                                    team: team,
                                    isFavorite: favorites.isFavorite(team: team),
                                    onTap: { Task { await viewModel.loadRoster(for: team) } },
                                    onToggleFavorite: { favorites.toggle(team: team, leagueGroup: viewModel.leagueGroup) }
                                )
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(theme.backgroundBase)
            .navigationTitle("Favorites")
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
            .task { await viewModel.loadTeams() }
            .onChange(of: viewModel.leagueGroup) { _ in
                Task { await viewModel.loadTeams() }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.rosterTeamName != nil },
                set: { if !$0 { viewModel.closeRoster() } }
            )) {
                RosterSheet(viewModel: viewModel, leagueGroup: viewModel.leagueGroup)
            }
        }
    }
}

private struct FavoritesSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(theme.textPrimary)
            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(theme.surfaceCardElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

private struct FavoriteTeamRow: View {
    let favorite: FavoriteTeam
    let onRemove: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            if let logo = favorite.team.logo, let url = URL(string: logo) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .frame(width: 28, height: 28)
            }
            Text(favorite.team.name)
                .font(.body)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Text(favorite.leagueGroup.shortDisplayName)
                .font(.caption2)
                .foregroundStyle(theme.textMuted)
            Button(action: onRemove) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(AppColors.tierInstantClassic)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
    }
}

private struct FavoritePlayerRow: View {
    let favorite: FavoritePlayer
    let playerHaterMode: Bool
    let isHated: Bool
    let onToggleHated: () -> Void
    let onRemove: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            PlayerAvatar(url: favorite.headshot)
            VStack(alignment: .leading, spacing: 0) {
                Text(favorite.name)
                    .font(.body)
                    .foregroundStyle(theme.textPrimary)
                Text(favorite.team)
                    .font(.caption2)
                    .foregroundStyle(theme.textMuted)
            }
            Spacer()
            if playerHaterMode {
                Button(action: onToggleHated) {
                    Image(systemName: isHated ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .foregroundStyle(isHated ? AppColors.liveRed : theme.textMuted)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }
            Button(action: onRemove) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(AppColors.tierInstantClassic)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
    }
}

private struct HatedPlayerRow: View {
    let player: FavoritePlayer
    let onRemove: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            PlayerAvatar(url: player.headshot)
            VStack(alignment: .leading, spacing: 0) {
                Text(player.name)
                    .font(.body)
                    .foregroundStyle(theme.textPrimary)
                Text(player.team)
                    .font(.caption2)
                    .foregroundStyle(theme.textMuted)
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "hand.thumbsdown.fill")
                    .foregroundStyle(AppColors.liveRed)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
    }
}

private struct BrowsableTeamRow: View {
    let team: TeamJson
    let isFavorite: Bool
    let onTap: () -> Void
    let onToggleFavorite: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if let logo = team.logo, let url = URL(string: logo) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Color.clear
                    }
                    .frame(width: 28, height: 28)
                }
                Text(team.name)
                    .font(.body)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(isFavorite ? AppColors.tierInstantClassic : theme.textMuted)
                    .onTapGesture(perform: onToggleFavorite)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

private struct PlayerAvatar: View {
    let url: String?

    var body: some View {
        Group {
            if let url, let imageUrl = URL(string: url) {
                AsyncImage(url: imageUrl) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }
}

private struct RosterSheet: View {
    @ObservedObject var viewModel: FavoritesViewModel
    @ObservedObject private var favorites = FavoritesStore.shared
    @Environment(\.appTheme) private var theme
    @AppStorage(AppSettingsKeys.playerHaterMode) private var playerHaterMode = false
    let leagueGroup: LeagueGroup

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingRoster {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(theme.backgroundBase)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.roster) { player in
                                RosterPlayerRow(
                                    player: player,
                                    isFavorite: favorites.isFavorite(player: player, team: viewModel.rosterTeamName ?? ""),
                                    playerHaterMode: playerHaterMode,
                                    isHated: favorites.isHated(name: player.name),
                                    onToggleFavorite: {
                                        favorites.toggle(player: player, team: viewModel.rosterTeamName ?? "", leagueGroup: leagueGroup)
                                    },
                                    onToggleHated: {
                                        favorites.toggleHated(player: player, team: viewModel.rosterTeamName ?? "", leagueGroup: leagueGroup)
                                    }
                                )
                            }
                        }
                        .padding(16)
                    }
                    .background(theme.backgroundBase)
                }
            }
            .navigationTitle(viewModel.rosterTeamName ?? "Roster")
            .toolbarBackground(theme.backgroundBase, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { viewModel.closeRoster() }
                }
            }
        }
    }
}

private struct RosterPlayerRow: View {
    let player: PlayerJson
    let isFavorite: Bool
    let playerHaterMode: Bool
    let isHated: Bool
    let onToggleFavorite: () -> Void
    let onToggleHated: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            PlayerAvatar(url: player.headshot)
            Text(player.name)
                .font(.body)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            if playerHaterMode {
                Button(action: onToggleHated) {
                    Image(systemName: isHated ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .foregroundStyle(isHated ? AppColors.liveRed : theme.textMuted)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }
            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(isFavorite ? AppColors.tierInstantClassic : theme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    FavoritesView()
}
