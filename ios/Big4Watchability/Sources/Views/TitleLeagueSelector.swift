import SwiftUI

// Swift mirror of LeagueSelector.kt's TitleLeagueSelector - a tab's top-bar
// title: a tappable league logo + name that opens a dropdown (SwiftUI's
// Menu, standing in for Android's DropdownMenu), not an always-visible
// segmented row. Replaces the plain iOS-native segmented Picker that was
// previously in GamesView/HistoryView's toolbar - visually nothing like
// Android's actual navigation, which never shows every league at once.
struct TitleLeagueSelector: View {
    let selectedLeague: LeagueGroup
    let onLeagueSelected: (LeagueGroup) -> Void
    var isAllLeaguesSelected: Bool = false
    // Non-nil turns on the "All Leagues" menu item - only Games and History
    // pass it (each merges every league's tiles into one combined list).
    var onAllLeaguesSelected: (() -> Void)?

    @Environment(\.appTheme) private var theme

    var body: some View {
        Menu {
            if let onAllLeaguesSelected {
                Button("All Leagues", action: onAllLeaguesSelected)
            }
            ForEach(LeagueGroup.allCases) { league in
                Button {
                    onLeagueSelected(league)
                } label: {
                    Label {
                        Text(league.displayName)
                    } icon: {
                        // SwiftUI's Menu can't render a remote AsyncImage
                        // inside a Label's icon slot reliably - the league
                        // name alone still matches Android's dropdown text,
                        // just without the leading crest there.
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if !isAllLeaguesSelected {
                    AsyncImage(url: URL(string: selectedLeague.logoUrl)) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Color.clear
                    }
                    .frame(width: 28, height: 28)
                }
                Text(isAllLeaguesSelected ? "All Leagues" : selectedLeague.shortDisplayName)
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(theme.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
            }
        }
    }
}
