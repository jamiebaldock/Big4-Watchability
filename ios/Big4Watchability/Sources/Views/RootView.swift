import SwiftUI

// First vertical slice: just the Games tab. Standings/Stats/News/Favorites/
// History/Alerts tabs get added once this compiles and the CI loop is
// proven out - see mobile/app/.../ui/ for the Android tab set to mirror.
struct RootView: View {
    var body: some View {
        TabView {
            GamesView()
                .tabItem {
                    Label("Games", systemImage: "sportscourt")
                }
        }
    }
}

#Preview {
    RootView()
}
