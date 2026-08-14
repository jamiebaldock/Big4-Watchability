import SwiftUI

// Which tab RootView's TabView opens on - mirrors BottomNavTab.kt's raw enum
// name persistence (AppSettingsKeys.defaultLandingTab), a plain string key
// rather than a typed enum so Settings' picker doesn't need to import
// RootView just to reference this.
enum AppTab: String, CaseIterable, Identifiable {
    case games, starred, favorites, history, standings, stats, news, settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .games: return "Games"
        case .starred: return "Starred"
        case .favorites: return "Favorites"
        case .history: return "History"
        case .standings: return "Standings"
        case .stats: return "Stats"
        case .news: return "News"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .games: return "sportscourt"
        case .starred: return "star.circle"
        case .favorites: return "star"
        case .history: return "clock.arrow.circlepath"
        case .standings: return "list.number"
        case .stats: return "chart.bar"
        case .news: return "newspaper"
        case .settings: return "gearshape"
        }
    }
}

// Eighth vertical slice adds Starred - full parity with Android's 7
// BottomNavTab entries reached (Games/Starred/Favorites/History/Leaders/
// News/Settings), though several Settings toggles are still inert - see
// SettingsView.swift/AppSettingsKeys.swift. Leaders on Android is a
// swipeable Standings+Stats combo; kept as two separate tabs here since iOS
// doesn't have an obvious equivalent gesture convention.
struct RootView: View {
    @AppStorage(AppSettingsKeys.lightTheme) private var lightTheme = false
    @AppStorage(AppSettingsKeys.defaultLandingTab) private var defaultLandingTabRawValue = AppTab.games.rawValue
    @State private var selectedTab: AppTab = .games

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                tabContent(for: tab)
                    .tabItem {
                        Label(tab.label, systemImage: tab.systemImage)
                    }
                    .tag(tab)
            }
        }
        .preferredColorScheme(lightTheme ? .light : nil)
        .onAppear {
            // Only sets the INITIAL tab on cold launch, not a "remember last
            // tab" - matches Android's defaultLandingTab, a Settings choice
            // rather than session-restore state.
            selectedTab = AppTab(rawValue: defaultLandingTabRawValue) ?? .games
        }
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .games: GamesView()
        case .starred: StarredView()
        case .favorites: FavoritesView()
        case .history: HistoryView()
        case .standings: StandingsView()
        case .stats: StatsView()
        case .news: NewsView()
        case .settings: SettingsView()
        }
    }
}

#Preview {
    RootView()
}
