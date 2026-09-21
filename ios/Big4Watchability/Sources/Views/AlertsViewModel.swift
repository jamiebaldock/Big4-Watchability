import Foundation

// Swift mirror of mobile/app/.../ui/AlertsViewModel.kt - owns the
// "any change re-registers the whole device state" loop that keeps
// alertStore.ts's full-state upsert honest.
//
// Every setter here follows the same three beats: write the pref locally so
// the UI updates instantly, push the complete new state to the backend, and
// (for anything starting-soon touches) rebuild the local notification queue.
// Registration is deliberately fire-and-forget - a failed sync must never
// block the toggle from flipping, since the next change re-sends everything
// anyway.

@MainActor
final class AlertsViewModel: ObservableObject {

    @Published private(set) var isSyncing = false
    /// Surfaced quietly under the settings list rather than as an alert -
    /// a failed sync is recoverable by the next change and shouldn't feel
    /// like an error the user has to act on.
    @Published private(set) var syncError: String?

    private let store = AlertsStore.shared
    private let push = PushNotificationManager.shared

    // Deliberately no `settings` / `authorizationDenied` passthroughs here:
    // views observe AlertsStore and PushNotificationManager directly, so a
    // passthrough on this non-observing object would silently snapshot and
    // never update.

    /// Called on first appearance of the Alerts screen and after a token
    /// rotation - makes sure the server's copy of this device matches what's
    /// on it right now.
    func onAppear() async {
        await Self.syncRegistration()
        await StartingSoonScheduler.pruneEndedAndReschedule()
    }

    // MARK: - Settings

    func setStartingSoonEnabled(_ value: Bool) async {
        store.setStartingSoonEnabled(value)
        // Starting-soon is purely local, so this needs no registration call -
        // only the notification queue. Permission is still required though.
        if value { await push.requestAuthorizationIfNeeded() }
        await StartingSoonScheduler.reschedule()
    }

    func setLeadTimeMinutes(_ value: Int) async {
        store.setLeadTimeMinutes(value)
        await StartingSoonScheduler.reschedule()
    }

    func setCloseSwingEnabled(_ value: Bool) async {
        store.setCloseSwingEnabled(value)
        if value { await push.requestAuthorizationIfNeeded() }
        await sync()
    }

    func setDelivery(_ value: AlertDelivery) async {
        store.setDelivery(value)
        // Delivery genuinely matters server-side on iOS (unlike Android,
        // where the client decides): the backend reads it to choose between
        // a real APNs alert payload and a silent content-available push.
        // See fcm.ts's sendPush.
        if value != .inApp { await push.requestAuthorizationIfNeeded() }
        await sync()
    }

    func setFavoritesOnly(_ value: Bool) async {
        store.setFavoritesOnly(value)
        await sync()
    }

    private func sync() async {
        isSyncing = true
        syncError = await Self.syncRegistration()
        isSyncing = false
    }

    /// The one place the register payload is assembled, shared with
    /// PushNotificationManager's token-rotation callback. Returns an error
    /// message on failure rather than throwing - every caller wants to keep
    /// going either way.
    @discardableResult
    static func syncRegistration() async -> String? {
        let store = AlertsStore.shared
        do {
            try await AlertsNetworkRepository.registerDevice(
                deviceId: store.deviceId,
                fcmToken: store.fcmToken,
                // Android sends only the leagues the user has enabled. This
                // app has no enabled-leagues concept at all (see
                // AppSettingsKeys' header: LeagueGroup only ever contains
                // the 5 shipped leagues, nothing to disable), so all 5 go up.
                leagues: LeagueGroup.allCases,
                favorites: FavoritesStore.shared.teams,
                closeSwingEnabled: store.settings.closeSwingEnabled,
                delivery: store.settings.delivery,
                favoritesOnly: store.settings.favoritesOnly
            )
            return nil
        } catch let error as AlertsRequestError {
            return error.message
        } catch {
            return error.localizedDescription
        }
    }

    /// The per-game bell, called from a game tile. Writes the local snapshot
    /// (so starting-soon can fire with no network), mirrors the subscription
    /// server-side, and rebuilds the notification queue.
    static func toggleBell(for game: GameJson) async {
        let store = AlertsStore.shared
        // game.eventId, NOT game.id: the backend keys alert_game_subs on
        // ESPN's own event id (GameJson.id server-side, mapped to `eventId`
        // here by CodingKeys), whereas Swift's `id` is the away@home@utc
        // composite used only for client-side identity/dedup. Belling with
        // the composite would write a subscription the poller never matches.
        guard let eventId = game.eventId else { return }
        let nowBelled = !store.isBelled(eventId: eventId)
        store.setBelled(
            BelledGameSnapshot(eventId: eventId, away: game.a, home: game.h, tipoffUtc: game.utc),
            belled: nowBelled
        )
        await StartingSoonScheduler.reschedule()
        try? await AlertsNetworkRepository.setGameSub(
            deviceId: store.deviceId,
            eventId: eventId,
            subscribed: nowBelled
        )
    }
}
