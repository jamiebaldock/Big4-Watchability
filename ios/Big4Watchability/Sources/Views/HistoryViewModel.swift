import Foundation

// Swift mirror of mobile/app/.../ui/HistoryViewModel.kt - loads the current
// season's window by default (earliestDate/seasons available for a future
// season picker, same as Android's SeasonCalendarDialog).
@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var games: [GameJson] = []
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
            let seasonStart = try await client.currentSeasonStart(leagueGroup: leagueGroup).date
            let end = Self.dayFormatter.string(from: Date())
            let response = try await client.history(start: seasonStart, end: end, leagueGroup: leagueGroup)
            games = response.games.sorted { $0.utc > $1.utc }
        } catch {
            errorMessage = "Couldn't load history: \(error.localizedDescription)"
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
