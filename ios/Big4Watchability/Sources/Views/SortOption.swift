import Foundation

// Swift mirror of SortMenu.kt's SortOption - the 4 ways a day's game list
// can be ordered, one active at a time.
enum SortOption: String, CaseIterable {
    case dateOldestFirst, dateNewestFirst, ratingHighestFirst, ratingLowestFirst

    var label: String {
        switch self {
        case .dateOldestFirst: return "Oldest first"
        case .dateNewestFirst: return "Newest first"
        case .ratingHighestFirst: return "Highest rated first"
        case .ratingLowestFirst: return "Lowest rated first"
        }
    }
}
