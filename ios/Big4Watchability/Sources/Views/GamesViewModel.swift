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

    func load(date: Date = Date(), allLeagues: Bool = false) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let day = Self.dayFormatter.string(from: date)
        do {
            if allLeagues {
                games = try await Self.fetchAllLeagues(day: day, client: client)
            } else {
                games = try await client.schedule(start: day, end: day, leagueGroup: leagueGroup)
            }
        } catch {
            errorMessage = "Couldn't load games: \(error.localizedDescription)"
        }
    }

    // Every league is an independent request, fired concurrently rather
    // than awaited one at a time - mirrors GameListViewModel.kt's
    // fetchScheduleChunked, which fixed a real "sequential awaiting" load
    // time regression (P1 investigation, see project memory).
    private static func fetchAllLeagues(day: String, client: APIClient) async throws -> [GameJson] {
        try await withThrowingTaskGroup(of: [GameJson].self) { group in
            for league in LeagueGroup.allCases {
                group.addTask { try await client.schedule(start: day, end: day, leagueGroup: league) }
            }
            var merged: [GameJson] = []
            for try await batch in group {
                merged += batch
            }
            return merged.sorted { $0.utc < $1.utc }
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
