import SwiftUI

// Swift mirror of SecretScreen.kt - unlocked by tapping About's version
// number 8 times, not reachable from the normal Settings list or any nav
// element by design. Only the toggle itself lives here so far; ticking
// which players get roasted (Favorites' hated-players list) and the actual
// roast-line swap on a game tile are separate, still to come.
struct SecretScreenView: View {
    @AppStorage(AppSettingsKeys.playerHaterMode) private var playerHaterMode = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("You found it. Nobody else knows this screen exists - flip the switch below, then go tick the players you want roasted from Favorites. Only the players you've ticked get the treatment - everyone else's standout callout stays normal.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Player Hater Mode", isOn: $playerHaterMode)
                }
            }
            .navigationTitle("🤫 Secret Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
