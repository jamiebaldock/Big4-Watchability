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

    func load(allLeagues: Bool = false) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if allLeagues {
                games = try await Self.fetchAllLeagues(client: client)
            } else {
                let seasonStart = try await client.currentSeasonStart(leagueGroup: leagueGroup).date
                let end = Self.dayFormatter.string(from: Date())
                let response = try await client.history(start: seasonStart, end: end, leagueGroup: leagueGroup)
                games = response.games.sorted { $0.utc > $1.utc }
            }
        } catch {
            errorMessage = "Couldn't load history: \(error.localizedDescription)"
        }
    }

    // Each league has its own season-start date (currentSeasonStart is a
    // per-league lookup), so this can't share one date range the way
    // GamesViewModel's fetchAllLeagues does - every league's own
    // (season-start-lookup, history-fetch) pair still runs concurrently
    // with every other league's, just not sharing a single start value.
    private static func fetchAllLeagues(client: APIClient) async throws -> [GameJson] {
        let end = dayFormatter.string(from: Date())
        return try await withThrowingTaskGroup(of: [GameJson].self) { group in
            for league in LeagueGroup.allCases {
                group.addTask {
                    let seasonStart = try await client.currentSeasonStart(leagueGroup: league).date
                    return try await client.history(start: seasonStart, end: end, leagueGroup: league).games
                }
            }
            var merged: [GameJson] = []
            for try await batch in group {
                merged += batch
            }
            return merged.sorted { $0.utc > $1.utc }
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
