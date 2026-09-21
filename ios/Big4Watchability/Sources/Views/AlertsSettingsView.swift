import SwiftUI

// Swift mirror of mobile/app/.../ui/AlertsSettingsScreen.kt. Row titles and
// helper copy are lifted verbatim from that screen so the two platforms say
// the same thing.
//
// Deliberate divergences from Android, both because the underlying platform
// concept doesn't exist here:
// - No "allow exact alarms" prompt row. That's an Android 12+ AlarmManager
//   permission; iOS local notifications need no equivalent grant.
// - Native List/Toggle/Picker rather than Android's hand-rolled custom rows,
//   matching the call already made for SettingsView and RubricWeightsView
//   during the visual-parity pass (an accessibility/native-behaviour
//   tradeoff, not an oversight).
struct AlertsSettingsView: View {
    @StateObject private var viewModel = AlertsViewModel()
    @ObservedObject private var store = AlertsStore.shared
    // Observed directly rather than read through the view model: the view
    // model isn't an observer of PushNotificationManager, so going through
    // it would snapshot authorizationDenied at build time and never update
    // when the permission prompt is answered - the same reactivity trap the
    // calendar game-counts sheet fell into on 2026-09-21.
    @ObservedObject private var push = PushNotificationManager.shared

    var body: some View {
        List {
            if push.authorizationDenied {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notifications are turned off")
                            .font(.subheadline.weight(.semibold))
                        Text("Alerts can't reach you until you allow notifications for Big4Watchability in iOS Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                Toggle("Starting-soon alerts", isOn: binding(
                    get: { store.settings.startingSoonEnabled },
                    set: { await viewModel.setStartingSoonEnabled($0) }
                ))
                if store.settings.startingSoonEnabled {
                    Picker("Lead time", selection: binding(
                        get: { store.settings.leadTimeMinutes },
                        set: { await viewModel.setLeadTimeMinutes($0) }
                    )) {
                        ForEach(leadTimeOptionsMinutes, id: \.self) { minutes in
                            Text("\(minutes) min before").tag(minutes)
                        }
                    }
                }
            } footer: {
                Text("Get notified before your favorites' (and belled) games start")
            }

            Section {
                Toggle("Close-swing alerts", isOn: binding(
                    get: { store.settings.closeSwingEnabled },
                    set: { await viewModel.setCloseSwingEnabled($0) }
                ))
            } footer: {
                Text("Get notified when a live game gets close in crunch time")
            }

            Section {
                Toggle("Alerts for favorite teams", isOn: binding(
                    get: { store.settings.favoritesOnly },
                    set: { await viewModel.setFavoritesOnly($0) }
                ))
            } footer: {
                Text("On: alerts for every favorite team's game, not just belled ones. Off: alerts only for games you've belled.")
            }

            Section {
                Picker("Delivery", selection: binding(
                    get: { store.settings.delivery },
                    set: { await viewModel.setDelivery($0) }
                )) {
                    ForEach(AlertDelivery.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } footer: {
                if let syncError = viewModel.syncError {
                    // Quiet, not an alert dialog: the next settings change
                    // re-sends everything, so this is informational.
                    Text("Couldn't sync alert settings — they'll retry on your next change. (\(syncError))")
                        .foregroundStyle(AppColors.liveRed)
                }
            }
        }
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.onAppear() }
    }

    /// Bridges SwiftUI's synchronous Binding to the view model's async
    /// setters - the setter kicks off a Task rather than blocking the
    /// control, so toggles stay instant while registration syncs behind.
    private func binding<T>(
        get: @escaping () -> T,
        set: @escaping (T) async -> Void
    ) -> Binding<T> {
        Binding(get: get, set: { newValue in Task { await set(newValue) } })
    }
}
