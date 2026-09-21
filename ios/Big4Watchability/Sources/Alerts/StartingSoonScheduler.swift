import Foundation
import UserNotifications

// The starting-soon half of Alerts - client-side only, synced to no server,
// exactly as on Android (AlertsRepository.kt: "Starting-soon is entirely
// client-side (local alarms) - synced nowhere").
//
// Android needs StartingSoonScheduler + AlarmReceiver + its own persisted
// scheduledAlarmIds bookkeeping, because AlarmManager hands back opaque
// handles that don't survive process death. iOS needs none of that:
// UNUserNotificationCenter owns the pending queue, survives restarts, and
// can be queried and diffed directly - so `scheduledAlarmIds` has no iOS
// equivalent and is deliberately not ported.
//
// Exact-alarm permission has no iOS analogue either: the "allow this app to
// schedule exact alarms" prompt in Android's AlertsSettingsScreen is a
// Android 12+ requirement with nothing matching it here, so the iOS
// settings screen omits that row rather than showing a dead control.

// @MainActor because every entry point reads AlertsStore, which is itself
// MainActor-isolated. UNUserNotificationCenter is safe to call from any
// actor, so this costs nothing and removes a pile of hops.
@MainActor
enum StartingSoonScheduler {

    /// Prefix that marks a pending request as ours, so a rebuild only ever
    /// clears starting-soon notifications and never touches anything else
    /// the app might schedule later.
    private static let identifierPrefix = "startingSoon."

    /// iOS keeps at most 64 pending local notifications per app and silently
    /// drops the rest. Belling more than that many games at once is not a
    /// realistic user, but the cap is real, so the soonest ones win.
    private static let maxPending = 64

    /// Rebuilds the whole pending queue from the current bell list. Cheap
    /// and idempotent - just call it after any change rather than trying to
    /// diff individual games.
    static func reschedule() async {
        let store = AlertsStore.shared
        let settings = store.settings
        let snapshots = store.belled

        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: existing)

        guard settings.startingSoonEnabled else { return }

        // Drop games whose tipoff (or whose lead-time window) is already
        // past - scheduling a trigger in the past is a silent no-op that
        // would leave a stale bell looking active forever.
        let now = Date()
        let lead = TimeInterval(settings.leadTimeMinutes * 60)
        let upcoming = snapshots
            .compactMap { snapshot -> (BelledGameSnapshot, Date)? in
                guard let tipoff = GameCardView.parseUtc(snapshot.tipoffUtc) else { return nil }
                let fireAt = tipoff.addingTimeInterval(-lead)
                return fireAt > now ? (snapshot, fireAt) : nil
            }
            .sorted { $0.1 < $1.1 }
            .prefix(maxPending)

        for (snapshot, fireAt) in upcoming {
            let content = UNMutableNotificationContent()
            content.title = "\(snapshot.away) @ \(snapshot.home)"
            content.body = "Starts in \(settings.leadTimeMinutes) min"
            content.sound = .default
            // Same keys the close-swing push uses, so a tap deep-links
            // through the identical path in PushNotificationManager.
            content.userInfo = ["eventId": snapshot.eventId, "utc": snapshot.tipoffUtc]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireAt
            )
            let request = UNNotificationRequest(
                identifier: identifierPrefix + snapshot.eventId,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    /// Drops bells for games that have already tipped off, then rebuilds.
    /// Android does this prune inside its scheduler refresh too - without it
    /// the bell list grows forever and old games keep reappearing in the
    /// Favorites/Starred bell state.
    static func pruneEndedAndReschedule() async {
        let store = AlertsStore.shared
        let snapshots = store.belled
        let now = Date()
        let ended = Set(
            snapshots
                .filter { snapshot in
                    guard let tipoff = GameCardView.parseUtc(snapshot.tipoffUtc) else { return false }
                    // A game is treated as done well after tipoff rather
                    // than at it - 6h comfortably covers even an extra-innings
                    // MLB game or a multi-OT NHL playoff.
                    return tipoff.addingTimeInterval(6 * 60 * 60) < now
                }
                .map(\.eventId)
        )
        if !ended.isEmpty {
            store.removeBelled(eventIds: ended)
        }
        await reschedule()
    }
}
