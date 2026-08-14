import SwiftUI

struct FavoritesView: View {
    @StateObject private var viewModel = FavoritesViewModel()
    @ObservedObject private var favorites = FavoritesStore.shared
    @AppStorage(AppSettingsKeys.playerHaterMode) private var playerHaterMode = false

    var body: some View {
        NavigationStack {
            List {
                if !favorites.teams.isEmpty {
                    Section("Favorite Teams") {
                        ForEach(favorites.teams) { favorite in
                            HStack {
                                Text(favorite.team.name)
                                Spacer()
                                Text(favorite.leagueGroup.rawValue.uppercased())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    favorites.toggle(team: favorite.team, leagueGroup: favorite.leagueGroup)
                                }
                            }
                        }
                    }
                }

                if !favorites.players.isEmpty {
                    Section("Favorite Players") {
                        ForEach(favorites.players) { favorite in
                            HStack {
                                Text(favorite.name)
                                Spacer()
                                Text(favorite.team)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if playerHaterMode, let leagueGroup = favorite.leagueGroup {
                                    let player = PlayerJson(id: favorite.name, name: favorite.name, headshot: favorite.headshot)
                                    Button {
                                        favorites.toggleHated(player: player, team: favorite.team, leagueGroup: leagueGroup)
                                    } label: {
                                        Image(systemName: favorites.isHated(name: favorite.name) ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(favorites.isHated(name: favorite.name) ? .red : .secondary)
                                }
                            }
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    if let leagueGroup = favorite.leagueGroup {
                                        let player = PlayerJson(id: favorite.name, name: favorite.name, headshot: favorite.headshot)
                                        favorites.toggle(player: player, team: favorite.team, leagueGroup: leagueGroup)
                                    }
                                }
                            }
                        }
                    }
                }

                // Player Hater Mode easter egg - only reachable while the
                // toggle (SecretScreenView) is on, same "never appears while
                // the mode is off" rule as FavoritesScreen.kt's 5th page.
                if playerHaterMode, !favorites.hatedPlayers.isEmpty {
                    Section("👎 Players") {
                        ForEach(favorites.hatedPlayers) { player in
                            HStack {
                                Text(player.name)
                                Spacer()
                                Text(player.team)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    favorites.removeHated(player)
                                }
                            }
                        }
                    }
                }

                Section("Add Teams (\(viewModel.leagueGroup.rawValue.uppercased()))") {
                    if viewModel.isLoadingTeams {
                        ProgressView()
                    } else {
                        ForEach(viewModel.browsableTeams) { team in
                            Button {
                                Task { await viewModel.loadRoster(for: team) }
                            } label: {
                                HStack {
                                    Text(team.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: favorites.isFavorite(team: team) ? "star.fill" : "star")
                                        .foregroundStyle(favorites.isFavorite(team: team) ? .yellow : .secondary)
                                        .onTapGesture {
                                            favorites.toggle(team: team, leagueGroup: viewModel.leagueGroup)
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Favorites")
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

private struct RosterSheet: View {
    @ObservedObject var viewModel: FavoritesViewModel
    @ObservedObject private var favorites = FavoritesStore.shared
    @AppStorage(AppSettingsKeys.playerHaterMode) private var playerHaterMode = false
    let leagueGroup: LeagueGroup

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingRoster {
                    ProgressView()
                } else {
                    List(viewModel.roster) { player in
                        HStack {
                            Button {
                                favorites.toggle(player: player, team: viewModel.rosterTeamName ?? "", leagueGroup: leagueGroup)
                            } label: {
                                HStack {
                                    Text(player.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: favorites.isFavorite(player: player, team: viewModel.rosterTeamName ?? "") ? "star.fill" : "star")
                                        .foregroundStyle(.yellow)
                                }
                            }
                            .buttonStyle(.plain)
                            if playerHaterMode {
                                Button {
                                    favorites.toggleHated(player: player, team: viewModel.rosterTeamName ?? "", leagueGroup: leagueGroup)
                                } label: {
                                    Image(systemName: favorites.isHated(name: player.name) ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(favorites.isHated(name: player.name) ? .red : .secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(viewModel.rosterTeamName ?? "Roster")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { viewModel.closeRoster() }
                }
            }
        }
    }
}

#Preview {
    FavoritesView()
}
