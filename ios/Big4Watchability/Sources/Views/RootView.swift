import SwiftUI

// Third vertical slice adds News. Stats/Favorites/History/Alerts tabs still
// to come - see mobile/app/.../ui/ for the Android tab set to mirror
// (BottomNavTab: Games/Starred/Favorites/History/Leaders/News/Settings).
struct RootView: View {
    var body: some View {
        TabView {
            GamesView()
                .tabItem {
                    Label("Games", systemImage: "sportscourt")
                }
            StandingsView()
                .tabItem {
                    Label("Standings", systemImage: "list.number")
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
