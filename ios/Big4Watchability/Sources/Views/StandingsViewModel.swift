import Foundation

// Swift mirror of mobile/app/.../ui/StandingsViewModel.kt.
@MainActor
final class StandingsViewModel: ObservableObject {
    @Published var groups: [StandingsGroup] = []
    @Published var season: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var leagueGroup: LeagueGroup = .nba

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await client.standings(leagueGroup: leagueGroup)
            season = response.season
            groups = response.groups
        } catch {
            errorMessage = "Couldn't load standings: \(error.localizedDescription)"
        }
    }
}
