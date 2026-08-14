import SwiftUI

// Swift mirror of StarredScreen.kt - purely local, no network call, since
// StarredGamesStore already holds full game snapshots.
struct StarredView: View {
    @ObservedObject private var store = StarredGamesStore.shared

    var body: some View {
        NavigationStack {
            if store.games.isEmpty {
                EmptyStateView(title: "Star a game to find it here", systemImage: "star")
                    .navigationTitle("Starred")
            } else {
                List {
                    ForEach(store.games) { game in
                        StarredRow(game: game)
                            .swipeActions {
                                Button("Unstar", role: .destructive) {
                                    store.toggle(game)
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .navigationTitle("Starred")
            }
        }
    }
}

private struct StarredRow: View {
    let game: GameJson

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(game.al ?? game.a) @ \(game.hl ?? game.h)")
                .font(.headline)
            Text(game.hook)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    StarredView()
}
