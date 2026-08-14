import SwiftUI

// Swift mirror of GameCard.kt's StandoutPerformerCallout - one line per
// standout performer in a game, shown on any tile regardless of tier so a
// player worth favoriting can be spotted mid-browse. Long-press toggles
// favorite status (same quick-add pattern as a favorited team's long-press
// elsewhere in this app). Player Hater Mode only roasts a performer who's
// also on the hated-players list (FavoritesStore.hatedPlayers) - being a
// standout here isn't enough on its own.
struct StandoutPerformerCallout: View {
    let game: GameJson
    let performers: [StandoutPerformer]

    @ObservedObject private var favorites = FavoritesStore.shared
    @AppStorage(AppSettingsKeys.playerHaterMode) private var playerHaterMode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(performers) { performer in
                PerformerRow(
                    performer: performer,
                    isFavorite: favorites.players.contains { $0.name == performer.name },
                    isHated: favorites.isHated(name: performer.name),
                    playerHaterMode: playerHaterMode,
                    onLongPress: {
                        let player = PlayerJson(id: performer.name, name: performer.name, headshot: nil)
                        favorites.toggle(player: player, team: performer.team ?? "", leagueGroup: LeagueGroup(espnLeague: game.lg))
                    }
                )
            }
        }
    }
}

private struct PerformerRow: View {
    let performer: StandoutPerformer
    let isFavorite: Bool
    let isHated: Bool
    let playerHaterMode: Bool
    let onLongPress: () -> Void

    // Picked once via onAppear (not recomputed on every redraw) so the
    // roast doesn't visibly flicker as the tile scrolls in and out of view.
    @State private var roastLine = ""

    var body: some View {
        HStack(spacing: 6) {
            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
            Text(displayText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, isFavorite ? 4 : 0)
        .background(isFavorite ? Color.yellow.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onLongPressGesture(perform: onLongPress)
        .onAppear {
            if roastLine.isEmpty {
                roastLine = playerHaterLine(name: performer.name, line: performer.line)
            }
        }
    }

    private var displayText: String {
        (playerHaterMode && isHated) ? roastLine : "\(performer.name): \(performer.line)"
    }
}
