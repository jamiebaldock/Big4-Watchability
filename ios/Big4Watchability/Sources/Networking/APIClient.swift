import Foundation

// Swift mirror of mobile/app/.../data/NetworkGameRepository.kt - same
// endpoints, same query params, same backend. Extend this file alongside
// that one whenever a new endpoint gets added server-side.

enum APIError: Error {
    case badResponse
    case decoding(Error)
}

struct APIClient {
    static let shared = APIClient()

    private let baseURL: String
    private let session: URLSession
    private let decoder: JSONDecoder

    init(baseURL: String = backendBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.badResponse
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badResponse
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// GET /schedule?start=&end=&leagueGroup= - the route wraps its result as
    /// {"schedule": [{"date": ..., "games": [...]}]} (see devServer.ts's
    /// `res.json({ schedule })`), not a bare array. Mirrors
    /// NetworkGameRepository.kt's ScheduleResponse/DayGamesResponse - this
    /// wrapper was missed in the initial iOS port, which decoded straight to
    /// [GameJson] and failed on every call (the Games tab never worked -
    /// found on the very first real-device TestFlight install, 2026-09-20).
    func schedule(start: String, end: String, leagueGroup: LeagueGroup) async throws -> [GameJson] {
        try await scheduleByDay(start: start, end: end, leagueGroup: leagueGroup).flatMap { $0.games }
    }

    /// Same endpoint as `schedule` above, but keeps the backend's per-day
    /// grouping instead of flattening it - needed for the multi-day paging
    /// view (GamesView's day-tab row + swipeable pager), which needs to know
    /// which games belong to which date, not just one merged list.
    func scheduleByDay(start: String, end: String, leagueGroup: LeagueGroup) async throws -> [DayGames] {
        struct ScheduleResponse: Decodable { let schedule: [DayGames] }
        let response: ScheduleResponse = try await get("/schedule?start=\(start)&end=\(end)&leagueGroup=\(leagueGroup.apiValue)")
        return response.schedule
    }

    /// GET /next-game-date?after=&leagueGroup=
    func nextGameDate(after: String, leagueGroup: LeagueGroup) async throws -> String? {
        struct Response: Decodable { let date: String? }
        let response: Response = try await get("/next-game-date?after=\(after)&leagueGroup=\(leagueGroup.apiValue)")
        return response.date
    }

    /// GET /season-window?leagueGroup=
    func seasonWindow(leagueGroup: LeagueGroup) async throws -> SeasonWindowResponse {
        try await get("/season-window?leagueGroup=\(leagueGroup.apiValue)")
    }

    /// GET /team-schedule?teamId=&leagueGroup=
    func teamSchedule(teamId: String, leagueGroup: LeagueGroup) async throws -> [GameJson] {
        try await get("/team-schedule?teamId=\(teamId)&leagueGroup=\(leagueGroup.apiValue)")
    }

    /// GET /schedule-counts?year=&month=&leagueGroup= - returns a flat JSON
    /// array of raw UTC tipoff timestamps (one per game), NOT pre-aggregated
    /// per-day counts - this was decoded as [String: Int] before, which can
    /// never match that shape and silently failed every single call (the
    /// calendar picker never actually showed a count, confirmed on the first
    /// real-device test, 2026-09-20). Mirrors NetworkGameRepository.kt's
    /// scheduleCounts exactly: group by the device's own LOCAL calendar date
    /// (not ESPN's US-Eastern scoreboard day - same reasoning as
    /// GamesViewModel.fetchDays' re-bucketing), a day with zero games is
    /// simply absent from the result rather than an explicit 0.
    func scheduleCounts(year: Int, month: Int, leagueGroup: LeagueGroup) async throws -> [String: Int] {
        let timestamps: [String] = try await get("/schedule-counts?year=\(year)&month=\(month)&leagueGroup=\(leagueGroup.apiValue)")
        var counts: [String: Int] = [:]
        for timestamp in timestamps {
            guard let date = GameCardView.parseUtc(timestamp) else { continue }
            counts[date.apiDateString, default: 0] += 1
        }
        return counts
    }

    // Mirrors NetworkLeagueContentRepository.kt below this point.

    /// GET /standings?leagueGroup=
    func standings(leagueGroup: LeagueGroup) async throws -> StandingsResponse {
        try await get("/standings?leagueGroup=\(leagueGroup.apiValue)")
    }

    /// GET /stats?leagueGroup=
    func stats(leagueGroup: LeagueGroup) async throws -> StatsResponse {
        try await get("/stats?leagueGroup=\(leagueGroup.apiValue)")
    }

    /// GET /news?leagueGroup=
    func news(leagueGroup: LeagueGroup) async throws -> NewsResponse {
        try await get("/news?leagueGroup=\(leagueGroup.apiValue)")
    }

    /// GET /api/history?start=&end=&leagueGroup=
    func history(start: String, end: String, leagueGroup: LeagueGroup) async throws -> HistoryResponse {
        try await get("/api/history?start=\(start)&end=\(end)&leagueGroup=\(leagueGroup.apiValue)")
    }

    /// GET /current-season-start?leagueGroup=
    func currentSeasonStart(leagueGroup: LeagueGroup) async throws -> CurrentSeasonStartResponse {
        try await get("/current-season-start?leagueGroup=\(leagueGroup.apiValue)")
    }

    /// GET /teams?leagueGroup=
    func teams(leagueGroup: LeagueGroup) async throws -> TeamsResponse {
        try await get("/teams?leagueGroup=\(leagueGroup.apiValue)")
    }

    /// GET /roster?leagueGroup=&team=
    func roster(leagueGroup: LeagueGroup, team: String) async throws -> RosterResponse {
        try await get("/roster?leagueGroup=\(leagueGroup.apiValue)&team=\(team)")
    }

    /// GET /game-detail?eventId= - backs the tap-a-tile popup (top
    /// performers/head-to-head/standings context). Fetched fresh every call,
    /// never cached client-side, matching the backend's own on-demand design.
    func gameDetail(eventId: String) async throws -> GameDetailResponse {
        guard let encoded = eventId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw APIError.badResponse
        }
        return try await get("/game-detail?eventId=\(encoded)")
    }
}

struct SeasonWindowResponse: Codable {
    let start: String
    let end: String
}
