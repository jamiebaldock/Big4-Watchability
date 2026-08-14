import Foundation

// UserDefaults keys for the flat settings AppSettingsRepository.kt persists
// as individual DataStore Preferences entries (unlike Favorites/Starred,
// which are JSON blobs - these are plain scalars, so @AppStorage is the
// direct native equivalent, no custom store class needed).
//
// enabledLeagues and isAllLeaguesSelected still need their own screens/
// plumbing before they're worth exposing here.
enum AppSettingsKeys {
    static let showNumericScore = "settings.showNumericScore"
    static let bumpFavoriteTeamGames = "settings.bumpFavoriteTeamGames"
    static let wifiOnlyHighlights = "settings.wifiOnlyHighlights"
    static let lightTheme = "settings.lightTheme"
    static let confettiEnabled = "settings.confettiEnabled"
    // Raw AppTab rawValue (e.g. "games") - which tab the app opens on.
    static let defaultLandingTab = "settings.defaultLandingTab"
    static let minTierFilterEnabled = "settings.minTierFilterEnabled"
    // Raw WatchabilityTier rawValue (e.g. "solid") - the lowest tier still
    // shown when the filter above is enabled; irrelevant while disabled.
    static let minTierFilter = "settings.minTierFilter"
    // Raw GameDetailTab rawValue - which tab the game-detail popup opens on.
    static let defaultGameDetailTab = "settings.defaultGameDetailTab"
    // Easter egg, unlocked via About's version-number tap counter (SecretScreenView) -
    // not shown in the normal Settings list.
    static let playerHaterMode = "settings.playerHaterMode"
}
