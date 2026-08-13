import Foundation

// Swift mirror of mobile/app/.../ui/StatsViewModel.kt.
@MainActor
final class StatsViewModel: ObservableObject {
    @Published var categories: [StatCategory] = []
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
            let response = try await client.stats(leagueGroup: leagueGroup)
            season = response.season
            categories = response.categories
        } catch {
            errorMessage = "Couldn't load stats: \(error.localizedDescription)"
        }
    }
}
