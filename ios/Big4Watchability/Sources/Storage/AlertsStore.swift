import Foundation

// Swift mirror of mobile/app/.../data/AlertsRepository.kt - UserDefaults
// standing in for Jetpack DataStore, same keys-and-meanings, same defaults.
//
// Two alert types live behind this store and they work very differently:
// - Close-swing is SERVER-driven. The prefs below are snapshotted to the
//   backend on every change (alertStore.ts's full-state upsert), and the
//   push arrives via FCM while the app may not even be running.
// - Starting-soon is ENTIRELY client-side, synced nowhere, exactly as on
//   Android - there it's AlarmManager, here it's UNUserNotificationCenter
//   local notifications (see StartingSoonScheduler.swift).

/// Mirrors alertStore.ts's AlertDelivery ("push" | "in_app" | "both").
enum AlertDelivery: String, CaseIterable, Identifiable {
    case push, inApp = "in_app", both

    var id: String { rawValue }
    var apiValue: String { rawValue }

    /// Matches AlertsRepository.kt's own labels verbatim.
    var label: String {
        switch self {
        case .push: return "Push notification only"
        case .inApp: return "In-app banner only"
        case .both: return "Push and in-app"
        }
    }
}

/// Everything StartingSoonScheduler needs to schedule a belled game's local
/// notification without any network call - captured from the Game at
/// bell-toggle time, since a belled non-favorite game has no other offline
/// source for its tipoff/names. Mirrors Android's BelledGameSnapshot.
struct BelledGameSnapshot: Codable, Identifiable, Hashable {
    let eventId: String
    let away: String
    let home: String
    let tipoffUtc: String

    var id: String { eventId }
}

/// The lead-time choices offered in AlertsSettingsView - default 15,
/// matching Android's LEAD_TIME_OPTIONS_MINUTES (James's confirmed presets).
let leadTimeOptionsMinutes = [5, 15, 30, 60]

struct AlertsSettings: Equatable {
    var closeSwingEnabled = true
    var startingSoonEnabled = true
    var leadTimeMinutes = 15
    var delivery: AlertDelivery = .both
    var favoritesOnly = true
}

@MainActor
final class AlertsStore: ObservableObject {
    static let shared = AlertsStore()

    @Published private(set) var settings = AlertsSettings()
    @Published private(set) var belled: [BelledGameSnapshot] = []
    /// Nil until APNs hands one over (or forever, if the user denies
    /// permission / Firebase is unconfigured) - registration still happens
    /// either way so prefs and favorites reach the server regardless.
    @Published private(set) var fcmToken: String?

    private let defaults: UserDefaults

    private enum Key {
        static let deviceId = "alerts.deviceId"
        static let fcmToken = "alerts.fcmToken"
        static let belled = "alerts.belledSnapshots"
        static let closeSwingEnabled = "alerts.closeSwingEnabled"
        static let startingSoonEnabled = "alerts.startingSoonEnabled"
        static let leadTimeMinutes = "alerts.leadTimeMinutes"
        static let delivery = "alerts.delivery"
        static let favoritesOnly = "alerts.favoritesOnly"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.fcmToken = defaults.string(forKey: Key.fcmToken)
        self.belled = Self.load(defaults, key: Key.belled) ?? []
        self.settings = AlertsSettings(
            // object(forKey:) rather than bool(forKey:) throughout: bool
            // returns false for a missing key, which would silently flip
            // every default from true to false on a fresh install.
            closeSwingEnabled: defaults.object(forKey: Key.closeSwingEnabled) as? Bool ?? true,
            startingSoonEnabled: defaults.object(forKey: Key.startingSoonEnabled) as? Bool ?? true,
            leadTimeMinutes: defaults.object(forKey: Key.leadTimeMinutes) as? Int ?? 15,
            delivery: AlertDelivery(rawValue: defaults.string(forKey: Key.delivery) ?? "") ?? .both,
            favoritesOnly: defaults.object(forKey: Key.favoritesOnly) as? Bool ?? true
        )
    }

    /// Stable per-install identity for /alerts/register and /alerts/game-sub -
    /// generated once and persisted forever after, deliberately independent
    /// of the push token (which rotates). Same contract as Android's
    /// getOrCreateDeviceId, minus the suspend - UserDefaults is synchronous.
    var deviceId: String {
        if let existing = defaults.string(forKey: Key.deviceId) { return existing }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: Key.deviceId)
        return generated
    }

    func setFcmToken(_ token: String) {
        guard token != fcmToken else { return }
        fcmToken = token
        defaults.set(token, forKey: Key.fcmToken)
    }

    // MARK: - Settings

    func setCloseSwingEnabled(_ value: Bool) {
        settings.closeSwingEnabled = value
        defaults.set(value, forKey: Key.closeSwingEnabled)
    }

    func setStartingSoonEnabled(_ value: Bool) {
        settings.startingSoonEnabled = value
        defaults.set(value, forKey: Key.startingSoonEnabled)
    }

    func setLeadTimeMinutes(_ value: Int) {
        settings.leadTimeMinutes = value
        defaults.set(value, forKey: Key.leadTimeMinutes)
    }

    func setDelivery(_ value: AlertDelivery) {
        settings.delivery = value
        defaults.set(value.rawValue, forKey: Key.delivery)
    }

    func setFavoritesOnly(_ value: Bool) {
        settings.favoritesOnly = value
        defaults.set(value, forKey: Key.favoritesOnly)
    }

    // MARK: - The per-game bell

    func isBelled(eventId: String) -> Bool {
        belled.contains { $0.eventId == eventId }
    }

    func setBelled(_ snapshot: BelledGameSnapshot, belled isBelled: Bool) {
        belled.removeAll { $0.eventId == snapshot.eventId }
        if isBelled { belled.append(snapshot) }
        Self.save(defaults, key: Key.belled, value: belled)
    }

    /// Bulk bell reset for games that have since ended - the prune path
    /// StartingSoonScheduler runs on refresh, mirroring Android's
    /// removeBelledEventIds.
    func removeBelled(eventIds: Set<String>) {
        guard !eventIds.isEmpty else { return }
        belled.removeAll { eventIds.contains($0.eventId) }
        Self.save(defaults, key: Key.belled, value: belled)
    }

    // MARK: - Codable helpers (same shape FavoritesStore uses)

    private static func load<T: Decodable>(_ defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ defaults: UserDefaults, key: String, value: T) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
