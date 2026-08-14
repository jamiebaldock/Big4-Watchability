import SwiftUI

// Swift mirror of a first slice of SettingsScreen.kt - see AppSettingsKeys.swift
// for which AppSettings.kt fields are wired up so far vs. still to come
// (rubric weight sliders, alerts config, admin PIN entry, and the About/
// Player Hater Mode easter egg are separate future screens, not toggles
// here).
struct SettingsView: View {
    @AppStorage(AppSettingsKeys.showNumericScore) private var showNumericScore = true
    @AppStorage(AppSettingsKeys.bumpFavoriteTeamGames) private var bumpFavoriteTeamGames = true
    @AppStorage(AppSettingsKeys.wifiOnlyHighlights) private var wifiOnlyHighlights = false
    @AppStorage(AppSettingsKeys.lightTheme) private var lightTheme = false
    @AppStorage(AppSettingsKeys.confettiEnabled) private var confettiEnabled = true

    var body: some View {
        NavigationStack {
            List {
                Section("Display") {
                    Toggle("Show numeric score", isOn: $showNumericScore)
                    Toggle("Force light theme", isOn: $lightTheme)
                    Toggle("Confetti on great games", isOn: $confettiEnabled)
                }
                Section("Games") {
                    Toggle("Bump favorite team games to top", isOn: $bumpFavoriteTeamGames)
                }
                Section("Highlights") {
                    Toggle("Wi-Fi only", isOn: $wifiOnlyHighlights)
                }
                Section {
                    NavigationLink("Rubric Weights") {
                        RubricWeightsView()
                    }
                }
                Section {
                    Text("Alerts and admin tools are coming in a later build.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
