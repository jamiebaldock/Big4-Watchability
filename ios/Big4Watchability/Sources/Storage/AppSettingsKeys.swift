import Foundation

// UserDefaults keys for the flat settings AppSettingsRepository.kt persists
// as individual DataStore Preferences entries (unlike Favorites/Starred,
// which are JSON blobs - these are plain scalars, so @AppStorage is the
// direct native equivalent, no custom store class needed).
//
// Only a first slice of AppSettings.kt's fields are wired up so far -
// enabledLeagues, defaultLandingTab, minTierFilter, defaultGameDetailTab,
// isAllLeaguesSelected, and playerHaterMode still need their own screens/
// plumbing before they're worth exposing here.
enum AppSettingsKeys {
    static let showNumericScore = "settings.showNumericScore"
    static let bumpFavoriteTeamGames = "settings.bumpFavoriteTeamGames"
    static let wifiOnlyHighlights = "settings.wifiOnlyHighlights"
    static let lightTheme = "settings.lightTheme"
    static let confettiEnabled = "settings.confettiEnabled"
}
