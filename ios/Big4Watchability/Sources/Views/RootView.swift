import SwiftUI

// Sixth vertical slice adds History. Alerts/Settings/Starred/admin/highlights
// still to come - see mobile/app/.../ui/ for the Android tab set to mirror
// (BottomNavTab: Games/Starred/Favorites/History/Leaders/News/Settings -
// Leaders on Android is a swipeable Standings+Stats combo; kept as two
// separate tabs here since iOS doesn't have an obvious equivalent gesture
// convention for that and simpler is fine for now).
struct RootView: View {
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
        }
    }
}

#Preview {
    RootView()
}
