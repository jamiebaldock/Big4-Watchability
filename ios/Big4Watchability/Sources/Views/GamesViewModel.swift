import Foundation

// Swift mirror of GameListViewModel.kt - a sliding window of days (rather
// than Android's narrow-window + full-season-prefetch two-phase load, which
// needs a chunked-fetch merge this port doesn't attempt yet): starts at
// +/-windowRadiusDays around today, and silently extends by fetching another
// windowRadiusDays chunk whenever the selected day gets close to either edge
// (see selectDay). Each chunk fetch stays under the backend's 21-day cap
// (httpHandler.ts's MAX_RANGE_DAYS) on its own.
@MainActor
final class GamesViewModel: ObservableObject {
    @Published var days: [DayGames] = []
    @Published var selectedDayIndex = 0
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var leagueGroup: LeagueGroup = .nba
    @Published var sortOption: SortOption = .dateOldestFirst
    @Published var isJumpingToToday = false
    @Published var isJumpingToNextGame = false
    @Published var isJumpingToDate = false
    @Published var jumpToNextGameError: String?
    @Published var monthCounts: [String: Int] = [:]
    @Published var monthCountsMonth: Date?
    @Published var isLoadingMonthCounts = false

    let today = Calendar.current.startOfDay(for: Date())

    private static let windowRadiusDays = 7
    private static let extendThreshold = 2

    private let client: APIClient
    private var isExtendingBackward = false
    private var isExtendingForward = false

    init(client: APIClient = .shared) {
        self.client = client
    }

    func load(allLeagues: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let start = addDays(-Self.windowRadiusDays, to: today)
        let end = addDays(Self.windowRadiusDays, to: today)
        do {
            let fetched = try await fetchDays(start: start, end: end, allLeagues: allLeagues)
            days = fetched
            selectedDayIndex = fetched.firstIndex { $0.date == today.apiDateString } ?? 0
        } catch {
            errorMessage = "Couldn't load games: \(error.localizedDescription)"
        }
    }

    func refresh(allLeagues: Bool) async {
        isRefreshing = true
        defer { isRefreshing = false }

        guard let firstDate = days.first.flatMap({ Date.fromApiDateString($0.date) }),
              let lastDate = days.last.flatMap({ Date.fromApiDateString($0.date) }) else {
            await load(allLeagues: allLeagues)
            return
        }
        let currentDate = days.indices.contains(selectedDayIndex) ? days[selectedDayIndex].date : nil
        do {
            let refreshed = try await fetchDays(start: firstDate, end: lastDate, allLeagues: allLeagues)
            days = refreshed
            if let currentDate, let idx = refreshed.firstIndex(where: { $0.date == currentDate }) {
                selectedDayIndex = idx
            }
        } catch {
            // Keep whatever was already on screen - a failed background
            // refresh shouldn't blow away good data, same as pull-to-refresh
            // everywhere else in this app.
        }
    }

    /// Every day-index change (a chip tap OR a pager swipe) routes through
    /// here rather than setting `selectedDayIndex` directly, so the window-
    /// extension side effect fires regardless of source.
    func selectDay(_ index: Int, allLeagues: Bool) {
        guard days.indices.contains(index) else { return }
        selectedDayIndex = index
        if index <= Self.extendThreshold {
            Task { await extendBackward(allLeagues: allLeagues) }
        } else if index >= days.count - 1 - Self.extendThreshold {
            Task { await extendForward(allLeagues: allLeagues) }
        }
    }

    private func extendBackward(allLeagues: Bool) async {
        guard !isExtendingBackward, let firstDate = days.first.flatMap({ Date.fromApiDateString($0.date) }) else { return }
        isExtendingBackward = true
        defer { isExtendingBackward = false }
        let end = addDays(-1, to: firstDate)
        let start = addDays(-Self.windowRadiusDays, to: end)
        guard let newDays = try? await fetchDays(start: start, end: end, allLeagues: allLeagues), !newDays.isEmpty else { return }
        days = newDays + days
        selectedDayIndex += newDays.count
    }

    private func extendForward(allLeagues: Bool) async {
        guard !isExtendingForward, let lastDate = days.last.flatMap({ Date.fromApiDateString($0.date) }) else { return }
        isExtendingForward = true
        defer { isExtendingForward = false }
        let start = addDays(1, to: lastDate)
        let end = addDays(Self.windowRadiusDays, to: start)
        guard let newDays = try? await fetchDays(start: start, end: end, allLeagues: allLeagues), !newDays.isEmpty else { return }
        days += newDays
    }

