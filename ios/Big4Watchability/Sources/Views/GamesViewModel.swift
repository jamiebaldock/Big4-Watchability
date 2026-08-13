import Foundation

// Swift mirror of the relevant slice of mobile/app/.../ui/GameListViewModel.kt
// - loads a single day's schedule for the selected league. Extend to match
// the Android multi-day/chunked-fetch behavior once this first slice is
// verified compiling via CI.
@MainActor
final class GamesViewModel: ObservableObject {
    @Published var games: [GameJson] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var leagueGroup: LeagueGroup = .nba

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func load(date: Date = Date()) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let day = Self.dayFormatter.string(from: date)
        do {
            games = try await client.schedule(start: day, end: day, leagueGroup: leagueGroup)
        } catch {
            errorMessage = "Couldn't load games: \(error.localizedDescription)"
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
