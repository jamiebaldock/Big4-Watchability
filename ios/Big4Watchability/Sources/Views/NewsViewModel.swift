import Foundation

// Swift mirror of mobile/app/.../ui/NewsViewModel.kt.
@MainActor
final class NewsViewModel: ObservableObject {
    @Published var articles: [NewsArticle] = []
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
            let response = try await client.news(leagueGroup: leagueGroup)
            articles = response.articles
        } catch {
            errorMessage = "Couldn't load news: \(error.localizedDescription)"
        }
    }
}
