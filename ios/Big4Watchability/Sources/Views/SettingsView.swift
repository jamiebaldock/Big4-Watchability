import SwiftUI

// Swift mirror of a first slice of SettingsScreen.kt - see AppSettingsKeys.swift
// for which AppSettings.kt fields are wired up so far vs. still to come
// (enabledLeagues/isAllLeaguesSelected's "All Leagues" merge, alerts config,
// admin PIN entry, and the About/Player Hater Mode easter egg are separate
// future screens, not toggles here).
struct SettingsView: View {
    @AppStorage(AppSettingsKeys.showNumericScore) private var showNumericScore = true
    @AppStorage(AppSettingsKeys.bumpFavoriteTeamGames) private var bumpFavoriteTeamGames = true
    @AppStorage(AppSettingsKeys.wifiOnlyHighlights) private var wifiOnlyHighlights = false
    @AppStorage(AppSettingsKeys.lightTheme) private var lightTheme = false
    @AppStorage(AppSettingsKeys.confettiEnabled) private var confettiEnabled = true
    @AppStorage(AppSettingsKeys.minTierFilterEnabled) private var minTierFilterEnabled = false
    @AppStorage(AppSettingsKeys.minTierFilter) private var minTierFilterRawValue = WatchabilityTier.skippable.rawValue
    @AppStorage(AppSettingsKeys.defaultLandingTab) private var defaultLandingTabRawValue = AppTab.games.rawValue
    @AppStorage(AppSettingsKeys.defaultGameDetailTab) private var defaultGameDetailTabRawValue = GameDetailTab.breakdown.rawValue

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
                    Toggle("Filter by minimum tier", isOn: $minTierFilterEnabled)
                    if minTierFilterEnabled {
                        Picker("Minimum tier to show", selection: $minTierFilterRawValue) {
                            ForEach([WatchabilityTier.instantClassic, .worthYourTime, .solid, .skippable], id: \.rawValue) { tier in
                                Text(tier.displayLabel).tag(tier.rawValue)
                            }
                        }
                    }
                }
                Section("Highlights") {
                    Toggle("Wi-Fi only", isOn: $wifiOnlyHighlights)
                }
                Section("Navigation") {
                    Picker("Default tab on launch", selection: $defaultLandingTabRawValue) {
                        ForEach(AppTab.allCases) { tab in
                            Text(tab.label).tag(tab.rawValue)
                        }
                    }
                    Picker("Default game-detail tab", selection: $defaultGameDetailTabRawValue) {
                        Text("Breakdown").tag(GameDetailTab.breakdown.rawValue)
                        Text("Top Performers").tag(GameDetailTab.topPerformers.rawValue)
                    }
                }
                Section {
                    NavigationLink("Rubric Weights") {
                        RubricWeightsView()
                    }
                    NavigationLink("About") {
                        AboutView()
                    }
                }
                Section {
                    Text("Alerts are coming in a later build.")
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
