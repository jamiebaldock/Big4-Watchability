import Foundation

// Swift mirror of AdminNetworkRepository.kt - talks to devServer.ts's admin
// routes directly (separate from APIClient since every call here needs a
// bearer token header APIClient's plain GETs don't use).
enum AdminNetworkRepository {
    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    static func login(baseUrl: String, pin: String) async throws -> String {
        let body = try encoder.encode(AdminLoginRequestBody(pin: pin))
        let data = try await post("\(baseUrl)/admin/login", body: body, token: nil)
        return try decoder.decode(AdminLoginResponse.self, from: data).token
    }

    static func stats(baseUrl: String, token: String) async throws -> AdminStats {
        let data = try await get("\(baseUrl)/admin/stats", token: token)
        return try decoder.decode(AdminStats.self, from: data)
    }

    static func missingHighlights(baseUrl: String, token: String) async throws -> [AdminMissingGame] {
        let data = try await get("\(baseUrl)/admin/missing-highlights", token: token)
        return try decoder.decode(AdminMissingHighlightsResponse.self, from: data).games
    }

    static func resendHighlights(baseUrl: String, token: String, eventId: String) async throws -> AdminResendResult {
        let body = try encoder.encode(AdminResendRequestBody(eventId: eventId))
        let data = try await post("\(baseUrl)/admin/resend-highlights", body: body, token: token)
        return try decoder.decode(AdminResendResult.self, from: data)
    }

    static func setHighlight(baseUrl: String, token: String, eventId: String, url: String) async throws -> AdminSetHighlightResult {
        let body = try encoder.encode(AdminSetHighlightRequestBody(eventId: eventId, url: url))
        let data = try await post("\(baseUrl)/admin/set-highlight", body: body, token: token)
        return try decoder.decode(AdminSetHighlightResult.self, from: data)
    }

    private static func get(_ urlString: String, token: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw AdminRequestError(message: "Bad URL") }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)
        return data
    }

    private static func post(_ urlString: String, body: Data, token: String?) async throws -> Data {
        guard let url = URL(string: urlString) else { throw AdminRequestError(message: "Bad URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)
        return data
    }

    private static func checkResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AdminRequestError(message: "No response")
        }
        if http.statusCode == 401 {
            let message = (try? decoder.decode(AdminErrorResponse.self, from: data))?.error ?? "unauthorized"
            throw AdminUnauthorizedError(message: message)
        }
        if !(200..<300).contains(http.statusCode) {
            let message = (try? decoder.decode(AdminErrorResponse.self, from: data))?.error ?? "Backend returned HTTP \(http.statusCode)"
            throw AdminRequestError(message: message)
        }
    }
}
