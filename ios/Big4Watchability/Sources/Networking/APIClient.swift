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

    /// GET /schedule?start=&end=&leagueGroup=
    func schedule(start: String, end: String, leagueGroup: LeagueGroup) async throws -> [GameJson] {
        try await get("/schedule?start=\(start)&end=\(end)&leagueGroup=\(leagueGroup.apiValue)")
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

    /// GET /schedule-counts?year=&month=&leagueGroup=
    func scheduleCounts(year: Int, month: Int, leagueGroup: LeagueGroup) async throws -> [String: Int] {
        try await get("/schedule-counts?year=\(year)&month=\(month)&leagueGroup=\(leagueGroup.apiValue)")
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
}

struct SeasonWindowResponse: Codable {
    let start: String
    let end: String
}
