import SwiftUI

// Eighth vertical slice adds Starred - full parity with Android's 7
// BottomNavTab entries reached (Games/Starred/Favorites/History/Leaders/
// News/Settings), though several Settings toggles are still inert - see
// SettingsView.swift/AppSettingsKeys.swift. Leaders on Android is a
// swipeable Standings+Stats combo; kept as two separate tabs here since iOS
// doesn't have an obvious equivalent gesture convention.
struct RootView: View {
    @AppStorage(AppSettingsKeys.lightTheme) private var lightTheme = false

    var body: some View {
        TabView {
            GamesView()
                .tabItem {
                    Label("Games", systemImage: "sportscourt")
                }
            StarredView()
                .tabItem {
                    Label("Starred", systemImage: "star.circle")
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
