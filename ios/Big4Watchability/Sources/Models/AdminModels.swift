import Foundation

// Swift mirror of AdminNetworkRepository.kt's response models - talks to
// devServer.ts's admin routes (adminService.ts), the hidden Admin page's own
// backend. Test-push is deliberately not ported here: it targets THIS
// device's own registered Alerts token, and the Alerts push stack itself
// isn't built on iOS yet.
struct LagPercentiles: Codable {
    let p50Ms: Int
    let sampleCount: Int
    let fromRealData: Bool
}

struct BudgetDay: Codable, Identifiable {
    var id: String { date }
    let date: String
    let count: Int
}

struct PushStats: Codable {
    let registeredDevices: Int
    let sentLastNDays: Int
    let deliveredLastNDays: Int
    let failedLastNDays: Int
}

struct RenderStatus: Codable {
    let configured: Bool
    let serviceStatus: String?
    let lastDeployStatus: String?
    let lastDeployAt: String?
    let error: String?
}

struct AnthropicUsage: Codable {
    let configured: Bool
    let last7DaysCostUsd: Double?
    let error: String?
}

struct AdminStats: Codable {
    let todayCount: Int
    let dailyCap: Int
    let budgetHistory: [BudgetDay]
    let lagPercentiles: [String: LagPercentiles]
    let outcomeCounts: [String: Int]
    let pushStats: PushStats
    let renderStatus: RenderStatus
    let anthropicUsage: AnthropicUsage
}

struct AdminMissingGame: Codable, Identifiable {
    let eventId: String
    var id: String { eventId }
    let league: String
    let leagueGroup: String
    let away: String
    let home: String
    let tipoffUtc: String
    let ytCheckCount: Int
    let ytLastCheckedAt: String?
}

struct AdminMissingHighlightsResponse: Codable {
    let games: [AdminMissingGame]
}

struct AdminLoginRequestBody: Codable {
    let pin: String
}

struct AdminLoginResponse: Codable {
    let token: String
}

struct AdminResendRequestBody: Codable {
    let eventId: String
}

struct AdminResendResult: Codable {
    let matched: Bool
    let videoId: String?
    let title: String?
}

struct AdminSetHighlightRequestBody: Codable {
    let eventId: String
    let url: String
}

struct AdminSetHighlightResult: Codable {
    let videoId: String
}

struct AdminErrorResponse: Codable {
    let error: String?
}

/// Thrown for a bad/expired token specifically, so the ViewModel can fall
/// back to the PIN screen rather than showing a generic error.
struct AdminUnauthorizedError: Error {
    let message: String
}

struct AdminRequestError: Error {
    let message: String
}
