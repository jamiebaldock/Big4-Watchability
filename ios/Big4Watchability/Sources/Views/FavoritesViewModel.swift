import Foundation

// Swift mirror of mobile/app/.../ui/FavoritesViewModel.kt (teams half) plus
// FavoritePlayersScreen.kt's roster-browsing (players half) - combined into
// one view model for this first pass rather than Android's separate screens.
@MainActor
final class FavoritesViewModel: ObservableObject {
    @Published var leagueGroup: LeagueGroup = .nba
    @Published var browsableTeams: [TeamJson] = []
    @Published var roster: [PlayerJson] = []
    @Published var rosterTeamName: String?
    @Published var isLoadingTeams = false
    @Published var isLoadingRoster = false
    @Published var errorMessage: String?

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func loadTeams() async {
        isLoadingTeams = true
        errorMessage = nil
        defer { isLoadingTeams = false }
        do {
            browsableTeams = try await client.teams(leagueGroup: leagueGroup).teams
        } catch {
            errorMessage = "Couldn't load teams: \(error.localizedDescription)"
        }
    }

    func loadRoster(for team: TeamJson) async {
        isLoadingRoster = true
        rosterTeamName = team.name
        defer { isLoadingRoster = false }
        do {
            roster = try await client.roster(leagueGroup: leagueGroup, team: team.name).players
        } catch {
            errorMessage = "Couldn't load roster: \(error.localizedDescription)"
        }
    }

    func closeRoster() {
        rosterTeamName = nil
        roster = []
    }
}
