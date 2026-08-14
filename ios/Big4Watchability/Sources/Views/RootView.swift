import SwiftUI

// Seventh vertical slice adds Settings - reaches feature-count parity with
// Android's 7 BottomNavTab entries (Games/Starred/Favorites/History/Leaders/
// News/Settings), though Starred and several Settings toggles still need
// their own wiring - see SettingsView.swift/AppSettingsKeys.swift. Leaders
// on Android is a swipeable Standings+Stats combo; kept as two separate tabs
// here since iOS doesn't have an obvious equivalent gesture convention.
struct RootView: View {
    @AppStorage(AppSettingsKeys.lightTheme) private var lightTheme = false

    var body: some View {
        TabView {
            GamesView()
                .tabItem {
                    Label("Games", systemImage: "sportscourt")
                }
            FavoritesView()
                .tabItem {
                    Label("Favorites", systemImage: "star")
                }
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
            StandingsView()
                .tabItem {
                    Label("Standings", systemImage: "list.number")
                }
            StatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar")
                }
            NewsView()
                .tabItem {
                    Label("News", systemImage: "newspaper")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .preferredColorScheme(lightTheme ? .light : nil)
    }
}

#Preview {
    RootView()
}
