import Foundation

// Mirrors backend/src/historyService.ts's HistoryResult and
// httpHandler.ts's CurrentSeasonStartResult.

struct HistoryResponse: Codable {
    let earliestDate: String
    let seasons: [String]
    let games: [GameJson]
}

struct CurrentSeasonStartResponse: Codable {
    let date: String
}