    func jumpToToday(allLeagues: Bool) async {
        if let idx = days.firstIndex(where: { $0.date == today.apiDateString }) {
            selectDay(idx, allLeagues: allLeagues)
            return
        }
        isJumpingToToday = true
        defer { isJumpingToToday = false }
        await load(allLeagues: allLeagues)
    }

    func jumpToDate(_ date: Date, allLeagues: Bool) async {
        let dateString = date.apiDateString
        if let idx = days.firstIndex(where: { $0.date == dateString }) {
            selectDay(idx, allLeagues: allLeagues)
            return
        }
        isJumpingToDate = true
        defer { isJumpingToDate = false }
        let start = addDays(-Self.windowRadiusDays, to: date)
        let end = addDays(Self.windowRadiusDays, to: date)
        do {
            let fetched = try await fetchDays(start: start, end: end, allLeagues: allLeagues)
            days = fetched
            selectedDayIndex = fetched.firstIndex { $0.date == dateString } ?? 0
        } catch {
            errorMessage = "Couldn't load games: \(error.localizedDescription)"
        }
    }

    func jumpToNextGame(allLeagues: Bool) async {
        guard days.indices.contains(selectedDayIndex), let currentDate = Date.fromApiDateString(days[selectedDayIndex].date) else { return }
        isJumpingToNextGame = true
        defer { isJumpingToNextGame = false }
        let afterString = currentDate.apiDateString
        do {
            let nextDateString: String?
            if allLeagues {
                nextDateString = try await withThrowingTaskGroup(of: String?.self) { group in
                    for league in LeagueGroup.allCases {
                        group.addTask { try await self.client.nextGameDate(after: afterString, leagueGroup: league) }
                    }
                    var earliest: String?
                    for try await candidate in group {
                        guard let candidate else { continue }
                        if earliest == nil || candidate < earliest! { earliest = candidate }
                    }
                    return earliest
                }
            } else {
                nextDateString = try await client.nextGameDate(after: afterString, leagueGroup: leagueGroup)
            }
            guard let nextDateString, let nextDate = Date.fromApiDateString(nextDateString) else {
                jumpToNextGameError = "No upcoming games found."
                return
            }
            await jumpToDate(nextDate, allLeagues: allLeagues)
        } catch {
            jumpToNextGameError = "Couldn't find the next game: \(error.localizedDescription)"
        }
    }

    func loadMonthCounts(month: Date, allLeagues: Bool) async {
        isLoadingMonthCounts = true
        defer { isLoadingMonthCounts = false }
        let comps = Calendar.current.dateComponents([.year, .month], from: month)
        guard let year = comps.year, let monthNum = comps.month else { return }
        do {
            if allLeagues {
                monthCounts = try await withThrowingTaskGroup(of: [String: Int].self) { group in
                    for league in LeagueGroup.allCases {
                        group.addTask { try await self.client.scheduleCounts(year: year, month: monthNum, leagueGroup: league) }
                    }
                    var merged: [String: Int] = [:]
                    for try await counts in group {
                        for (date, count) in counts { merged[date, default: 0] += count }
                    }
                    return merged
                }
            } else {
                monthCounts = try await client.scheduleCounts(year: year, month: monthNum, leagueGroup: leagueGroup)
            }
            monthCountsMonth = month
        } catch {
            monthCounts = [:]
        }
    }

    private func fetchDays(start: Date, end: Date, allLeagues: Bool) async throws -> [DayGames] {
        let startString = start.apiDateString
        let endString = end.apiDateString
        if allLeagues {
            return try await withThrowingTaskGroup(of: [DayGames].self) { group in
                for league in LeagueGroup.allCases {
                    group.addTask { try await self.client.scheduleByDay(start: startString, end: endString, leagueGroup: league) }
                }
                var merged: [String: DayGames] = [:]
                for try await leagueDays in group {
                    for day in leagueDays {
                        merged[day.date, default: DayGames(date: day.date, games: [])].games += day.games
                    }
                }
                return merged.values.sorted { $0.date < $1.date }
            }
        } else {
            return try await client.scheduleByDay(start: startString, end: endString, leagueGroup: leagueGroup)
        }
    }

    private func addDays(_ n: Int, to date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: n, to: date) ?? date
    }
}
